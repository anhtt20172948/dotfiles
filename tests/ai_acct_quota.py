"""Exercise the real CLI with synthetic credentials and an offline quota binary."""
import json
import os
import pty
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
ACCT = ROOT / '.local/bin/ai-acct'


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
time.sleep(float(os.environ.get('FAKE_DELAY', '0')))
p = {'provider': provider, 'state': {'status': 'fresh', 'stale': False}, 'windows': []}
if name == 'limited':
    p['state'] = {'status': 'rate_limited', 'stale': False, 'retryAfter': '2099-10-19T12:30:00Z'}
if name not in ('limited', 'unknown'):
    p['windows'] = [{'id': 'session', 'label': 'session', 'kind': 'session', 'percentRemaining': 75 if name == 'work' else 25, 'resetsAt': '2099-10-19T12:00:00Z'}]
if name == 'work':
    p['windows'].append({'id': 'week', 'label': 'week', 'kind': 'weekly', 'percentRemaining': 90, 'resetsAt': '2099-10-24T08:00:00Z'})
    p['quotaSemantics'] = {'effectiveAvailability': [{'scope': 'all_models', 'status': 'known', 'effectivePercentRemaining': 75, 'limitingWindowIds': ['session']}]}
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
                    'PATH': str(bindir) + ':' + os.environ['PATH'],
                    'CLAUDE_CODE_OAUTH_TOKEN': 'synthetic-inherited',
                    'ANTHROPIC_API_KEY': 'synthetic-api',
                    'CLAUDE_CONFIG_DIR': '/wrong',
                    'QUOTA_AXI_CLAUDE_PROFILES': '/wrong', 'TZ': 'UTC'}

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
        lines = output.splitlines()
        start = lines.index(title)
        end = next((i for i in range(start + 1, len(lines)) if not lines[i].startswith(' ')), len(lines))
        return lines[start + 1:end]

    def test_status_waits_and_shows_every_window(self):
        output = self.run_cli('status')
        work = self.section(output, '✦ Claude work (active)')
        self.assertEqual(len(work), 2)
        self.assertRegex(work[0], r'^    session +█{8}░{2}  75% left  ↻ Oct 19 12:00 UTC$')
        self.assertRegex(work[1], r'^    week +█{9}░  90% left  ↻ Oct 24 08:00 UTC$')
        self.assertIn('25% left', self.section(output, '✦ Claude personal')[0])
        self.assertEqual(self.section(output, '✦ Claude limited'),
                         ['    ◌ rate-limited (retry after Oct 19 12:30 UTC)'])
        self.assertEqual(self.section(output, '✦ Claude unknown'),
                         ['    session          █████████░  90% left'])
        self.assertIn('25% left', self.section(output, '◆ Codex')[0])
        self.assertEqual(output.count('Codex'), 1)
        self.assertEqual(sorted(self.names_called()),
                         ['codex', 'limited', 'personal', 'unknown', 'work'])
        for _ in range(3):
            listing = self.run_cli('list', '--quota')
            self.assertIn('work\tactive\t████████░░  75% left\n', listing)
            self.assertIn('limited\t\t◌ rate-limited (retry after Oct 19 12:30 UTC)\n', listing)
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
                output = os.read(master, 8192).decode()
                self.assertEqual('\x1b[' in output, not no_color)
                self.assertNotIn('synthetic-', output)
            finally:
                os.close(master)
                os.close(slave)

    def test_real_fzf_menu_uses_cached_bars(self):
        self.run_cli('status')
        (self.home / 'bin/ai-acct').symlink_to(ACCT)
        fzf = self.home / 'bin/fzf'
        fzf.write_text('#!/bin/sh\ncat > "$HOME/menu-input"\nexit 130\n')
        fzf.chmod(0o700)
        result = subprocess.run(['bash', str(ROOT / '.config/tmux/scripts/ai-account.sh')],
                                env={**self.env, 'TMUX': ''}, capture_output=True,
                                text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        menu = (self.home / 'menu-input').read_text()
        self.assertIn('Use work (active)  ████████░░  75% left', menu)
        self.assertIn('rate-limited', menu)
        self.assertNotIn('synthetic-', menu + result.stdout + result.stderr)

    def test_slow_menu_is_immediate_and_deduplicated(self):
        delay = 3
        self.env['FAKE_DELAY'] = str(delay)
        start = time.monotonic()
        for _ in range(3):
            self.assertIn('unknown', self.run_cli('list', '--quota'))
        self.assertLess(time.monotonic() - start, delay)
        self.poll(lambda: len(self.names_called()) == 4, 'menu refreshes did not start')
        self.assertIn('75% left', self.run_cli('status'))
        self.assertEqual(sorted(self.names_called()),
                         ['codex', 'limited', 'personal', 'unknown', 'work'])

    def test_status_falls_back_after_bounded_wait(self):
        self.env['FAKE_DELAY'] = '30'
        start = time.monotonic()
        output = self.run_cli('status', timeout=25)
        self.assertLess(time.monotonic() - start, 20)
        self.assertEqual(self.section(output, '✦ Claude work (active)'), ['    ◌ unknown'])
        self.assertEqual(self.section(output, '◆ Codex'), ['    ◌ unknown'])

    def test_malformed_cache_is_a_miss(self):
        self.run_cli('status')
        path = self.home / 'cache/ai-acct/claude-work.json'
        record = json.loads(path.read_text())
        path.write_text(json.dumps({'identity': record['identity'], 'time': 'x'}))
        self.assertIn('work\tactive\t◌ unknown', self.run_cli('list', '--quota'))
        self.assertIn('75% left', self.run_cli('status'))

    def test_expiry_rate_backoff_and_token_replacement(self):
        self.run_cli('status')
        cache = self.home / 'cache/ai-acct'
        # Expire ordinary entries; the rate limit stays backed off until retryAfter.
        for path in cache.glob('*.json'):
            record = json.loads(path.read_text())
            path.write_text(json.dumps({**record, 'time': time.time() - 360}))
        output = self.run_cli('list', '--quota')
        self.assertIn('(stale)', output)
        self.poll(lambda: self.names_called().count('work') == 2, 'stale entry was not refreshed')
        self.assertEqual(self.names_called().count('limited'), 1)
        (self.accounts / 'work.token').write_text('synthetic-personal')
        self.assertIn('unknown', self.run_cli('list', '--quota').splitlines()[-1])
        work = self.section(self.run_cli('status'), '✦ Claude work (active)')
        self.assertIn('25% left', work[0])

    def test_invalid_account_does_not_hide_others(self):
        (self.accounts / 'work.token').chmod(0o644)
        output = self.run_cli('status')
        self.assertEqual(self.section(output, '✦ Claude work (active)'), ['    ◌ unknown'])
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
