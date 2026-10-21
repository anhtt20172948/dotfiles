"""Exercise the real CLI with synthetic credentials and an offline quota binary."""
import datetime as dt
import errno
import json
import os
import pty
import re
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
ACCT = ROOT / '.local/bin/ai-acct'
STATUSLINE = ROOT / '.local/bin/agent-statusline-claude'
ANSI = re.compile(r'\x1b\[[0-9;]*m')


class QuotaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.accounts = self.home / '.config/claude-accounts'
        self.accounts.mkdir(parents=True)
        for name in ('work', 'personal', 'limited', 'unknown'):
            path = self.accounts / (name + '.token')
            path.write_text('synthetic-' + name)
            path.chmod(0o600)
        (self.accounts / 'active').write_text('work')
        bindir = self.home / 'bin'
        bindir.mkdir()
        fake = bindir / 'quota-axi'
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
token = os.environ.get('CLAUDE_CODE_OAUTH_TOKEN', '')
assert not os.environ.get('ANTHROPIC_API_KEY')
assert not os.environ.get('CLAUDE_CONFIG_DIR')
assert not os.environ.get('QUOTA_AXI_CLAUDE_PROFILES')
assert not any('synthetic-' in a for a in sys.argv)
provider = sys.argv[sys.argv.index('--provider') + 1]
name = token.removeprefix('synthetic-') if provider == 'claude' else 'codex'
assert name in ('work', 'personal', 'limited', 'unknown', 'codex')
assert provider != 'codex' or not token
with open(Path(os.environ['HOME']) / 'calls', 'a') as f:
    f.write(json.dumps({'name': name, 'argv': sys.argv[1:]}) + '\\n')
gate = os.environ.get('FAKE_GATE')
if gate:
    deadline = time.monotonic() + 30
    while not Path(gate).exists():
        assert time.monotonic() < deadline, 'test gate never released'
        time.sleep(.05)
time.sleep(float(os.environ.get('FAKE_DELAY', '0')))
p = {'provider': provider, 'state': {'status': 'fresh', 'stale': False}, 'windows': []}
if name == 'limited' or os.environ.get('FAKE_LIMIT') == name:
    p['state'] = {'status': 'rate_limited', 'stale': False, 'retryAfter': '2099-10-19T12:30:00Z'}
if name not in ('limited', 'unknown') and os.environ.get('FAKE_LIMIT') != name:
    p['windows'] = [{'id': 'session', 'label': 'session', 'kind': 'session', 'percentRemaining': 75 if name == 'work' else 25, 'resetsAt': '2099-10-19T12:00:00Z'}]
if name == 'work' and os.environ.get('FAKE_LIMIT') != name:
    p['windows'].append({'id': 'week', 'label': 'week', 'kind': 'weekly', 'percentRemaining': 90, 'resetsAt': '2099-10-24T08:00:00Z'})
    p['quotaSemantics'] = {'effectiveAvailability': [{'scope': 'all_models', 'status': 'known', 'effectivePercentRemaining': 75, 'limitingWindowIds': ['session']}]}
if os.environ.get('FAKE_EMPTY') == name:
    p['windows'] = []
    p.pop('quotaSemantics', None)
if name == 'unknown':
    p['windows'] = [{'id': 'session', 'label': 'session', 'kind': 'session', 'percentRemaining': 90}]
    p['quotaSemantics'] = {'effectiveAvailability': [{'scope': 'all_models', 'status': 'unknown'}]}
# Deliberately hostile diagnostic fields must never be rendered or cached.
p['message'] = token
print(json.dumps({'providers': [p]}))
''')
        fake.chmod(0o700)
        self.env = {**os.environ, 'HOME': str(self.home),
                    'XDG_CACHE_HOME': str(self.home / 'cache'),
                    'XDG_CONFIG_HOME': str(self.home / '.config'),
                    'XDG_DATA_HOME': str(self.home / 'data'),
                    'XDG_STATE_HOME': str(self.home / 'state'),
                    'CODEX_HOME': str(self.home / '.codex'),
                    'PATH': str(bindir) + ':' + os.environ['PATH'],
                    'CLAUDE_CODE_OAUTH_TOKEN': 'synthetic-inherited',
                    'ANTHROPIC_API_KEY': 'synthetic-api',
                    'CLAUDE_CONFIG_DIR': '/wrong',
                    'QUOTA_AXI_CLAUDE_PROFILES': '/wrong', 'TZ': 'UTC'}
        self.addCleanup(self.drain_workers)

    def drain_workers(self):
        self.release_reads()
        subprocess.run([str(ACCT), 'status'], env={**self.env, 'FAKE_DELAY': '0'},
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)

    def block_reads(self):
        gate = self.home / 'release'
        gate.unlink(missing_ok=True)
        self.env['FAKE_GATE'] = str(gate)

    def release_reads(self):
        (self.home / 'release').touch()

    def run_cli(self, *args, timeout=15):
        result = subprocess.run([str(ACCT), *args], env=self.env,
                                capture_output=True, text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('synthetic-', result.stdout + result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        return result.stdout

    def names_called(self):
        calls = self.home / 'calls'
        if not calls.exists():
            return []
        return [json.loads(line)['name'] for line in calls.read_text().splitlines()]

    def poll(self, check, what):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(.05)
        self.fail(what)

    def section(self, output, title):
        # Rows of one account's box, without frame or padding.
        lines = output.splitlines()
        start = next(i for i, line in enumerate(lines) if line.startswith('╭─ ' + title + ' '))
        end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith('╰'))
        return [line[2:-2].rstrip() for line in lines[start + 1:end]]

    def capture(self, token, rate_limits, age=0, **env):
        # Feed the real statusline as Claude Code would, then backdate the capture.
        payload = {'model': {'display_name': 'Opus'}, 'rate_limits': rate_limits}
        result = subprocess.run([str(STATUSLINE)], input=json.dumps(payload), text=True,
                                capture_output=True, env={**self.env, 'CLAUDE_CODE_OAUTH_TOKEN': token, **env})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('synthetic-', result.stdout + result.stderr)
        if age:
            path = self.home / 'cache/ai-acct/claude-{}.limits.json'.format(token.removeprefix('synthetic-'))
            record = json.loads(path.read_text())
            path.write_text(json.dumps({**record, 'time': time.time() - age}))

    def listed(self, name):
        for line in self.run_cli('list', '--quota').splitlines():
            if line.split('\t')[0] == name:
                return line.split('\t')[2]
        self.fail('no such account ' + name)

    def test_status_waits_and_shows_every_window(self):
        output = self.run_cli('status')
        work = self.section(output, '✦ Claude work (active)')
        self.assertEqual(len(work), 2)
        self.assertRegex(work[0], r'^session +█{15}░{5}  75% left  ↻ Oct 19 12:00 UTC$')
        self.assertRegex(work[1], r'^week +█{18}░{2}  90% left  ↻ Oct 24 08:00 UTC$')
        self.assertIn('25% left', self.section(output, '✦ Claude personal')[0])
        # Throttled means unreadable, never "out of quota".
        self.assertEqual(self.section(output, '✦ Claude limited'),
                         ['◌ could not read quota - usage API limited until Oct 19 12:30 UTC'])
        self.assertNotIn('rate-limited', output)
        self.assertRegex(self.section(output, '✦ Claude unknown')[0], r'^session +█{18}░{2}  90% left$')
        # Every box has the same width, so the frames line up.
        frame = [line for line in output.splitlines() if line[:1] in '╭│╰']
        self.assertEqual(len({len(line) for line in frame}), 1)
        self.assertIn('25% left', self.section(output, '◆ Codex')[0])
        self.assertEqual(output.count('Codex'), 1)
        self.assertEqual(sorted(self.names_called()),
                         ['codex', 'limited', 'personal', 'unknown', 'work'])
        for _ in range(3):
            listing = self.run_cli('list', '--quota')
            self.assertIn('work\tactive\t████████░░  75% left\n', listing)
            self.assertIn('limited\t\t◌ could not read quota - usage API limited until Oct 19 12:30 UTC\n', listing)
            self.assertIn('unknown\t\t◌ unknown\n', listing)
        self.run_cli('status')
        self.assertEqual(len(self.names_called()), 5)
        for path in (self.home / 'cache/ai-acct').rglob('*'):
            if path.is_file():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertNotIn('synthetic-', path.read_text())
        self.assertEqual((self.home / 'cache/ai-acct').stat().st_mode & 0o777, 0o700)

    def test_terminal_colors_and_no_color(self):
        self.run_cli('status')
        for no_color in (False, True):
            master, slave = pty.openpty()
            try:
                env = {k: v for k, v in self.env.items() if k != 'NO_COLOR'}
                if no_color:
                    env['NO_COLOR'] = '1'
                result = subprocess.run([str(ACCT), 'status'], env=env, stdout=slave,
                                        stderr=subprocess.PIPE, timeout=15)
                self.assertEqual(result.returncode, 0)
                os.close(slave)
                slave = None
                chunks = []
                while True:
                    try:
                        chunk = os.read(master, 8192)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
                output = b''.join(chunks).decode()
                self.assertEqual('\x1b[' in output, not no_color)
                self.assertNotIn('synthetic-', output)
            finally:
                os.close(master)
                if slave is not None:
                    os.close(slave)

    def test_real_fzf_menu_uses_cached_bars(self):
        self.run_cli('status')
        (self.home / 'bin/ai-acct').symlink_to(ACCT)
        fzf = self.home / 'bin/fzf'
        fzf.write_text('#!/bin/sh\ncat > "$HOME/menu-input"\nexit 130\n')
        fzf.chmod(0o700)
        env = {k: v for k, v in self.env.items() if k != 'NO_COLOR'}
        result = subprocess.run(['bash', str(ROOT / '.config/tmux/scripts/ai-account.sh')],
                                env={**env, 'TMUX': ''}, capture_output=True,
                                text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        menu = (self.home / 'menu-input').read_text()
        self.assertIn('\x1b[32m████████\x1b[0m', menu)
        plain = ANSI.sub('', menu)
        self.assertIn('use:work\tUse work (active)  ████████░░  75% left', plain)
        self.assertIn('use:personal\tUse personal       ██░░░░░░░░  25% left', plain)
        self.assertIn('Use limited        ◌ could not read quota - usage API limited', plain)
        self.assertNotIn('synthetic-', menu + result.stdout + result.stderr)

    def test_slow_menu_is_immediate_and_deduplicated(self):
        # Reads cannot finish until explicitly released. Menu opens must finish
        # while the gate is closed, with a generous outer deadlock timeout.
        self.block_reads()
        for _ in range(3):
            self.assertIn('unknown', self.run_cli('list', '--quota', timeout=5))
        self.poll(lambda: len(self.names_called()) == 4, 'menu refreshes did not start')
        self.release_reads()
        self.assertIn('75% left', self.run_cli('status'))
        self.assertEqual(sorted(self.names_called()),
                         ['codex', 'limited', 'personal', 'unknown', 'work'])

    def test_status_falls_back_after_bounded_wait(self):
        self.env['FAKE_DELAY'] = '30'
        start = time.monotonic()
        output = self.run_cli('status', timeout=25)
        self.assertLess(time.monotonic() - start, 20)
        self.assertEqual(self.section(output, '✦ Claude work (active)'), ['◌ unknown'])
        self.assertEqual(self.section(output, '◆ Codex'), ['◌ unknown'])
        # A timed-out read is not cached: once the endpoint recovers, status retries.
        self.env['FAKE_DELAY'] = '0'
        self.assertIn('75% left', self.section(self.run_cli('status'), '✦ Claude work (active)')[0])

    def test_malformed_cache_is_a_miss(self):
        self.run_cli('status')
        path = self.home / 'cache/ai-acct/claude-work.json'
        record = json.loads(path.read_text())
        path.write_text(json.dumps({'identity': record['identity'], 'time': 'x'}))
        self.block_reads()
        self.assertIn('work\tactive\t◌ unknown', self.run_cli('list', '--quota'))
        self.release_reads()
        self.assertIn('75% left', self.run_cli('status'))

    def test_expiry_rate_backoff_and_token_replacement(self):
        self.run_cli('status')
        cache = self.home / 'cache/ai-acct'
        self.block_reads()
        # Expire ordinary entries; the rate limit stays backed off until retryAfter.
        for path in cache.glob('*.json'):
            record = json.loads(path.read_text())
            path.write_text(json.dumps({**record, 'time': time.time() - 360}))
        output = self.run_cli('list', '--quota')
        self.assertIn('75% left  (stale, 6m ago)', output)
        self.release_reads()
        self.run_cli('status')
        self.assertEqual(self.names_called().count('work'), 2)
        self.assertEqual(self.names_called().count('limited'), 1)
        self.block_reads()
        (self.accounts / 'work.token').write_text('synthetic-personal')
        self.assertIn('unknown', self.run_cli('list', '--quota').splitlines()[-1])
        self.release_reads()
        work = self.section(self.run_cli('status'), '✦ Claude work (active)')
        self.assertIn('25% left', work[0])

    def test_forced_color_for_pipes_but_no_color_wins(self):
        self.run_cli('status')
        env = {k: v for k, v in self.env.items() if k != 'NO_COLOR'}
        forced = subprocess.run([str(ACCT), 'list', '--quota'], env={**env, 'AI_ACCT_COLOR': '1'},
                                capture_output=True, text=True, timeout=15).stdout
        self.assertIn('\x1b[32m', forced)
        silenced = subprocess.run([str(ACCT), 'list', '--quota'],
                                  env={**self.env, 'AI_ACCT_COLOR': '1', 'NO_COLOR': '1'},
                                  capture_output=True, text=True, timeout=15).stdout
        self.assertNotIn('\x1b', silenced)

    def test_statusline_limits_fill_in_while_usage_api_is_limited(self):
        self.run_cli('status')
        self.capture('synthetic-limited', {'five_hour': {'used_percentage': 40, 'resets_at': 4070000000},
                                           'seven_day': {'used_percentage': 90}}, age=600)
        self.assertEqual(self.listed('limited'), '█░░░░░░░░░  10% left  (via statusline, 10m ago)')
        box = self.section(self.run_cli('status'), '✦ Claude limited')
        self.assertRegex(box[0], r'^session +█{12}░{8}  60% left  ↻ \w{3} \d\d \d\d:\d\d UTC$')
        self.assertRegex(box[1], r'^week +█{2}░{18}  10% left$')
        self.assertEqual(box[2], '⟳ via statusline, 10m ago')
        self.assertEqual(len(box), 3)

    def test_fresh_usage_api_reading_beats_statusline(self):
        self.run_cli('status')
        self.capture('synthetic-work', {'five_hour': {'used_percentage': 50}})
        self.assertEqual(self.listed('work'), '████████░░  75% left')

    def test_newest_of_last_good_and_statusline_wins_with_age(self):
        self.run_cli('status')
        cache = self.home / 'cache/ai-acct/claude-work.json'
        record = json.loads(cache.read_text())
        cache.write_text(json.dumps({**record, 'time': time.time() - 3600}))
        self.block_reads()
        self.assertEqual(self.listed('work'), '████████░░  75% left  (stale, 1h ago)')
        self.capture('synthetic-work', {'five_hour': {'used_percentage': 50}}, age=300)
        self.assertEqual(self.listed('work'), '█████░░░░░  50% left  (via statusline, 5m ago)')
        self.capture('synthetic-work', {'five_hour': {'used_percentage': 50}}, age=7200)
        self.assertEqual(self.listed('work'), '████████░░  75% left  (stale, 1h ago)')

    def test_last_good_reading_survives_a_throttled_refresh(self):
        self.run_cli('status')
        cache = self.home / 'cache/ai-acct/claude-work.json'
        record = json.loads(cache.read_text())
        cache.write_text(json.dumps({**record, 'time': time.time() - 360}))
        self.env['FAKE_LIMIT'] = 'work'
        box = self.section(self.run_cli('status'), '✦ Claude work (active)')
        self.assertRegex(box[0], r'^session +█{15}░{5}  75% left')
        self.assertRegex(box[1], r'^week +█{18}░{2}  90% left')
        self.assertEqual(box[2], '⟳ stale, 6m ago')
        self.assertEqual(self.listed('work'), '████████░░  75% left  (stale, 6m ago)')
        self.assertIn('good', json.loads(cache.read_text()))

    def test_fresh_reading_without_windows_keeps_the_last_good_one(self):
        self.run_cli('status')
        cache = self.home / 'cache/ai-acct/claude-work.json'
        record = json.loads(cache.read_text())
        cache.write_text(json.dumps({**record, 'time': time.time() - 360}))
        self.env['FAKE_EMPTY'] = 'work'
        box = self.section(self.run_cli('status'), '✦ Claude work (active)')
        self.assertEqual(json.loads(cache.read_text())['quota']['windows'], [])
        self.assertRegex(box[0], r'^session +█{15}░{5}  75% left')
        self.assertEqual(box[2], '⟳ stale, 6m ago')
        self.assertEqual(self.listed('work'), '████████░░  75% left  (stale, 6m ago)')
        self.capture('synthetic-work', {'five_hour': {'used_percentage': 50}})
        self.assertEqual(self.listed('work'), '█████░░░░░  50% left  (via statusline, just now)')

    def test_statusline_windows_reset_since_capture_show_full(self):
        clock = 4_000_000_000
        self.env['AI_ACCT_NOW'] = str(clock - 3 * 3600)
        self.capture('synthetic-limited', {'five_hour': {'used_percentage': 95, 'resets_at': clock - 3600},
                                           'seven_day': {'used_percentage': 30, 'resets_at': clock + 86400}})
        path = self.home / 'cache/ai-acct/claude-limited.limits.json'
        path.write_text(json.dumps({**json.loads(path.read_text()), 'time': clock - 3 * 3600}))
        self.assertEqual(self.listed('limited'), '░░░░░░░░░░   5% left  (via statusline, just now)')
        self.env['AI_ACCT_NOW'] = str(clock)
        self.assertEqual(self.listed('limited'), '███████░░░  70% left  (via statusline, 3h ago)')
        box = self.section(self.run_cli('status'), '✦ Claude limited')
        self.assertRegex(box[0], r'^session +█{20} 100% left  ↻ reset since last reading$')
        self.assertRegex(box[1], r'^week +█{14}░{6}  70% left  ↻ ')
        self.assertEqual(box[2], '⟳ via statusline, 3h ago')

    def test_stale_windows_reset_since_reading_show_full(self):
        # The fake's session resets 2099-10-19T12:00Z and its week 2099-10-24T08:00Z.
        day = lambda d: str(dt.datetime(2099, 10, d, tzinfo=dt.timezone.utc).timestamp())
        self.env['AI_ACCT_NOW'] = day(19)
        self.run_cli('status')
        self.block_reads()
        self.env['AI_ACCT_NOW'] = day(20)
        self.assertEqual(self.listed('work'), '█████████░  90% left  (stale, 24h ago)')
        self.env['AI_ACCT_NOW'] = day(25)
        self.assertEqual(self.listed('work'), '██████████ 100% left  (stale, 6d ago)')
        self.release_reads()

    def test_statusline_capture_is_tied_to_the_token_that_made_it(self):
        self.run_cli('status')
        self.capture('synthetic-limited', {'five_hour': {'used_percentage': 40}})
        self.assertIn('60% left', self.listed('limited'))
        # Replacing the token discards what the old token reported.
        (self.accounts / 'limited.token').write_text('synthetic-replaced')
        self.assertTrue(self.listed('limited').startswith('◌ '))

    def test_statusline_ignores_unknown_tokens_and_leaks_nothing(self):
        self.capture('synthetic-inherited', {'five_hour': {'used_percentage': 40}})
        self.capture('synthetic-work', {'five_hour': {'used_percentage': 40}})
        cache = self.home / 'cache/ai-acct'
        self.assertEqual(sorted(p.name for p in cache.iterdir()), ['claude-work.limits.json'])
        path = cache / 'claude-work.limits.json'
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(cache.stat().st_mode & 0o777, 0o700)
        self.assertNotIn('synthetic-', path.read_text())
        self.assertNotIn('synthetic-', self.run_cli('status') + self.run_cli('list', '--quota'))

    def test_invalid_account_does_not_hide_others(self):
        (self.accounts / 'work.token').chmod(0o644)
        output = self.run_cli('status')
        self.assertEqual(self.section(output, '✦ Claude work (active)'), ['◌ unknown'])
        self.assertIn('25% left', self.section(output, '✦ Claude personal')[0])
        self.assertNotIn('75%', output)

    def test_invalid_selector_reports_ai_acct_error(self):
        (self.accounts / 'active').write_text('Bad')
        result = subprocess.run([str(ACCT), 'status'], env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr, 'ai-acct: Invalid active selector; use ai-acct use NAME.\n')


if __name__ == '__main__':
    unittest.main()
