"""The crew ledger: one record per Firstmate task, kept after the task is torn down.

Teardown removes a task's state/<id>.meta, and pooled worktrees are reused, so
once a crewmate is gone nothing else says which harness and models it ran or
what it spent. Every poll upserts one record per live task here, keyed by its
home, id and first start; a task whose meta is gone from a home this poll read
is marked finished at the time it was last seen. Nothing is backfilled: the
ledger starts with the first poll that runs this code.

A record holds the task's id, home, the home it was reached from (root), its
harness, dispatched model and effort, kind, project, first start, last activity
and its token counts per provider, account, model and request time. No credential,
prompt, tool text or worktree path is kept. Each poll atomically replaces the
JSON-lines snapshot in the private reading-history folder; records 90 days
past their end are dropped.
"""

import json
import math
import os

import crew_quota as quota

SCHEMA_VERSION = 1
TOKEN_FIELDS = ("requests", "input", "output", "cacheRead", "cacheWrite", "reasoning")
RETAIN_MS = 90 * 86400000


def ledger_path():
    return os.path.join(quota.state_dir(), "crew-history.jsonl")


def number(value):
    return quota.number(value) and math.isfinite(value)


def valid_usage(usage):
    if not isinstance(usage, dict):
        return False
    for provider, accounts in usage.items():
        if not isinstance(provider, str) or not isinstance(accounts, dict):
            return False
        for account, models in accounts.items():
            if not isinstance(account, str) or not isinstance(models, dict):
                return False
            for model, samples in models.items():
                if not isinstance(model, str) or not isinstance(samples, dict):
                    return False
                for at, counts in samples.items():
                    if (not isinstance(at, str) or not at.isascii() or not at.isdecimal()
                            or not isinstance(counts, list) or len(counts) != len(TOKEN_FIELDS)
                            or not all(number(n) for n in counts)):
                        return False
    return True


def valid(rec):
    return (isinstance(rec, dict) and rec.get("v") == SCHEMA_VERSION and isinstance(rec.get("id"), str)
            and isinstance(rec.get("home"), str) and isinstance(rec.get("root"), str) and number(rec.get("since"))
            and number(rec.get("seenAt")) and (rec.get("finishedAt") is None or number(rec.get("finishedAt")))
            and valid_usage(rec.get("usage")))


def key(rec):
    return rec["home"], rec["id"], rec["since"]


def read_ledger(path=None):
    """(the latest valid version of each record, the lines read); a torn or foreign line is skipped, never fatal."""
    latest, lines = {}, 0
    try:
        with open(path or ledger_path(), "rb") as stream:
            for raw in stream:
                lines += 1
                try:
                    rec = json.loads(raw)
                except ValueError:
                    continue
                if not valid(rec):
                    continue
                if rec.get("gone"):
                    latest.pop(key(rec), None)
                else:
                    latest[key(rec)] = rec
    except OSError:
        pass
    return latest, lines


def ended(rec):
    return rec["finishedAt"] if rec["finishedAt"] is not None else rec["seenAt"]


def upsert(current, live, visited, now):
    """(the ledger after this poll, the changed records).

    current: the latest record per key. live: this poll's record of each task. visited: the homes (real paths)
    this poll read in full. A live task replaces its own record, or an unfinished one of the same home and id
    whose first start has since moved back (the start is the earliest status stamp, so it only moves back, and
    never past the time the record was last seen). Any other unfinished record of a visited home, or reached
    from a visited one, is finished at the time it was last seen: its meta is gone.
    """
    fresh = {(rec["home"], rec["id"]): rec for rec in live}
    view, out = {}, []
    for k, rec in current.items():
        match = fresh.get((rec["home"], rec["id"]))
        if match is not None and match["since"] == rec["since"]:
            continue
        if match is not None and rec["finishedAt"] is None and match["since"] <= rec["seenAt"]:
            out.append({**rec, "gone": True})
            continue
        if rec["finishedAt"] is None and (match is not None or rec["home"] in visited or rec["root"] in visited):
            rec = {**rec, "finishedAt": rec["seenAt"]}
            out.append(rec)
        view[k] = rec
    for rec in live:
        old = current.get(key(rec))
        if old != rec:
            out.append(rec)
            view[key(rec)] = rec
        else:
            view[key(rec)] = old
    return {k: rec for k, rec in view.items() if ended(rec) >= now - RETAIN_MS}, out


def dump(records):
    return "".join(json.dumps(rec, separators=(",", ":")) + "\n" for rec in records)


def save(live, visited, now, path=None):
    """Upsert this poll into the ledger; (the records after it, whether it was written).

    Concurrent sessions take turns on the lock. Without it, or when the disk refuses, the
    records are still returned (from the file as read), so the pane can show them this time.
    """
    path = path or ledger_path()
    try:
        quota.ensure_private_dir(os.path.dirname(path))
        with quota.locked(path) as held:
            current, _ = read_ledger(path)
            view, out = upsert(current, live, visited, now)
            if not held:
                return view, False
            expired = any(ended(rec) < now - RETAIN_MS for rec in current.values())
            if expired or out:
                quota.write_private(path, dump(view.values()))
            return view, True
    except OSError:
        return upsert(read_ledger(path)[0], live, visited, now)[0], False


def week_starts(readings, now):
    """Only dated quota windows qualify; an unknown reset never becomes a rolling week."""
    return {(r["provider"], r["account"]): r["windowStart"] for r in readings.values()
            if r.get("windowStartKnown") and number(r.get("windowStart")) and r["windowStart"] <= now}


def summarize(records, readings, now):
    """The per-model sums of the records over the quota week and over all time.

    A record counts in a window when it has usage there; one with no readable usage at
    all counts when it was seen in the last 7 days (week) or ever (all time).
    """
    starts = week_starts(readings, now)
    out = {}
    for window in ("week", "all"):
        models, finished, live, unread, unwindowed, measured = {}, 0, 0, 0, 0, 0
        for rec in records:
            used, missing_window = False, False
            for provider, accounts in rec["usage"].items():
                for account, by_model in accounts.items():
                    first = starts.get((provider, account)) if window == "week" else None
                    if window == "week" and first is None:
                        missing_window = True
                        continue
                    for model, samples in by_model.items():
                        sums = [0] * len(TOKEN_FIELDS)
                        for at, counts in samples.items():
                            if first is None or (0 < int(at) <= now and int(at) >= first):
                                sums = [a + b for a, b in zip(sums, counts)]
                        if not any(sums):
                            continue
                        used = True
                        row = models.setdefault((provider, model), {"model": model, "provider": provider, "crew": set(),
                                                                    **dict.fromkeys(TOKEN_FIELDS, 0)})
                        row["crew"].add(key(rec))
                        for field, n in zip(TOKEN_FIELDS, sums):
                            row[field] += n
            unwindowed += missing_window
            measured += used
            if not used and not missing_window:
                # Its usage all fell outside the window, or it has none and was last seen before it.
                if any(rec["usage"].values()) or (window == "week" and ended(rec) < now - quota.WEEK_MS):
                    continue
                unread += 1
            finished += rec["finishedAt"] is not None
            live += rec["finishedAt"] is None
        rows = [{**{k: v for k, v in row.items() if k != "crew"}, "crewmates": len(row["crew"])} for row in models.values()]
        total = lambda r: r["input"] + r["output"] + r["cacheRead"] + r["cacheWrite"]  # noqa: E731
        out[window] = {"window": window, "models": sorted(rows, key=lambda r: (-total(r), r["model"])),
                       "finished": finished, "live": live, "unreadable": unread, "unwindowed": unwindowed,
                       "crewmates": finished + live, "measured": measured}
    return out
