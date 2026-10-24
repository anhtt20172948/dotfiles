"""Weekly-quota estimate: accounts, reading history, anchors and request-level boundaries.

Every transcript, account and reading here is fabricated; no real home, token
or quota cache is read, and nothing is sent anywhere.
"""
from contextlib import redirect_stdout
from datetime import datetime, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / "scripts"
SPEC = importlib.util.spec_from_file_location("crew_usage", SCRIPTS / "crew_usage.py")
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)
quota = usage.quota

HAIKU = "claude-haiku-5-5"  # price ratio 1: a row's cost is its input tokens
DAY = 86400
FINGERPRINT = "f" * 64
LOGIN_ENV = "fabricated-login-value"


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat()


class QuotaTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        home = self.root / "home"
        for name, value in (("HOME", str(home)), ("CLAUDE_PROJECTS", str(home / ".claude" / "projects")),
                            ("CODEX_SESSIONS", str(home / ".codex" / "sessions")),
                            ("CACHE_PATH", str(home / ".cache" / "crew-watch" / "cache.json"))):
            patcher = patch.object(usage, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        env = patch.dict(os.environ, {"XDG_CACHE_HOME": str(home / ".cache"), "XDG_STATE_HOME": str(home / ".local" / "state")})
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("CLAUDE_CONFIG_DIR", None)
        self.now = int(usage.time.time())
        self.fm = self.root / "fm"
        (self.fm / "state").mkdir(parents=True)
        self.history = Path(quota.history_path())

    # ---- fabricated logs ----

    def project(self, worktree):
        return Path(usage.claude_project_dir(worktree))

    def turn(self, path, mid, ago, tokens=None):
        """A Claude response `ago` seconds old; without tokens it carries no usage (cost 0)."""
        path.parent.mkdir(parents=True, exist_ok=True)
        message = {"id": mid, "model": HAIKU, "content": []}
        if tokens is not None:
            message["usage"] = {"input_tokens": tokens}
        with path.open("a") as stream:
            stream.write(json.dumps({"type": "assistant", "timestamp": iso(self.now - ago), "message": message}) + "\n")

    def task(self, tid, worktree, started=3600):
        (self.fm / "state" / f"{tid}.meta").write_text(
            f"harness=claude\nworktree={worktree}\nspawn_gen=s{self.now - started}.1.2\n")

    def register(self, session, account):
        accounts = Path(usage.accounts_path())
        known = quota.load_accounts(str(accounts))
        known[session] = {"account": account, "at": self.now * 1000}
        accounts.parent.mkdir(parents=True, exist_ok=True)
        accounts.write_text(json.dumps(known))

    def limits(self, percent, resets_in=DAY):
        return json.dumps([{"kind": "seven_day", "percentUsed": percent, "resetsAt": iso(self.now + resets_in)}])

    def run_report(self, *args):
        with redirect_stdout(io.StringIO()) as output, patch.object(
                usage.sys, "argv", ["crew_usage.py", "--home", str(self.fm), *args]):
            usage.main()
        return json.loads(output.getvalue())

    def pane(self, percent, session="pane", account="acct-a", resets_in=DAY):
        return ["--claude-session", session, "--claude-account", account, "--claude-limits", self.limits(percent, resets_in)]

    def records(self):
        return [json.loads(line) for line in self.history.read_text().splitlines()] if self.history.exists() else []


class AccountSeparationTest(QuotaTestCase):
    def test_a_percent_is_only_split_by_the_usage_of_its_own_account(self):
        # Account A is at 20% and this task is all of A; account B costs four times as much.
        # Dividing A's percent by both accounts' cost gave 20 x 20/100 = 4; it is 20.
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=3 * 3600)
        mine = self.project(worktree) / "sess-a.jsonl"
        self.turn(mine, "a1", 7200, 10)
        self.turn(mine, "a2", 30, 10)
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "sess-b.jsonl", "b1", 3600, 80)
        self.register("sess-b", "acct-b")
        report = self.run_report(*self.pane(20, session="sess-a"))
        figures = report["crew"][0]["quota"]
        self.assertEqual(list(figures), ["claude|acct-a|seven_day"])
        session = figures["claude|acct-a|seven_day"]["session"]
        self.assertAlmostEqual(session["percent"], 20.0)
        self.assertEqual((session["share"], session["basis"]), (1.0, "estimated"))
        self.assertAlmostEqual(report["quota"]["fleet"]["claude|acct-a|seven_day"]["session"]["percent"], 20.0)
        # B has no reading of its own: it is never given A's percent.
        other = report["quota"]["readings"]["claude|acct-b|seven_day"]
        self.assertEqual((other["percent"], other["accountKnown"]), (None, True))
        self.assertNotIn("claude|acct-b|seven_day", figures)

    def test_a_session_of_no_known_account_shows_only_its_raw_local_share(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=3 * 3600)
        mine = self.project(worktree) / "sess-a.jsonl"
        self.turn(mine, "a1", 7200, 10)
        self.turn(mine, "a2", 30, 10)
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "sess-b.jsonl", "b1", 3600, 80)
        report = self.run_report("--claude-session", "sess-a", "--claude-limits", self.limits(20))
        figure = report["crew"][0]["quota"]["claude|unknown|seven_day"]["session"]
        self.assertEqual((figure["percent"], figure["basis"]), (None, "raw"))
        self.assertAlmostEqual(figure["share"], 20 / 100)
        reading = report["quota"]["readings"]["claude|unknown|seven_day"]
        self.assertEqual((reading["percent"], reading["accountKnown"]), (None, False))
        # An observation nobody owns is not kept.
        self.assertEqual(self.records(), [])

    def test_one_task_that_ran_under_two_accounts_reports_each_against_its_own(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        for session, account, cost in (("s1", "acct-a", 30), ("s2", "acct-b", 10)):
            self.turn(self.project(worktree) / f"{session}.jsonl", session + "m", 600, cost)
            self.register(session, account)
        report = self.run_report("--claude-session", "s1", "--claude-account", "acct-a", "--claude-limits", self.limits(10))
        self.assertEqual(sorted(report["crew"][0]["quota"]), ["claude|acct-a|seven_day", "claude|acct-b|seven_day"])
        self.assertAlmostEqual(report["crew"][0]["quota"]["claude|acct-a|seven_day"]["session"]["share"], 1.0)
        self.assertIsNone(report["crew"][0]["quota"]["claude|acct-b|seven_day"]["session"]["percent"])

    def test_subagent_transcripts_belong_to_the_account_of_their_session(self):
        base = Path(usage.CLAUDE_PROJECTS)
        self.assertEqual(usage.claude_session_id(str(base / "-proj" / "abc-1.jsonl")), "abc-1")
        self.assertEqual(usage.claude_session_id(str(base / "-proj" / "abc-1" / "subagents" / "agent-9.jsonl")), "abc-1")
        self.assertEqual(usage.claude_session_id("/elsewhere/x.jsonl"), "")
        sessions = {"abc-1": {"account": "acct-a", "at": 1}}
        self.assertEqual(usage.entry_account("claude", str(base / "-proj" / "abc-1" / "subagents" / "a.jsonl"), {}, sessions), "acct-a")
        self.assertEqual(usage.entry_account("claude", str(base / "-proj" / "zzz.jsonl"), {}, sessions), "unknown")

    def test_the_registry_keeps_names_only_and_is_private(self):
        path = usage.accounts_path()
        known = quota.register_account(path, "sess-1", "acct-a", self.now * 1000)
        self.assertEqual(known["sess-1"]["account"], "acct-a")
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode), 0o700)
        self.assertNotIn(FINGERPRINT, Path(path).read_text())
        for bad in ("UPPER", "has space", "../x", "", "unknown", "x" * 33):
            self.assertEqual(quota.claude_account_name(bad), "unknown", bad)
        self.assertEqual(quota.claude_account_name("a-1_b"), "a-1_b")
        # Entries age out so the registry stays bounded.
        later = self.now * 1000 + 31 * DAY * 1000
        self.assertNotIn("sess-1", quota.register_account(path, "sess-2", "acct-b", later))

    def test_ai_acct_limit_windows_are_read_without_their_fingerprint(self):
        cache = Path(usage.ai_acct_cache_dir())
        cache.mkdir(parents=True)
        (cache / "claude-acct-a.limits.json").write_text(json.dumps({
            "fingerprint": FINGERPRINT, "time": self.now,
            "windows": {"five_hour": {"used": 3, "resets_at": self.now + 300}, "seven_day": {"used": 41, "resets_at": self.now + DAY}}}))
        (cache / "claude-UPPER.limits.json").write_text("{}")
        (cache / "claude-stale.limits.json").write_text("not json")
        found = usage.account_cache_candidates()
        self.assertEqual([(c["account"], c["percent"], c["observedAt"], c["source"]) for c in found],
                         [("acct-a", 41.0, None, "account cache")])
        self.assertNotIn(FINGERPRINT, json.dumps(found))
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-a.jsonl", "a1", 60, 10)
        self.register("sess-a", "acct-a")
        report = self.run_report()
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        # Its age is unknown, so it is stale and keeps no forecast.
        self.assertEqual((reading["percent"], reading["source"], reading["stale"], reading["observedAt"], reading["forecast"]),
                         (41.0, "account cache", True, None, None))
        self.assertNotIn(FINGERPRINT, json.dumps(report))

    def test_a_numeric_resets_at_dates_the_pane_window_like_an_iso_one(self):
        # $.session.usage().rateLimits may carry resetsAt as an epoch in seconds or milliseconds, or as ISO text.
        resets = self.now + DAY
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-a.jsonl", "a1", 60, 10)
        for value in (resets, resets * 1000, float(resets), iso(resets)):
            limits = json.dumps([{"kind": "seven_day", "percentUsed": 30, "resetsAt": value}])
            report = self.run_report("--claude-session", "sess-a", "--claude-account", "acct-a", "--claude-limits", limits)
            reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
            self.assertEqual(reading["resetsAt"], resets * 1000, value)
            self.assertEqual(reading["windowStart"], (resets - 7 * DAY) * 1000, value)

    def test_ts_ms_reads_iso_text_and_numeric_epochs_and_rejects_the_rest(self):
        self.assertEqual(usage.ts_ms("2026-01-02T03:04:05Z"), 1767323045000)
        self.assertEqual(usage.ts_ms(1767323045), 1767323045000)
        self.assertEqual(usage.ts_ms(1767323045.5), 1767323045500)
        self.assertEqual(usage.ts_ms(1767323045000), 1767323045000)
        for bad in (None, "", 0, -5, True, False, "not a time", float("nan"), float("inf"), [], {}):
            self.assertEqual(usage.ts_ms(bad), 0, bad)

    def test_codex_accounts_are_told_apart_by_a_hash_and_the_id_is_never_kept(self):
        resets = self.now + DAY
        worktree = str(self.root / "codex-slot")
        (self.fm / "state" / "c.meta").write_text(f"harness=codex\nworktree={worktree}\nspawn_gen=s{self.now - 3600}.1.2\n")

        def rollout(name, creator, percent, limit_id="codex"):
            meta = {"cwd": worktree}
            if creator:
                meta["creator_account_id"] = creator
            count = {"type": "event_msg", "timestamp": iso(self.now - 120), "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 100, "total_tokens": 100}, "last_token_usage": {"input_tokens": 100}},
                "rate_limits": {"limit_id": limit_id, "plan_type": "plus",
                                "primary": {"used_percent": 4.0, "window_minutes": 300, "resets_at": self.now + 600},
                                "secondary": {"used_percent": percent, "window_minutes": 10080, "resets_at": resets}}}}
            path = Path(usage.CODEX_SESSIONS) / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("".join(json.dumps(row) + "\n" for row in [{"type": "session_meta", "payload": meta}, count]))

        rollout("rollout-1.jsonl", "creator-one", 30.0)
        rollout("rollout-2.jsonl", "creator-two", 12.5)
        rollout("rollout-3.jsonl", None, 99.0)
        rollout("rollout-4.jsonl", "creator-one", 77.0, limit_id="codex_other")
        report = self.run_report()
        readings = report["quota"]["readings"]
        keys = sorted(k for k in readings if k.startswith("codex|"))
        self.assertEqual(len(keys), 3)
        known = {k: r for k, r in readings.items() if r["accountKnown"] and k.startswith("codex|")}
        self.assertEqual(sorted(r["percent"] for r in known.values()), [12.5, 30.0])
        self.assertTrue(all(k.endswith("|codex:10080m") for k in known))
        unknown = readings["codex|unknown|weekly"]
        self.assertEqual((unknown["percent"], unknown["accountKnown"]), (None, False))
        text = json.dumps(report) + self.history.read_text()
        self.assertNotIn("creator-one", text)
        self.assertNotIn("creator-two", text)
        # The model-specific limit is not an anchor of the account's weekly usage.
        self.assertNotIn(77.0, [r["percent"] for r in readings.values()])
        # It is kept in the history under its own scope, never mixed into the account's.
        self.assertEqual(sorted((r["percent"], r["scope"].split(":")[0]) for r in self.records()),
                         [(12.5, "codex"), (30.0, "codex"), (77.0, "codex_other")])


class AnchorAndForecastTest(QuotaTestCase):
    def two_account_week(self):
        """A task with 20 of the account's 100 weighted tokens before a 10% reading taken a minute ago."""
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=4 * 3600)
        self.turn(self.project(worktree) / "sess-m.jsonl", "m1", 3 * 3600, 20)
        pane = self.root / "home" / ".claude" / "projects" / "elsewhere" / "pane.jsonl"
        self.turn(pane, "p1", 3 * 3600, 80)
        self.turn(pane, "p2", 60)
        self.register("sess-m", "acct-a")

    def test_the_share_does_not_fall_when_other_sessions_spend_after_the_reading(self):
        # P = 10 with a task cost of 20 of 100 gave 2%; 100 more tokens elsewhere after the reading made it 1%.
        self.two_account_week()
        first = self.run_report(*self.pane(10))
        key = "claude|acct-a|seven_day"
        self.assertAlmostEqual(first["crew"][0]["quota"][key]["session"]["percent"], 2.0)
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "other.jsonl", "o1", 10, 100)
        self.register("other", "acct-a")
        second = self.run_report(*self.pane(10))
        figure = second["crew"][0]["quota"][key]["session"]
        self.assertAlmostEqual(figure["percent"], 2.0)
        self.assertEqual((figure["settled"], figure["basis"]), (figure["percent"], "estimated"))
        # The account forecast moves instead: the measured 10 plus what the 100 tokens cost at the period's own rate.
        reading = second["quota"]["readings"][key]
        self.assertAlmostEqual(reading["percent"], 10.0)
        self.assertAlmostEqual(reading["sinceCost"], 100.0)
        self.assertAlmostEqual(reading["forecast"], 20.0)

    def test_settled_intervals_split_each_rise_by_the_share_inside_that_interval(self):
        index = quota.CostIndex({"1000": [10.0, 0.0], "2000": [40.0, 0.0], "3000": [50.0, 0.0], "4000": [10.0, 0.0]})
        member = quota.CostIndex({"1000": [10.0, 0.0], "3000": [25.0, 0.0]})
        blocks, boundary, inclusive, percent = quota.settled_blocks(
            [{"percent": 0.0, "observedAt": 1500}, {"percent": 2.0, "observedAt": 2500}, {"percent": 2.0, "observedAt": 3200},
             {"percent": 5.0, "observedAt": 3500}, {"percent": 4.0, "observedAt": 3600}], 500)
        # Rises close blocks at 2500 (+2) and 3500 (+3); a flat or fallen reading settles nothing.
        self.assertEqual(blocks, [(500, 2500, 2.0, True), (2500, 3500, 3.0, False)])
        self.assertEqual((boundary, inclusive, percent), (3500, False, 5.0))
        # Block 1: member 10 of 50 -> 2 x 0.2; block 2: member 25 of 50 -> 3 x 0.5.
        self.assertAlmostEqual(quota.settled_percent(blocks, member, index, 0), 0.4 + 1.5)

    def test_a_tools_figure_is_split_by_the_whole_accounts_usage_not_its_tool_calls(self):
        # Tool calls are part of their session's cost: 50 of 1000 weighted tokens is 5% of a 10 point rise.
        account = quota.CostIndex({"1000": [1000.0, 50.0]})
        member = quota.CostIndex({"1000": [100.0, 50.0]})
        blocks = [(0, 2000, 10.0, True)]
        self.assertAlmostEqual(quota.settled_percent(blocks, member, account, 0), 1.0)
        self.assertAlmostEqual(quota.settled_percent(blocks, member, account, 1), 0.5)

    def test_a_stale_reading_is_extrapolated_only_when_calibrated_and_within_the_calibrated_horizon(self):
        now = self.now * 1000
        index = quota.CostIndex({str(now - 5 * 3600000): [100.0, 0.0], str(now - 60000): [10.0, 0.0]})

        def run(age_ms, calibrated):
            anchor = usage.candidate("claude", "acct-a", "history", "seven_day", 10.0, now + DAY * 1000, 7 * DAY * 1000, now - age_ms)
            history = []
            if calibrated:
                history = [{"provider": "claude", "account": "acct-a", "scope": "seven_day", "observedAt": now - 10 * 3600000 + n * 1800000,
                            "percent": 1.0, "residual": {"rise": 4.0, "error": 0.2, "forecast": 0, "anchorAt": 0, "sinceMs": 0}} for n in range(12)]
            readings, _ = usage.build_readings({("claude", "acct-a")}, [anchor], history, {("claude", "acct-a"): index},
                                               {"claude": True}, now, "acct-a", "", "")
            return readings["claude|acct-a|seven_day"]

        self.assertTrue(run(3600000, False)["stale"])
        self.assertIsNone(run(3600000, False)["forecast"])
        self.assertEqual(run(3600000, True)["confidence"]["label"], "calibrated")
        self.assertIsNotNone(run(3600000, True)["forecast"])
        # Past the two hours the calibration was measured over, nothing is extrapolated.
        self.assertIsNone(run(3 * 3600000, True)["forecast"])
        self.assertIsNotNone(run(60000, False)["forecast"])

    def test_cost_before_the_window_start_is_never_counted(self):
        # A row at 09:01 with the window starting at 09:07 sat in the same 15-minute bucket and counted.
        t = lambda hour, minute: ((hour * 60) + minute) * 60000
        agg = usage.empty_agg()
        usage.add_cost(agg, "claude", t(9, 1), 100.0, 40.0)
        usage.add_cost(agg, "claude", t(9, 8), 5.0, 1.0)
        index = quota.CostIndex(agg["cost"]["claude"])
        self.assertEqual(index.between(t(9, 7), t(9, 30), True), (5.0, 1.0))
        self.assertEqual(index.between(t(9, 1), t(9, 30), True), (105.0, 41.0))
        # The boundary request itself belongs to the interval it ends, not the one it starts.
        self.assertEqual(index.between(t(9, 1), t(9, 30)), (5.0, 1.0))
        self.assertEqual(index.between(0, t(9, 1)), (100.0, 40.0))
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=3 * DAY)
        mine = self.project(worktree) / "sess-a.jsonl"
        # The week began at the reset 6 days and 23 hours ago; a row 5 minutes before it must not count.
        reset_in = 3600
        self.turn(mine, "old", 7 * DAY - reset_in + 300, 100)
        self.turn(mine, "new", 120, 7)
        report = self.run_report(*self.pane(30, session="sess-a", resets_in=reset_in))
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        self.assertAlmostEqual(reading["localCost"], 7.0)

    def test_an_old_transcript_resumed_and_edited_recently_counts_only_requests_since_the_task_started(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=3600)
        resumed = self.project(worktree) / "resumed.jsonl"
        self.turn(resumed, "old1", 3 * DAY, 50)
        self.turn(resumed, "old2", 3 * DAY - 60, 50)
        self.turn(resumed, "new1", 1800, 10)
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "x.jsonl", "x1", 600, 90)
        report = self.run_report()
        figure = report["crew"][0]["quota"]["claude|unknown|seven_day"]["session"]
        # 10 of the 200 tokens of the week are the task's; a file-mtime filter gave it the 110 of its transcript.
        self.assertAlmostEqual(figure["share"], 10 / 200)
        self.assertAlmostEqual(report["quota"]["readings"]["claude|unknown|seven_day"]["localCost"], 200.0)

    def test_a_reading_older_than_half_an_hour_keeps_its_time_and_shows_only_the_local_delta(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=6 * 3600)
        pane = self.project(worktree) / "pane.jsonl"
        self.turn(pane, "p1", 5 * 3600, 60)
        self.turn(pane, "p2", 7200)
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "o.jsonl", "o1", 600, 40)
        self.register("o", "acct-a")
        report = self.run_report(*self.pane(10))
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        self.assertEqual((reading["percent"], reading["stale"], reading["forecast"]), (10.0, True, None))
        self.assertAlmostEqual(reading["observedAt"] / 1000, self.now - 7200, delta=1)
        figure = report["crew"][0]["quota"]["claude|acct-a|seven_day"]["session"]
        # Settled over the reading's own interval only, plus the raw delta since, and no extrapolation.
        self.assertEqual((figure["basis"], figure["open"]), ("settled", None))
        self.assertAlmostEqual(figure["percent"], 10.0)
        self.assertAlmostEqual(figure["since"], 0.0)

    def test_a_reading_of_unknown_age_is_stale_and_unsettled(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-a.jsonl", "a1", 60, 10)
        self.register("sess-a", "acct-a")
        report = self.run_report("--claude-session", "missing-session", "--claude-account", "acct-a",
                                 "--claude-limits", self.limits(25))
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        self.assertEqual((reading["percent"], reading["observedAt"], reading["stale"], reading["forecast"]), (25.0, None, True, None))
        figure = report["crew"][0]["quota"]["claude|acct-a|seven_day"]["session"]
        self.assertEqual((figure["percent"], figure["basis"], figure["since"]), (None, "raw", None))
        self.assertAlmostEqual(figure["share"], 1.0)
        self.assertEqual([r["observedAt"] for r in self.records()], [None])

    def test_a_reading_that_crossed_its_reset_is_not_an_anchor(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-a.jsonl", "a1", 60, 10)
        report = self.run_report(*self.pane(60, session="sess-a", resets_in=-5))
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        self.assertEqual((reading["percent"], reading["reset"], reading["forecast"]), (None, True, None))
        figure = report["crew"][0]["quota"]["claude|acct-a|seven_day"]["session"]
        self.assertEqual((figure["percent"], figure["basis"]), (None, "raw"))

    def test_a_new_reading_re_anchors_and_records_how_far_the_forecast_missed(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree, started=6 * 3600)
        pane = self.project(worktree) / "pane.jsonl"
        self.turn(pane, "p1", 3 * 3600, 100)
        self.turn(pane, "p2", 40 * 60)
        first = self.run_report(*self.pane(10, session="pane"))
        self.assertEqual(len(self.records()), 1)
        self.assertNotIn("residual", self.records()[0])
        self.assertAlmostEqual(first["quota"]["readings"]["claude|acct-a|seven_day"]["percent"], 10.0)
        # 50 more tokens, a reading 38 minutes after the first: 10% + 50 x (10/100) = 15% was forecast; the vendor says 17%.
        self.turn(pane, "p3", 5 * 60, 50)
        self.turn(pane, "p4", 120)
        second = self.run_report(*self.pane(17, session="pane"))
        self.assertAlmostEqual(second["quota"]["readings"]["claude|acct-a|seven_day"]["percent"], 17.0)
        record = self.records()[-1]
        self.assertEqual(len(self.records()), 2)
        self.assertAlmostEqual(record["residual"]["forecast"], 15.0)
        self.assertAlmostEqual(record["residual"]["error"], 2.0)
        self.assertAlmostEqual(record["residual"]["rise"], 7.0)
        self.assertAlmostEqual(record["residual"]["sinceMs"] / 60000, 38.0, delta=0.1)
        # One informative comparison is evidence, not calibration.
        self.assertEqual(second["quota"]["readings"]["claude|acct-a|seven_day"]["confidence"], {"label": "low", "samples": 1})

    def test_confidence_counts_informative_spaced_residuals_and_never_claims_more_than_they_show(self):
        def rec(at_min, rise, error):
            return {"provider": "claude", "account": "a", "scope": "s", "observedAt": at_min * 60000, "percent": 1.0,
                    "residual": {"rise": rise, "error": error, "forecast": 0, "anchorAt": 0, "sinceMs": 0}}
        none = quota.confidence([], "claude", "a", "s")
        self.assertEqual(none, {"label": "uncalibrated", "samples": 0})
        # A flat reading (rise under a point) proves nothing; two readings a minute apart are one sample.
        weak = [rec(1, 0.2, 0.0), rec(30, 2.0, 0.5), rec(31, 2.0, 0.1)]
        self.assertEqual(quota.confidence(weak, "claude", "a", "s"), {"label": "low", "samples": 1})
        self.assertEqual(quota.confidence(weak, "claude", "b", "s")["samples"], 0)
        good = [rec(30 * n, 4.0, 0.4) for n in range(1, 12)]
        self.assertEqual(quota.confidence(good, "claude", "a", "s"), {"label": "calibrated", "samples": 11})
        poor = [rec(30 * n, 4.0, 3.0) for n in range(1, 12)]
        self.assertEqual(quota.confidence(poor, "claude", "a", "s"), {"label": "low", "samples": 11})
        few = good[:9]
        self.assertEqual(quota.confidence(few, "claude", "a", "s")["label"], "low")


class ReadingHistoryTest(QuotaTestCase):
    def record(self, **over):
        base = dict(provider="claude", account="acct-a", source="session", scope="seven_day", kind="seven_day", percent=12.5,
                    resets_at=(self.now + DAY) * 1000, duration_ms=7 * DAY * 1000, observed_at=(self.now - 60) * 1000,
                    received_at=self.now * 1000, session="pane", plan="Max 5x")
        base.update(over)
        return quota.make_record(**base)

    def test_each_new_observation_is_one_private_line_without_secrets(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "pane.jsonl", "p1", 60, 10)
        with patch.dict(os.environ, {"AI_ACCT_FINGERPRINT": FINGERPRINT, "CLAUDE_CODE_OAUTH_TOKEN": LOGIN_ENV}):
            self.run_report(*self.pane(12.5, session="pane"))
        (record,) = self.records()
        self.assertEqual(sorted(record), sorted(["v", "provider", "account", "source", "kind", "scope", "percent", "resetsAt",
                                                 "durationMs", "observedAt", "receivedAt", "session", "plan"]))
        self.assertEqual((record["v"], record["provider"], record["account"], record["source"], record["scope"]),
                         (1, "claude", "acct-a", "session", "seven_day"))
        self.assertEqual(record["percent"], 12.5)
        self.assertAlmostEqual(record["observedAt"] / 1000, self.now - 60, delta=1)
        self.assertGreaterEqual(record["receivedAt"] / 1000, self.now - 1)
        self.assertEqual(record["durationMs"], 7 * DAY * 1000)
        self.assertNotIn("pane", self.history.read_text().replace('"session"', ""))
        self.assertEqual(len(record["session"]), 12)
        text = self.history.read_text()
        for secret in (FINGERPRINT, LOGIN_ENV, str(self.root)):
            self.assertNotIn(secret, text)
        self.assertEqual(stat.S_IMODE(os.stat(self.history).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.history.parent).st_mode), 0o700)

    def test_a_repeated_callback_is_not_new_but_an_unchanged_percent_in_a_new_response_is(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        pane = self.project(worktree) / "pane.jsonl"
        self.turn(pane, "p1", 300, 10)
        for _ in range(3):
            self.run_report(*self.pane(12.5, session="pane"))
        self.assertEqual(len(self.records()), 1)
        self.turn(pane, "p2", 30, 10)
        self.run_report(*self.pane(12.5, session="pane"))
        self.run_report(*self.pane(12.5, session="pane"))
        records = self.records()
        self.assertEqual([r["percent"] for r in records], [12.5, 12.5])
        self.assertEqual(len({r["observedAt"] for r in records}), 2)

    def test_a_reading_of_unknown_time_is_null_never_now_and_a_repeat_of_it_counts_once(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "pane.jsonl", "p1", 60, 10)
        for _ in range(2):
            self.run_report("--claude-session", "no-such-session", "--claude-account", "acct-a", "--claude-limits", self.limits(7.25))
        (record,) = self.records()
        self.assertIsNone(record["observedAt"])
        self.assertEqual(record["percent"], 7.25)
        self.assertGreater(record["receivedAt"], 0)

    def test_the_percent_is_kept_raw_without_rounding(self):
        quota.append_readings([self.record(percent=12.3456789)], self.now * 1000)
        self.assertEqual(self.records()[0]["percent"], 12.3456789)

    def test_concurrent_sessions_append_every_observation_exactly_once(self):
        barrier = threading.Barrier(8)
        written = []

        def session(n):
            barrier.wait()
            for i in range(25):
                records = [self.record(observed_at=(self.now - 10000 + n * 100 + i) * 1000, session=f"s{n}", percent=float(i))]
                # Every session also replays one shared observation, which must land once.
                records.append(self.record(observed_at=(self.now - 9000) * 1000, percent=1.0))
                written.append(quota.append_readings(records, self.now * 1000))

        threads = [threading.Thread(target=session, args=(n,)) for n in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertNotIn(None, written)
        lines = self.history.read_text().splitlines()
        parsed = [json.loads(line) for line in lines]
        self.assertEqual(len(parsed), 8 * 25 + 1)
        self.assertEqual(len({quota.observation_key(r) for r in parsed}), len(parsed))

    def test_a_locked_history_reports_failure_and_keeps_nothing_half_written(self):
        self.history.parent.mkdir(parents=True)
        with quota.locked(str(self.history)) as held:
            self.assertTrue(held)
            with patch.object(quota, "LOCK_SECONDS", 0.05):
                self.assertIsNone(quota.append_readings([self.record()], self.now * 1000))
        self.assertFalse(self.history.exists())
        self.assertEqual(quota.append_readings([self.record()], self.now * 1000), 1)

    def test_an_append_after_a_torn_line_is_not_swallowed_by_it(self):
        self.history.parent.mkdir(parents=True)
        self.history.write_text(json.dumps(self.record(session="before")) + "\n" + '{"v":1,"provider":"cl')
        self.assertEqual(quota.append_readings([self.record(session="after", percent=3.0)], self.now * 1000), 1)
        self.assertEqual([r["percent"] for r in quota.read_history(str(self.history))], [12.5, 3.0])

    def test_the_newest_queued_codex_readings_survive_a_long_rollout(self):
        entry = usage.fresh_entry()
        limits = lambda n: {"at": n, "plan": "plus", "windows": [{"percent": float(n), "minutes": 10080, "resetsAt": 5}]}
        with patch.object(quota, "PENDING_LIMIT", 5):
            for n in range(1, 11):
                usage.note_codex_reading(entry, "codex", limits(n))
        self.assertEqual([r["at"] for r in entry["readings"]], [6, 7, 8, 9, 10])

    def test_a_hand_edited_registry_cannot_crash_the_poll(self):
        path = Path(usage.accounts_path())
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"ok": {"account": "acct-a", "at": 5}, "bad": {"account": "acct-a", "at": "yesterday"}, "worse": 3}))
        self.assertEqual(list(quota.load_accounts(str(path))), ["ok"])

    def test_a_torn_or_foreign_line_is_skipped(self):
        self.history.parent.mkdir(parents=True)
        good = json.dumps(self.record())
        self.history.write_text(good + "\n" + '{"v": 99, "provider": "claude"}\n' + "not json\n" + '{"v":1,"provider":"claude"')
        self.assertEqual(len(quota.read_history(str(self.history))), 1)

    def test_old_readings_are_pruned_and_old_runs_thinned_to_where_the_percent_moved(self):
        now = self.now * 1000
        day = DAY * 1000
        ancient = [self.record(observed_at=now - 40 * day, received_at=now - 40 * day)]
        old = [self.record(observed_at=now - 10 * day + n * 60000, received_at=now - 10 * day + n * 60000,
                           percent=5.0 if n < 50 else 6.0, session="old") for n in range(100)]
        recent = [self.record(observed_at=now - 3600000 + n * 1000, received_at=now - 3600000 + n * 1000, percent=9.0, session="new")
                  for n in range(20)]
        kept = quota.compact(ancient + old + recent, now)
        self.assertEqual(len([r for r in kept if r["session"] == quota.anonymous("new")]), 20)
        thinned = [r for r in kept if r["session"] == quota.anonymous("old")]
        # First and last of the run, and both sides of the 5 -> 6 step.
        self.assertEqual([r["percent"] for r in thinned], [5.0, 5.0, 6.0, 6.0])
        self.assertFalse([r for r in kept if r["observedAt"] < now - 35 * day])

    def test_the_file_stays_bounded_by_shrinking_the_detail_window(self):
        now = self.now * 1000
        records = [self.record(observed_at=now - n * 1000, received_at=now - n * 1000, percent=float(n % 2), session=f"s{n % 7}")
                   for n in range(2000)]
        with patch.object(quota, "COMPACT_BYTES", 50_000), patch.object(quota, "TARGET_BYTES", 40_000):
            quota.append_readings(records, now)
            size = os.path.getsize(self.history)
        # Everything is inside the detail window, so only the hour-scale windows can thin it; it must still hold readings.
        self.assertGreater(size, 0)
        self.assertGreater(len(self.records()), 0)
        self.assertEqual(stat.S_IMODE(os.stat(self.history).st_mode), 0o600)

    def test_a_reading_past_retention_is_dropped_on_the_next_write(self):
        now = self.now * 1000
        quota.append_readings([self.record(observed_at=now - 36 * DAY * 1000, received_at=now - 36 * DAY * 1000, session="gone")], now - 36 * DAY * 1000)
        quota.append_readings([self.record(session="kept")], now)
        self.assertEqual([r["session"] for r in self.records()], [quota.anonymous("kept")])

    def test_each_session_reads_what_the_others_recorded_for_their_account(self):
        # Another session of account B saw 33% a minute ago: this pane shows B's measured reading with its true age.
        quota.append_readings([self.record(account="acct-b", percent=33.0)], self.now * 1000)
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-b.jsonl", "b1", 120, 10)
        self.register("sess-b", "acct-b")
        report = self.run_report()
        reading = report["quota"]["readings"]["claude|acct-b|seven_day"]
        self.assertEqual((reading["percent"], reading["source"], reading["stale"]), (33.0, "history", False))
        self.assertAlmostEqual(reading["observedAt"] / 1000, self.now - 60, delta=1)


class FiveHourWindowTest(QuotaTestCase):
    """The 5-hour window rides beside each account's weekly reading: the vendor percent only, never estimated."""

    def codex_rollout(self, creator, five=None, week=30.0):
        worktree = str(self.root / "codex-slot")
        (self.fm / "state" / "c.meta").write_text(f"harness=codex\nworktree={worktree}\nspawn_gen=s{self.now - 3600}.1.2\n")
        windows = {"secondary": {"used_percent": week, "window_minutes": 10080, "resets_at": self.now + DAY}}
        if five is not None:
            windows["primary"] = {"used_percent": five, "window_minutes": 300, "resets_at": self.now + 600}
        count = {"type": "event_msg", "timestamp": iso(self.now - 120), "payload": {"type": "token_count", "info": {
            "total_token_usage": {"input_tokens": 100, "total_tokens": 100}, "last_token_usage": {"input_tokens": 100}},
            "rate_limits": {"limit_id": "codex", "plan_type": "plus", **windows}}}
        path = Path(usage.CODEX_SESSIONS) / f"rollout-{creator}.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(row) + "\n" for row in [{"type": "session_meta", "payload": {"cwd": worktree, "creator_account_id": creator}}, count]))

    def test_the_pane_sessions_five_hour_window_is_its_accounts_measured_reading(self):
        worktree = str(self.root / "slot")
        self.task("a", worktree)
        self.turn(self.project(worktree) / "sess-a.jsonl", "a1", 600, 10)
        self.register("sess-a", "acct-a")
        self.turn(self.root / "home" / ".claude" / "projects" / "elsewhere" / "pane.jsonl", "p1", 60)
        limits = json.dumps([{"kind": "five_hour", "percentUsed": 12.5, "resetsAt": iso(self.now + 3600)},
                             {"kind": "seven_day", "percentUsed": 40, "resetsAt": iso(self.now + DAY)}])
        report = self.run_report("--claude-session", "pane", "--claude-account", "acct-a", "--claude-limits", limits)
        reading = report["quota"]["readings"]["claude|acct-a|seven_day"]
        self.assertEqual(reading["percent"], 40.0)
        five = reading["fiveHour"]
        self.assertEqual((five["percent"], five["resetsAt"], five["source"], five["stale"], five["reset"]),
                         (12.5, (self.now + 3600) * 1000, "session", False, False))
        self.assertAlmostEqual(five["observedAt"] / 1000, self.now - 60, delta=1)
        # The history keeps the weekly window only.
        self.assertEqual([r["scope"] for r in self.records()], ["seven_day"])

    def test_an_account_cache_without_a_five_hour_window_has_none(self):
        cache = Path(usage.ai_acct_cache_dir())
        cache.mkdir(parents=True)
        (cache / "claude-acct-a.limits.json").write_text(json.dumps({
            "fingerprint": FINGERPRINT, "time": self.now,
            "windows": {"five_hour": {"used": 3, "resets_at": self.now + 300}, "seven_day": {"used": 41, "resets_at": self.now + DAY}}}))
        (cache / "claude-acct-b.limits.json").write_text(json.dumps({
            "fingerprint": FINGERPRINT, "time": self.now, "windows": {"seven_day": {"used": 9, "resets_at": self.now + DAY}}}))
        report = self.run_report()
        readings = report["quota"]["readings"]
        five = readings["claude|acct-a|seven_day"]["fiveHour"]
        # Of unknown age like the weekly window beside it, so it is stale.
        self.assertEqual((five["percent"], five["resetsAt"], five["observedAt"], five["source"], five["stale"]),
                         (3.0, (self.now + 300) * 1000, None, "account cache", True))
        self.assertIsNone(readings["claude|acct-b|seven_day"]["fiveHour"])
        self.assertNotIn(FINGERPRINT, json.dumps(report))

    def test_a_five_hour_window_that_has_reset_says_so_instead_of_a_percent(self):
        cache = Path(usage.ai_acct_cache_dir())
        cache.mkdir(parents=True)
        (cache / "claude-acct-a.limits.json").write_text(json.dumps({
            "windows": {"five_hour": {"used": 88, "resets_at": self.now - 60}, "seven_day": {"used": 41, "resets_at": self.now + DAY}}}))
        five = self.run_report()["quota"]["readings"]["claude|acct-a|seven_day"]["fiveHour"]
        self.assertEqual((five["percent"], five["reset"]), (None, True))

    def test_a_codex_rollouts_300_minute_window_is_its_five_hour_reading(self):
        self.codex_rollout("creator-one", five=4.0)
        self.codex_rollout("creator-two")
        readings = self.run_report()["quota"]["readings"]
        by_week = {r["percent"]: r for k, r in readings.items() if k.startswith("codex|") and r["accountKnown"]}
        self.assertEqual(len(by_week), 1)
        five = by_week[30.0]["fiveHour"]
        self.assertEqual((five["percent"], five["source"], five["stale"]), (4.0, "codex log", False))
        self.assertAlmostEqual(five["observedAt"] / 1000, self.now - 120, delta=1)

    def test_codex_accounts_without_a_five_hour_window_or_identity_have_none(self):
        self.codex_rollout("creator-two")
        readings = self.run_report()["quota"]["readings"]
        self.assertEqual([r["fiveHour"] for k, r in readings.items() if k.startswith("codex|")], [None])


if __name__ == "__main__":
    unittest.main()
