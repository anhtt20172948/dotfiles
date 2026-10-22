"""Weekly-quota bookkeeping for crew-watch: account keys, the reading history, anchors and forecasts.

Every figure here belongs to one (provider, account, scope): the vendor percent
of one account's weekly limit is only ever compared with the local usage of that
same account. An account is a non-secret key: the ai-acct account NAME for
Claude, a short hash of the rollout's creator account id for Codex, or "unknown"
when a session cannot be tied to one (then only its raw local share is shown).

Anchor and forecast. A vendor reading P(t0) is an anchor. Until the next reading
the estimate is P(t0) + slope x weighted tokens in (t0, now], while the period is
valid. The slope is P(t0) over the weighted tokens of the period up to t0: the
current price ratios as an uncalibrated prior, never a fitted weight. A new
reading re-anchors and records its residual against the forecast the previous
one made; the residuals are the only evidence behind a confidence label.

A member's share of the week sums settled intervals instead of dividing the whole
week by a denominator that keeps growing: each rise of the vendor percent closes
a block, and the block's rise is split by the member's share of the account's
usage inside that block alone.

The reading history is one JSON line per genuinely new observation, in a private
file outside the repository (see history_path). It holds no token, fingerprint,
prompt or tool result.
"""

import fcntl
import hashlib
import json
import os
import re
import time
from bisect import bisect_left, bisect_right
from contextlib import contextmanager

SCHEMA_VERSION = 1
WEEK_MS = 7 * 86400000
STALE_MS = 30 * 60000
UNKNOWN = "unknown"
ACCOUNT_NAME = re.compile(r"[a-z0-9][a-z0-9_-]{0,31}")
# The vendor's reset time jitters by a few seconds between responses of one period.
RESET_JITTER_MS = 10_000

# History retention: five weekly periods, every observation for the last two days and
# only the readings where the percent moved (plus run ends) before that.
RETAIN_MS = 35 * 86400000
DETAIL_MS = 2 * 86400000
COMPACT_BYTES = 2 * 1024 * 1024
TARGET_BYTES = 1024 * 1024
LOCK_SECONDS = 2.0
PENDING_LIMIT = 500

# Confidence: only residuals of forecasts 10 minutes to 2 hours old count, and only
# those where the vendor percent rose at least a point (a flat reading proves nothing).
MIN_HORIZON_MS = 10 * 60000
MAX_HORIZON_MS = 2 * 3600000
INFORMATIVE_RISE = 1.0
CALIBRATED_SAMPLES = 10
CALIBRATED_P90_ERROR = 0.5


def anonymous(value):
    """A short one-way key of an identifier, for rows that must not carry the identifier itself."""
    return hashlib.sha256(("crew-watch:" + str(value)).encode("utf-8")).hexdigest()[:12]


def codex_account(creator_id):
    """A Codex account key from the rollout's creator account id; the id itself is never kept."""
    return "codex-" + anonymous(creator_id)[:8] if creator_id else UNKNOWN


def claude_account_name(value):
    """An ai-acct account name, or UNKNOWN when it is not a plain name."""
    text = str(value or "")
    return text if ACCOUNT_NAME.fullmatch(text) and text != UNKNOWN else UNKNOWN


def reading_key(provider, account, scope):
    return f"{provider}|{account}|{scope}"


def default_scope(provider):
    return "seven_day" if provider == "claude" else "weekly"


def is_stale(observed_at, now):
    """A reading older than half an hour, or of unknown age, is not current."""
    return observed_at is None or now - observed_at > STALE_MS


def same_period(a, b):
    """Two resets of one period: both unknown, or within the vendor's jitter."""
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) <= RESET_JITTER_MS


# ---- the reading history ---------------------------------------------------


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "crew-watch")


def history_path():
    return os.path.join(state_dir(), "readings.jsonl")


def record_time(record):
    return record.get("observedAt") or record["receivedAt"]


def make_record(provider, account, source, scope, kind, percent, resets_at, duration_ms, observed_at, received_at, session, plan):
    """One observation; observedAt is the time of the response that carried it, None when unknown."""
    return {
        "v": SCHEMA_VERSION,
        "provider": provider,
        "account": account,
        "source": source,
        "kind": kind,
        "scope": scope,
        "percent": percent,
        "resetsAt": resets_at,
        "durationMs": duration_ms,
        "observedAt": observed_at,
        "receivedAt": received_at,
        "session": anonymous(session),
        "plan": plan or "",
    }


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def valid_record(rec):
    return (isinstance(rec, dict) and rec.get("v") == SCHEMA_VERSION and rec.get("provider") in ("claude", "codex")
            and isinstance(rec.get("account"), str) and isinstance(rec.get("scope"), str) and number(rec.get("percent"))
            and number(rec.get("receivedAt")) and (rec.get("observedAt") is None or number(rec.get("observedAt")))
            and (rec.get("resetsAt") is None or number(rec.get("resetsAt"))))


def read_history(path=None):
    """Every valid record, in file order; a partial or foreign line is skipped, never fatal."""
    records = []
    try:
        with open(path or history_path(), "rb") as stream:
            for raw in stream:
                try:
                    rec = json.loads(raw)
                except ValueError:
                    continue
                if valid_record(rec):
                    records.append(rec)
    except OSError:
        pass
    return records


def observation_key(rec):
    """The same response seen again is the same observation; an unchanged percent in a new response is not.

    A reading of unknown time cannot be told apart from a repeated callback, so its
    session joins the key and an unchanged one from that session counts once.
    """
    undated = rec.get("observedAt") is None
    return (rec["provider"], rec["account"], rec["scope"], rec.get("observedAt"), rec["percent"], rec.get("resetsAt"),
            rec.get("session") if undated else "")


def thin(records, now, detail_ms):
    """Drop what is past retention; before the detail window keep only readings where the percent moved."""
    live = sorted((r for r in records if record_time(r) >= now - RETAIN_MS), key=record_time)
    runs = {}
    for rec in live:
        runs.setdefault((rec["provider"], rec["account"], rec["scope"]), []).append(rec)
    kept = []
    for run in runs.values():
        for i, rec in enumerate(run):
            moved = (i == 0 or i == len(run) - 1 or rec["percent"] != run[i - 1]["percent"]
                     or rec["percent"] != run[i + 1]["percent"])
            if record_time(rec) >= now - detail_ms or moved or rec.get("residual"):
                kept.append(rec)
    return sorted(kept, key=record_time)


def compact(records, now):
    """Records bounded by age and, past the target size, by progressively shorter detail windows."""
    detail = DETAIL_MS
    kept = thin(records, now, detail)
    while detail > 3600000 and sum(len(json.dumps(r)) + 1 for r in kept) > TARGET_BYTES:
        detail //= 4
        kept = thin(records, now, detail)
    return kept


def ensure_private_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)


@contextmanager
def locked(path, seconds=LOCK_SECONDS):
    """An exclusive advisory lock beside path, shared by every session; yields False if not taken in time."""
    fd = os.open(path + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    held = False
    try:
        deadline = time.monotonic() + seconds
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                held = True
                break
            except OSError:
                if time.monotonic() >= deadline:
                    break
                time.sleep(0.02)
        yield held
    finally:
        if held:
            fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def write_private(path, text):
    """Replace path atomically with a mode 600 file."""
    tmp = f"{path}.tmp.{os.getpid()}"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def append_lines(path, text):
    """Append whole lines; a torn last line left by a dead writer is closed first so it cannot swallow the new one."""
    data = text.encode("utf-8")
    fd = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        size = os.fstat(fd).st_size
        if size and os.pread(fd, 1, size - 1) != b"\n":
            data = b"\n" + data
        while data:
            data = data[os.write(fd, data):]
    finally:
        os.close(fd)


def append_readings(records, now, path=None):
    """Append the observations the history does not hold yet.

    Returns how many were new, or None when the history could not be written
    (locked for too long, or the disk refused): the caller keeps its records.
    Concurrent sessions take turns on the lock; each append is one write.
    """
    path = path or history_path()
    try:
        ensure_private_dir(os.path.dirname(path))
        with locked(path) as held:
            if not held:
                return None
            existing = read_history(path)
            seen = {observation_key(r) for r in existing}
            fresh = []
            for rec in records:
                key = observation_key(rec)
                if key not in seen:
                    seen.add(key)
                    fresh.append(rec)
            if fresh:
                append_lines(path, "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in fresh))
            os.chmod(path, 0o600)
            oldest = min((record_time(r) for r in existing), default=now)
            if os.path.getsize(path) > COMPACT_BYTES or oldest < now - RETAIN_MS:
                write_private(path, "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in compact(existing + fresh, now)))
            return len(fresh)
    except OSError:
        return None


# ---- session -> account registry ------------------------------------------


def load_accounts(path):
    """Claude session id -> {"account": name, "at": ms}, as the sessions that run this mod recorded it."""
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {sid: v for sid, v in data.items()
            if isinstance(v, dict) and isinstance(v.get("account"), str) and number(v.get("at"))}


def register_account(path, session_id, account, now, keep_ms=30 * 86400000, refresh_ms=6 * 3600000):
    """Remember which account a Claude session runs as (a name, never a fingerprint); returns the registry."""
    known = load_accounts(path)
    entry = known.get(session_id)
    if entry and entry["account"] == account and now - entry.get("at", 0) < refresh_ms:
        return known
    try:
        ensure_private_dir(os.path.dirname(path))
        with locked(path) as held:
            if not held:
                return known
            known = load_accounts(path)
            known[session_id] = {"account": account, "at": now}
            known = {sid: v for sid, v in known.items() if now - v.get("at", 0) < keep_ms}
            write_private(path, json.dumps(known))
    except OSError:
        pass
    return known


# ---- costs by request time -------------------------------------------------


class CostIndex:
    """Weighted cost by request timestamp, queried by half-open time ranges."""

    def __init__(self, *slot_maps, since=0):
        merged = {}
        for slots in slot_maps:
            for key, (session, tools) in slots.items():
                at = int(key)
                if at >= since:
                    old = merged.get(at, (0.0, 0.0))
                    merged[at] = (old[0] + session, old[1] + tools)
        self.times = sorted(merged)
        self.session = [0.0]
        self.tools = [0.0]
        for at in self.times:
            self.session.append(self.session[-1] + merged[at][0])
            self.tools.append(self.tools[-1] + merged[at][1])

    def between(self, lo, hi, lo_inclusive=False):
        """(session, tools) of requests with lo < at <= hi, or lo <= at <= hi when lo_inclusive."""
        i = bisect_left(self.times, lo) if lo_inclusive else bisect_right(self.times, lo)
        j = bisect_right(self.times, hi)
        if j <= i:
            return 0.0, 0.0
        return max(0.0, self.session[j] - self.session[i]), max(0.0, self.tools[j] - self.tools[i])

    def empty(self):
        return not self.times


# ---- anchors, blocks and forecasts ----------------------------------------


def pick_anchor(candidates, now):
    """The freshest reading still in force; a window that has reset says nothing about the new one.

    Candidates are ordered by the time of the response that carried them (unknown
    last); between equals a live source beats the history that replays it.
    """
    live = [c for c in candidates if c["resetsAt"] is None or c["resetsAt"] > now]
    return max(live, key=lambda c: (c["observedAt"] or 0, c["source"] != "history")) if live else None


def period_readings(history, provider, account, scope, resets_at, start):
    """Dated readings of one period of one key, oldest first."""
    return sorted((r for r in history if r["provider"] == provider and r["account"] == account and r["scope"] == scope
                   and r.get("observedAt") is not None and r["observedAt"] >= start and same_period(r.get("resetsAt"), resets_at)),
                  key=lambda r: r["observedAt"])


def settled_blocks(readings, start):
    """(blocks, boundary, boundary_inclusive, percent) from the period start through the last rise.

    A block is (lo, hi, rise, lo_inclusive): the usage since the previous rise of the
    vendor percent, which is what produced the rise. An unchanged or fallen reading
    settles nothing: a fall is never refunded to anyone.
    """
    blocks = []
    boundary, inclusive, previous = start, True, 0.0
    for rec in readings:
        if rec["percent"] > previous:
            blocks.append((boundary, rec["observedAt"], rec["percent"] - previous, inclusive))
            boundary, inclusive, previous = rec["observedAt"], False, rec["percent"]
    return blocks, boundary, inclusive, previous


def settled_percent(blocks, member, account, dim):
    """The member's points of the week over the blocks: each rise split by its share of the account's usage in that block."""
    total = 0.0
    for lo, hi, rise, inclusive in blocks:
        # The rise is the whole account's usage; a tool call's cost is part of its session's, so the
        # denominator is always the account's whole-session cost.
        whole = account.between(lo, hi, inclusive)[0]
        if whole > 0:
            total += rise * min(whole, member.between(lo, hi, inclusive)[dim]) / whole
    return total


def prior_slope(percent, account, start, anchored_at):
    """Points per weighted token: the period's own average up to the anchor (an uncalibrated prior), or None."""
    if anchored_at is None or percent <= 0:
        return None
    spent = account.between(start, anchored_at, True)[0]
    return percent / spent if spent > 0 else None


def forecast_from(prev, now_or_at, account, start):
    """P(t0) + slope x tokens in (t0, at] from a dated reading, or None when no slope exists."""
    slope = prior_slope(prev["percent"], account, start, prev["observedAt"])
    if slope is None:
        return None
    return prev["percent"] + slope * account.between(prev["observedAt"], now_or_at)[0]


def residual_against(history, rec, account, indexed=True):
    """How far the forecast the newest reading 10 minutes to 2 hours older made missed this reading, or None."""
    if not indexed or rec.get("observedAt") is None:
        return None
    window = rec["durationMs"] or WEEK_MS
    start = max((rec["resetsAt"] - window) if rec.get("resetsAt") else rec["observedAt"] - WEEK_MS, rec["observedAt"] - WEEK_MS)
    older = [r for r in period_readings(history, rec["provider"], rec["account"], rec["scope"], rec.get("resetsAt"), start)
             if MIN_HORIZON_MS <= rec["observedAt"] - r["observedAt"] <= MAX_HORIZON_MS]
    if not older:
        return None
    prev = older[-1]
    expected = forecast_from(prev, rec["observedAt"], account, start)
    if expected is None:
        return None
    return {"forecast": expected, "anchorAt": prev["observedAt"], "sinceMs": rec["observedAt"] - prev["observedAt"],
            "rise": rec["percent"] - prev["percent"], "error": rec["percent"] - expected}


def confidence(history, provider, account, scope):
    """{"label", "samples"}: uncalibrated without evidence, low with some, calibrated once the forecast has held up.

    Evidence is the residuals recorded when a new reading met its forecast, one per
    10 minutes at most, from readings where the vendor percent rose at least a
    point. Calibrated means the forecast tracked at least ten of them within half
    their rise (90th percentile); it says nothing about fitted weights, which are
    not shipped.
    """
    found = sorted((r for r in history if r["provider"] == provider and r["account"] == account and r["scope"] == scope
                    and isinstance(r.get("residual"), dict) and r.get("observedAt") is not None
                    and r["residual"].get("rise", 0) >= INFORMATIVE_RISE), key=lambda r: r["observedAt"])
    spaced, last = [], None
    for rec in found:
        if last is None or rec["observedAt"] - last >= MIN_HORIZON_MS:
            spaced.append(abs(rec["residual"]["error"]) / rec["residual"]["rise"])
            last = rec["observedAt"]
    if not spaced:
        return {"label": "uncalibrated", "samples": 0}
    spaced.sort()
    p90 = spaced[min(len(spaced) - 1, int(0.9 * len(spaced)))]
    label = "calibrated" if len(spaced) >= CALIBRATED_SAMPLES and p90 <= CALIBRATED_P90_ERROR else "low"
    return {"label": label, "samples": len(spaced)}
