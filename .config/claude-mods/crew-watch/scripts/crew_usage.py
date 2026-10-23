#!/usr/bin/env python3
"""Summarize what every live Firstmate crewmate is doing and what it costs.

Reads each home's state/*.meta (one per live task), finds the task's own
transcripts by its worktree, written since the task first started (pooled
worktrees are reused; a relaunch keeps earlier usage, even under another
harness), and prints one JSON document on stdout:

  {"generatedAt": ms, "crew": [...], "totals": {...}, "quota": {...}, "history": {...}, "errors": [...]}

Every task reads both Claude transcripts from ~/.claude/projects/<encoded
worktree>/**.jsonl (subagent transcripts included) and Codex rollouts in
~/.codex/sessions whose session cwd is the worktree. A task with neither and
another harness gets a meta-only row.

Parsing is incremental: per-file byte offsets and partial sums are cached in
~/.cache/crew-watch/cache.json, so a poll only reads what was appended.
A secondmate's own home is followed recursively for its crew. A resumed or
forked Claude session copies earlier messages, ids included, into a new
transcript: each message id counts once, in the first transcript parsed that
logged it.

Tokens per model. Every request's tokens are also kept per provider, model and
request time (each Codex count's growth goes to the model then serving), so a crewmate's
per-model sums add up to its totals. The crew ledger (crew_history.py) keeps them
per task after the task is torn down; "history" sums the ledger's records of the
watched homes per model, over the quota week and over all time.

Tokens per tool call. The API bills requests, not tool calls, so a call is
charged with (a) the output tokens of the request that emitted it, split evenly
between that request's calls, and (b) the input its result added to the next
request: the growth of the context window (next context - this context - this
request's output), split between the request's calls by result size. When there
is no next request yet, or the growth is unusable (negative after a compaction,
no usage in the log), (b) is estimated from the result size at four characters
per token and flagged as estimated. Codex rollouts work the same way from
their token_count events; a log without usage fields attributes nothing.
This is a call's direct cost: every later request re-reads its result from the
cache, and those re-reads count to the session only, never to the call.

Weekly quota. Vendors publish no weekly caps in tokens, so none is hard-coded.
Every figure is keyed by provider + account + scope (see crew_quota.py): the
percent of one account's limit is only compared with the local usage of that
same account. A Claude session is tied to its account by the ai-acct name the
pane passes (--claude-account, found from AI_ACCT_FINGERPRINT) and a registry of
session id -> account name that every session keeps; a Codex rollout by a hash
of its creator account id. A session of no known account is "unknown" and shows
only its raw share of local usage.

The vendor percent is an anchor, dated by the response that carried it: the
rate limits of the pane session's last API response (--claude-limits, dated by
the newest response in its own transcript, found by --claude-session), the
reading history, ai-acct's stored limit windows (of unknown age) and Codex
rollout rate-limit events. The freshest one whose window has not reset wins.
Each weekly reading also carries the account's 5-hour window as the vendor
reported it (fiveHour), from the same sources but the history: shown, never
estimated or recorded.
Every new observation is appended to ~/.local/state/crew-watch/readings.jsonl.
Between readings the estimate is the anchor plus the weighted tokens since it,
priced by PRICE_RATIO and FAMILY_PRICE below, with a slope that is an
uncalibrated prior. A member's share sums settled intervals (each rise of the
vendor percent split by the member's share of that interval alone), so usage
after the reading cannot change it. A reading older than STALE_MS, or of unknown
age, is stale: it keeps its timestamp and only the raw local delta is shown.
Costs are kept per request, so a task start and a window start cut at the
request's own time, never at a file's mtime or a 15-minute bucket.
"""

import argparse
import ast
import json
import os
import re
import shlex
import sys
import time
from datetime import datetime

# `python3 -I` leaves the script's own folder off sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crew_history as ledger  # noqa: E402
import crew_quota as quota  # noqa: E402

CACHE_VERSION = 12
HOME = os.path.expanduser("~")
CLAUDE_PROJECTS = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude")), "projects")
CODEX_SESSIONS = os.path.join(os.environ.get("CODEX_HOME", os.path.join(HOME, ".codex")), "sessions")
CACHE_PATH = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "crew-watch", "cache.json")
LOOKBACK_DAYS = 30
SNIPPET = 180
MAX_EVENTS = 10
ACTIVITY_MINUTES = 60
WEEK_MS = quota.WEEK_MS
FIVE_HOUR_MINUTES = 300
CHARS_PER_TOKEN = 4
SCAN_BUDGET_SECONDS = 10
RESIDUAL_LIMIT = 50
STALE_MS = quota.STALE_MS
TOKEN_FIELDS = ledger.TOKEN_FIELDS

# Relative price of a token by type, per provider (input = 1). Only ratios
# matter for a share: a cache read costs a tenth of an input token, a Claude
# cache write a quarter more (twice as much when kept for an hour), an output
# token several times more.
PRICE_RATIO = {
    "claude": {"input": 1.0, "output": 5.0, "cacheRead": 0.1, "cacheWrite": 1.25, "cacheWrite1h": 2.0},
    "codex": {"input": 1.0, "output": 8.0, "cacheRead": 0.1, "cacheWrite": 1.0, "cacheWrite1h": 1.0},
}
# Relative input price by model family: the first key found in the model id wins.
FAMILY_PRICE = {
    "claude": (("opus", 5.0), ("sonnet", 3.0), ("haiku", 1.0), ("", 3.0)),
    "codex": (("nano", 0.04), ("mini", 0.2), ("", 1.0)),
}


# Context window of a Claude model, in tokens, matched against the model id with
# any date or [1m] suffix removed. Claude transcripts never record the window and
# no local catalog lists Claude models (the Codex one lists only OpenAI models),
# so this small table is the one place that answers it: the window each model
# supports, from the model list in Anthropic's docs. Claude Code may compact
# earlier through its auto-compact setting; this is the model's own limit.
CLAUDE_WINDOWS = (
    (r"claude-3-.*|claude-haiku-4-5|claude-(opus|sonnet)-4(-[015])?", 200_000),
    (r"claude-(opus-4-[6-9]|sonnet-4-[6-9]|(opus|sonnet|haiku|fable|mythos)-5(-\d+)?)", 1_000_000),
)


def claude_model_window(model):
    """The window of a Claude model id, or None for one the table does not know."""
    base = re.sub(r"(\[\w+\]|-\d{8})$", "", (model or "").lower())
    return next((window for pattern, window in CLAUDE_WINDOWS if re.fullmatch(pattern, base)), None)


def codex_model_window(model):
    """The window ~/.codex/models_cache.json (Codex's own model catalog) gives a model slug."""
    catalog = read_json(os.path.join(os.path.dirname(CODEX_SESSIONS), "models_cache.json"))
    for entry in catalog.get("models") or []:
        if isinstance(entry, dict) and entry.get("slug") == model:
            window = entry.get("context_window")
            return window if isinstance(window, (int, float)) and window > 0 else None
    return None


def resolve_window(harness, agg, pinned):
    """(window, model, source): the transcript's own figure first, then the model catalogs.

    The model is the one that served most requests, else the one the task was
    dispatched with. A window stays None when no source knows that model.
    """
    models = agg["models"]
    model = max(models, key=models.get) if models else (pinned if pinned and pinned != "default" else "")
    if agg["contextWindow"]:
        return agg["contextWindow"], model, "transcript"
    if not model:
        return None, "", ""
    if harness.startswith("claude"):
        window = claude_model_window(model)
        return window, model, "claude model table" if window else ""
    if harness == "codex":
        window = codex_model_window(model)
        return window, model, "codex model catalog" if window else ""
    return None, model, ""


def empty_agg():
    return {
        "requests": 0,
        "input": 0,
        "output": 0,
        "cacheRead": 0,
        "cacheWrite": 0,
        "reasoning": 0,
        "toolCalls": 0,
        "tools": {},
        "models": {},
        "context": 0,
        "contextWindow": None,
        "events": [],
        "activity": {},
        "lastTool": "",
        "lastText": "",
        "lastAt": 0,
        "cost": {},
        "acctCost": {},
        "toolTokens": {},
        "modelTokens": {},
        "acctTokens": {},
    }


def token_weights(provider, model):
    base = next(price for key, price in FAMILY_PRICE[provider] if key in (model or "").lower())
    return {kind: base * ratio for kind, ratio in PRICE_RATIO[provider].items()}


def weigh(provider, model, fresh=0, output=0, cache_read=0, cache_write=0, cache_write_1h=0):
    w = token_weights(provider, model)
    return (fresh * w["input"] + output * w["output"] + cache_read * w["cacheRead"] + cache_write * w["cacheWrite"]
            + cache_write_1h * w["cacheWrite1h"])


def add_cost(agg, provider, at, session=0.0, tool=0.0):
    """Weighted tokens by provider and request time (ms): [whole session, its tool calls]."""
    if at <= 0 or not (session or tool):
        return
    slots = agg["cost"].setdefault(provider, {})
    key = str(at)
    old = slots.get(key, (0.0, 0.0))
    slots[key] = [old[0] + session, old[1] + tool]


def add_tokens(agg, provider, model, at, sign=1, **counts):
    """A request's tokens by provider, model and timestamp, as [requests, input, output, cacheRead, cacheWrite, reasoning].

    Unlike costs these are never cut at a task's start: they add up to the task's own totals.
    An unknown time goes to timestamp 0, which no week counts.
    """
    stamp = str(max(0, at))
    slot = agg["modelTokens"].setdefault(provider, {}).setdefault(model or provider, {}).setdefault(stamp, [0] * len(TOKEN_FIELDS))
    for i, field in enumerate(TOKEN_FIELDS):
        slot[i] += sign * counts.get(field, 0)


def fold_tokens(into, provider, account, models):
    """Add per-model token samples to into's tokens of one account."""
    mine = into["acctTokens"].setdefault(provider, {}).setdefault(account, {})
    for model, hours in models.items():
        for hour, counts in hours.items():
            slot = mine.setdefault(model, {}).setdefault(hour, [0] * len(TOKEN_FIELDS))
            for i, n in enumerate(counts):
                slot[i] += n


def model_totals(agg):
    """Model id -> its summed tokens over every provider, account and request of an aggregate."""
    out = {}
    for accounts in agg["acctTokens"].values():
        for models in accounts.values():
            for model, hours in models.items():
                sums = out.setdefault(model, dict.fromkeys(TOKEN_FIELDS, 0))
                for counts in hours.values():
                    for field, n in zip(TOKEN_FIELDS, counts):
                        sums[field] += n
    return out


def fold_cost(into, provider, account, slots, since=0):
    """Add per-request costs to into's costs of one account, keeping only requests at or after since."""
    mine = into["acctCost"].setdefault(provider, {}).setdefault(account, {})
    for key, (whole, calls) in slots.items():
        if int(key) >= since:
            old = mine.get(key, (0.0, 0.0))
            mine[key] = [old[0] + whole, old[1] + calls]


def merge(into, part, account=quota.UNKNOWN, since=0):
    """Fold part into into; part's own costs belong to account, and only requests at or after since count."""
    for k in ("requests", "input", "output", "cacheRead", "cacheWrite", "reasoning", "toolCalls"):
        into[k] += part[k]
    for k in ("tools", "models"):
        for name, n in part[k].items():
            into[k][name] = into[k].get(name, 0) + n
    into["events"] = sorted(into["events"] + part["events"], key=lambda event: event["at"])[-MAX_EVENTS:]
    for name, tt in part["toolTokens"].items():
        mine = into["toolTokens"].setdefault(name, {"calls": 0, "output": 0, "input": 0, "estimated": 0, "estCalls": 0})
        for k, v in tt.items():
            mine[k] += v
    for provider, slots in part["cost"].items():
        fold_cost(into, provider, account, slots, since)
    for provider, accounts in part["acctCost"].items():
        for name, slots in accounts.items():
            fold_cost(into, provider, name, slots, since)
    for provider, models in part["modelTokens"].items():
        fold_tokens(into, provider, account, models)
    for provider, accounts in part["acctTokens"].items():
        for name, models in accounts.items():
            fold_tokens(into, provider, name, models)
    for minute, count in part["activity"].items():
        into["activity"][minute] = into["activity"].get(minute, 0) + count
    into["activity"] = dict(sorted(into["activity"].items(), key=lambda item: int(item[0]))[-ACTIVITY_MINUTES:])
    if part["lastAt"] >= into["lastAt"]:
        into["lastAt"] = part["lastAt"]
        into["context"] = part["context"] or into["context"]
        into["contextWindow"] = part["contextWindow"]
        into["lastTool"] = part["lastTool"] or into["lastTool"]
        into["lastText"] = part["lastText"] or into["lastText"]


def note_activity(agg, at):
    if at <= 0:
        return
    minute = str(at // 60000)
    activity = {**agg["activity"], minute: agg["activity"].get(minute, 0) + 1}
    agg["activity"] = dict(sorted(activity.items(), key=lambda item: int(item[0]))[-ACTIVITY_MINUTES:])


def note_event(agg, at, text, call=None):
    if at > 0:
        event = {"at": at, "kind": "tool", "text": text}
        if call:
            event["id"] = call["id"]
            event["tool"] = call["name"]
        agg["events"] = (agg["events"] + [event])[-MAX_EVENTS:]


def new_request(at, model, ctx, out):
    return {"at": at, "model": model, "ctx": ctx or None, "out": out, "calls": [], "sizes": {}}


def text_size(value):
    """Characters of a tool result: a string, text blocks or any JSON."""
    if isinstance(value, str):
        return len(value)
    if isinstance(value, list):
        return sum(text_size(v.get("text") if isinstance(v, dict) and "text" in v else v) for v in value)
    if value is None:
        return 0
    return len(json.dumps(value))


def note_result(rec, call_id, size):
    if rec and call_id and any(call["id"] == call_id for call in rec["calls"]):
        rec["sizes"][call_id] = size


def split_even(total, n):
    return [total // n + (1 if i < total % n else 0) for i in range(n)]


def split_by(total, weights):
    """Whole tokens in proportion to weights, evenly when they are all zero."""
    whole = sum(weights)
    if whole <= 0:
        return split_even(total, len(weights))
    shares = [total * w // whole for w in weights]
    for i in range(total - sum(shares)):
        shares[i % len(shares)] += 1
    return shares


def settle_request(agg, provider, rec, nxt):
    """Charge a request's tool calls with its output and the input their results added.

    nxt describes the request that followed it (ctx, fresh and write input, model),
    or is None while it has not been logged: the input is then estimated.
    """
    calls = rec["calls"]
    if not calls:
        return
    added = None
    if nxt and rec["ctx"] and nxt["ctx"]:
        grown = nxt["ctx"] - rec["ctx"] - rec["out"]
        if grown >= 0:
            added = grown
    sizes = [rec["sizes"].get(call["id"], 0) for call in calls]
    if added is None:
        inputs = [-(-size // CHARS_PER_TOKEN) for size in sizes]
        price = token_weights(provider, rec["model"])["input"]
    else:
        inputs = split_by(added, sizes)
        new = nxt["fresh"] + nxt["write"] + nxt["write1h"]
        price = (weigh(provider, nxt["model"], nxt["fresh"], cache_write=nxt["write"], cache_write_1h=nxt["write1h"]) / new
                 if new else token_weights(provider, nxt["model"])["cacheRead"])
    w_out = token_weights(provider, rec["model"])["output"]
    estimated = added is None
    for call, out, tokens_in in zip(calls, split_even(rec["out"], len(calls)), inputs):
        tt = agg["toolTokens"].setdefault(call["name"], {"calls": 0, "output": 0, "input": 0, "estimated": 0, "estCalls": 0})
        tt["calls"] += 1
        tt["output"] += out
        tt["input"] += tokens_in
        if estimated:
            tt["estimated"] += tokens_in
            tt["estCalls"] += 1
        add_cost(agg, provider, rec["at"], 0.0, out * w_out + tokens_in * price)
        for i, event in enumerate(agg["events"]):
            if event.get("id") == call["id"]:
                agg["events"][i] = {**event, "outTokens": out, "inTokens": tokens_in, "estimated": estimated}


def settled_agg(entry, provider):
    """The entry's totals plus its newest request's calls, charged as if no request followed."""
    rec = entry["flow"]["cur"]
    agg = entry["agg"]
    if not rec or not rec["calls"]:
        return agg
    view = {
        **agg,
        "toolTokens": {name: dict(tt) for name, tt in agg["toolTokens"].items()},
        "cost": {**agg["cost"], provider: dict(agg["cost"].get(provider, {}))},
        "events": list(agg["events"]),
    }
    settle_request(view, provider, rec, None)
    return view


def one_line(text, limit=SNIPPET):
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def ts_ms(value):
    if not value:
        return 0
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def wrapped_command(script):
    """Read a literal cmd in a code-mode exec_command call, never execute JS."""
    literal = r'''("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')'''
    match = re.search(r'''\bexec_command\s*\(\s*\{[\s\S]*?(?<![\w$])(?:["']cmd["']|cmd)\s*:\s*''' + literal, script)
    if not match:
        return None
    try:
        value = json.loads(match[1]) if match[1].startswith('"') else ast.literal_eval(match[1])
    except (ValueError, SyntaxError):
        return None
    return value if isinstance(value, str) else None


def relative_detail(text, worktree):
    """Abbreviate only this task's own worktree; leave other directories intact."""
    root = worktree.rstrip("/")
    if not root:
        return text
    lead = re.match(r'''^\s*cd\s+("(?:[^"\\]|\\.)*"|'[^']*'|[^\s;&]+)\s*(?:&&|;)\s*''', text)
    if lead:
        try:
            directory = shlex.split(lead[1])[0]
        except (ValueError, IndexError):
            directory = ""
        if os.path.normpath(directory) == os.path.normpath(root):
            text = text[lead.end():]
    path = re.compile(r'''(?<![\w/.-])''' + re.escape(root) + r'''(/|(?=$|[\s'";]))''')
    return path.sub(lambda match: "" if match[1] == "/" else ".", text)


def tool_summary(name, value, worktree):
    return one_line(f"{name}: {relative_detail(str(value), worktree)}")


def describe_tool(name, args, worktree=""):
    if not isinstance(args, dict):
        try:
            args = json.loads(args) if isinstance(args, str) else {}
        except ValueError:
            command = wrapped_command(args)
            return tool_summary(name, command if command is not None else args, worktree)
        if not isinstance(args, dict):
            args = {}
    for key in ("command", "cmd", "file_path", "path", "pattern", "url", "description", "prompt", "query"):
        val = args.get(key)
        if val:
            if isinstance(val, list):
                val = " ".join(str(v) for v in val)
            return tool_summary(name, val, worktree)
    for key in ("code", "script", "input"):
        script = args.get(key)
        if isinstance(script, str):
            command = wrapped_command(script)
            if command is not None:
                return tool_summary(name, command, worktree)
    return name


def read_new_lines(path, entry):
    """Yield complete lines appended since entry['offset'], advancing it."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return
    if size < entry.get("offset", 0):
        entry.clear()
        entry.update(fresh_entry())
    if size == entry["offset"]:
        return
    with open(path, "rb") as f:
        f.seek(entry["offset"])
        data = f.read()
    end = data.rfind(b"\n")
    if end < 0:
        return
    entry["offset"] += end + 1
    for raw in data[: end + 1].splitlines():
        if raw.strip():
            try:
                yield json.loads(raw)
            except ValueError:
                continue


def fresh_entry():
    return {"offset": 0, "agg": empty_agg(), "msgId": None, "msgUsage": None, "msgAt": 0, "msgModel": "", "meta": {},
            "flow": {"cur": None, "open": None}, "ids": [], "readings": []}


def claude_writes(usage):
    """Cache writes by lifetime, (5-minute, 1-hour); a log without the split has only 5-minute ones."""
    total = usage.get("cache_creation_input_tokens") or 0
    hour = min(total, (usage.get("cache_creation") or {}).get("ephemeral_1h_input_tokens") or 0)
    return total - hour, hour


def apply_claude_usage(agg, usage, sign, model="", at=0):
    agg["input"] += sign * (usage.get("input_tokens") or 0)
    agg["output"] += sign * (usage.get("output_tokens") or 0)
    agg["cacheRead"] += sign * (usage.get("cache_read_input_tokens") or 0)
    agg["cacheWrite"] += sign * (usage.get("cache_creation_input_tokens") or 0)
    add_cost(agg, "claude", at, sign * weigh(
        "claude", model, usage.get("input_tokens") or 0, usage.get("output_tokens") or 0,
        usage.get("cache_read_input_tokens") or 0, *claude_writes(usage)))
    details = usage.get("output_tokens_details") or {}
    agg["reasoning"] += sign * (details.get("thinking_tokens") or 0)
    add_tokens(agg, "claude", model, at, sign, input=usage.get("input_tokens") or 0, output=usage.get("output_tokens") or 0,
               cacheRead=usage.get("cache_read_input_tokens") or 0, cacheWrite=usage.get("cache_creation_input_tokens") or 0,
               reasoning=details.get("thinking_tokens") or 0)


def message_owners(*stores):
    """Message id -> the transcript that counts it, from the ids each cached entry claimed."""
    owners = {}
    for store in stores:
        for path, entry in store.items():
            for mid in entry["ids"]:
                owners.setdefault(mid, path)
    return owners


def parse_claude(path, entry, owners, worktree=""):
    for row in read_new_lines(path, entry):
        agg = entry["agg"]
        flow = entry["flow"]
        if row.get("type") == "user":
            content = (row.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    note_result(flow["cur"], block.get("tool_use_id"), text_size(block.get("content")))
            continue
        if row.get("type") != "assistant":
            continue
        msg = row.get("message") or {}
        at = ts_ms(row.get("timestamp"))
        usage = msg.get("usage") or {}
        model = msg.get("model") or ""
        if model == "<synthetic>":
            continue
        ctx = (
            (usage.get("input_tokens") or 0)
            + (usage.get("cache_read_input_tokens") or 0)
            + (usage.get("cache_creation_input_tokens") or 0)
        )
        write, write_1h = claude_writes(usage)
        nxt = {"ctx": ctx, "fresh": usage.get("input_tokens") or 0, "write": write, "write1h": write_1h, "model": model}
        mid = msg.get("id")
        if mid and owners.setdefault(mid, path) != path:
            if flow["cur"]:
                settle_request(agg, "claude", flow["cur"], nxt)
                flow["cur"] = None
            continue
        note_activity(agg, at)
        # One API message is written as one row per content block, each with
        # the message's usage so far: count it once, at its latest reading.
        if mid and mid == entry["msgId"]:
            if entry["msgUsage"]:
                apply_claude_usage(agg, entry["msgUsage"], -1, entry["msgModel"], entry["msgAt"])
            if flow["cur"]:
                flow["cur"]["out"] = usage.get("output_tokens") or flow["cur"]["out"]
                flow["cur"]["ctx"] = ctx or flow["cur"]["ctx"]
        else:
            agg["requests"] += 1
            add_tokens(agg, "claude", model, at, requests=1)
            if model:
                agg["models"][model] = agg["models"].get(model, 0) + 1
            if mid:
                entry["ids"].append(mid)
            if flow["cur"]:
                settle_request(agg, "claude", flow["cur"], nxt)
            flow["cur"] = new_request(at, model, ctx, usage.get("output_tokens") or 0)
        if usage:
            apply_claude_usage(agg, usage, 1, model, at)
            agg["context"] = ctx
        entry["msgId"] = mid
        entry["msgUsage"] = usage or None
        entry["msgAt"] = at
        entry["msgModel"] = model
        for block in msg.get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                name = block.get("name") or "?"
                call = {"id": block.get("id") or f"{mid}:{len(flow['cur']['calls'])}", "name": name}
                if not any(known["id"] == call["id"] for known in flow["cur"]["calls"]):
                    flow["cur"]["calls"].append(call)
                agg["toolCalls"] += 1
                agg["tools"][name] = agg["tools"].get(name, 0) + 1
                agg["lastTool"] = describe_tool(name, block.get("input"), worktree)
                note_event(agg, at, agg["lastTool"], call)
            elif block.get("type") == "text" and (block.get("text") or "").strip():
                agg["lastText"] = one_line(block["text"])
        if at:
            agg["lastAt"] = max(agg["lastAt"], at)


def weekly_window(windows):
    """The longest window of at least a week, or None."""
    weekly = [w for w in windows if (w.get("minutes") or 0) >= 7200]
    return max(weekly, key=lambda w: w["minutes"]) if weekly else None


def note_codex_reading(entry, limit_id, limits):
    """Queue a weekly rate-limit observation of this rollout for the reading history (written once per poll)."""
    week = weekly_window(limits["windows"])
    percent = week.get("percent") if week else None
    if week and isinstance(percent, (int, float)) and not isinstance(percent, bool):
        # The newest observations are the ones worth keeping when a long rollout is read at once.
        del entry["readings"][: max(0, len(entry["readings"]) + 1 - quota.PENDING_LIMIT)]
        entry["readings"].append({"at": limits["at"], "limitId": limit_id, "plan": limits["plan"], "percent": float(percent),
                                  "minutes": week["minutes"], "resetsAt": (week.get("resetsAt") or 0) * 1000 or None})


def parse_codex(path, entry, worktree=""):
    for row in read_new_lines(path, entry):
        agg = entry["agg"]
        meta = entry["meta"]
        kind = row.get("type")
        payload = row.get("payload") or {}
        at = ts_ms(row.get("timestamp"))
        if kind == "session_meta":
            meta["cwd"] = payload.get("cwd") or ""
            meta["account"] = quota.codex_account(payload.get("creator_account_id"))
        elif kind == "turn_context":
            if payload.get("model"):
                if payload["model"] != meta.get("model"):
                    agg["contextWindow"] = None
                meta["model"] = payload["model"]
        elif kind == "event_msg" and payload.get("type") == "token_count":
            info = payload.get("info") or {}
            window = info.get("model_context_window")
            if isinstance(window, (int, float)) and window > 0:
                agg["contextWindow"] = window
            limits = payload.get("rate_limits")
            if isinstance(limits, dict):
                windows = [w for w in (limits.get("primary"), limits.get("secondary")) if isinstance(w, dict)]
                if windows:
                    # One entry per limit id: a model-specific limit is never mistaken for the account's own.
                    limit_id = str(limits.get("limit_id") or "codex")
                    meta.setdefault("limits", {})[limit_id] = {"at": at, "plan": limits.get("plan_type") or "", "windows": [
                        {"percent": w.get("used_percent"), "minutes": w.get("window_minutes"), "resetsAt": w.get("resets_at")}
                        for w in windows]}
                    note_codex_reading(entry, limit_id, meta["limits"][limit_id])
            total = info.get("total_token_usage") or {}
            last = info.get("last_token_usage") or {}
            # Codex repeats a token_count when only its rate limits changed.
            if not total or total.get("total_tokens") == meta.get("total"):
                continue
            meta["total"] = total.get("total_tokens")
            note_activity(agg, at)
            cached = total.get("cached_input_tokens") or 0
            # OpenAI input_tokens includes the cached part; split it out.
            agg["input"] = max(0, (total.get("input_tokens") or 0) - cached)
            agg["cacheRead"] = cached
            agg["cacheWrite"] = total.get("cache_write_input_tokens") or 0
            agg["output"] = total.get("output_tokens") or 0
            agg["reasoning"] = total.get("reasoning_output_tokens") or 0
            model = meta.get("model") or "codex"
            # The totals are running sums: each count's growth goes to the model serving it, so the per-model
            # sums add up to the totals.
            sums = {field: agg[field] for field in TOKEN_FIELDS[1:]}
            before = meta.get("sums") or dict.fromkeys(TOKEN_FIELDS[1:], 0)
            add_tokens(agg, "codex", model, at, requests=1 if last else 0, **{f: sums[f] - before.get(f, 0) for f in sums})
            meta["sums"] = sums
            if last:
                agg["requests"] += 1
                agg["context"] = last.get("input_tokens") or 0
                agg["models"][model] = agg["models"].get(model, 0) + 1
                cached_now = last.get("cached_input_tokens") or 0
                fresh_now = max(0, (last.get("input_tokens") or 0) - cached_now)
                write_now = last.get("cache_write_input_tokens") or 0
                out_now = last.get("output_tokens") or 0
                add_cost(agg, "codex", at, weigh("codex", model, fresh_now, out_now, cached_now, write_now))
                # The items logged since the previous count belong to this request.
                flow = entry["flow"]
                if flow["cur"]:
                    nxt = {"ctx": last.get("input_tokens") or 0, "fresh": fresh_now, "write": write_now, "write1h": 0,
                           "model": model}
                    settle_request(agg, "codex", flow["cur"], nxt)
                flow["cur"] = {**(flow["open"] or new_request(0, "", 0, 0)), "at": at, "model": model,
                               "ctx": last.get("input_tokens") or None, "out": out_now}
                flow["open"] = None
        elif kind == "response_item":
            ptype = payload.get("type")
            if ptype in ("function_call", "custom_tool_call", "local_shell_call", "web_search_call"):
                name = payload.get("name") or ptype
                agg["toolCalls"] += 1
                agg["tools"][name] = agg["tools"].get(name, 0) + 1
                args = payload.get("arguments") or payload.get("input") or payload.get("action") or {}
                agg["lastTool"] = describe_tool(name, args, worktree)
                opened = entry["flow"]["open"] = entry["flow"]["open"] or new_request(0, "", 0, 0)
                call = {"id": payload.get("call_id") or f"{at}:{name}:{len(opened['calls'])}", "name": name}
                opened["calls"].append(call)
                note_event(agg, at, agg["lastTool"], call)
                note_activity(agg, at)
            elif ptype and ptype.endswith("_output") and payload.get("call_id"):
                size = text_size(payload.get("output"))
                for rec in (entry["flow"]["open"], entry["flow"]["cur"]):
                    note_result(rec, payload["call_id"], size)
            elif ptype == "message" and payload.get("role") == "assistant":
                for block in payload.get("content") or []:
                    text = block.get("text") if isinstance(block, dict) else None
                    if text and text.strip():
                        agg["lastText"] = one_line(text)
                        note_activity(agg, at)
        if at:
            agg["lastAt"] = max(agg["lastAt"], at)


def modified_ms(path):
    try:
        return int(os.path.getmtime(path) * 1000)
    except OSError:
        return -1


def task_start(meta, meta_path, status_path):
    """When the task first started; an older log in its worktree is another task's.

    A relaunch writes a new spawn_gen, but the status log keeps the first [at=].
    """
    starts = []
    try:
        with open(status_path, "rb") as f:
            starts = [int(at) * 1000 for at in re.findall(rb"\[at=(\d+)\]", f.read())]
    except OSError:
        pass
    spawned = re.match(r"s(\d+)", meta.get("spawn_gen") or "")
    if spawned:
        starts.append(int(spawned[1]) * 1000)
    return min(starts) if starts else max(0, modified_ms(meta_path))


def claude_project_dir(worktree):
    return os.path.join(CLAUDE_PROJECTS, re.sub(r"[^A-Za-z0-9]", "-", worktree))


def claude_files(worktree, since):
    root = claude_project_dir(worktree)
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(dirpath, name)
            if name.endswith(".jsonl") and modified_ms(path) >= since:
                out.append(path)
    return out


def codex_files(cache, now):
    """Every recent rollout with its mtime; a session cwd is cached once its first line is complete."""
    cwds = cache.setdefault("codexCwd", {})
    out = []
    cutoff = now - LOOKBACK_DAYS * 86400000
    for dirpath, _dirs, files in os.walk(CODEX_SESSIONS):
        for name in files:
            if not (name.startswith("rollout-") and name.endswith(".jsonl")):
                continue
            path = os.path.join(dirpath, name)
            modified = modified_ms(path)
            if modified < cutoff:
                continue
            if path not in cwds:
                try:
                    with open(path, "rb") as f:
                        first = f.readline()
                except OSError:
                    continue
                if not first.endswith(b"\n"):
                    continue
                try:
                    row = json.loads(first)
                except ValueError:
                    row = None
                session = isinstance(row, dict) and row.get("type") == "session_meta"
                cwds[path] = ((row.get("payload") or {}).get("cwd") or "") if session else ""
            out.append((path, cwds[path], modified))
    return out


def read_meta(path):
    meta = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if "=" in line:
                    k, v = line.rstrip("\n").split("=", 1)
                    meta[k] = v
    except OSError:
        pass
    return meta


def last_status(path):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 4096))
            lines = [l for l in f.read().decode("utf-8", "replace").splitlines() if l.strip()]
    except OSError:
        return "", 0
    if not lines:
        return "", 0
    try:
        at = int(os.path.getmtime(path) * 1000)
    except OSError:
        at = 0
    return one_line(lines[-1], 140), at


def status_events(path):
    """Only the bounded tail; use protocol timestamps, mtime only for the last line."""
    try:
        with open(path, "rb") as stream:
            stream.seek(0, 2)
            start = max(0, stream.tell() - 16384)
            stream.seek(start)
            if start:
                stream.readline()
            lines = [line for line in stream.read().decode("utf-8", "replace").splitlines() if line.strip()]
        modified = int(os.path.getmtime(path) * 1000)
    except OSError:
        return []
    events = []
    for index, line in enumerate(lines[-MAX_EVENTS:]):
        stamp = re.search(r"\[at=(\d+)\]", line)
        at = int(stamp.group(1)) * 1000 if stamp else modified if index == len(lines[-MAX_EVENTS:]) - 1 else 0
        if at > 0:
            events.append({"at": at, "kind": "status", "text": one_line(line)})
    return events


def collect_tasks(home, depth, seen, root=None, visited=None):
    """The live tasks of a home and its secondmates' homes; visited gets each home whose state was read in full."""
    real = os.path.realpath(home)
    if real in seen or depth > 4:
        return []
    seen.add(real)
    state = os.path.join(home, "state")
    tasks = []
    try:
        names = sorted(os.listdir(state))
    except OSError:
        return tasks
    if visited is not None:
        visited.add(real)
    root = root or real
    for name in names:
        if not name.endswith(".meta") or name.startswith("."):
            continue
        tid = name[: -len(".meta")]
        meta = read_meta(os.path.join(state, name))
        status, status_at = last_status(os.path.join(state, tid + ".status"))
        since = task_start(meta, os.path.join(state, name), os.path.join(state, tid + ".status"))
        tasks.append({"id": tid, "home": home, "root": root, "depth": depth, "meta": meta, "since": since,
                      "status": status, "statusAt": status_at})
        if meta.get("kind") == "secondmate" and meta.get("worktree") and not meta.get("remote_host"):
            tasks.extend(collect_tasks(meta["worktree"], depth + 1, seen, root, visited))
    return tasks


def accounts_path():
    """The session -> account registry, beside the log cache."""
    return os.path.join(os.path.dirname(CACHE_PATH), "accounts.json")


def claude_session_id(path):
    """The session a Claude transcript belongs to: its own file name, or the folder a subagent transcript sits in."""
    parts = os.path.relpath(path, CLAUDE_PROJECTS).split(os.sep)
    if len(parts) < 2 or parts[0] == "..":
        return ""
    return parts[1][: -len(".jsonl")] if parts[1].endswith(".jsonl") else parts[1]


def entry_account(provider, path, entry, sessions):
    """The account a transcript or rollout was written under, or "unknown" when nothing ties it to one."""
    if provider == "codex":
        return (entry.get("meta") or {}).get("account") or quota.UNKNOWN
    known = sessions.get(claude_session_id(path))
    return quota.claude_account_name(known["account"]) if known else quota.UNKNOWN


def scan_local(files, scan, owners, codex_index, touched, now, deadline):
    """Every local session of the last week, per provider, for the quota denominator.

    Files a crewmate owns reuse that entry; the rest are parsed into a separate
    cache so their tool texts are never abbreviated for the wrong worktree.
    Parsing stops at the run's deadline; the next poll resumes, and the provider
    is flagged as still indexing. Returns (path, entry) pairs per provider.
    """
    since = now - WEEK_MS
    todo = []
    for dirpath, _dirs, names in os.walk(CLAUDE_PROJECTS):
        for name in names:
            path = os.path.join(dirpath, name)
            if name.endswith(".jsonl") and modified_ms(path) >= since:
                todo.append(("claude", path))
    todo.extend(("codex", path) for path, _cwd, modified in codex_index if modified >= since)
    found = {"claude": [], "codex": []}
    indexed = {"claude": True, "codex": True}
    for provider, path in todo:
        if path in touched:
            found[provider].append((path, files[path]))
            continue
        entry = scan.get(path)
        if time.monotonic() > deadline:
            indexed[provider] = False
        else:
            entry = scan.setdefault(path, fresh_entry())
            if provider == "claude":
                parse_claude(path, entry, owners)
            else:
                parse_codex(path, entry)
        if entry is not None:
            found[provider].append((path, entry))
    for path in [p for p in scan if p in touched or modified_ms(p) < since]:
        del scan[path]
    return found, indexed


def account_indexes(found, sessions):
    """Per (provider, account): every local request's weighted cost by its own time."""
    maps = {}
    for provider, items in found.items():
        for path, entry in items:
            account = entry_account(provider, path, entry, sessions)
            maps.setdefault((provider, account), []).append(entry["agg"]["cost"].get(provider, {}))
    return {key: quota.CostIndex(*slots) for key, slots in maps.items()}


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def claude_config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")


def claude_global_config():
    base = os.environ.get("CLAUDE_CONFIG_DIR")
    return read_json(os.path.join(base, ".claude.json") if base else os.path.join(HOME, ".claude.json"))


def claude_plan():
    """Plan label from local metadata: credentials' subscription type, else the account's rate-limit tier."""
    oauth = read_json(os.path.join(claude_config_dir(), ".credentials.json")).get("claudeAiOauth")
    oauth = oauth if isinstance(oauth, dict) else {}
    account = claude_global_config().get("oauthAccount")
    account = account if isinstance(account, dict) else {}
    tier = str(oauth.get("rateLimitTier") or account.get("userRateLimitTier") or "")
    subscription = str(oauth.get("subscriptionType") or "").lower()
    match = re.search(r"max_(\d+)x", tier)
    if match:
        label = f"Max {match[1]}x"
    elif subscription or "pro" in tier:
        label = (subscription or "pro").title()
    else:
        return ""
    return label + (" · Team" if account.get("organizationType") == "claude_team" else "")


def claude_login():
    """How this process signs in to Claude, from the environment's presence alone (no value is read).

    A token login (CLAUDE_CODE_OAUTH_TOKEN, what ai-acct sets) leaves no
    credentials file and no account record, so it carries no plan label.
    """
    if os.environ.get("CLAUDE_CODE_OAUTH_TOKEN"):
        return "token"
    if os.environ.get("ANTHROPIC_API_KEY"):
        return "api-key"
    return "account" if claude_plan() else ""


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def candidate(provider, account, source, scope, percent, resets_at, window_ms, observed_at, plan="", session=""):
    """One vendor reading of one account's weekly limit; None unless the percent is a number."""
    if not number(percent):
        return None
    return {"provider": provider, "account": account, "source": source, "scope": scope, "percent": float(percent),
            "resetsAt": resets_at or None, "windowMs": window_ms or WEEK_MS, "observedAt": observed_at or None,
            "plan": plan, "session": session}


def session_transcript(session_id):
    """The pane session's own transcript: its id is the file's name, in some project directory."""
    if not re.fullmatch(r"[\w-]+", session_id or ""):
        return None
    try:
        projects = os.listdir(CLAUDE_PROJECTS)
    except OSError:
        return None
    paths = (os.path.join(CLAUDE_PROJECTS, name, session_id + ".jsonl") for name in projects)
    return next((path for path in paths if os.path.isfile(path)), None)


def pane_candidates(limits, limits_at, account, plan, session_id):
    """The pane session's rate limits, as of its last API response (None when that time is unknown)."""
    out = []
    for limit in limits if isinstance(limits, list) else []:
        if isinstance(limit, dict) and limit.get("kind") == "seven_day":
            out.append(candidate("claude", account, "session", "seven_day", limit.get("percentUsed"),
                                 ts_ms(limit.get("resetsAt")), WEEK_MS, limits_at, plan, session_id))
    return [c for c in out if c]


def pane_five_hour(limits, limits_at, account):
    """The pane session's 5-hour window, dated like its weekly one."""
    return [c for c in (candidate("claude", account, "session", "five_hour", limit.get("percentUsed"), ts_ms(limit.get("resetsAt")),
                                  FIVE_HOUR_MINUTES * 60000, limits_at)
                        for limit in (limits if isinstance(limits, list) else [])
                        if isinstance(limit, dict) and limit.get("kind") == "five_hour") if c]


def ai_acct_cache_dir():
    return os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "ai-acct")


def account_cache_candidates(kind="seven_day"):
    """ai-acct's stored window of one kind per account: the window only, never the fingerprint beside it.

    The file's time is when a status-line callback wrote it, not when the vendor
    measured it, so these readings are of unknown age.
    """
    directory = ai_acct_cache_dir()
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return []
    out = []
    for name in names:
        match = re.fullmatch(r"claude-([a-z0-9][a-z0-9_-]{0,31})\.limits\.json", name)
        if not match or quota.claude_account_name(match[1]) == quota.UNKNOWN:
            continue
        window = (read_json(os.path.join(directory, name)).get("windows") or {}).get(kind)
        if isinstance(window, dict) and number(window.get("resets_at")):
            out.append(candidate("claude", match[1], "account cache", kind, window.get("used"),
                                 window["resets_at"] * 1000, WEEK_MS if kind == "seven_day" else FIVE_HOUR_MINUTES * 60000, None))
    return [c for c in out if c]


def history_candidates(history):
    """The newest dated reading of each key in the history."""
    newest = {}
    for rec in history:
        if rec.get("observedAt") is None:
            continue
        key = quota.reading_key(rec["provider"], rec["account"], rec["scope"])
        if key not in newest or rec["observedAt"] > newest[key]["observedAt"]:
            newest[key] = rec
    return [candidate(r["provider"], r["account"], "history", r["scope"], r["percent"], r.get("resetsAt"),
                      r.get("durationMs"), r["observedAt"], r.get("plan") or "", r.get("session") or "") for r in newest.values()]


def newest_codex_limits(found, sessions):
    """The newest rate-limit event of each Codex account's own limit (id "codex") any local rollout recorded."""
    newest = {}
    for path, entry in found:
        account = entry_account("codex", path, entry, sessions)
        limits = (entry.get("meta") or {}).get("limits", {}).get("codex")
        if limits and (account not in newest or limits["at"] >= newest[account]["at"]):
            newest[account] = limits
    return newest


def codex_candidates(found, sessions):
    """The weekly window of each Codex account's newest rate-limit event."""
    out = []
    for account, limits in newest_codex_limits(found, sessions).items():
        week = weekly_window(limits["windows"])
        if week:
            out.append(candidate("codex", account, "codex log", f"codex:{week['minutes']}m", week.get("percent"),
                                 (week.get("resetsAt") or 0) * 1000, week["minutes"] * 60000, limits["at"], limits["plan"].title()))
    return [c for c in out if c]


def codex_five_hour(found, sessions):
    """The 300-minute window of each Codex account's newest rate-limit event."""
    out = []
    for account, limits in newest_codex_limits(found, sessions).items():
        for w in limits["windows"]:
            if w.get("minutes") == FIVE_HOUR_MINUTES:
                out.append(candidate("codex", account, "codex log", "five_hour", w.get("percent"), (w.get("resetsAt") or 0) * 1000,
                                     FIVE_HOUR_MINUTES * 60000, limits["at"]))
    return [c for c in out if c]


def five_hour_of(candidates, provider, account, now):
    """An account's 5-hour window: the freshest vendor reading still in force, `reset` once it has passed, else None."""
    mine = [c for c in candidates if c["provider"] == provider and c["account"] == account] if account != quota.UNKNOWN else []
    if not mine:
        return None
    anchor = quota.pick_anchor(mine, now)
    if anchor is None:
        return {"percent": None, "resetsAt": None, "observedAt": None, "source": "", "stale": False, "reset": True}
    return {"percent": anchor["percent"], "resetsAt": anchor["resetsAt"], "observedAt": anchor["observedAt"],
            "source": anchor["source"], "stale": quota.is_stale(anchor["observedAt"], now), "reset": False}


def new_records(pane, found, sessions, now):
    """The observations of this poll for the history: the pane's own response and every queued Codex event.

    An account of unknown identity is never recorded: its percent belongs to nobody in particular.
    """
    out = []
    for c in pane:
        if c["account"] != quota.UNKNOWN:
            out.append(quota.make_record("claude", c["account"], c["source"], c["scope"], "seven_day", c["percent"],
                                         c["resetsAt"], c["windowMs"], c["observedAt"], now, c["session"], c["plan"]))
    for path, entry in found["codex"]:
        account = entry_account("codex", path, entry, sessions)
        if account == quota.UNKNOWN:
            continue
        for r in entry["readings"]:
            out.append(quota.make_record("codex", account, "codex log", f"{r['limitId']}:{r['minutes']}m", "weekly", r["percent"],
                                         r["resetsAt"], r["minutes"] * 60000, r["at"], now, path, r["plan"].title()))
    return out


def record_with_residuals(records, history, indexes, indexed):
    """The records not in the history yet, each with how its forecast missed it (oldest first).

    Only the newest RESIDUAL_LIMIT are compared, so a first poll that backfills a
    week of rollouts stays quick; the older ones are history without a residual.
    """
    known = list(history)
    seen = {quota.observation_key(r) for r in known}
    fresh = []
    for rec in sorted(records, key=lambda r: r.get("observedAt") or 0):
        key = quota.observation_key(rec)
        if key not in seen:
            seen.add(key)
            fresh.append(rec)
    out = []
    for i, rec in enumerate(fresh):
        residual = None
        if i >= len(fresh) - RESIDUAL_LIMIT:
            index = indexes.get((rec["provider"], rec["account"]), quota.CostIndex())
            residual = quota.residual_against(known, rec, index, indexed[rec["provider"]])
        out.append({**rec, "residual": residual} if residual else rec)
        known.append(out[-1])
    return out


def build_readings(groups, candidates, history, indexes, indexed, now, pane_account, plan, login):
    """Per (provider, account): the vendor anchor, what has happened since and how far to trust it.

    Returns (public readings by key, internals by (provider, account)). A percent is only ever
    carried by an account that is known; "unknown" keeps raw local usage and nothing else.
    """
    readings, inner = {}, {}
    for provider, account in sorted(groups):
        mine = [c for c in candidates if c["provider"] == provider and c["account"] == account] if account != quota.UNKNOWN else []
        anchor = quota.pick_anchor(mine, now)
        scope = anchor["scope"] if anchor else quota.default_scope(provider)
        known = bool(anchor and anchor["resetsAt"])
        start = max(anchor["resetsAt"] - anchor["windowMs"], now - WEEK_MS) if known else now - WEEK_MS
        index = indexes.get((provider, account)) or quota.CostIndex()
        dated = bool(anchor and anchor["observedAt"] is not None)
        stale = bool(anchor) and quota.is_stale(anchor["observedAt"], now)
        sure = quota.confidence(history, provider, account, scope)
        slope = quota.prior_slope(anchor["percent"], index, start, anchor["observedAt"]) if anchor and known and dated else None
        # A stale anchor is extrapolated only with a trusted slope, and never past the horizon the
        # calibration was measured over.
        trusted = sure["label"] == "calibrated" and dated and now - anchor["observedAt"] <= quota.MAX_HORIZON_MS
        usable = slope is not None and (not stale or trusted)
        since = index.between(anchor["observedAt"], now)[0] if dated else None
        blocks, boundary, inclusive = None, start, True
        if anchor and known and anchor["percent"] > 0:
            seen = quota.period_readings(history, provider, account, scope, anchor["resetsAt"], start)
            if dated and not any(r["observedAt"] == anchor["observedAt"] for r in seen):
                seen = sorted(seen + [{"percent": anchor["percent"], "observedAt": anchor["observedAt"]}], key=lambda r: r["observedAt"])
            blocks, boundary, inclusive, _ = quota.settled_blocks(seen, start)
        readings[quota.reading_key(provider, account, scope)] = {
            "provider": provider,
            "account": account,
            "accountKnown": account != quota.UNKNOWN,
            "scope": scope,
            "plan": (anchor or {}).get("plan") or (plan if (provider, account) == ("claude", pane_account) else ""),
            "login": login if provider == "claude" and account == pane_account else "rollout" if provider == "codex" else "",
            "percent": anchor["percent"] if anchor else None,
            "observedAt": anchor["observedAt"] if anchor else None,
            "source": anchor["source"] if anchor else "",
            "resetsAt": anchor["resetsAt"] if anchor else None,
            "windowMs": anchor["windowMs"] if anchor else WEEK_MS,
            "windowStart": start,
            "windowStartKnown": known,
            "stale": stale,
            "reset": bool(mine) and anchor is None,
            "indexed": indexed[provider],
            "localCost": index.between(start, now, True)[0],
            "sinceCost": since,
            "forecast": min(100.0, anchor["percent"] + slope * since) if usable and known and since is not None else None,
            "confidence": sure,
        }
        inner[(provider, account)] = {"key": quota.reading_key(provider, account, scope), "index": index, "blocks": blocks,
                                      "boundary": boundary, "inclusive": inclusive, "slope": slope if usable else None}
    return readings, inner


def figure(share, settled, extra, since):
    """One quota figure: share of local usage, settled points, estimated points since, and what the basis is."""
    if settled is None:
        return {"share": share, "percent": None, "settled": None, "open": None, "since": since, "basis": "raw"}
    return {"share": share, "percent": settled + (extra or 0.0), "settled": settled, "open": extra, "since": since,
            "basis": "estimated" if extra is not None else "settled"}


def quota_of(agg, ctx):
    """Per account the member (or the fleet) used: its share of the week, from settled intervals plus the open one."""
    out = {}
    now, readings, inner, indexed = ctx["now"], ctx["readings"], ctx["inner"], ctx["indexed"]
    for provider, accounts in agg["acctCost"].items():
        for account, slots in accounts.items():
            if (provider, account) not in inner:
                continue
            info = inner[(provider, account)]
            reading = readings[info["key"]]
            member = quota.CostIndex(slots)
            whole = member.between(reading["windowStart"], now, True)
            if whole == (0.0, 0.0):
                continue
            figures = []
            for dim in (0, 1):
                if not indexed[provider]:
                    figures.append({"share": None, "percent": None, "settled": None, "open": None, "since": None, "basis": "raw"})
                    continue
                share = min(1.0, whole[dim] / reading["localCost"]) if reading["localCost"] > 0 else None
                settled = extra = None
                if reading["percent"] is not None:
                    if reading["percent"] == 0:
                        settled = 0.0
                    elif info["blocks"]:
                        settled = quota.settled_percent(info["blocks"], member, info["index"], dim)
                    if settled is not None and info["slope"] is not None and reading["forecast"] is not None:
                        extra = info["slope"] * member.between(info["boundary"], now, info["inclusive"])[dim]
                since = member.between(reading["observedAt"], now)[dim] if reading["observedAt"] is not None else None
                figures.append(figure(share, settled, extra, since))
            out[info["key"]] = {"session": figures[0], "tools": figures[1]}
    return out


def ledger_record(task, agg, now):
    """A live task and its token samples, without prompts, credentials or workspace paths."""
    meta = task["meta"]
    return {
        "v": ledger.SCHEMA_VERSION,
        "id": task["id"],
        "home": os.path.realpath(task["home"]),
        "root": task["root"],
        "harness": meta.get("harness") or "?",
        "model": meta.get("model") or "",
        "effort": meta.get("effort") or "",
        "kind": meta.get("kind") or "ship",
        "project": os.path.basename(meta.get("project") or ""),
        "since": task["since"],
        "lastAt": max(agg["lastAt"], task["statusAt"]),
        "seenAt": now,
        "finishedAt": None,
        "usage": agg["acctTokens"],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--home", action="append", default=[], help="Firstmate home to read (repeatable)")
    ap.add_argument("--claude-limits", default="[]", help="JSON rate-limit windows of the pane session's last API response")
    ap.add_argument("--claude-session", default="", help="the pane session's id, to date those rate limits")
    ap.add_argument("--claude-login", default="", choices=["", "token", "api-key"], help="how the pane session signs in, when this process cannot see its environment")
    ap.add_argument("--claude-account", default="", help="the ai-acct account name the pane session runs as, when it is known")
    args = ap.parse_args()
    deadline = time.monotonic() + SCAN_BUDGET_SECONDS
    homes = args.home or [os.environ.get("FM_HOME") or os.getcwd()]
    now = int(time.time() * 1000)
    errors = []

    cache = {}
    try:
        with open(CACHE_PATH, encoding="utf-8") as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}
    if cache.get("version") != CACHE_VERSION:
        cache = {"version": CACHE_VERSION}
    files = cache.setdefault("files", {})
    owners = message_owners(files, cache.setdefault("scan", {}))
    touched = set()
    known_sessions = quota.load_accounts(accounts_path())
    pane_session = args.claude_session if re.fullmatch(r"[\w-]+", args.claude_session or "") else ""
    pane_account = quota.claude_account_name(args.claude_account)
    if pane_session and pane_account != quota.UNKNOWN:
        known_sessions = quota.register_account(accounts_path(), pane_session, pane_account, now)
    elif pane_session in known_sessions:
        pane_account = quota.claude_account_name(known_sessions[pane_session]["account"])

    seen, visited = set(), set()
    tasks = []
    for home in homes:
        if not os.path.isdir(os.path.join(home, "state")):
            errors.append(f"not a firstmate home: {home}")
            continue
        tasks.extend(collect_tasks(home, 0, seen, None, visited))

    codex_index = None
    rows = []
    totals = empty_agg()
    for task in tasks:
        meta = task["meta"]
        harness = meta.get("harness") or "?"
        worktree = meta.get("worktree") or ""
        agg = empty_agg()
        count = 0
        if worktree:
            for path in claude_files(worktree, task["since"]):
                entry = files.setdefault(path, fresh_entry())
                parse_claude(path, entry, owners, worktree)
                touched.add(path)
                merge(agg, settled_agg(entry, "claude"), entry_account("claude", path, entry, known_sessions), task["since"])
                count += 1
            if codex_index is None:
                codex_index = codex_files(cache, now)
            prefix = worktree.rstrip("/") + "/"
            for path, cwd, modified in codex_index:
                if modified >= task["since"] and (cwd == worktree or cwd.startswith(prefix)):
                    entry = files.setdefault(path, fresh_entry())
                    parse_codex(path, entry, worktree)
                    touched.add(path)
                    merge(agg, settled_agg(entry, "codex"), entry_account("codex", path, entry, known_sessions), task["since"])
                    count += 1
        rows.append((task, agg, count))
        merge(totals, agg)

    if codex_index is None:
        codex_index = codex_files(cache, now)
    found, indexed = scan_local(files, cache["scan"], owners, codex_index, touched, now, deadline)
    try:
        limits = json.loads(args.claude_limits)
    except ValueError:
        limits = []
    own = session_transcript(pane_session)
    own_entry = files.get(own) if own in touched else cache["scan"].get(own)
    limits_at = own_entry["agg"]["lastAt"] if own_entry and own_entry["agg"]["lastAt"] else None
    plan = claude_plan()
    login = args.claude_login or claude_login()
    history = quota.read_history()
    indexes = account_indexes(found, known_sessions)
    pane = pane_candidates(limits, limits_at, pane_account, plan, pane_session)
    candidates = pane + account_cache_candidates() + history_candidates(history) + codex_candidates(found["codex"], known_sessions)
    fresh = record_with_residuals(new_records(pane, found, known_sessions, now), history, indexes, indexed)
    written = quota.append_readings(fresh, now) if fresh else 0
    history = history + fresh
    if written is not None:
        for entry in [*files.values(), *cache["scan"].values()]:
            entry["readings"] = []
    elif fresh:
        errors.append("reading history not saved")
    groups = {(provider, account) for provider, account in indexes} | {(c["provider"], c["account"]) for c in candidates}
    readings, inner = build_readings(groups, candidates, history, indexes, indexed, now, pane_account, plan, login)
    five_hour = (pane_five_hour(limits, limits_at, pane_account) + account_cache_candidates("five_hour")
                 + codex_five_hour(found["codex"], known_sessions))
    readings = {key: {**r, "fiveHour": five_hour_of(five_hour, r["provider"], r["account"], now)} for key, r in readings.items()}
    ctx = {"now": now, "readings": readings, "inner": inner, "indexed": indexed}

    crew = []
    for task, agg, count in rows:
        meta = task["meta"]
        harness = meta.get("harness") or "?"
        worktree = meta.get("worktree") or ""
        readable = harness.startswith("claude") or harness == "codex" or count > 0
        window, window_model, window_source = resolve_window(harness, agg, meta.get("model"))
        top = sorted(agg["tools"].items(), key=lambda kv: -kv[1])[:4]
        statuses = status_events(os.path.join(task["home"], "state", task["id"] + ".status"))
        for event in statuses:
            note_activity(agg, event["at"])
        events = agg["events"] + statuses
        events = sorted(events, key=lambda event: event["at"])[-MAX_EVENTS:]
        activity = [{"minute": int(minute), "count": count} for minute, count in agg["activity"].items()
                    if now // 60000 - ACTIVITY_MINUTES < int(minute) <= now // 60000]
        crew.append(
            {
                "id": task["id"],
                "home": task["home"],
                "depth": task["depth"],
                "kind": meta.get("kind") or "ship",
                "harness": harness,
                "model": meta.get("model") or "",
                "effort": meta.get("effort") or "",
                "project": os.path.basename(meta.get("project") or ""),
                "branch": meta.get("branch") or "",
                "worktree": worktree,
                "description": meta.get("description") or meta.get("title") or task["id"],
                "status": task["status"],
                "statusAt": task["statusAt"],
                "readable": readable,
                "sessions": count,
                "models": agg["models"],
                "requests": agg["requests"],
                "input": agg["input"],
                "output": agg["output"],
                "cacheRead": agg["cacheRead"],
                "cacheWrite": agg["cacheWrite"],
                "reasoning": agg["reasoning"],
                "context": agg["context"],
                "contextWindow": window,
                "contextModel": window_model,
                "windowSource": window_source,
                "events": events,
                "recentTools": agg["events"][-5:],
                "activity": activity,
                "modelTokens": model_totals(agg),
                "tools": agg["tools"],
                "toolCalls": agg["toolCalls"],
                "toolTokens": agg["toolTokens"],
                "topTools": [{"name": n, "count": c} for n, c in top],
                "quota": quota_of(agg, ctx),
                "lastTool": agg["lastTool"],
                "lastText": agg["lastText"],
                "lastAt": max(agg["lastAt"], task["statusAt"]),
            }
        )

    records, saved = ledger.save([ledger_record(task, agg, now) for task, agg, _ in rows], visited, now)
    if not saved and visited:
        errors.append("crew history not saved")
    mine = [rec for rec in records.values() if rec["root"] in visited or rec["home"] in visited]

    # Other sessions share this cache for other homes: drop only logs that are gone or long idle.
    cutoff = now - LOOKBACK_DAYS * 86400000
    cache["files"] = {p: e for p, e in files.items() if p in touched or modified_ms(p) >= cutoff}
    if codex_index is not None:
        live = {p for p, _, _ in codex_index}
        cache["codexCwd"] = {p: c for p, c in cache.get("codexCwd", {}).items() if p in live}
    if tasks:
        try:
            os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
            tmp = CACHE_PATH + f".tmp.{os.getpid()}"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(cache, f)
            os.replace(tmp, CACHE_PATH)
        except OSError as err:
            errors.append(f"cache not saved: {err}")

    json.dump(
        {
            "generatedAt": now,
            "crew": crew,
            "totals": {k: totals[k] for k in ("requests", "input", "output", "cacheRead", "cacheWrite", "reasoning", "toolCalls")},
            "quota": {"readings": readings, "fleet": quota_of(totals, ctx)},
            "history": ledger.summarize(mine, readings, now),
            "errors": errors,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
