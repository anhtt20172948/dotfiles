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
check|use) ;;
exec) shift; [[ $1 != --account ]] || shift 2; exec "$@" ;;
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

    def wait_dead(session="firstmate", count=1):
        for _ in range(200):
            dead = tmux("list-panes", "-t", session, "-F", "#{pane_dead}", check=False).stdout.split()
            if len(dead) == count and all(d == "1" for d in dead):
                return
            time.sleep(.02)
        raise AssertionError("pane did not exit")

    def pane_pid(target):
        return int(tmux("list-panes", "-t", target, "-F", "#{pane_pid}").stdout.split()[0])

    def window_names(session="firstmate"):
        return tmux("list-windows", "-t", session, "-F", "#{window_name}").stdout.split("\n")[:-1]

    def resume_args(agent):
        if agent == "claude":
            return f"--resume {session_id['claude']}"
        return f"resume -C {firstmate} {session_id['codex']}"

    slug = "".join(c if c.isascii() and c.isalnum() else "-" for c in str(firstmate))
    claude_id = "5b0e7a52-0000-4000-8000-000000000001"
    codex_id = "019a0000-0000-7000-8000-000000000001"
    claude = home / ".claude/projects" / slug / f"{claude_id}.jsonl"
    claude.parent.mkdir(parents=True)

    def claude_line(cwd):
        return json.dumps({"type": "user", "cwd": str(cwd), "message": {"role": "user", "content": "test"}}) + "\n"

    def codex_line(cwd, session):
        return json.dumps({"type": "session_meta", "payload": {"cwd": str(cwd), "id": session}}) + "\n"

    claude.write_text(claude_line(firstmate))
    codex = home / ".codex/sessions/2026/10/21/rollout-test.jsonl"
    codex.parent.mkdir(parents=True)
    codex.write_text(codex_line(firstmate, codex_id))
    session_id = {"claude": claude_id, "codex": codex_id}
    lock = firstmate / "state/.lock"
    try:
        for agent in ("claude", "codex"):
            env["AI_FIRSTMATE_AGENT"] = agent
            for dead_lock in (False, True):
                reset()
                if dead_lock:
                    lock.write_text("2147483647\nopaque metadata\n")
                output, _ = run()
                assert f"{agent}:{firstmate}:{resume_args(agent)}\n" in output, output
                assert "Model ›" not in output and "Effort ›" not in output, output
                assert "debug models" not in output, output
                if agent == "codex":
                    assert f"arg:resume\narg:-C\narg:{firstmate}\narg:{codex_id}\n" in output, output
                    assert "--last" not in output, output
                else:
                    assert f"arg:--resume\narg:{claude_id}\n" in output, output
                    assert "--continue" not in output, output
                    assert f"account:exec --account test claude --resume {claude_id}" in output, output
                    # Launching binds the account to the pane; it never switches the selector.
                    assert "account:use" not in output and "account:check test" in output, output
                if dead_lock:
                    assert lock.read_text() == "2147483647\nopaque metadata\n"
                    lock.unlink()
            # An exited agent must not suppress recovery: the dead pane is reused.
            wait_dead()
            log.write_text("")
            output, _ = run()
            assert "offer:resume" in output, output
            assert f"{agent}:{firstmate}:{resume_args(agent)}\n" in output, output
            assert window_names() == ["firstmate"], window_names()

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
        assert f"codex:{firstmate}:{resume_args('codex')}" in output, output
        assert "busy" in tmux("list-windows", "-t", "firstmate", "-F", "#{window_name}").stdout

        # A reused PID belonging to a non-agent must not block recovery.
        with subprocess.Popen(["sleep", "30"]) as other:
            reset()
            lock.write_text(f"{other.pid}\n")
            output, _ = run()
            assert f"codex:{firstmate}:{resume_args('codex')}" in output, output
            other.terminate()
        lock.unlink()

        # --- window identity -------------------------------------------------
        env["AI_FIRSTMATE_AGENT"] = "claude"
        agent_cmd = f"exec {lab}/claude 30"

        def assert_recovered(output, agent="claude"):
            assert "picker:" in output and f"{agent}:{firstmate}:{resume_args(agent)}" in output, output

        # A live primary holding the lock is focused under any window name.
        for session, name in (("firstmate", "firstmate"), ("other", "renamed")):
            reset()
            tmux("new-session", "-d", "-s", session, "-n", name, "-c", str(firstmate), agent_cmd)
            lock.write_text(f"{pane_pid(session)}\n")
            output, _ = run(expect_launch=False)
            assert "picker:" not in output and f"-t {session}" in output, output
            lock.unlink()
        # The lock owner may be a descendant of the pane process.
        reset()
        tmux("new-session", "-d", "-s", "firstmate", "-n", "firstmate", "-c", str(firstmate),
             f"sh -c '{lab}/claude 30 & wait'")
        time.sleep(.3)
        child = subprocess.run(["pgrep", "-P", str(pane_pid("firstmate"))], text=True,
                               capture_output=True).stdout.split()[0]
        lock.write_text(f"{child}\n")
        output, _ = run(expect_launch=False)
        assert "picker:" not in output and "focus:" in output, output
        lock.unlink()
        # A primary that has not taken the lock yet is recognised by its process.
        reset()
        tmux("new-session", "-d", "-s", "firstmate", "-n", "firstmate", "-c", str(firstmate), agent_cmd)
        output, _ = run(expect_launch=False)
        assert "picker:" not in output and "focus:" in output, output

        # Dead pane, stale lock pid, shell-only pane, an unrelated window with
        # the same name and another home's primary all lead to recovery.
        reset()
        tmux("new-session", "-d", "-s", "firstmate", "-n", "firstmate", "-c", str(firstmate), "true")
        wait_dead()
        lock.write_text("2147483647\n")
        output, _ = run()
        assert_recovered(output)
        assert window_names() == ["firstmate"], window_names()
        lock.unlink()
        reset()
        tmux("new-session", "-d", "-s", "firstmate", "-n", "firstmate", "-c", str(firstmate))
        output, _ = run()
        assert_recovered(output)
        reset()
        tmux("new-session", "-d", "-s", "unrelated", "-n", "firstmate", "-c", str(home), "sleep 30")
        output, _ = run()
        assert_recovered(output)
        assert "unrelated" in tmux("list-sessions", "-F", "#{session_name}").stdout.split()
        assert window_names("unrelated") == ["firstmate"]
        other_home = home / "other-home"
        other_home.mkdir()
        reset()
        tmux("new-session", "-d", "-s", "elsewhere", "-n", "firstmate", "-c", str(other_home), agent_cmd)
        output, _ = run()
        assert_recovered(output)

        # --- lock identity ---------------------------------------------------
        install = lab / "install/claude/versions"
        install.mkdir(parents=True)
        versioned = install / "2.1.220"
        versioned.symlink_to("/bin/sleep")
        real_bin = Path(os.environ["HOME"]) / ".local/share/firstmate/bin"
        lock_libs = {"fallback": None}
        if (real_bin / "fm-session-lock-lib.sh").exists():
            lock_libs["firstmate helper"] = real_bin
        for label, source in lock_libs.items():
            if source:
                (firstmate / "bin").mkdir(exist_ok=True)
                for lib in source.glob("fm-*lib.sh"):
                    shutil.copy(lib, firstmate / "bin" / lib.name)
            with subprocess.Popen([str(versioned), "30"]) as holder:
                reset()
                lock.write_text(f"{holder.pid}\nunchanged\n")
                output, _ = run()
                assert "message:" in output and "lock" in output.lower(), (label, output)
                assert "picker:" not in output, (label, output)
                assert lock.read_text() == f"{holder.pid}\nunchanged\n"
                holder.terminate()
            lock.unlink()
            shutil.rmtree(firstmate / "bin", ignore_errors=True)
        # The firstmate helper, when present, owns the verdict.
        (firstmate / "bin").mkdir()
        (firstmate / "bin/fm-session-lock-lib.sh").write_text('''
fm_harness_pid_alive() { return 0; }
fm_session_lock_inspect() {
  FM_LOCK_INSPECT_STATE=held
  FM_LOCK_INSPECT_PID=$(head -n 1 "$1/.lock")
}
''')
        with subprocess.Popen(["sleep", "30"]) as other:
            reset()
            lock.write_text(f"{other.pid}\n")
            output, _ = run()
            assert "message:" in output and "picker:" not in output, output
            other.terminate()
        lock.unlink()
        shutil.rmtree(firstmate / "bin")

        # --- explicit session id --------------------------------------------
        # The newest transcript for this home is resumed by id; a newer session
        # of another home, an older one of this home and a corrupt file are not.
        extra = []

        def add(path, text, age):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            os.utime(path, (time.time() - age, time.time() - age))
            extra.append(path)

        for agent in ("claude", "codex"):
            env["AI_FIRSTMATE_AGENT"] = agent
            reset()
            if agent == "claude":
                store = claude.parent
                add(store / "newest-other-home.jsonl", claude_line(other_home), 10)
                add(store / "newest-corrupt.jsonl", "not json\n", 20)
                add(store / "newer-home-session.jsonl", claude_line(firstmate), 30)
                os.utime(claude, (time.time() - 300, time.time() - 300))
                wanted = "--resume newer-home-session"
            else:
                store = home / ".codex/sessions/2026/10"
                add(store / "22/rollout-other.jsonl", codex_line(other_home, "other-home-id"), 10)
                add(store / "22/rollout-corrupt.jsonl", "not json\n", 20)
                add(store / "21/rollout-newer.jsonl", codex_line(firstmate, "newer-home-id"), 30)
                add(store / "20/rollout-no-id.jsonl", json.dumps({"type": "session_meta", "payload": {"cwd": str(firstmate)}}) + "\n", 5)
                os.utime(codex, (time.time() - 300, time.time() - 300))
                wanted = f"resume -C {firstmate} newer-home-id"
            output, _ = run()
            assert f"{agent}:{firstmate}:{wanted}\n" in output, output
            assert "--continue" not in output and "--last" not in output, output
            for path in extra:
                path.unlink()
            extra.clear()
            os.utime(claude, None)
            os.utime(codex, None)

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
