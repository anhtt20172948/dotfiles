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
p = {'provider': provider, 'status': 'rate_limited' if name == 'limited' else 'fresh', 'windows': []}
if name not in ('limited', 'unknown'):
    p['windows'] = [{'id': 'session', 'kind': 'session', 'percentRemaining': 75 if name == 'work' else 25, 'resetsAt': '2099-10-19T12:00:00Z'}]
if name == 'work':
    p['quotaSemantics'] = {'effectiveAvailability': [{'scope': 'all_models', 'status': 'known', 'effectivePercentRemaining': 75, 'limitingWindowIds': ['session']}]}
if name == 'unknown':
    p['windows'] = [{'kind': 'session', 'percentRemaining': 90}]
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
                    'QUOTA_AXI_CLAUDE_PROFILES': '/wrong'}

    def run_cli(self, *args):
        result = subprocess.run([str(ACCT), *args], env=self.env,
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('synthetic-', result.stdout + result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        return result.stdout

    def wait_for(self, text):
        for _ in range(100):
            output = self.run_cli('status')
            if text in output and len(list((self.home / 'cache/ai-acct').glob('*.json'))) == 5:
                return output
            time.sleep(.05)
        self.fail('background quota refresh did not complete')

    def test_account_isolation_rendering_and_cache(self):
        self.run_cli('status')
        output = self.wait_for('75%')
        self.assertIn('work (active)', output)
        self.assertIn('personal', output)
        self.assertIn('25%', output)
        self.assertIn('█', output)
        self.assertIn('reset', output)
        self.assertIn('rate-limited', output)
        self.assertIn('unknown', output)
        self.assertNotIn('█', next(line for line in output.splitlines() if 'unknown ' in line))
        self.assertNotIn('█', next(line for line in output.splitlines() if 'limited ' in line))
        self.assertEqual(output.count('Codex'), 1)
        calls = self.home / 'calls'
        records = [json.loads(line) for line in calls.read_text().splitlines()]
        self.assertEqual(sorted(r['name'] for r in records),
                         ['codex', 'limited', 'personal', 'unknown', 'work'])
        for _ in range(3):
            listing = self.run_cli('list', '--quota')
            self.assertIn('work\tactive\t', listing)
            self.assertIn('75%', listing)
        time.sleep(.15)
        self.assertEqual(len(calls.read_text().splitlines()), 5)
        for path in (self.home / 'cache/ai-acct').rglob('*'):
            if path.is_file():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertNotIn('synthetic-', path.read_text())
        self.assertEqual((self.home / 'cache/ai-acct').stat().st_mode & 0o777, 0o700)

    def test_terminal_colors_and_no_color(self):
        self.wait_for('75%')
        for no_color in (False, True):
            master, slave = pty.openpty()
            try:
                env = {k: v for k, v in self.env.items() if k != 'NO_COLOR'}
                if no_color:
                    env['NO_COLOR'] = '1'
                result = subprocess.run([str(ACCT), 'status'], env=env, stdout=slave,
                                        stderr=subprocess.PIPE, timeout=3)
                self.assertEqual(result.returncode, 0)
                output = os.read(master, 8192).decode()
                self.assertEqual('\x1b[' in output, not no_color)
                self.assertNotIn('synthetic-', output)
            finally:
                os.close(master)
                os.close(slave)

    def test_real_fzf_menu_uses_cached_bars(self):
        self.wait_for('75%')
        (self.home / 'bin/ai-acct').symlink_to(ACCT)
        fzf = self.home / 'bin/fzf'
        fzf.write_text('#!/bin/sh\ncat > "$HOME/menu-input"\nexit 130\n')
        fzf.chmod(0o700)
        result = subprocess.run(['bash', str(ROOT / '.config/tmux/scripts/ai-account.sh')],
                                env={**self.env, 'TMUX': ''}, capture_output=True,
                                text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        menu = (self.home / 'menu-input').read_text()
        self.assertIn('Use work (active)  █', menu)
        self.assertIn('75%', menu)
        self.assertIn('rate-limited', menu)
        self.assertNotIn('synthetic-', menu + result.stdout + result.stderr)

    def test_slow_menu_is_immediate_and_deduplicated(self):
        self.env['FAKE_DELAY'] = '.6'
        start = time.monotonic()
        for _ in range(3):
            self.assertIn('unknown', self.run_cli('list', '--quota'))
        self.assertLess(time.monotonic() - start, .6)
        self.wait_for('75%')

    def test_expiry_rate_backoff_and_token_replacement(self):
        self.wait_for('75%')
        cache = self.home / 'cache/ai-acct'
        # Expire ordinary entries, but a rate limit remains backed off at 6m.
        for path in cache.glob('*.json'):
            record = json.loads(path.read_text())
            path.write_text(json.dumps({**record, 'time': time.time() - 360}))
        output = self.run_cli('list', '--quota')
        self.assertIn('(stale)', output)
        time.sleep(.3)
        calls = [json.loads(line)['name'] for line in (self.home / 'calls').read_text().splitlines()]
        self.assertEqual(calls.count('limited'), 1)
        self.assertEqual(calls.count('work'), 2)
        (self.accounts / 'work.token').write_text('synthetic-personal')
        output = self.run_cli('status')
        work = next(line for line in output.splitlines() if 'work (active)' in line)
        self.assertIn('unknown', work)
        for _ in range(100):
            output = self.run_cli('status')
            work = next(line for line in output.splitlines() if 'work (active)' in line)
            if '25%' in work:
                break
            time.sleep(.05)
        self.assertIn('25%', work)

    def test_invalid_account_does_not_hide_others(self):
        (self.accounts / 'work.token').chmod(0o644)
        output = self.wait_for('25%')
        self.assertIn('work (active)', output)
        self.assertIn('unknown', output)
        self.assertNotIn('75%', output)


if __name__ == '__main__':
    unittest.main()
