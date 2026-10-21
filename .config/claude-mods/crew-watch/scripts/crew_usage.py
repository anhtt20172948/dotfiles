#!/usr/bin/env python3
"""Summarize what every live Firstmate crewmate is doing and what it costs.

Reads each home's state/*.meta (one per live task), finds the task's own
transcripts by its worktree, and prints one JSON document on stdout:

  {"generatedAt": ms, "crew": [...], "totals": {...}, "errors": [...]}

Claude crewmates are read from ~/.claude/projects/<encoded worktree>/**.jsonl
(subagent transcripts included), Codex crewmates from ~/.codex/sessions rollouts
whose session cwd is the worktree. Other harnesses get a meta-only row.

Parsing is incremental: per-file byte offsets and partial sums are cached in
~/.cache/crew-watch/cache.json, so a poll only reads what was appended.
A secondmate's own home is followed recursively for its crew.
"""

import argparse
import json
import os
import re
import sys
import time

CACHE_VERSION = 4
HOME = os.path.expanduser("~")
CLAUDE_PROJECTS = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude")), "projects")
CODEX_SESSIONS = os.path.join(os.environ.get("CODEX_HOME", os.path.join(HOME, ".codex")), "sessions")
CACHE_PATH = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "crew-watch", "cache.json")
CODEX_LOOKBACK_DAYS = 30
SNIPPET = 180
MAX_EVENTS = 10
ACTIVITY_MINUTES = 60


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
    }


def merge(into, part):
    for k in ("requests", "input", "output", "cacheRead", "cacheWrite", "reasoning", "toolCalls"):
        into[k] += part[k]
    for k in ("tools", "models"):
        for name, n in part[k].items():
            into[k][name] = into[k].get(name, 0) + n
    into["events"] = sorted(into["events"] + part["events"], key=lambda event: event["at"])[-MAX_EVENTS:]
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


def note_event(agg, at, text):
    if at > 0:
        agg["events"] = (agg["events"] + [{"at": at, "kind": "tool", "text": text}])[-MAX_EVENTS:]


def one_line(text, limit=SNIPPET):
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def ts_ms(value):
    if not value:
        return 0
    try:
        from datetime import datetime

        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def describe_tool(name, args):
    if not isinstance(args, dict):
        try:
            args = json.loads(args) if isinstance(args, str) else {}
        except ValueError:
            # Codex code-mode tools wrap the real call in a script.
            cmd = re.search(r'"cmd"\s*:\s*"((?:[^"\\]|\\.)*)"', args)
            return one_line(f"{name}: {cmd.group(1) if cmd else args}")
        if not isinstance(args, dict):
            args = {}
    for key in ("command", "cmd", "file_path", "path", "pattern", "url", "description", "prompt", "query"):
        val = args.get(key)
        if val:
            if isinstance(val, list):
                val = " ".join(str(v) for v in val)
            return one_line(f"{name}: {val}")
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
    return {"offset": 0, "agg": empty_agg(), "msgId": None, "msgUsage": None, "meta": {}}


def apply_claude_usage(agg, usage, sign):
    agg["input"] += sign * (usage.get("input_tokens") or 0)
    agg["output"] += sign * (usage.get("output_tokens") or 0)
    agg["cacheRead"] += sign * (usage.get("cache_read_input_tokens") or 0)
    agg["cacheWrite"] += sign * (usage.get("cache_creation_input_tokens") or 0)
    details = usage.get("output_tokens_details") or {}
    agg["reasoning"] += sign * (details.get("thinking_tokens") or 0)


def parse_claude(path, entry):
    for row in read_new_lines(path, entry):
        agg = entry["agg"]
        if row.get("type") != "assistant":
            continue
        msg = row.get("message") or {}
        at = ts_ms(row.get("timestamp"))
        usage = msg.get("usage") or {}
        model = msg.get("model") or ""
        if model == "<synthetic>":
            continue
        note_activity(agg, at)
        # One API message is written as one row per content block, each with
        # the message's usage so far: count it once, at its latest reading.
        mid = msg.get("id")
        if mid and mid == entry["msgId"]:
            if entry["msgUsage"]:
                apply_claude_usage(agg, entry["msgUsage"], -1)
        else:
            agg["requests"] += 1
            if model:
                agg["models"][model] = agg["models"].get(model, 0) + 1
        if usage:
            apply_claude_usage(agg, usage, 1)
            agg["context"] = (
                (usage.get("input_tokens") or 0)
                + (usage.get("cache_read_input_tokens") or 0)
                + (usage.get("cache_creation_input_tokens") or 0)
            )
        entry["msgId"] = mid
        entry["msgUsage"] = usage or None
        for block in msg.get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                name = block.get("name") or "?"
                agg["toolCalls"] += 1
                agg["tools"][name] = agg["tools"].get(name, 0) + 1
                agg["lastTool"] = describe_tool(name, block.get("input"))
                note_event(agg, at, agg["lastTool"])
            elif block.get("type") == "text" and (block.get("text") or "").strip():
                agg["lastText"] = one_line(block["text"])
        if at:
            agg["lastAt"] = max(agg["lastAt"], at)


def parse_codex(path, entry):
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
        elif kind == "response_item":
            ptype = payload.get("type")
            if ptype in ("function_call", "custom_tool_call", "local_shell_call", "web_search_call"):
                name = payload.get("name") or ptype
                agg["toolCalls"] += 1
                agg["tools"][name] = agg["tools"].get(name, 0) + 1
                args = payload.get("arguments") or payload.get("input") or payload.get("action") or {}
                agg["lastTool"] = describe_tool(name, args)
                note_event(agg, at, agg["lastTool"])
                note_activity(agg, at)
            elif ptype == "message" and payload.get("role") == "assistant":
                for block in payload.get("content") or []:
                    text = block.get("text") if isinstance(block, dict) else None
                    if text and text.strip():
                        agg["lastText"] = one_line(text)
                        note_activity(agg, at)
        if at:
            agg["lastAt"] = max(agg["lastAt"], at)


def claude_project_dir(worktree):
    return os.path.join(CLAUDE_PROJECTS, re.sub(r"[^A-Za-z0-9]", "-", worktree))


def claude_files(worktree):
    root = claude_project_dir(worktree)
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if name.endswith(".jsonl"):
                out.append(os.path.join(dirpath, name))
    return out


def codex_files(cache, now):
    """Every recent rollout, its session cwd read once and cached."""
    cwds = cache.setdefault("codexCwd", {})
    out = []
    cutoff = now / 1000 - CODEX_LOOKBACK_DAYS * 86400
    for dirpath, _dirs, files in os.walk(CODEX_SESSIONS):
        for name in files:
            if not (name.startswith("rollout-") and name.endswith(".jsonl")):
                continue
            path = os.path.join(dirpath, name)
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
            except OSError:
                continue
            if path not in cwds:
                cwd = ""
                try:
                    with open(path, "rb") as f:
                        first = json.loads(f.readline() or b"{}")
                    if first.get("type") == "session_meta":
                        cwd = (first.get("payload") or {}).get("cwd") or ""
                except (OSError, ValueError):
                    cwd = ""
                cwds[path] = cwd
            out.append((path, cwds[path]))
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
        tasks.append({"id": tid, "home": home, "depth": depth, "meta": meta, "status": status, "statusAt": status_at})
        if meta.get("kind") == "secondmate" and meta.get("worktree") and not meta.get("remote_host"):
            tasks.extend(collect_tasks(meta["worktree"], depth + 1, seen))
    return tasks


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--home", action="append", default=[], help="Firstmate home to read (repeatable)")
    args = ap.parse_args()
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
    touched = set()

    seen = set()
    tasks = []
    for home in homes:
        if not os.path.isdir(os.path.join(home, "state")):
            errors.append(f"not a firstmate home: {home}")
            continue
        tasks.extend(collect_tasks(home, 0, seen))

    codex_index = None
    crew = []
    totals = empty_agg()
    for task in tasks:
        meta = task["meta"]
        harness = meta.get("harness") or "?"
        worktree = meta.get("worktree") or ""
        agg = empty_agg()
        sessions = 0
        readable = harness.startswith("claude") or harness == "codex"
        if worktree and harness.startswith("claude"):
            for path in claude_files(worktree):
                entry = files.setdefault(path, fresh_entry())
                parse_claude(path, entry)
                touched.add(path)
                merge(agg, entry["agg"])
                sessions += 1
        elif worktree and harness == "codex":
            if codex_index is None:
                codex_index = codex_files(cache, now)
            prefix = worktree.rstrip("/") + "/"
            for path, cwd in codex_index:
                if cwd == worktree or cwd.startswith(prefix):
                    entry = files.setdefault(path, fresh_entry())
                    parse_codex(path, entry)
                    touched.add(path)
                    merge(agg, entry["agg"])
                    sessions += 1
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
                "contextWindow": agg["contextWindow"],
                "events": events,
                "recentTools": agg["events"][-5:],
                "activity": activity,
                "tools": agg["tools"],
                "toolCalls": agg["toolCalls"],
                "topTools": [{"name": n, "count": c} for n, c in top],
                "lastTool": agg["lastTool"],
                "lastText": agg["lastText"],
                "lastAt": max(agg["lastAt"], task["statusAt"]),
            }
        )
        merge(totals, agg)

    # Keep only files a live task still reads, so the cache never grows unbounded.
    cache["files"] = {p: e for p, e in files.items() if p in touched}
    if codex_index is not None:
        live = {p for p, _ in codex_index}
        cache["codexCwd"] = {p: c for p, c in cache.get("codexCwd", {}).items() if p in live}
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
            "errors": errors,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
