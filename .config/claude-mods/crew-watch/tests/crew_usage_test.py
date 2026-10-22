"""Bounded incremental telemetry; no real homes or transcripts are read."""
from contextlib import redirect_stdout
from datetime import datetime, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "crew_usage", Path(__file__).parents[1] / "scripts" / "crew_usage.py"
)
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)


def ts_of(stamp):
    return int(datetime.fromisoformat(stamp).timestamp() * 1000)


class TelemetryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "log.jsonl"
        # Never read the real account, quota cache or session logs.
        home = Path(self.tmp.name) / "home"
        for name, value in (("HOME", str(home)), ("CLAUDE_PROJECTS", str(home / ".claude" / "projects")),
                            ("CODEX_SESSIONS", str(home / ".codex" / "sessions"))):
            patcher = patch.object(usage, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        env = patch.dict(os.environ, {"XDG_CACHE_HOME": str(home / ".cache")})
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("CLAUDE_CONFIG_DIR", None)

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
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["requests"], 70)
        self.assertEqual(len(entry["agg"]["events"]), 10)
        self.assertLessEqual(len(entry["agg"]["activity"]), 60)
        self.assertIsNone(entry["agg"]["contextWindow"])
        with self.path.open("a") as stream:
            stream.write("\n")
        usage.parse_claude(self.path, entry, {})
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

    def report(self, *homes):
        with redirect_stdout(io.StringIO()) as output:
            with patch.object(usage.sys, "argv", ["crew_usage.py", *[a for h in homes for a in ("--home", str(h))]]):
                usage.main()
        return json.loads(output.getvalue())

    def claude_turn(self, path, mid, model, at="2026-10-21T17:00:00Z"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"type": "assistant", "timestamp": at, "message": {
            "id": mid, "model": model, "usage": {"input_tokens": 10},
            "content": [{"type": "tool_use", "name": "Read", "input": {"path": "/x"}}]}}) + "\n")

    def codex_rollout(self, path, cwd, tokens):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(row) + "\n" for row in [
            {"type": "session_meta", "payload": {"cwd": cwd}},
            {"type": "event_msg", "timestamp": "2026-10-21T17:00:00Z", "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": tokens, "total_tokens": tokens}, "last_token_usage": {"input_tokens": tokens}}}},
        ]))

    def test_reused_worktree_slot_reports_only_logs_written_since_spawn(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        spawned = int(usage.time.time()) - 60
        claude_slot, codex_slot = str(root / "slot1"), str(root / "slot2")
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={claude_slot}\nspawn_gen=s{spawned}.1.2\n")
        (fm / "state" / "b.meta").write_text(f"harness=codex\nworktree={codex_slot}\nspawn_gen=s{spawned}.3.4\n")
        with patch.object(usage, "CLAUDE_PROJECTS", str(root / "projects")), patch.object(
            usage, "CODEX_SESSIONS", str(root / "sessions")
        ), patch.object(usage, "CACHE_PATH", str(root / "cache" / "cache.json")):
            project = Path(usage.claude_project_dir(claude_slot))
            self.claude_turn(project / "previous.jsonl", "old", "claude-old")
            self.claude_turn(project / "previous" / "subagents" / "agent.jsonl", "older", "claude-old")
            self.claude_turn(project / "current.jsonl", "new", "claude-new")
            self.codex_rollout(root / "sessions" / "rollout-previous.jsonl", codex_slot, 5000)
            self.codex_rollout(root / "sessions" / "rollout-current.jsonl", codex_slot, 30)
            for old in (project / "previous.jsonl", project / "previous" / "subagents" / "agent.jsonl",
                        root / "sessions" / "rollout-previous.jsonl"):
                os.utime(old, (spawned - 3600, spawned - 3600))
            crew = {m["id"]: m for m in self.report(fm)["crew"]}
        self.assertEqual((crew["a"]["models"], crew["a"]["toolCalls"], crew["a"]["sessions"]), ({"claude-new": 1}, 1, 1))
        self.assertEqual((crew["b"]["input"], crew["b"]["requests"], crew["b"]["sessions"]), (30, 1, 1))

    def test_relaunch_keeps_usage_from_the_first_incarnation(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        now = int(usage.time.time())
        claude_slot, codex_slot = str(root / "slot1"), str(root / "slot2")
        for tid, harness, slot in (("a", "claude", claude_slot), ("b", "codex", codex_slot)):
            (fm / "state" / f"{tid}.meta").write_text(f"harness={harness}\nworktree={slot}\nspawn_gen=s{now - 60}.1.2\n")
            (fm / "state" / f"{tid}.status").write_text(
                f"working [at={now - 7200}]: started\nworking [at={now - 30}]: relaunched with new effort\n")
        with patch.object(usage, "CLAUDE_PROJECTS", str(root / "projects")), patch.object(
            usage, "CODEX_SESSIONS", str(root / "sessions")
        ), patch.object(usage, "CACHE_PATH", str(root / "cache" / "cache.json")):
            project = Path(usage.claude_project_dir(claude_slot))
            self.claude_turn(project / "other-task.jsonl", "other", "claude-other")
            self.claude_turn(project / "first.jsonl", "first", "claude-first")
            self.claude_turn(project / "relaunched.jsonl", "second", "claude-second")
            self.codex_rollout(root / "sessions" / "rollout-other-task.jsonl", codex_slot, 5000)
            self.codex_rollout(root / "sessions" / "rollout-first.jsonl", codex_slot, 200)
            self.codex_rollout(root / "sessions" / "rollout-relaunched.jsonl", codex_slot, 30)
            for path, age in ((project / "other-task.jsonl", 10000), (project / "first.jsonl", 3600),
                              (root / "sessions" / "rollout-other-task.jsonl", 10000),
                              (root / "sessions" / "rollout-first.jsonl", 3600)):
                os.utime(path, (now - age, now - age))
            crew = {m["id"]: m for m in self.report(fm)["crew"]}
        self.assertEqual(crew["a"]["models"], {"claude-first": 1, "claude-second": 1})
        self.assertEqual((crew["b"]["input"], crew["b"]["requests"], crew["b"]["sessions"]), (230, 2, 2))

    def test_harness_switch_keeps_usage_from_the_earlier_harness(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        now = int(usage.time.time())
        codex_slot, pi_slot = str(root / "slot1"), str(root / "slot2")
        for tid, harness, slot in (("a", "codex", codex_slot), ("b", "pi", pi_slot)):
            (fm / "state" / f"{tid}.meta").write_text(f"harness={harness}\nworktree={slot}\nspawn_gen=s{now - 60}.1.2\n")
            (fm / "state" / f"{tid}.status").write_text(f"working [at={now - 7200}]: started\n")
        with patch.object(usage, "CLAUDE_PROJECTS", str(root / "projects")), patch.object(
            usage, "CODEX_SESSIONS", str(root / "sessions")
        ), patch.object(usage, "CACHE_PATH", str(root / "cache" / "cache.json")):
            for slot in (codex_slot, pi_slot):
                first = Path(usage.claude_project_dir(slot)) / "first.jsonl"
                self.claude_turn(first, "first-" + Path(slot).name, "claude-first")
                os.utime(first, (now - 3600, now - 3600))
            self.codex_rollout(root / "sessions" / "rollout-relaunched.jsonl", codex_slot, 30)
            crew = {m["id"]: m for m in self.report(fm)["crew"]}
        self.assertEqual(crew["a"]["models"], {"claude-first": 1, "codex": 1})
        self.assertEqual((crew["a"]["sessions"], crew["a"]["toolCalls"]), (2, 1))
        self.assertEqual((crew["b"]["readable"], crew["b"]["models"]), (True, {"claude-first": 1}))

    def test_sessions_watching_other_homes_keep_each_others_cached_offsets(self):
        root = Path(self.tmp.name)
        homes = [root / "fm1", root / "fm2"]
        for n, home in enumerate(homes):
            (home / "state").mkdir(parents=True)
            (home / "state" / "t.meta").write_text(f"harness=claude\nworktree={root / f'wt{n}'}\n")
        cache = root / "cache" / "cache.json"
        with patch.object(usage, "CLAUDE_PROJECTS", str(root / "projects")), patch.object(usage, "CACHE_PATH", str(cache)):
            transcript = Path(usage.claude_project_dir(str(root / "wt0"))) / "s.jsonl"
            self.claude_turn(transcript, "one", "claude-test")
            self.report(homes[0])
            saved = json.loads(cache.read_text())["files"][str(transcript)]
            self.report(root)
            self.report(homes[1])
            self.assertEqual(json.loads(cache.read_text())["files"].get(str(transcript)), saved)

    def test_codex_cwd_is_cached_only_after_a_complete_session_meta_line(self):
        root = Path(self.tmp.name) / "sessions"
        root.mkdir()
        rollout = root / "rollout-new.jsonl"
        rollout.write_text("")
        cache = {}
        with patch.object(usage, "CODEX_SESSIONS", str(root)):
            now = int(usage.time.time() * 1000)
            self.assertEqual(usage.codex_files(cache, now), [])
            rollout.write_text('{"type": "session_meta", "payload": {"cwd": "/pool/1"')
            self.assertEqual(usage.codex_files(cache, now), [])
            rollout.write_text(json.dumps({"type": "session_meta", "payload": {"cwd": "/pool/1"}}) + "\n")
            self.assertEqual([(p, c) for p, c, _ in usage.codex_files(cache, now)], [(str(rollout), "/pool/1")])

    def test_truncated_transcript_resets_new_telemetry(self):
        self.append({"type": "assistant", "timestamp": "2026-10-21T17:00:00Z", "message": {
            "id": "one", "usage": {"input_tokens": 10}, "content": [{"type": "tool_use", "name": "Read"}]}})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        self.path.write_text(json.dumps({"type": "assistant", "message": {"id": "two", "content": []}}) + "\n")
        usage.parse_claude(self.path, entry, {})
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

    def claude_request(self, mid, at, usage_row, blocks):
        """One row per content block, as Claude Code logs a message."""
        for block in blocks:
            self.append({"type": "assistant", "timestamp": at, "message": {
                "id": mid, "model": "claude-sonnet-5-5", "usage": usage_row, "content": [block]}})

    def claude_result(self, call_id, text):
        self.append({"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": call_id, "content": text}]}})

    def two_call_request(self, second_usage):
        calls = [{"type": "tool_use", "id": "t-read", "name": "Read", "input": {"path": "/a"}},
                 {"type": "tool_use", "id": "t-bash", "name": "Bash", "input": {"command": "ls"}}]
        # Context 1000 = 10 + 800 + 190; this request emitted 100 output tokens.
        self.claude_request("m1", "2026-10-21T17:00:00Z",
                            {"input_tokens": 10, "cache_read_input_tokens": 800, "cache_creation_input_tokens": 190, "output_tokens": 100}, calls)
        self.claude_result("t-read", "r" * 300)
        self.claude_result("t-bash", "b" * 100)
        if second_usage:
            self.claude_request("m2", "2026-10-21T17:01:00Z", second_usage, [{"type": "text", "text": "done"}])

    def test_calls_of_one_request_split_its_output_evenly_and_the_measured_input_by_result_size(self):
        # Next context 1400: it grew by 300 beyond the first context and its 100 output tokens.
        self.two_call_request({"input_tokens": 5, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 395, "output_tokens": 7})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        tools = entry["agg"]["toolTokens"]
        self.assertEqual(tools["Read"], {"calls": 1, "output": 50, "input": 225, "estimated": 0, "estCalls": 0})
        self.assertEqual(tools["Bash"], {"calls": 1, "output": 50, "input": 75, "estimated": 0, "estCalls": 0})
        events = {event["tool"]: event for event in entry["agg"]["events"]}
        self.assertEqual((events["Read"]["outTokens"], events["Read"]["inTokens"], events["Read"]["estimated"]), (50, 225, False))
        self.assertEqual((events["Bash"]["outTokens"], events["Bash"]["inTokens"]), (50, 75))
        self.assertEqual(entry["agg"]["toolCalls"], 2)

    def test_a_request_without_a_successor_is_estimated_from_result_size_until_one_arrives(self):
        self.two_call_request(None)
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["toolTokens"], {})
        pending = usage.settled_agg(entry, "claude")
        # 300 and 100 characters at four characters per token, flagged as estimated.
        self.assertEqual(pending["toolTokens"]["Read"], {"calls": 1, "output": 50, "input": 75, "estimated": 75, "estCalls": 1})
        self.assertEqual(pending["toolTokens"]["Bash"]["input"], 25)
        self.assertTrue(all(event["estimated"] for event in pending["events"]))
        self.assertNotIn("outTokens", entry["agg"]["events"][0])
        # The view never leaks into what is cached; the next request replaces the estimate.
        self.append({"type": "assistant", "timestamp": "2026-10-21T17:01:00Z", "message": {
            "id": "m2", "model": "claude-sonnet-5-5", "content": [{"type": "text", "text": "done"}],
            "usage": {"input_tokens": 5, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 395, "output_tokens": 7}}})
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["toolTokens"]["Read"]["estCalls"], 0)
        self.assertEqual(entry["agg"]["toolTokens"]["Read"]["input"], 225)
        self.assertIs(usage.settled_agg(entry, "claude"), entry["agg"])

    def test_an_expired_cache_still_measures_the_delta_and_prices_it_as_cache_write(self):
        # The whole 1400-token context is rewritten: growth is still 300, charged at the cache-write price.
        self.two_call_request({"input_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 1400, "output_tokens": 7})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["toolTokens"]["Read"]["input"], 225)
        self.assertEqual(entry["agg"]["toolTokens"]["Read"]["estCalls"], 0)
        w = usage.token_weights("claude", "claude-sonnet-5-5")
        session, tools = usage.window_cost(entry["agg"], "claude", 0)
        self.assertAlmostEqual(tools, 100 * w["output"] + 300 * w["cacheWrite"])
        self.assertGreater(session, tools)

    def test_one_hour_cache_writes_weigh_more_than_five_minute_ones(self):
        # The next request writes its whole 1400-token context to the one-hour cache.
        self.two_call_request({"input_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 1400, "output_tokens": 7,
                               "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 1400}})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        w = usage.token_weights("claude", "claude-sonnet-5-5")
        self.assertGreater(w["cacheWrite1h"], w["cacheWrite"])
        session, tools = usage.window_cost(entry["agg"], "claude", 0)
        self.assertAlmostEqual(tools, 100 * w["output"] + 300 * w["cacheWrite1h"])
        first = 10 * w["input"] + 800 * w["cacheRead"] + 190 * w["cacheWrite"] + 100 * w["output"]
        self.assertAlmostEqual(session, first + 1400 * w["cacheWrite1h"] + 7 * w["output"])
        self.assertEqual(entry["agg"]["cacheWrite"], 190 + 1400)

    def test_a_mixed_cache_write_weighs_each_lifetime_at_its_own_price(self):
        self.claude_request("m1", "2026-10-21T17:00:00Z", {"cache_creation_input_tokens": 1000, "cache_creation": {
            "ephemeral_5m_input_tokens": 600, "ephemeral_1h_input_tokens": 400}}, [{"type": "text", "text": "hi"}])
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        w = usage.token_weights("claude", "claude-sonnet-5-5")
        self.assertAlmostEqual(usage.window_cost(entry["agg"], "claude", 0)[0], 600 * w["cacheWrite"] + 400 * w["cacheWrite1h"])

    def test_a_context_that_shrinks_falls_back_to_the_estimate(self):
        # A compaction: the next context is smaller than the last one.
        self.two_call_request({"input_tokens": 50, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0, "output_tokens": 7})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["toolTokens"]["Read"], {"calls": 1, "output": 50, "input": 75, "estimated": 75, "estCalls": 1})

    def test_a_log_without_usage_attributes_estimates_only_and_never_negative_tokens(self):
        for mid, at in (("a", "2026-10-21T17:00:00Z"), ("b", "2026-10-21T17:01:00Z")):
            self.append({"type": "assistant", "timestamp": at, "message": {"id": mid, "content": [
                {"type": "tool_use", "id": "t" + mid, "name": "Read"}]}})
        entry = usage.fresh_entry()
        usage.parse_claude(self.path, entry, {})
        self.assertEqual(entry["agg"]["toolTokens"]["Read"], {"calls": 1, "output": 0, "input": 0, "estimated": 0, "estCalls": 1})

    def test_codex_calls_split_the_request_output_and_measure_the_next_contexts_growth(self):
        def count(at, context, out, total):
            self.append({"type": "event_msg", "timestamp": at, "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": context, "total_tokens": total},
                "last_token_usage": {"input_tokens": context, "cached_input_tokens": context // 2, "output_tokens": out}}}})
        self.append({"type": "turn_context", "payload": {"model": "gpt-test"}})
        for call_id, name in (("c1", "exec"), ("c2", "apply_patch")):
            self.append({"type": "response_item", "timestamp": "2026-10-21T17:00:00Z", "payload": {
                "type": "custom_tool_call", "name": name, "call_id": call_id, "input": "x"}})
        self.append({"type": "response_item", "payload": {"type": "custom_tool_call_output", "call_id": "c1", "output": "o" * 400}})
        self.append({"type": "response_item", "payload": {"type": "custom_tool_call_output", "call_id": "c2", "output": "o" * 400}})
        count("2026-10-21T17:00:02Z", 1000, 80, 1080)
        count("2026-10-21T17:01:00Z", 1500, 10, 2590)
        entry = usage.fresh_entry()
        usage.parse_codex(self.path, entry)
        tools = entry["agg"]["toolTokens"]
        # Growth 1500 - 1000 - 80 = 420, split evenly by equal result sizes; output 80 split evenly.
        self.assertEqual((tools["exec"]["output"], tools["exec"]["input"]), (40, 210))
        self.assertEqual((tools["apply_patch"]["output"], tools["apply_patch"]["input"]), (40, 210))
        self.assertEqual({e["tool"]: e["inTokens"] for e in entry["agg"]["events"]}, {"exec": 210, "apply_patch": 210})
        saved = json.loads(json.dumps(entry))
        usage.parse_codex(self.path, entry)
        self.assertEqual(entry, saved)

    def test_codex_rollout_without_a_following_count_is_estimated(self):
        self.append({"type": "response_item", "payload": {"type": "function_call", "name": "shell", "call_id": "c1", "arguments": "{}"}})
        self.append({"type": "response_item", "payload": {"type": "function_call_output", "call_id": "c1", "output": "o" * 80}})
        self.append({"type": "event_msg", "timestamp": "2026-10-21T17:00:02Z", "payload": {"type": "token_count", "info": {
            "total_token_usage": {"input_tokens": 100, "total_tokens": 130},
            "last_token_usage": {"input_tokens": 100, "output_tokens": 30}}}})
        entry = usage.fresh_entry()
        usage.parse_codex(self.path, entry)
        self.assertEqual(entry["agg"]["toolTokens"], {})
        self.assertEqual(usage.settled_agg(entry, "codex")["toolTokens"]["shell"],
                         {"calls": 1, "output": 30, "input": 20, "estimated": 20, "estCalls": 1})

    def test_cache_reads_weigh_less_than_inputs_and_outputs_more(self):
        w = usage.token_weights("claude", "claude-opus-5-5")
        self.assertLess(w["cacheRead"], w["input"])
        self.assertLess(w["input"], w["cacheWrite"])
        self.assertLess(w["cacheWrite"], w["output"])
        self.assertGreater(w["input"], usage.token_weights("claude", "claude-haiku-5-5")["input"])
        self.assertEqual(usage.token_weights("claude", "mystery")["input"], usage.token_weights("claude", "claude-sonnet-5")["input"])
        self.assertLess(usage.token_weights("codex", "gpt-5-mini")["input"], usage.token_weights("codex", "gpt-5")["input"])
        self.assertEqual(usage.weigh("codex", "gpt-5", 10, 1, 100, 0), 10 * 1 + 1 * 8 + 100 * 0.1)

    def test_quota_share_math(self):
        self.assertEqual(usage.quota_share(40.0, 25.0, 100.0), {"share": 0.25, "percent": 10.0})
        # Unknown window percent: only the raw share of local usage.
        self.assertEqual(usage.quota_share(None, 25.0, 100.0), {"share": 0.25, "percent": None})
        # Nothing local to divide by: no share and no percent, never a division error.
        self.assertEqual(usage.quota_share(40.0, 0.0, 0.0), {"share": None, "percent": None})
        self.assertEqual(usage.quota_share(40.0, 5.0, 0.0), {"share": None, "percent": None})
        # Rounding noise cannot push a share past the whole.
        self.assertEqual(usage.quota_share(50.0, 100.0000001, 100.0), {"share": 1.0, "percent": 50.0})

    def test_window_cost_ignores_buckets_before_the_window_start(self):
        agg = usage.empty_agg()
        bucket = usage.BUCKET_MS
        usage.add_cost(agg, "claude", 10 * bucket, 100.0, 40.0)
        usage.add_cost(agg, "claude", 20 * bucket, 10.0, 1.0)
        usage.add_cost(agg, "codex", 20 * bucket, 7.0, 0.0)
        self.assertEqual(usage.window_cost(agg, "claude", 0), (110.0, 41.0))
        self.assertEqual(usage.window_cost(agg, "claude", 15 * bucket), (10.0, 1.0))
        self.assertEqual(usage.window_cost(agg, "claude", 20 * bucket + 1), (10.0, 1.0))
        self.assertEqual(usage.window_cost(agg, "claude", 21 * bucket), (0.0, 0.0))
        self.assertEqual(usage.window_cost(agg, "codex", 0), (7.0, 0.0))

    def test_a_window_that_has_reset_gives_no_percent(self):
        now = 1_000_000_000
        ended = usage.window_candidate("usage cache", 100, now - 1, usage.WEEK_MS, now - 5000)
        live = usage.window_candidate("this session", 30, now + 86_400_000, usage.WEEK_MS, now - 9000)
        self.assertIsNone(usage.pick_window([ended], now))
        self.assertEqual(usage.pick_window([ended, live], now)["percent"], 30.0)
        window = usage.provider_window([ended], "Max 5x", now)
        self.assertEqual((window["percentUsed"], window["reset"], window["stale"], window["windowStartKnown"]), (None, True, False, False))
        self.assertEqual(window["windowStart"], now - usage.WEEK_MS)
        window = usage.provider_window([live], "", now)
        self.assertEqual(window["windowStart"], now + 86_400_000 - usage.WEEK_MS)
        self.assertEqual((window["reset"], window["stale"]), (False, False))
        self.assertEqual((usage.provider_window([], "", now)["reset"], usage.provider_window([], "", now)["stale"]), (False, False))
        # A window reported without a usable percent is no reading, not a reset one.
        invalid = usage.window_candidate("this session", None, now + 86_400_000, usage.WEEK_MS, now)
        self.assertEqual((usage.provider_window([invalid], "", now)["reset"], usage.provider_window([invalid], "", now)["percentUsed"]), (False, None))
        self.assertEqual(usage.provider_window([invalid, ended], "", now)["reset"], True)

    def test_the_freshest_reading_wins_and_one_older_than_half_an_hour_is_stale(self):
        now = 10_000_000_000
        resets = now + 86_400_000
        old = usage.window_candidate("usage cache", 10, resets, usage.WEEK_MS, now - 4 * 86_400_000)
        recent = usage.window_candidate("codex log", 50, resets, usage.WEEK_MS, now - 60_000)
        window = usage.provider_window([old, recent], "", now)
        self.assertEqual((window["percentUsed"], window["source"], window["readAt"], window["stale"]), (50.0, "codex log", now - 60_000, False))
        window = usage.provider_window([old], "", now)
        self.assertEqual((window["percentUsed"], window["source"], window["stale"]), (10.0, "usage cache", True))
        self.assertTrue(usage.provider_window([usage.window_candidate("x", 1, resets, usage.WEEK_MS, now - usage.STALE_MS - 1)], "", now)["stale"])
        self.assertFalse(usage.provider_window([usage.window_candidate("x", 1, resets, usage.WEEK_MS, now - usage.STALE_MS)], "", now)["stale"])
        unknown = usage.provider_window([usage.window_candidate("usage cache", 1, resets, usage.WEEK_MS, None)], "", now)
        self.assertEqual((unknown["readAt"], unknown["stale"]), (None, True))

    def test_messages_copied_into_a_resumed_or_forked_transcript_count_once(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        mine, other = str(root / "mine"), str(root / "other")
        now = int(usage.time.time())
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={mine}\nspawn_gen=s{now - 600}.1.2\n")
        stamp = lambda seconds: datetime.fromtimestamp(now - seconds, timezone.utc).isoformat()
        row = lambda mid, seconds, tokens: json.dumps({"type": "assistant", "timestamp": stamp(seconds), "message": {
            "id": mid, "model": "claude-sonnet-5-5", "usage": {"input_tokens": tokens},
            "content": [{"type": "tool_use", "id": "t" + mid, "name": "Read", "input": {"path": "/x"}}]}}) + "\n"
        project = Path(usage.claude_project_dir(mine))
        project.mkdir(parents=True)
        (project / "first.jsonl").write_text(row("m1", 300, 100))
        # --resume copies m1 into the new transcript before its own m2.
        (project / "resumed.jsonl").write_text(row("m1", 300, 100) + row("m2", 60, 50))
        # A fork elsewhere copies m1 too and adds m3.
        forked = Path(usage.claude_project_dir(other))
        forked.mkdir(parents=True)
        (forked / "fork.jsonl").write_text(row("m1", 300, 100) + row("m3", 30, 200))
        tomorrow = datetime.fromtimestamp(now + 86400, timezone.utc).isoformat()
        limits = json.dumps([{"kind": "seven_day", "percentUsed": 70, "resetsAt": tomorrow}])
        reports = []
        for _ in range(2):
            with redirect_stdout(io.StringIO()) as output, patch.object(usage, "CACHE_PATH", str(root / "cache.json")), patch.object(
                    usage.sys, "argv", ["crew_usage.py", "--home", str(fm), "--claude-limits", limits]):
                usage.main()
            reports.append(json.loads(output.getvalue()))
        for report in reports:
            member = report["crew"][0]
            self.assertEqual((member["requests"], member["input"], member["toolCalls"], member["sessions"]), (2, 150, 2, 2))
            self.assertEqual(member["toolTokens"]["Read"]["calls"], 2)
            w = usage.token_weights("claude", "claude-sonnet-5-5")
            self.assertAlmostEqual(report["quota"]["providers"]["claude"]["localCost"], 350 * w["input"])
            self.assertAlmostEqual(member["quota"]["claude"]["session"]["share"], 150 / 350)

    def test_report_estimates_the_weekly_share_from_the_window_percent_and_local_usage(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        mine, other = str(root / "mine"), str(root / "other")
        now = int(usage.time.time())
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={mine}\nspawn_gen=s{now - 600}.1.2\n")
        projects = Path(usage.CLAUDE_PROJECTS)
        stamp = lambda seconds: datetime.fromtimestamp(now - seconds, timezone.utc).isoformat()
        row = lambda at, tokens: json.dumps({"type": "assistant", "timestamp": at, "message": {
            "id": "m" + at, "model": "claude-sonnet-5-5", "usage": {"input_tokens": tokens}, "content": []}}) + "\n"
        (projects / Path(usage.claude_project_dir(mine)).name).mkdir(parents=True)
        Path(usage.claude_project_dir(mine), "s.jsonl").write_text(row(stamp(60), 100))
        # Another local session: one row inside the window and one 5 days old, still inside it.
        Path(usage.claude_project_dir(other)).mkdir(parents=True)
        Path(usage.claude_project_dir(other), "pane.jsonl").write_text(row(stamp(5 * 86400), 9000) + row(stamp(120), 300))
        limits = json.dumps([{"kind": "five_hour", "percentUsed": 1, "resetsAt": stamp(-60)},
                             {"kind": "seven_day", "percentUsed": 40, "resetsAt": stamp(-86400)}])
        with redirect_stdout(io.StringIO()) as output, patch.object(usage, "CACHE_PATH", str(root / "cache.json")), patch.object(
                usage.sys, "argv", ["crew_usage.py", "--home", str(fm), "--claude-limits", limits, "--claude-session", "pane"]):
            usage.main()
        report = json.loads(output.getvalue())
        claude = report["quota"]["providers"]["claude"]
        self.assertEqual((claude["percentUsed"], claude["windowStartKnown"], claude["indexed"]), (40.0, True, True))
        # The limits are dated by the pane session's newest response, two minutes ago.
        self.assertEqual((claude["source"], claude["readAt"], claude["stale"]), ("this session", ts_of(stamp(120)), False))
        # The window began about 6 days ago: the 5-day-old row counts, the others too; 100 of 9400 input tokens are the crewmate's.
        member = report["crew"][0]["quota"]["claude"]
        self.assertAlmostEqual(member["session"]["share"], 100 / 9400)
        self.assertAlmostEqual(member["session"]["percent"], 40 * 100 / 9400)
        self.assertEqual(member["tools"]["share"], 0.0)
        self.assertEqual(report["quota"]["fleet"]["claude"]["session"]["share"], member["session"]["share"])
        self.assertNotIn("codex", report["crew"][0]["quota"])
        # Without a current percent the raw share stays and the percent is unknown.
        with redirect_stdout(io.StringIO()) as output, patch.object(usage, "CACHE_PATH", str(root / "cache.json")), patch.object(
                usage.sys, "argv", ["crew_usage.py", "--home", str(fm)]):
            usage.main()
        member = json.loads(output.getvalue())["crew"][0]["quota"]["claude"]
        self.assertIsNone(member["session"]["percent"])
        self.assertIsNotNone(member["session"]["share"])

    def test_limits_of_a_session_without_a_transcript_are_of_unknown_age(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={root / 'mine'}\n")
        recent = datetime.fromtimestamp(usage.time.time() - 60, timezone.utc).isoformat()
        self.claude_turn(Path(usage.claude_project_dir(str(root / "mine"))) / "s.jsonl", "m", "claude-sonnet-5-5", recent)
        tomorrow = datetime.fromtimestamp(usage.time.time() + 86400, timezone.utc).isoformat()
        limits = json.dumps([{"kind": "seven_day", "percentUsed": 40, "resetsAt": tomorrow}])
        for session in ("missing", "../s"):
            with redirect_stdout(io.StringIO()) as output, patch.object(usage, "CACHE_PATH", str(root / "cache.json")), patch.object(
                    usage.sys, "argv", ["crew_usage.py", "--home", str(fm), "--claude-limits", limits, "--claude-session", session]):
                usage.main()
            claude = json.loads(output.getvalue())["quota"]["providers"]["claude"]
            self.assertEqual((claude["percentUsed"], claude["readAt"], claude["stale"]), (40.0, None, True))

    def test_the_scan_budget_counts_from_the_start_of_the_run(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={root / 'mine'}\n")
        recent = datetime.fromtimestamp(usage.time.time() - 60, timezone.utc).isoformat()
        self.claude_turn(Path(usage.claude_project_dir(str(root / "mine"))) / "s.jsonl", "m", "claude-sonnet-5-5", recent)
        self.claude_turn(Path(usage.CLAUDE_PROJECTS) / "elsewhere" / "s.jsonl", "n", "claude-sonnet-5-5", recent)
        collect = usage.collect_tasks
        def slow_crew(*args):
            usage.time.sleep(0.3)
            return collect(*args)
        with patch.object(usage, "SCAN_BUDGET_SECONDS", 0.2), patch.object(usage, "collect_tasks", slow_crew), patch.object(
                usage, "CACHE_PATH", str(root / "cache.json")), redirect_stdout(io.StringIO()) as output, patch.object(
                usage.sys, "argv", ["crew_usage.py", "--home", str(fm)]):
            usage.main()
        self.assertFalse(json.loads(output.getvalue())["quota"]["providers"]["claude"]["indexed"])

    def test_a_scan_over_its_time_budget_reports_indexing_instead_of_a_partial_share(self):
        root = Path(self.tmp.name)
        fm = root / "fm"
        (fm / "state").mkdir(parents=True)
        mine = str(root / "mine")
        (fm / "state" / "a.meta").write_text(f"harness=claude\nworktree={mine}\n")
        project = Path(usage.claude_project_dir(mine))
        recent = datetime.fromtimestamp(usage.time.time() - 60, timezone.utc).isoformat()
        self.claude_turn(project / "s.jsonl", "m", "claude-sonnet-5-5", recent)
        self.claude_turn(Path(usage.CLAUDE_PROJECTS) / "elsewhere" / "s.jsonl", "n", "claude-sonnet-5-5", recent)
        tomorrow = datetime.fromtimestamp(usage.time.time() + 86400, timezone.utc).isoformat()
        limits = json.dumps([{"kind": "seven_day", "percentUsed": 40, "resetsAt": tomorrow}])
        with patch.object(usage, "SCAN_BUDGET_SECONDS", -1), patch.object(usage, "CACHE_PATH", str(root / "cache.json")):
            with redirect_stdout(io.StringIO()) as output, patch.object(
                    usage.sys, "argv", ["crew_usage.py", "--home", str(fm), "--claude-limits", limits]):
                usage.main()
        report = json.loads(output.getvalue())
        self.assertFalse(report["quota"]["providers"]["claude"]["indexed"])
        self.assertEqual(report["crew"][0]["quota"]["claude"]["session"], {"share": None, "percent": None})

    def test_codex_window_and_plan_come_from_the_newest_rollout_event(self):
        resets = int(usage.time.time()) + 86400
        limits = lambda percent, at: {"type": "event_msg", "timestamp": at, "payload": {"type": "token_count", "info": None, "rate_limits": {
            "plan_type": "plus", "primary": {"used_percent": 3.0, "window_minutes": 300, "resets_at": resets},
            "secondary": {"used_percent": percent, "window_minutes": 10080, "resets_at": resets}}}}
        old, new = usage.fresh_entry(), usage.fresh_entry()
        for path, entry, percent, at in ((self.path, old, 11.0, "2026-10-21T17:00:00Z"),
                                         (Path(self.tmp.name) / "new.jsonl", new, 25.0, "2026-10-21T18:00:00Z")):
            path.write_text(json.dumps(limits(percent, at)) + "\n")
            usage.parse_codex(path, entry)
        candidates, plan = usage.codex_candidates([old, new])
        self.assertEqual(plan, "plus")
        window = usage.provider_window(candidates, plan.title(), int(usage.time.time() * 1000))
        self.assertEqual((window["percentUsed"], window["plan"], window["source"]), (25.0, "Plus", "codex log"))
        self.assertTrue(window["windowStartKnown"])

    def test_claude_plan_and_cached_window_come_from_local_files_only(self):
        home = Path(usage.HOME)
        home.mkdir(parents=True)
        (home / ".claude.json").write_text(json.dumps({
            "oauthAccount": {"userRateLimitTier": "default_claude_max_5x", "organizationType": "claude_team"},
            "cachedUsageUtilization": {"fetchedAtMs": 5, "utilization": {"seven_day": {"utilization": 12, "resets_at": "2999-01-01T00:00:00+00:00"}}}}))
        self.assertEqual(usage.claude_plan(), "Max 5x · Team")
        candidates = usage.claude_candidates([{"kind": "seven_day", "percentUsed": 50, "resetsAt": "2999-01-02T00:00:00Z"}], 10)
        self.assertEqual(sorted((c["source"], c["percent"]) for c in candidates), [("this session", 50.0), ("usage cache", 12.0)])
        self.assertEqual(usage.pick_window(candidates, 10)["source"], "this session")
        cached = usage.provider_window(usage.claude_candidates([], 10), "", 5 + usage.STALE_MS + 1)
        self.assertEqual((cached["percentUsed"], cached["source"], cached["readAt"], cached["stale"]), (12.0, "usage cache", 5, True))
        # Undated session limits are never fresh: the dated cache wins, and alone they are stale.
        undated = usage.claude_candidates([{"kind": "seven_day", "percentUsed": 50, "resetsAt": "2999-01-02T00:00:00Z"}], None)
        self.assertEqual(usage.pick_window(undated, 10)["source"], "usage cache")
        window = usage.provider_window(undated[:1], "", 10)
        self.assertEqual((window["source"], window["readAt"], window["stale"]), ("this session", None, True))
        (home / ".claude").mkdir()
        (home / ".claude" / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {"subscriptionType": "max", "rateLimitTier": "default_claude_max_20x", "accessToken": "secret"}}))
        self.assertEqual(usage.claude_plan(), "Max 20x · Team")


if __name__ == "__main__":
    unittest.main()
