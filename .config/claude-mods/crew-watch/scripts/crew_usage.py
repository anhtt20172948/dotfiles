#!/usr/bin/env python3
"""Summarize what every live Firstmate crewmate is doing and what it costs.

Reads each home's state/*.meta (one per live task), finds the task's own
transcripts by its worktree, written since the task first started (pooled
worktrees are reused; a relaunch keeps earlier usage, even under another
harness), and prints one JSON document on stdout:

  {"generatedAt": ms, "crew": [...], "totals": {...}, "errors": [...]}

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

Weekly quota share. Vendors publish no weekly caps in tokens, so the share is
(weekly window percent used) x (weighted tokens of the crewmate, or the direct
cost of its tool calls, since the window started) / (weighted tokens of every
local session of that provider since then). Tokens are weighted by PRICE_RATIO
and FAMILY_PRICE below. The percent, reset time and plan come from local
sources only: the rate limits of the pane session's last API response
(--claude-limits, read at the newest response in its own transcript, found by
--claude-session), Claude Code's cached usage in ~/.claude.json, Codex rollout
rate-limit events and Claude's local plan metadata. The freshest reading whose
window has not reset wins, reported with its source and read time; one older
than STALE_MS, or of unknown age, is flagged stale. Without a reading only the
raw share of local usage is reported. Usage from other machines or the web is
invisible here, so with a current reading the share is an upper bound for local
work; a stale reading can understate it.
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

CACHE_VERSION = 9
HOME = os.path.expanduser("~")
CLAUDE_PROJECTS = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude")), "projects")
CODEX_SESSIONS = os.path.join(os.environ.get("CODEX_HOME", os.path.join(HOME, ".codex")), "sessions")
CACHE_PATH = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "crew-watch", "cache.json")
LOOKBACK_DAYS = 30
SNIPPET = 180
MAX_EVENTS = 10
ACTIVITY_MINUTES = 60
BUCKET_MS = 15 * 60000
WEEK_MS = 7 * 86400000
CHARS_PER_TOKEN = 4
SCAN_BUDGET_SECONDS = 10
STALE_MS = 30 * 60000

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
        "toolTokens": {},
    }


def token_weights(provider, model):
    base = next(price for key, price in FAMILY_PRICE[provider] if key in (model or "").lower())
    return {kind: base * ratio for kind, ratio in PRICE_RATIO[provider].items()}


def weigh(provider, model, fresh=0, output=0, cache_read=0, cache_write=0, cache_write_1h=0):
    w = token_weights(provider, model)
    return (fresh * w["input"] + output * w["output"] + cache_read * w["cacheRead"] + cache_write * w["cacheWrite"]
            + cache_write_1h * w["cacheWrite1h"])


def add_cost(agg, provider, at, session=0.0, tool=0.0):
    """Weighted tokens by provider and 15-minute bucket: [whole session, its tool calls]."""
    if at <= 0 or not (session or tool):
        return
    slots = agg["cost"].setdefault(provider, {})
    key = str(at // BUCKET_MS)
    old = slots.get(key, (0.0, 0.0))
    slots[key] = [old[0] + session, old[1] + tool]


def window_cost(agg, provider, start):
    """(session, tool calls) weighted tokens in buckets that end after start."""
    first = start // BUCKET_MS
    session = tools = 0.0
    for key, (whole, calls) in agg["cost"].get(provider, {}).items():
        if int(key) >= first:
            session += whole
            tools += calls
    return max(0.0, session), max(0.0, tools)


def merge(into, part):
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
    for provider, buckets in part["cost"].items():
        mine = into["cost"].setdefault(provider, {})
        for key, (whole, calls) in buckets.items():
            old = mine.get(key, (0.0, 0.0))
            mine[key] = [old[0] + whole, old[1] + calls]
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
            "flow": {"cur": None, "open": None}, "ids": []}


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


def parse_codex(path, entry, worktree=""):
    for row in read_new_lines(path, entry):
        agg = entry["agg"]
        meta = entry["meta"]
        kind = row.get("type")
        payload = row.get("payload") or {}
        at = ts_ms(row.get("timestamp"))
        if kind == "session_meta":
            meta["cwd"] = payload.get("cwd") or ""
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
                    meta["limits"] = {"at": at, "plan": limits.get("plan_type") or "", "windows": [
                        {"percent": w.get("used_percent"), "minutes": w.get("window_minutes"), "resetsAt": w.get("resets_at")}
                        for w in windows]}
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
            if last:
                agg["requests"] += 1
                agg["context"] = last.get("input_tokens") or 0
                model = meta.get("model") or "codex"
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


def collect_tasks(home, depth, seen):
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
    for name in names:
        if not name.endswith(".meta") or name.startswith("."):
            continue
        tid = name[: -len(".meta")]
        meta = read_meta(os.path.join(state, name))
        status, status_at = last_status(os.path.join(state, tid + ".status"))
        since = task_start(meta, os.path.join(state, name), os.path.join(state, tid + ".status"))
        tasks.append({"id": tid, "home": home, "depth": depth, "meta": meta, "since": since,
                      "status": status, "statusAt": status_at})
        if meta.get("kind") == "secondmate" and meta.get("worktree") and not meta.get("remote_host"):
            tasks.extend(collect_tasks(meta["worktree"], depth + 1, seen))
    return tasks


def scan_local(files, scan, owners, codex_index, touched, now, deadline):
    """Every local session of the last week, per provider, for the quota denominator.

    Files a crewmate owns reuse that entry; the rest are parsed into a separate
    cache so their tool texts are never abbreviated for the wrong worktree.
    Parsing stops at the run's deadline; the next poll resumes, and the provider
    is flagged as still indexing.
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
            found[provider].append(files[path])
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
            found[provider].append(entry)
    for path in [p for p in scan if p in touched or modified_ms(p) < since]:
        del scan[path]
    return found, indexed


def quota_of(agg, providers):
    """Per provider: the estimated share of the weekly limit for the session and for its tool calls."""
    out = {}
    for name, info in providers.items():
        session, tools = window_cost(agg, name, info["windowStart"])
        if session <= 0 and tools <= 0:
            continue
        percent = info["percentUsed"]
        measured = info["indexed"]
        out[name] = {
            "session": quota_share(percent, session, info["localCost"]) if measured else {"share": None, "percent": None},
            "tools": quota_share(percent, tools, info["localCost"]) if measured else {"share": None, "percent": None},
        }
    return out


def quota_share(percent, part, total):
    """Share of local usage and, with a current window percent, of the weekly limit."""
    if total <= 0 or part < 0:
        return {"share": None, "percent": None}
    share = min(1.0, part / total)
    return {"share": share, "percent": None if percent is None else percent * share}


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


def window_candidate(source, percent, resets_at, window_ms, read_at):
    if not isinstance(percent, (int, float)) or isinstance(percent, bool):
        return None
    return {"source": source, "percent": float(percent), "resetsAt": resets_at or None,
            "windowMs": window_ms or WEEK_MS, "readAt": read_at or None}


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


def claude_candidates(limits, limits_at):
    """The pane session's rate limits, read at its last API response (None when unknown), and Claude Code's cached /usage."""
    out = []
    for limit in limits if isinstance(limits, list) else []:
        if isinstance(limit, dict) and limit.get("kind") == "seven_day":
            out.append(window_candidate("this session", limit.get("percentUsed"), ts_ms(limit.get("resetsAt")), WEEK_MS,
                                        limits_at))
    cached = claude_global_config().get("cachedUsageUtilization")
    week = ((cached or {}).get("utilization") or {}).get("seven_day") if isinstance(cached, dict) else None
    if isinstance(week, dict):
        out.append(window_candidate("usage cache", week.get("utilization"), ts_ms(week.get("resets_at")), WEEK_MS,
                                    cached.get("fetchedAtMs")))
    return out


def codex_candidates(entries):
    """The newest rate-limit event any local rollout recorded, and the plan it names."""
    newest = None
    for entry in entries:
        limits = entry.get("meta", {}).get("limits")
        if limits and (newest is None or limits["at"] >= newest["at"]):
            newest = limits
    plan = (newest or {}).get("plan") or ""
    weekly = [w for w in (newest or {}).get("windows", []) if (w.get("minutes") or 0) >= 7200]
    if not weekly:
        return [], plan
    week = max(weekly, key=lambda w: w["minutes"])
    return [window_candidate("codex log", week.get("percent"), (week.get("resetsAt") or 0) * 1000,
                             week["minutes"] * 60000, newest["at"])], plan


def pick_window(candidates, now):
    """The freshest weekly reading still in force; a window that has reset says nothing about the new one."""
    live = [c for c in candidates if c["resetsAt"] is None or c["resetsAt"] > now]
    return max(live, key=lambda c: c["readAt"] or 0) if live else None


def provider_window(candidates, plan, now, login=""):
    candidates = [c for c in candidates if c]
    window = pick_window(candidates, now)
    known = bool(window and window["resetsAt"])
    start = window["resetsAt"] - window["windowMs"] if known else now - WEEK_MS
    return {
        "plan": plan,
        "login": login,
        "percentUsed": window["percent"] if window else None,
        "resetsAt": window["resetsAt"] if window else None,
        "windowStart": max(start, now - WEEK_MS),
        "windowStartKnown": known,
        "source": window["source"] if window else "",
        "readAt": window["readAt"] if window else None,
        "stale": bool(window) and (window["readAt"] is None or now - window["readAt"] > STALE_MS),
        "reset": bool(candidates) and window is None,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--home", action="append", default=[], help="Firstmate home to read (repeatable)")
    ap.add_argument("--claude-limits", default="[]", help="JSON rate-limit windows of the pane session's last API response")
    ap.add_argument("--claude-session", default="", help="the pane session's id, to date those rate limits")
    ap.add_argument("--claude-login", default="", choices=["", "token", "api-key"], help="how the pane session signs in, when this process cannot see its environment")
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

    seen = set()
    tasks = []
    for home in homes:
        if not os.path.isdir(os.path.join(home, "state")):
            errors.append(f"not a firstmate home: {home}")
            continue
        tasks.extend(collect_tasks(home, 0, seen))

    codex_index = None
    rows = []
    totals = empty_agg()
    for task in tasks:
        meta = task["meta"]
        harness = meta.get("harness") or "?"
        worktree = meta.get("worktree") or ""
        agg = empty_agg()
        sessions = 0
        if worktree:
            for path in claude_files(worktree, task["since"]):
                entry = files.setdefault(path, fresh_entry())
                parse_claude(path, entry, owners, worktree)
                touched.add(path)
                merge(agg, settled_agg(entry, "claude"))
                sessions += 1
            if codex_index is None:
                codex_index = codex_files(cache, now)
            prefix = worktree.rstrip("/") + "/"
            for path, cwd, modified in codex_index:
                if modified >= task["since"] and (cwd == worktree or cwd.startswith(prefix)):
                    entry = files.setdefault(path, fresh_entry())
                    parse_codex(path, entry, worktree)
                    touched.add(path)
                    merge(agg, settled_agg(entry, "codex"))
                    sessions += 1
        rows.append((task, agg, sessions))
        merge(totals, agg)

    if codex_index is None:
        codex_index = codex_files(cache, now)
    found, indexed = scan_local(files, cache["scan"], owners, codex_index, touched, now, deadline)
    try:
        limits = json.loads(args.claude_limits)
    except ValueError:
        limits = []
    own = session_transcript(args.claude_session)
    own_entry = files.get(own) if own in touched else cache["scan"].get(own)
    limits_at = own_entry["agg"]["lastAt"] if own_entry else None
    codex_cands, codex_rollout_plan = codex_candidates(found["codex"])
    providers = {
        "claude": provider_window(claude_candidates(limits, limits_at), claude_plan(), now, args.claude_login or claude_login()),
        "codex": provider_window(codex_cands, codex_rollout_plan.title(), now, "rollout"),
    }
    for name, info in providers.items():
        info["indexed"] = indexed[name]
        info["localCost"] = sum(window_cost(e["agg"], name, info["windowStart"])[0] for e in found[name])

    crew = []
    for task, agg, sessions in rows:
        meta = task["meta"]
        harness = meta.get("harness") or "?"
        worktree = meta.get("worktree") or ""
        readable = harness.startswith("claude") or harness == "codex" or sessions > 0
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
                "sessions": sessions,
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
                "tools": agg["tools"],
                "toolCalls": agg["toolCalls"],
                "toolTokens": agg["toolTokens"],
                "topTools": [{"name": n, "count": c} for n, c in top],
                "quota": quota_of(agg, providers),
                "lastTool": agg["lastTool"],
                "lastText": agg["lastText"],
                "lastAt": max(agg["lastAt"], task["statusAt"]),
            }
        )

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
            "quota": {"providers": providers, "fleet": quota_of(totals, providers)},
            "errors": errors,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
