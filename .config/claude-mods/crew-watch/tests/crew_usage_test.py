"""Bounded incremental telemetry; no real homes or transcripts are read."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "crew_usage", Path(__file__).parents[1] / "scripts" / "crew_usage.py"
)
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)


class TelemetryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "log.jsonl"

    def append(self, row, newline=True):
        with self.path.open("a") as stream:
            stream.write(json.dumps(row) + ("\n" if newline else ""))

    def test_codex_window_events_and_repeat_usage_are_incremental(self):
        self.append({"type": "turn_context", "payload": {"model": "gpt-test"}})
        count = {"type": "event_msg", "timestamp": "2026-10-21T17:00:00Z", "payload": {
            "type": "token_count", "info": {"model_context_window": 200000,
            "total_token_usage": {"input_tokens": 200, "cached_input_tokens": 100, "total_tokens": 220, "output_tokens": 20},
            "last_token_usage": {"input_tokens": 200}}}}
        self.append(count)
        self.append(count)
        self.append({"type": "response_item", "timestamp": "2026-10-21T17:00:01Z", "payload": {
            "type": "function_call", "name": "exec_command", "arguments": '{"cmd":"pwd"}'}})
        entry = usage.fresh_entry()
        usage.parse_codex(self.path, entry)
        self.assertEqual(entry["agg"]["contextWindow"], 200000)
        self.assertEqual(entry["agg"]["requests"], 1)
        self.assertEqual(entry["agg"]["events"][0]["text"], "exec_command: pwd")
        saved = json.loads(json.dumps(entry))
        usage.parse_codex(self.path, entry)
        self.assertEqual(entry, saved)

    def test_claude_partial_lines_and_bounded_history(self):
        entry = usage.fresh_entry()
        for minute in range(70):
            self.append({"type": "assistant", "timestamp": f"2026-10-21T{16 + minute // 60:02}:{minute % 60:02}:00Z",
                "message": {"id": f"m{minute}", "model": "claude-test", "usage": {"input_tokens": 10},
                "content": [{"type": "tool_use", "name": "Read", "input": {"path": f"/file/{minute}"}}]}})
        partial = {"type": "assistant", "timestamp": "2026-10-21T17:11:00Z", "message": {
            "id": "partial", "model": "claude-test", "content": [{"type": "text", "text": "finished"}]}}
        self.append(partial, newline=False)
        usage.parse_claude(self.path, entry)
        self.assertEqual(entry["agg"]["requests"], 70)
        self.assertEqual(len(entry["agg"]["events"]), 10)
        self.assertLessEqual(len(entry["agg"]["activity"]), 60)
        self.assertIsNone(entry["agg"]["contextWindow"])
        with self.path.open("a") as stream:
            stream.write("\n")
        usage.parse_claude(self.path, entry)
        self.assertEqual(entry["agg"]["requests"], 71)
        self.assertEqual(entry["agg"]["lastText"], "finished")

    def test_status_history_uses_recorded_times_and_is_bounded(self):
        self.path.write_text("".join(f"working [at={1000 + n}]: event {n}\n" for n in range(20)))
        events = usage.status_events(self.path)
        self.assertEqual(len(events), 10)
        self.assertEqual(events[-1], {"at": 1019000, "kind": "status", "text": "working [at=1019]: event 19"})

    def test_report_follows_nested_homes_and_reuses_cache_without_double_counting(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        second = root / "second"
        (fm / "state").mkdir(parents=True)
        (second / "state").mkdir(parents=True)
        (fm / "state" / "lead.meta").write_text(f"kind=secondmate\nworktree={second}\nharness=claude\n")
        worktree = str(root / "worktree")
        (second / "state" / "child.meta").write_text(f"harness=claude\nworktree={worktree}\nbranch=fm/child\n")
        (second / "state" / "child.status").write_text("working [at=1792602000]: parsing\n")
        with patch.object(usage, "CLAUDE_PROJECTS", str(root / "projects")), patch.object(
            usage, "CACHE_PATH", str(root / "cache" / "cache.json")
        ), patch.object(usage.sys, "argv", ["crew_usage.py", "--home", str(fm)]):
            transcript = Path(usage.claude_project_dir(worktree)) / "session.jsonl"
            transcript.parent.mkdir(parents=True)
            transcript.write_text(json.dumps({"type": "assistant", "timestamp": "2026-10-21T17:00:00Z", "message": {
                "id": "one", "model": "claude-test", "usage": {"input_tokens": 10},
                "content": [{"type": "tool_use", "name": "Read", "input": {"path": worktree + "/src/main.py"}}]}}) + "\n")
            reports = []
            for _ in range(2):
                with redirect_stdout(io.StringIO()) as output:
                    usage.main()
                reports.append(json.loads(output.getvalue()))
            self.assertEqual(reports[0]["totals"], reports[1]["totals"])
            child = reports[1]["crew"][1]
            self.assertEqual(child["depth"], 1)
            self.assertEqual(child["tools"], {"Read": 1})
            self.assertEqual(child["lastTool"], "Read: src/main.py")
            self.assertEqual(child["recentTools"][0]["text"], "Read: src/main.py")
            self.assertEqual([event["kind"] for event in child["events"]], ["tool", "status"])
            self.assertEqual(reports[1]["totals"]["toolCalls"], 1)
            self.assertIsNone(child["contextWindow"])
            self.assertEqual(reports[1]["errors"], [])

    def test_truncated_transcript_resets_new_telemetry(self):
        self.append({"type": "assistant", "timestamp": "2026-10-21T17:00:00Z", "message": {
            "id": "one", "usage": {"input_tokens": 10}, "content": [{"type": "tool_use", "name": "Read"}]}})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry)
        self.path.write_text(json.dumps({"type": "assistant", "message": {"id": "two", "content": []}}) + "\n")
        usage.parse_claude(self.path, entry)
        self.assertEqual(entry["agg"]["events"], [])
        self.assertEqual(entry["agg"]["requests"], 1)

    def test_codex_wrappers_show_the_real_command_without_evaluating_js(self):
        wrappers = [
            'text(await tools.exec_command({cmd: "git status", workdir: "/repo"}));',
            'text(await tools.exec_command({"cmd": "git status"}));',
            "text(await tools.exec_command({'cmd': 'git status'}));",
        ]
        for wrapper in wrappers:
            self.assertEqual(usage.describe_tool("exec", wrapper), "exec: git status")
        self.assertEqual(usage.describe_tool("exec", {"code": wrappers[0]}), "exec: git status")
        command = 'echo "hello"'
        wrapper = 'text(await tools.exec_command({cmd: ' + json.dumps(command) + '}));'
        self.assertEqual(usage.describe_tool("exec", wrapper), 'exec: echo "hello"')

    def test_codex_wrapper_events_are_abbreviated_before_being_cached(self):
        command = "cd /pool/own && git status"
        wrapper = 'text(await tools.exec_command({cmd: ' + json.dumps(command) + '}));'
        self.append({"type": "response_item", "timestamp": "2026-10-21T17:00:00Z", "payload": {
            "type": "custom_tool_call", "name": "exec", "input": wrapper}})
        entry = usage.fresh_entry()
        usage.parse_codex(self.path, entry, "/pool/own")
        self.assertEqual(entry["agg"]["lastTool"], "exec: git status")
        self.assertEqual(entry["agg"]["events"][0]["text"], "exec: git status")

    def test_tool_paths_and_leading_cd_are_relative_only_to_the_own_worktree(self):
        home = "/pool/my worktree"
        for lead in (f"cd '{home}' && ", f'cd "{home}"; '):
            self.assertEqual(usage.describe_tool("Bash", {"command": lead + "git status"}, home), "Bash: git status")
        self.assertEqual(usage.describe_tool("Read", {"file_path": home + "/src/main.py"}, home), "Read: src/main.py")
        self.assertEqual(usage.describe_tool("Bash", {"command": f'git -C "{home}" status'}, home), 'Bash: git -C "." status')
        self.assertEqual(usage.describe_tool("Bash", {"command": "cd /elsewhere && pwd"}, home), "Bash: cd /elsewhere && pwd")
        self.assertEqual(usage.describe_tool("Read", {"path": "/pool/my worktree-other/file"}, home), "Read: /pool/my worktree-other/file")
        self.assertEqual(usage.describe_tool("Read", {"path": "/other/pool/my worktree/file"}, home), "Read: /other/pool/my worktree/file")
        long_home = "/pool/" + "x" * 200
        self.assertEqual(usage.describe_tool("Bash", {"command": f"cd {long_home} && git status"}, long_home), "Bash: git status")


if __name__ == "__main__":
    unittest.main()
