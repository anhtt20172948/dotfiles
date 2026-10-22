#!/usr/bin/env bash
# Run the public launcher on a private server with only recording agents.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
export ROOT
python3 - <<'PYTEST'
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="firstmate-resume-") as tmp:
    lab = Path(tmp)
    home = lab / "home"
    firstmate = home / ".local/share/first mate"
    (firstmate / ".git").mkdir(parents=True)
    (firstmate / "state").mkdir()
    # The launcher works from the physical path (pwd -P), as do the agents that
    # record transcript cwds. macOS temp dirs sit behind the /var symlink.
    firstmate = firstmate.resolve()
    tools = lab / "bin"
    tools.mkdir()
    real_tmux = shutil.which("tmux")
    env = {**os.environ, "HOME": str(home), "CODEX_HOME": str(home / ".codex"),
           "CLAUDE_CONFIG_DIR": str(home / ".claude"), "FIRSTMATE_DIR": str(firstmate),
           "TMUX": "private-test", "SOCKET": str(lab / "tmux.sock"),
           "LOG": str(lab / "log"), "PICK": "resume", "AI_FIRSTMATE_AGENT": "claude",
           "PATH": str(tools) + os.pathsep + os.environ["PATH"]}

    def executable(name, body):
        path = tools / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
        path.chmod(0o755)

    executable("tmux", f'''case "$1" in
switch-client) printf 'focus:%s\\n' "$*" >> "$LOG" ;;
display-message) printf 'message:%s\\n' "$*" >> "$LOG" ;;
*) exec {real_tmux} -S "$SOCKET" "$@" ;;
esac
''')
    executable("fzf", '''rows=$(cat)
printf 'picker:%s\\n' "$*" >> "$LOG"
case "$*" in
*'Session › '*)
  printf 'offer:%s\\n' "$rows" >> "$LOG"
  [[ $PICK != cancel ]] || exit 130
  printf '%s\\n' "$PICK" ;;
*) printf '%s\\n' "$rows" | head -n1 | cut -f1 ;;
esac
''')
    executable("ai-acct", '''printf 'account:%s\\n' "$*" >> "$LOG"
case "$1" in
list) printf 'test\\tactive\\n' ;;
use) ;;
exec) shift; exec "$@" ;;
esac
''')
    # The args go first: run() returns once the "<agent>:<cwd>:" line shows up.
    for agent in ("claude", "codex"):
        executable(agent, f'''printf 'arg:%s\\n' "$@" >> "$LOG"
printf '{agent}:%s:%s\\n' "$PWD" "$*" >> "$LOG"
[[ ${{1:-}} != debug ]] || {{ printf '{{"models":[]}}\\n'; exit 0; }}
exit 0
''')
    # A separate fake primary makes kill -0 and process inspection real. Link,
    # not copy: ps reports the name the process was exec'd as, and macOS kills
    # a copied system binary (launch constraints) before it ever runs.
    primary = lab / "claude"
    primary.symlink_to("/bin/sleep")
    workflow = str(Path(os.environ["ROOT"]) / ".config/tmux/scripts/ai-workflow.sh")
    log = lab / "log"

    def tmux(*args, check=True):
        return subprocess.run([real_tmux, "-S", env["SOCKET"], *args], env=env,
                              text=True, capture_output=True, check=check)

    def reset():
        tmux("kill-server", check=False)
        env["SOCKET"] = str(lab / f"tmux-{time.monotonic_ns()}.sock")
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "origin", "-c", str(home), "sleep 30")
        tmux("set-option", "-g", "base-index", "1")
        tmux("set-option", "-g", "default-shell", "/bin/bash")
        tmux("set-option", "-g", "remain-on-exit", "on")
        log.write_text("")

    def run(expect_launch=True):
        result = subprocess.run(["bash", workflow, "firstmate"], env=env, text=True,
                                capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        for _ in range(100):
            output = log.read_text()
            launched = f"{env['AI_FIRSTMATE_AGENT']}:{firstmate}:" in output
            if "message:" in output or ("focus:" in output and (launched or not expect_launch)):
                return output, result.stderr
            time.sleep(.02)
        raise AssertionError("launcher did not finish")

    slug = "".join(c if c.isascii() and c.isalnum() else "-" for c in str(firstmate))
    claude = home / ".claude/projects" / slug / "test.jsonl"
    claude.parent.mkdir(parents=True)
    claude.write_text(json.dumps({"type": "user", "cwd": str(firstmate), "message": {"role": "user", "content": "test"}}) + "\n")
    codex = home / ".codex/sessions/2026/10/21/rollout-test.jsonl"
    codex.parent.mkdir(parents=True)
    codex.write_text(json.dumps({"type": "session_meta", "payload": {"cwd": str(firstmate)}}) + "\n")
    lock = firstmate / "state/.lock"
    try:
        for agent in ("claude", "codex"):
            env["AI_FIRSTMATE_AGENT"] = agent
            for dead_lock in (False, True):
                reset()
                if dead_lock:
                    lock.write_text("2147483647\nopaque metadata\n")
                output, _ = run()
                expected = "--continue" if agent == "claude" else f"resume -C {firstmate} --last"
                assert f"{agent}:{firstmate}:{expected}\n" in output, output
                assert "Model ›" not in output and "Effort ›" not in output, output
                assert "debug models" not in output, output
                if agent == "codex":
                    assert f"arg:resume\narg:-C\narg:{firstmate}\narg:--last\n" in output, output
                else:
                    assert "arg:--continue\n" in output, output
                if agent == "claude":
                    assert "account:use test" in output and "account:exec claude --continue" in output, output
                if dead_lock:
                    assert lock.read_text() == "2147483647\nopaque metadata\n"
                    lock.unlink()
            # Existing window focuses without showing any picker.
            log.write_text("")
            output, _ = run(expect_launch=False)
            assert "picker:" not in output and "focus:" in output, output

        reset()
        env["PICK"] = "cancel"
        result = subprocess.run(["bash", workflow, "firstmate"], env=env, text=True,
                                capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert "focus:" not in log.read_text() and "account:use" not in log.read_text()
        assert tmux("has-session", "-t", "=firstmate", check=False).returncode != 0

        for agent in ("claude", "codex"):
            env["AI_FIRSTMATE_AGENT"] = agent
            reset()
            env["PICK"] = "new"
            output, _ = run()
            assert f"{agent}:{firstmate}:\n" in output, output
            assert "Resume last Firstmate session" in output, output
            assert "Model ›" in output and "Effort ›" in output, output
        env["PICK"] = "resume"

        for name in ("claude", "codex"):
            holder_path = lab / name
            if not holder_path.exists():
                holder_path.symlink_to("/bin/sleep")
            with subprocess.Popen([str(holder_path), "30"]) as holder:
                reset()
                lock.write_text(f"{holder.pid}\nunchanged\n")
                output, _ = run()
                assert "message:" in output and "lock" in output.lower(), output
                assert "picker:" not in output and f"codex:{firstmate}:" not in output, output
                assert lock.read_text() == f"{holder.pid}\nunchanged\n"
                holder.terminate()
            lock.unlink()

        reset()
        tmux("new-session", "-d", "-s", "firstmate", "-n", "busy", "sleep 30")
        output, _ = run()
        assert f"codex:{firstmate}:resume -C {firstmate} --last" in output, output
        assert "busy" in tmux("list-windows", "-t", "firstmate", "-F", "#{window_name}").stdout

        # A reused PID belonging to a non-agent must not block recovery.
        with subprocess.Popen(["sleep", "30"]) as other:
            reset()
            lock.write_text(f"{other.pid}\n")
            output, _ = run()
            assert f"codex:{firstmate}:resume -C {firstmate} --last" in output, output
            other.terminate()
        lock.unlink()

        for agent, transcript in (("claude", claude), ("codex", codex)):
            env["AI_FIRSTMATE_AGENT"] = agent
            reset()
            original = transcript.read_text()
            transcript.write_text(original.replace(str(firstmate), str(home / "other")))
            env["PICK"] = "new"
            output, stderr = run()
            assert "no" in stderr.lower() and "resume" in stderr and "new" in stderr.lower(), stderr
            assert "offer:new" in output and "offer:resume" not in output, output
            assert "Model ›" in output and "Effort ›" in output, output
            assert f"{agent}:{firstmate}:\n" in output, output
            assert "--continue" not in output and "resume -C" not in output, output
            # Empty or malformed files must also leave only the new-session offer.
            for invalid in (None, "", "not json\n"):
                reset()
                if invalid is None:
                    transcript.unlink()
                else:
                    transcript.write_text(invalid)
                output, stderr = run()
                assert "Resume last Firstmate session" not in output, output
                assert "No" in stderr and "transcript" in stderr, stderr
        print("firstmate resume: OK")
    finally:
        tmux("kill-server", check=False)
PYTEST
