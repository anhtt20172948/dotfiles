#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
export ROOT
python3 - <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid


with tempfile.TemporaryDirectory(prefix="ai-sessions-") as scratch:
    # Physical path: the scripts and agents record cwd as pwd -P, and macOS temp
    # dirs sit behind the /var -> /private/var symlink.
    tmp = Path(scratch).resolve()
    home = tmp / "home"
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    home.mkdir()
    scripts = Path(os.environ["ROOT"]) / ".config/tmux/scripts"
    env = {**os.environ, "HOME": str(home), "PATH": f"{bin_dir}:{os.environ['PATH']}",
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"),
           "XDG_STATE_HOME": str(home / ".local/state"), "XDG_CACHE_HOME": str(home / ".cache"),
           "CODEX_HOME": str(home / ".codex"), "AI_POPUP_LOCATION": "host",
           "AI_POPUP_CONTAINER": "", "AI_POPUP_CONTAINER_PATH": "",
           "CAPTURE": str(tmp / "entries")}
    failures = []

    def check(condition, description):
        print(f"{'ok' if condition else 'FAIL'}: {description}")
        if not condition:
            failures.append(description)

    def stub(name, body):
        path = bin_dir / name
        path.write_text("#!/usr/bin/env bash\n" + body + "\n")
        path.chmod(0o755)

    stub("tmux", "exit 1")
    stub("claude", "exit 0")
    stub("fzf", 'cat > "$CAPTURE"\nawk -F "\\t" \'$1 == "resume" {print; found=1; exit} END {if (!found) exit 130}\' "$CAPTURE" | cut -f1-7\nexit "${PIPESTATUS[0]}"')

    def run(command, cwd, extra=None):
        return subprocess.run(command, cwd=cwd, env={**env, "PWD": str(cwd), **(extra or {})},
                              text=True, capture_output=True, check=True, timeout=20).stdout

    def transcript(cwd, tool="claude", newer=False):
        session = str(uuid.uuid4())
        timestamp = "2026-10-21T00:00:00Z"
        if tool == "claude":
            slug = re.sub(r"[^a-zA-Z0-9]", "-", str(cwd))
            path = home / ".claude/projects" / slug / f"{session}.jsonl"
            rows = [{"type": "user", "sessionId": session, "cwd": str(cwd),
                     "timestamp": timestamp, "message": {"content": "fixture session"}},
                    {"type": "assistant", "sessionId": session, "cwd": str(cwd),
                     "timestamp": timestamp, "message": {"usage": {"input_tokens": 42}}}]
        else:
            path = home / ".codex/sessions/2026/10/21" / f"rollout-{session}.jsonl"
            rows = [{"type": "session_meta", "payload": {
                "id": session, "cwd": str(cwd), "timestamp": timestamp}},
                {"type": "event_msg", "payload": {
                    "type": "user_message", "message": "fixture session"}}]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        os.utime(path, (2000000000 if newer else 1000000000,) * 2)
        return session, path

    def picker(cwd, tool, wanted, description):
        output = run(["bash", str(scripts / "ai-sessions.sh"), "--tool", tool], cwd)
        check(output == f"resume\t{tool}\t{wanted}\t{cwd.resolve()}\n", description)

    # Drive the real picker entry point; only terminal UI and tmux are replaced.
    plain = tmp / "plain"
    dotted = home / ".local/share/firstmate"
    underscored = tmp / "project_name"
    for cwd in (plain, dotted, underscored):
        cwd.mkdir(parents=True)
        session, _ = transcript(cwd)
        picker(cwd, "claude", session, f"Claude picker lists {cwd.name}")
        if cwd == dotted:
            dotted_id = session
    alias = tmp / "alias"
    alias.symlink_to(dotted, target_is_directory=True)
    output = run(["bash", str(scripts / "ai-sessions.sh"), "--tool", "claude"], alias)
    check(output == f"resume\tclaude\t{dotted_id}\t{dotted}\n", "Claude picker resolves symlink cwd")

    # Distinct cwd values can share a slug. Newer collisions must not starve it.
    collision = tmp / "a-b"
    other = tmp / "a_b"
    collision.mkdir()
    wanted, _ = transcript(collision)
    for _ in range(110):
        transcript(other, newer=True)
    picker(collision, "claude", wanted, "scoped Claude survives 110 newer slug collisions")
    check(len((tmp / "entries").read_text().splitlines()) == 2,
          "scoped Claude excludes sessions of a colliding cwd")

    codex_id, _ = transcript(plain, "codex")
    for _ in range(110):
        transcript(other, "codex", newer=True)
    picker(plain, "codex", codex_id, "scoped Codex survives 110 newer projects")
    plain_alias = tmp / "plain-alias"
    plain_alias.symlink_to(plain, target_is_directory=True)
    output = run(["bash", str(scripts / "ai-sessions.sh"), "--tool", "codex"], plain_alias)
    check(output == f"resume\tcodex\t{codex_id}\t{plain}\n", "Codex picker resolves symlink cwd")

    # Source only function definitions to exercise all-mode and destructive paths
    # without entering the interactive picker. Every path is in this scratch HOME.
    definitions = '''
source "$1/ai-lib.sh"
# eval, not source <(...): bash 3.2 (macOS /bin/bash) sources nothing from a pipe.
eval "$(sed -n '/^list_codex_sessions() {$/,/^}$/p; /^list_claude_sessions() {$/,/^}$/p; /^delete_saved_session() {$/,/^}$/p; /^clean_title() {$/,/^}$/p' "$1/ai-sessions.sh")"
shift
"$@"
'''
    def function(*args, cwd=plain):
        return run(["bash", "-c", definitions, "test", str(scripts), *map(str, args)], cwd)

    for tool in ("claude", "codex"):
        rows = function(f"list_{tool}_sessions", home, plain, 1).splitlines()
        check(len(rows) == 100, f"all-projects {tool} retains 100-file limit")

    # Copied container stores use container cwd strings, even when the same path
    # happens to be a symlink on the host.
    snapshot = tmp / "snapshot"
    for tool in ("claude", "codex"):
        remote_id, path = transcript(alias, tool)
        dest = snapshot / path.relative_to(home)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        rows = function(f"list_{tool}_sessions", snapshot, alias, 0).splitlines()
        check(len(rows) == 1 and rows[0].split("\t")[0] == remote_id,
              f"copied {tool} store keeps container cwd independent of host symlinks")

    busy = tmp / "busy"
    busy.mkdir()
    busy_ids = {transcript(busy)[0] for _ in range(105)}
    rows = function("list_claude_sessions", home, busy, 0).splitlines()
    check({row.split("\t")[0] for row in rows} == busy_ids,
          "scoped Claude lists every transcript of the requested cwd")

    preview = run(["bash", str(scripts / "ai-picker.sh"), "--preview", "claude"], dotted)
    check(re.search(r"Input.*42 tokens", preview) is not None,
          "tool picker reads dotted cwd usage")

    stub("trash", 'printf "%s\\n" "$@" > "$CAPTURE"')
    (tmp / "entries").write_text("")
    try:
        function("delete_saved_session", "claude", dotted_id, cwd=dotted)
    except subprocess.CalledProcessError as error:
        check(False, f"delete helper succeeds (exit {error.returncode})")
    expected = home / ".claude/projects" / re.sub(r"[^a-zA-Z0-9]", "-", str(dotted)) / f"{dotted_id}.jsonl"
    check((tmp / "entries").read_text() == f"{expected}\n", "delete uses the same dotted cwd slug")

    container_dir = "/root/.local/share/firstmate"
    stub("docker", '''
case "$1" in
  exec) printf /root ;;
  cp) printf '%s\\n' "$2" "$3" > "$CAPTURE" ;;
  *) exit 1 ;;
esac''')
    function("extract_container_sessions", "fixture", "claude", container_dir, tmp / "copy")
    check((tmp / "entries").read_text().splitlines() == [
        "fixture:/root/.claude/projects/-root--local-share-firstmate",
        str(tmp / "copy/.claude/projects/-root--local-share-firstmate")],
        "container extraction uses the same dotted cwd slug")
    if failures:
        raise SystemExit(f"{len(failures)} session regression(s) failed")
    print("AI sessions: OK")
PY
