"""Behavioral tests for the portable Claude and Codex status line setup."""

import json
import os
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parent.parent
INSTALLER = ROOT / ".local/bin/install-agent-statusline"
RENDERER = ROOT / ".local/bin/agent-statusline-claude"


class RendererTests(unittest.TestCase):
    def render(self, payload):
        return subprocess.run(
            [str(RENDERER)], input=json.dumps(payload), text=True,
            capture_output=True, check=False,
        )

    def test_live_context_and_effort(self):
        payload = {
            "model": {"display_name": "Sonnet 4.5"},
            "effort": {"level": "high"},
            "context_window": {
                "context_window_size": 200000,
                "used_percentage": 12.5,
                "remaining_percentage": 87.5,
                "current_usage": {
                    "input_tokens": 1000,
                    "cache_creation_input_tokens": 3000,
                    "cache_read_input_tokens": 21000,
                    "output_tokens": 500,
                },
            },
        }
        result = self.render(payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(),
                         "Sonnet 4.5 | effort high | ctx 12.5% used, 87.5% remaining | 25,000 / 200,000 input tokens")

    def test_startup_and_compaction_nulls_are_unknown(self):
        payload = {"model": {"display_name": "Opus"}, "context_window": {
            "context_window_size": 200000, "used_percentage": None,
            "remaining_percentage": None, "current_usage": None,
            "total_input_tokens": 0,
        }}
        result = self.render(payload)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(),
                         "Opus | effort n/a | ctx unknown used, unknown remaining | n/a / 200,000 input tokens")

    def test_missing_context_and_concurrent_payloads_do_not_leak(self):
        payloads = [
            {"model": {"display_name": "A"}, "effort": {"level": "low"}},
            {"model": {"display_name": "B"}, "effort": {"level": "max"},
             "context_window": {"context_window_size": 1000,
                                "used_percentage": 50,
                                "remaining_percentage": 50,
                                "current_usage": {"input_tokens": 500}}},
        ]
        with ThreadPoolExecutor(max_workers=2) as executor:
            first, second = list(executor.map(self.render, payloads))
        self.assertEqual(first.stdout.strip(),
                         "A | effort low | ctx unknown used, unknown remaining | n/a / n/a input tokens")
        self.assertEqual(second.stdout.strip(),
                         "B | effort max | ctx 50% used, 50% remaining | 500 / 1,000 input tokens")


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        (self.home / ".claude").mkdir(parents=True)
        (self.home / ".codex").mkdir()
        self.claude = self.home / ".claude/settings.json"
        self.codex = self.home / ".codex/config.toml"
        self.claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": []}]},
                                           "model": "opus"}))
        self.codex.write_text('model = "gpt-6-astra"\n[features]\nhooks = true\n[tui]\nshow_tooltips = false\n')

    def install(self, *args):
        return subprocess.run([str(INSTALLER), "--home", str(self.home), *args],
                              text=True, capture_output=True, check=False,
                              env={**os.environ, "HOME": "/wrong/home"})

    def test_check_apply_idempotence_and_unrelated_settings(self):
        before = (self.claude.read_bytes(), self.codex.read_bytes())
        check = self.install("--check")
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(json.loads(check.stdout), {"changed": True, "changes": ["claude", "codex"]})
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), before)
        applied = self.install()
        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertEqual(json.loads(applied.stdout), {"changed": True, "changes": ["claude", "codex"]})
        data = json.loads(self.claude.read_text())
        self.assertEqual(data["model"], "opus")
        self.assertEqual(data["hooks"], {"Stop": [{"hooks": []}]})
        self.assertEqual(data["statusLine"]["type"], "command")
        self.assertIn("$HOME", data["statusLine"]["command"])
        config = tomllib.loads(self.codex.read_text())
        self.assertEqual(config["model"], "gpt-6-astra")
        self.assertEqual(config["features"], {"hooks": True})
        self.assertEqual(config["tui"]["show_tooltips"], False)
        self.assertEqual(config["tui"]["status_line"],
                         ["model-with-reasoning", "context-used", "context-remaining", "context-window-size"])
        after = (self.claude.read_bytes(), self.codex.read_bytes())
        again = self.install()
        self.assertEqual(json.loads(again.stdout), {"changed": False, "changes": []})
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), after)

    def test_invalid_config_fails_without_partial_write(self):
        self.codex.write_text("[tui\n")
        before = (self.claude.read_bytes(), self.codex.read_bytes())
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), before)

    def test_existing_multiline_codex_status_line_is_replaced_only_once(self):
        self.codex.write_text('''model = "gpt-6-astra"
[tui]
show_tooltips = false
status_line = [
  "current-dir",
  "git-branch",
]
[features]
hooks = true
''')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = tomllib.loads(self.codex.read_text())
        self.assertEqual(data['tui']['status_line'],
                         ['model-with-reasoning', 'context-used', 'context-remaining', 'context-window-size'])
        self.assertEqual(data['features']['hooks'], True)
        self.assertEqual(data['tui']['show_tooltips'], False)

    def test_existing_symlink_is_not_replaced(self):
        outside = Path(self.tmp.name) / 'external-settings.json'
        outside.write_text('{"theme":"dark"}')
        self.claude.unlink()
        self.claude.symlink_to(outside)
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.claude.is_symlink())
        self.assertEqual(outside.read_text(), '{"theme":"dark"}')

    def test_explicit_home_works_without_home_environment(self):
        env = {key: value for key, value in os.environ.items() if key != 'HOME'}
        result = subprocess.run([str(INSTALLER), '--home', str(self.home), '--check'],
                                env=env, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['changes'], ['claude', 'codex'])

    def test_empty_existing_claude_settings_fail_closed(self):
        self.claude.write_text('')
        before = self.codex.read_bytes()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.claude.read_text(), '')
        self.assertEqual(self.codex.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
