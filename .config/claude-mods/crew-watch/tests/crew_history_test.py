"""The crew ledger: upserts, finishing torn-down tasks, retention, compaction and the per-model windows."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("crew_history", SCRIPTS / "crew_history.py")
ledger = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ledger)

HOUR = 3600000
NOW = 1_800_000 * HOUR
DAY = 24 * HOUR


def record(tid, since=NOW - HOUR, seen=NOW, finished=None, home="/fm", root="/fm", usage=None):
    return {"v": 1, "id": tid, "home": home, "root": root, "harness": "claude", "model": "", "effort": "", "kind": "ship",
            "project": "dotfiles", "since": since, "lastAt": seen, "seenAt": seen, "finishedAt": finished,
            "usage": usage if usage is not None else {"claude": {"acct": {"claude-opus-5-5": {str(NOW): [1, 10, 2, 100, 5, 0]}}}}}


def keyed(*records):
    return {ledger.key(r): r for r in records}


class UpsertTest(unittest.TestCase):
    def test_a_task_gone_from_a_visited_home_is_finished_when_it_was_last_seen(self):
        old = record("a", seen=NOW - 5000)
        view, out = ledger.upsert(keyed(old), [], {"/fm"}, NOW)
        self.assertEqual(view[ledger.key(old)]["finishedAt"], NOW - 5000)
        self.assertEqual(out, [{**old, "finishedAt": NOW - 5000}])

    def test_a_task_of_a_home_this_poll_did_not_read_stays_unfinished(self):
        old = record("a", home="/elsewhere", root="/elsewhere", seen=NOW - 5000)
        view, out = ledger.upsert(keyed(old), [], {"/fm"}, NOW)
        self.assertIsNone(view[ledger.key(old)]["finishedAt"])
        self.assertEqual(out, [])

    def test_a_nested_crewmate_is_finished_through_the_home_it_was_reached_from(self):
        old = record("child", home="/removed-secondmate", root="/fm", seen=NOW - 5000)
        view, _ = ledger.upsert(keyed(old), [], {"/fm"}, NOW)
        self.assertEqual(view[ledger.key(old)]["finishedAt"], NOW - 5000)

    def test_every_poll_preserves_its_exact_last_seen_time(self):
        old = record("a", seen=NOW - 5000)
        live = {**old, "seenAt": NOW}
        view, out = ledger.upsert(keyed(old), [live], {"/fm"}, NOW)
        self.assertEqual((out, view[ledger.key(live)]), ([live], live))
        finished, _ = ledger.upsert(view, [], {"/fm"}, NOW + 5000)
        self.assertEqual(finished[ledger.key(live)]["finishedAt"], NOW)

    def test_a_record_finished_by_a_missed_listing_comes_back_once(self):
        old = record("a", seen=NOW - 5000, finished=NOW - 5000)
        live = record("a")
        view, out = ledger.upsert(keyed(old), [live], {"/fm"}, NOW)
        self.assertEqual(list(view.values()), [live])
        self.assertEqual(out, [live])

    def test_a_first_start_that_moved_back_replaces_the_record_and_retires_the_old_key(self):
        old = record("a", since=NOW - HOUR, seen=NOW - 5000)
        live = record("a", since=NOW - 2 * HOUR)
        view, out = ledger.upsert(keyed(old), [live], {"/fm"}, NOW)
        self.assertEqual(list(view.values()), [live])
        self.assertEqual(out, [{**old, "gone": True}, live])

    def test_a_new_task_reusing_an_id_finishes_the_old_one_and_keeps_both(self):
        old = record("a", since=NOW - DAY, seen=NOW - HOUR)
        live = record("a", since=NOW - 60_000)
        view, _ = ledger.upsert(keyed(old), [live], {"/fm"}, NOW)
        self.assertEqual(view[ledger.key(old)]["finishedAt"], NOW - HOUR)
        self.assertIsNone(view[ledger.key(live)]["finishedAt"])

    def test_records_past_the_retention_horizon_are_dropped(self):
        old = record("a", seen=NOW - ledger.RETAIN_MS - 1, finished=NOW - ledger.RETAIN_MS - 1)
        kept = record("b", seen=NOW - ledger.RETAIN_MS + 1, finished=NOW - ledger.RETAIN_MS + 1)
        view, _ = ledger.upsert(keyed(old, kept), [], {"/fm"}, NOW)
        self.assertEqual(list(view), [ledger.key(kept)])


class SaveTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "state" / "crew-history.jsonl"

    def test_every_update_replaces_the_file_atomically_and_keeps_one_record_per_task(self):
        ledger.save([record("a")], {"/fm"}, NOW, str(self.path))
        with self.path.open() as old_snapshot:
            ledger.save([], {"/fm"}, NOW + 5000, str(self.path))
            self.assertIsNone(json.loads(old_snapshot.read())["finishedAt"])
        rows = [json.loads(line) for line in self.path.read_text().splitlines()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["finishedAt"], NOW)

    def test_failed_atomic_replace_keeps_the_previous_snapshot(self):
        ledger.save([record("a")], {"/fm"}, NOW, str(self.path))
        before = self.path.read_bytes()
        with patch.object(ledger.quota.os, "replace", side_effect=OSError("disk unavailable")):
            _, saved = ledger.save([], {"/fm"}, NOW + 5000, str(self.path))
        self.assertFalse(saved)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.path.parent.glob("*.tmp.*")), [])

    def test_the_ledger_is_private_and_skips_a_torn_line(self):
        view, saved = ledger.save([record("a")], {"/fm"}, NOW, str(self.path))
        self.assertTrue(saved)
        self.assertEqual(oct(self.path.stat().st_mode & 0o777), "0o600")
        self.assertEqual(oct(self.path.parent.stat().st_mode & 0o777), "0o700")
        with self.path.open("a") as stream:
            stream.write('{"v": 1, "id": "torn"')
        ledger.save([], {"/fm"}, NOW + 1000, str(self.path))
        latest, lines = ledger.read_ledger(str(self.path))
        self.assertEqual(lines, 1)
        self.assertEqual([r["finishedAt"] for r in latest.values()], [NOW])

    def test_repeated_polls_keep_one_line_per_task(self):
        for poll in range(5):
            ledger.save([record("a", seen=NOW + poll * 5000)], {"/fm"}, NOW + poll * 5000, str(self.path))
        _, lines = ledger.read_ledger(str(self.path))
        self.assertEqual(lines, 1)
        self.assertEqual(list(self.path.parent.glob("*.tmp.*")), [])

    def test_expired_records_are_compacted_away(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps(record("old", seen=NOW - ledger.RETAIN_MS - 1, finished=NOW - ledger.RETAIN_MS - 1)) + "\n")
        ledger.save([record("a")], {"/fm"}, NOW, str(self.path))
        self.assertEqual([r["id"] for r in ledger.read_ledger(str(self.path))[0].values()], ["a"])
        self.assertEqual(len(self.path.read_text().splitlines()), 1)

    def test_a_ledger_held_by_another_session_still_returns_this_polls_view(self):
        ledger.save([record("a", seen=NOW - 5000)], {"/fm"}, NOW - 5000, str(self.path))
        with patch.object(ledger.quota, "locked") as locked:
            locked.return_value.__enter__.return_value = False
            view, saved = ledger.save([], {"/fm"}, NOW, str(self.path))
        self.assertFalse(saved)
        self.assertEqual([r["finishedAt"] for r in view.values()], [NOW - 5000])
        self.assertIsNone(next(iter(ledger.read_ledger(str(self.path))[0].values()))["finishedAt"])

    def test_nothing_is_written_while_no_home_has_a_task(self):
        view, saved = ledger.save([], {"/fm"}, NOW, str(self.path))
        self.assertEqual((view, saved, self.path.exists()), ({}, True, False))

    def test_malformed_usage_is_skipped_before_it_can_break_the_summary(self):
        self.path.parent.mkdir(parents=True)
        invalid = [None, {"claude": []}, {"claude": {"acct": {"opus": {"bad-time": [1] * 6}}}},
                   {"claude": {"acct": {"opus": {"0": [1, 2]}}}},
                   {"claude": {"acct": {"opus": {"0": [float("nan")] * 6}}}}]
        self.path.write_text(ledger.dump([record(str(i), usage=u) if u is not None else {**record(str(i)), "usage": None}
                                         for i, u in enumerate(invalid)] + [record("valid")]))
        records, _ = ledger.read_ledger(str(self.path))
        self.assertEqual([r["id"] for r in records.values()], ["valid"])
        self.assertEqual(ledger.summarize(records.values(), {}, NOW)["all"]["measured"], 1)


class SummaryTest(unittest.TestCase):
    def reading(self, provider, account, start, known=True):
        return {f"{provider}|{account}|weekly": {"provider": provider, "account": account, "windowStart": start, "windowStartKnown": known}}

    def test_week_uses_the_exact_reset_boundary_instead_of_rounding_to_an_hour(self):
        start = NOW - HOUR + 123456
        usage = {"claude": {"acct": {"opus": {str(start - 1): [1, 100, 0, 0, 0, 0],
                                                str(start): [1, 5, 0, 0, 0, 0],
                                                str(NOW + 1): [1, 999, 0, 0, 0, 0]}}}}
        result = ledger.summarize([record("a", usage=usage)], self.reading("claude", "acct", start), NOW)
        self.assertEqual(result["week"]["models"][0]["input"], 5)

    def test_missing_quota_reset_never_substitutes_a_rolling_week(self):
        result = ledger.summarize([record("a")], {}, NOW)
        self.assertEqual(result["week"]["models"], [])
        self.assertEqual(result["week"]["unwindowed"], 1)
        self.assertEqual(result["all"]["models"][0]["input"], 10)
        self.assertEqual(result["week"]["measured"], 0)

    def test_total_crew_counts_only_tasks_with_measured_usage_even_when_accounts_are_mixed(self):
        mixed = {"claude": {"acct": {"opus": {str(NOW): [1, 10, 0, 0, 0, 0]}}},
                 "codex": {"unknown": {"gpt": {str(NOW): [1, 20, 0, 0, 0, 0]}}}}
        out = ledger.summarize([record("mixed", usage=mixed), record("unknown")],
                               self.reading("claude", "acct", NOW - DAY), NOW)
        self.assertEqual((out["week"]["measured"], out["week"]["unwindowed"]), (2, 1))

    def test_the_week_counts_each_accounts_requests_from_its_own_reset_and_all_time_counts_everything(self):
        before, after = str(NOW - 30 * HOUR), str(NOW - 2 * HOUR)
        usage = {"claude": {"acct": {"claude-opus-5-5": {before: [1, 100, 0, 0, 0, 0], after: [2, 10, 1, 0, 0, 0]}}},
                 "codex": {"codex-1": {"gpt-6": {before: [1, 7, 0, 0, 0, 0]}}}}
        records = [record("a", usage=usage, finished=NOW - HOUR), record("b")]
        # Each provider has its own measured quota window.
        readings = {**self.reading("claude", "acct", NOW - DAY - 3000), **self.reading("codex", "codex-1", NOW - 7 * DAY)}
        out = ledger.summarize(records, readings, NOW)
        week = {r["model"]: r for r in out["week"]["models"]}
        self.assertEqual(week["claude-opus-5-5"], {"model": "claude-opus-5-5", "provider": "claude", "requests": 3, "input": 10 + 10,
                                                   "output": 3, "cacheRead": 100, "cacheWrite": 5, "reasoning": 0, "crewmates": 2})
        self.assertEqual(week["gpt-6"]["input"], 7)
        self.assertEqual((out["week"]["finished"], out["week"]["live"]), (1, 1))
        everything = {r["model"]: r for r in out["all"]["models"]}
        self.assertEqual(everything["claude-opus-5-5"]["input"], 120)
        self.assertEqual([r["model"] for r in out["all"]["models"]], ["claude-opus-5-5", "gpt-6"])

    def test_a_crewmate_without_readable_usage_is_counted_apart_and_only_while_recent(self):
        recent = record("pi", usage={}, seen=NOW - HOUR, finished=NOW - HOUR)
        old = record("pi-old", usage={}, seen=NOW - 8 * DAY, finished=NOW - 8 * DAY)
        out = ledger.summarize([recent, old], {}, NOW)
        self.assertEqual((out["week"]["unreadable"], out["week"]["finished"]), (1, 1))
        self.assertEqual((out["all"]["unreadable"], out["all"]["finished"]), (2, 2))
        self.assertEqual(out["week"]["models"], [])

    def test_usage_only_before_the_week_leaves_the_crewmate_out_of_it(self):
        usage = {"claude": {"acct": {"claude-haiku-5-5": {str(NOW - 200 * HOUR): [1, 1, 1, 0, 0, 0], "0": [1, 1, 0, 0, 0, 0]}}}}
        out = ledger.summarize([record("a", usage=usage, finished=NOW - DAY)], self.reading("claude", "acct", NOW - 7 * DAY), NOW)
        self.assertEqual((out["week"]["models"], out["week"]["finished"]), ([], 0))
        self.assertEqual(out["all"]["models"][0]["requests"], 2)


if __name__ == "__main__":
    unittest.main()
