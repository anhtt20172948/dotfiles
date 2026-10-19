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
CODEX_ITEMS = ["model-with-reasoning", "context-used", "context-remaining", "context-window-size",
               "five-hour-limit", "weekly-limit", "total-input-tokens", "total-output-tokens"]


def assistant(message_id, usage):
    return json.dumps({"type": "assistant", "message": {"id": message_id, "usage": usage}})


class RendererTests(unittest.TestCase):
    def render(self, payload):
        return subprocess.run(
            [str(RENDERER)], input=json.dumps(payload), text=True,
            capture_output=True, check=False,
            env={**os.environ, "TZ": "UTC"},
        )

    def transcript(self, *lines):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "session.jsonl"
        path.write_text("\n".join(lines) + "\n")
        return str(path)

    def test_rate_limits_session_totals_and_throughput(self):
        transcript = self.transcript(
            assistant("m1", {"input_tokens": 10, "cache_creation_input_tokens": 990,
                             "cache_read_input_tokens": 0, "output_tokens": 5}),
            assistant("m1", {"input_tokens": 10, "cache_creation_input_tokens": 990,
                             "cache_read_input_tokens": 0, "output_tokens": 200}),
            assistant("m2", {"input_tokens": 20, "cache_creation_input_tokens": 0,
                             "cache_read_input_tokens": 1980, "output_tokens": 300}),
            json.dumps({"type": "user", "message": {"content": "hi"}}),
        )
        result = self.render({
            "model": {"display_name": "Opus"},
            "transcript_path": transcript,
            "cost": {"total_api_duration_ms": 10000},
            "rate_limits": {
                "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
                "seven_day": {"used_percentage": 41.2, "resets_at": 1738857600},
            },
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "Opus | ctx unknown used, unknown remaining | 5h 24% (resets 16:00) | "
            "7d 41% (resets Thu 16:00) | session 3k in, 500 out | avg 300/s in, 50/s out")

    def test_absent_rate_limits_and_transcript_are_omitted(self):
        result = self.render({
            "model": {"display_name": "Opus"},
            "transcript_path": "/nonexistent/session.jsonl",
            "cost": {"total_api_duration_ms": 10000},
            "rate_limits": {"five_hour": {"resets_at": 1738425600}, "seven_day": None},
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Opus | ctx unknown used, unknown remaining")

    def test_weekly_limit_alone_and_zero_api_duration_has_no_rate(self):
        transcript = self.transcript(assistant("m1", {"input_tokens": 1500, "output_tokens": 2500}))
        result = self.render({
            "model": {"display_name": "Opus"},
            "transcript_path": transcript,
            "cost": {"total_api_duration_ms": 0},
            "rate_limits": {"seven_day": {"used_percentage": 5, "resets_at": 1738857600}},
        })
        self.assertEqual(
            result.stdout.strip(),
            "Opus | ctx unknown used, unknown remaining | 7d 5% (resets Thu 16:00) | "
            "session 1.5k in, 2.5k out")

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
                         "Opus | ctx unknown used, unknown remaining")

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
                         "A | effort low | ctx unknown used, unknown remaining")
        self.assertEqual(second.stdout.strip(),
                         "B | effort max | ctx 50% used, 50% remaining | 500 / 1,000 input tokens")


class CaptureTests(unittest.TestCase):
    """The statusline records rate limits for the account its process runs as."""

    LIMITS = {"five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
              "seven_day": {"used_percentage": 41, "resets_at": 1738857600}}

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        accounts = self.home / ".config/claude-accounts"
        accounts.mkdir(parents=True)
        for name in ("work", "personal"):
            (accounts / f"{name}.token").write_text(f"synthetic-{name}\n")
        self.cache = self.home / "cache/ai-acct"
        self.env = {**os.environ, "HOME": str(self.home), "TZ": "UTC",
                    "XDG_CACHE_HOME": str(self.home / "cache")}
        self.env.pop("CLAUDE_CODE_OAUTH_TOKEN", None)

    def run_line(self, rate_limits, account="work", **env):
        payload = {"model": {"display_name": "Opus"}, "rate_limits": rate_limits}
        env = {**self.env, **env}
        if account is not None:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = "synthetic-" + account
        result = subprocess.run([str(RENDERER)], input=json.dumps(payload), text=True,
                                capture_output=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("synthetic-", result.stdout + result.stderr)
        return result.stdout.strip()

    def test_records_both_windows_for_the_matching_account_privately(self):
        line = self.run_line(self.LIMITS)
        self.assertIn("5h 24%", line)
        path = self.cache / "claude-work.limits.json"
        record = json.loads(path.read_text())
        self.assertEqual(record["windows"], {
            "five_hour": {"used": 23.5, "resets_at": 1738425600},
            "seven_day": {"used": 41, "resets_at": 1738857600}})
        self.assertRegex(record["fingerprint"], r"^[0-9a-f]{64}$")
        self.assertGreater(record["time"], 0)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.cache.stat().st_mode & 0o777, 0o700)
        self.assertEqual([p.name for p in self.cache.iterdir()], ["claude-work.limits.json"])
        self.assertNotIn("synthetic-", path.read_text())

    def test_picks_the_account_of_this_process_not_the_selector(self):
        (self.home / ".config/claude-accounts/active").write_text("work\n")
        self.run_line({"seven_day": {"used_percentage": 5}}, account="personal")
        self.assertEqual([p.name for p in self.cache.iterdir()], ["claude-personal.limits.json"])
        record = json.loads((self.cache / "claude-personal.limits.json").read_text())
        self.assertEqual(record["windows"], {"seven_day": {"used": 5, "resets_at": None}})

    def test_nothing_is_written_without_a_matching_token_or_valid_limits(self):
        self.run_line(self.LIMITS, account=None)
        self.run_line(self.LIMITS, account="stranger")
        self.run_line({"five_hour": {"resets_at": 1}, "seven_day": {"used_percentage": 101}})
        self.run_line(None)
        self.assertFalse(self.cache.exists())

    def test_capture_failure_never_changes_the_status_line(self):
        expected = self.run_line(self.LIMITS)
        blocker = self.home / "blocker"
        blocker.write_text("not a directory")
        self.assertEqual(self.run_line(self.LIMITS, XDG_CACHE_HOME=str(blocker)), expected)


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
                         CODEX_ITEMS)
        after = (self.claude.read_bytes(), self.codex.read_bytes())
        again = self.install()
        self.assertEqual(json.loads(again.stdout), {"changed": False, "changes": []})
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), after)

    def test_context_settings_merge_preserves_model_effort_and_environment(self):
        original = {"model": "opus[1m]", "effortLevel": "max",
                    "env": {"OTHER_VAR": "keep", "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "90"}}
        self.claude.write_text(json.dumps(original))
        self.codex.write_text('''# private settings
model = "gpt-6-astra"
model_reasoning_effort = "high"
model_context_window = 272000 # previous window
"model_auto_compact_token_limit" = 200000
[profiles.private]
model_context_window = 100000
[tui]
show_tooltips = false
''')
        before = (self.claude.read_bytes(), self.codex.read_bytes())
        preview = self.install("--check")
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), before)
        applied = self.install()
        self.assertEqual(applied.returncode, 0, applied.stderr)
        claude = json.loads(self.claude.read_text())
        self.assertEqual(claude["env"], {"OTHER_VAR": "keep",
                         "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "60",
                         "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"})
        self.assertEqual(claude["model"], original["model"])
        self.assertEqual(claude["effortLevel"], original["effortLevel"])
        codex = tomllib.loads(self.codex.read_text())
        self.assertEqual(codex["model_context_window"], 872000)
        self.assertEqual(codex["model_auto_compact_token_limit"], 523200)
        self.assertEqual(codex["model"], "gpt-6-astra")
        self.assertEqual(codex["model_reasoning_effort"], "high")
        self.assertEqual(codex["profiles"]["private"], {"model_context_window": 100000})
        self.assertIn("# private settings", self.codex.read_text())
        self.assertFalse(json.loads(self.install().stdout)["changed"])

    def test_missing_settings_get_global_context_defaults(self):
        self.claude.unlink()
        self.codex.unlink()
        self.assertEqual(self.install().returncode, 0)
        claude = json.loads(self.claude.read_text())
        self.assertEqual(claude["env"]["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"], "60")
        self.assertEqual(claude["env"]["CLAUDE_CODE_AUTO_COMPACT_WINDOW"], "1000000")
        self.assertNotIn("model", claude)
        codex = tomllib.loads(self.codex.read_text())
        self.assertEqual(codex["model_context_window"], 872000)
        self.assertEqual(codex["model_auto_compact_token_limit"], 523200)
        self.assertNotIn("model", codex)

    def test_invalid_claude_environment_fails_without_writes(self):
        self.claude.write_text('{"env": []}')
        before = (self.claude.read_bytes(), self.codex.read_bytes())
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.claude.read_bytes(), self.codex.read_bytes()), before)

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
                         CODEX_ITEMS)
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
