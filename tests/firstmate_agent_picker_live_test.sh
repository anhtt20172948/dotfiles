#!/usr/bin/env bash
# Drive the real launcher with real fzf on a private tmux server: a slow quota
# lookup must leave the Agent rows usable, then default to the better headroom.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
for tool in tmux fzf jq; do
  command -v "$tool" >/dev/null || { printf 'SKIP firstmate agent picker live (needs %s)\n' "$tool"; exit 0; }
done
# Background header updates need fzf 0.63+ (bg-transform).
status=0
fzf --filter x --bind 'start:bg-transform:true' </dev/null >/dev/null 2>&1 || status=$?
if [[ $status == 2 ]]; then
  printf 'SKIP firstmate agent picker live (fzf without bg-transform)\n'
  exit 0
fi
TMP=$(mktemp -d)
SOCKET="$TMP/tmux.sock"
trap 'tmux -S "$SOCKET" kill-server 2>/dev/null || true; rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" FIRSTMATE_DIR="$TMP/firstmate" AGENT_LOG="$TMP/agent.log"
mkdir -p "$TMP/bin" "$HOME" "$FIRSTMATE_DIR/.git"
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/usr/bin/env bash
sleep 3
printf '%s\n' '{"providers":[{"provider":"claude","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":20}]}},{"provider":"codex","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":80}]}}]}'
MOCK
cat > "$TMP/bin/codex" <<'MOCK'
#!/usr/bin/env bash
[[ $1 != debug ]] || exit 1
printf 'codex %s\n' "$*" >> "$AGENT_LOG"
sleep 60
MOCK
printf '#!/usr/bin/env bash\nsleep 60\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; tmux -S "$SOCKET" capture-pane -p -t picker >&2 || true; exit 1; }
screen() { tmux -S "$SOCKET" capture-pane -p -t picker; }
# Poll the pane: the launcher and fzf start asynchronously.
wait_for() {
  local pattern=$1 limit=$2 waited=0
  until screen | grep -Fq -- "$pattern"; do
    ((waited < limit * 10)) || fail "timed out waiting for '$pattern'"
    sleep 0.1; waited=$((waited + 1))
  done
}
launch() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$AGENT_LOG" "$TMP/exit"
  tmux -S "$SOCKET" -f /dev/null new-session -d -s picker -x 120 -y 30 \
    "bash '$ROOT/.config/tmux/scripts/ai-workflow.sh' firstmate; echo \$? > '$TMP/exit'; sleep 60"
}

# Enter while quota is still loading picks the highlighted row, not a cancel.
launch
wait_for 'Agent ›' 5
SECONDS=0
screen | grep -Fq 'Quota …' || fail 'quota placeholder missing'
screen | grep -Eq ' claude +│' || fail 'claude row missing while quota loads'
screen | grep -Eq ' codex +│' || fail 'codex row missing while quota loads'
tmux -S "$SOCKET" send-keys -t picker Enter
wait_for 'Session ›' 2
[[ $SECONDS -lt 3 ]] || fail 'Agent picker waited for quota'
tmux -S "$SOCKET" send-keys -t picker Escape
for _ in $(seq 50); do [[ -s $TMP/exit ]] && break; sleep 0.1; done
[[ $(cat "$TMP/exit" 2>/dev/null) == 0 ]] || fail 'cancelled launch did not exit cleanly'

# Once quota lands, the header shows it and an untouched cursor moves to the
# agent with more headroom, which Enter then launches.
launch
wait_for 'codex 80% left' 8
screen | grep -Fq 'claude 20% left' || fail 'claude quota missing'
tmux -S "$SOCKET" send-keys -t picker Enter
wait_for 'Session ›' 3
tmux -S "$SOCKET" send-keys -t picker Enter   # New session
wait_for 'Model ›' 3
tmux -S "$SOCKET" send-keys -t picker Enter   # default model
wait_for 'Effort ›' 3
tmux -S "$SOCKET" send-keys -t picker Enter   # default effort
for _ in $(seq 50); do [[ -s $AGENT_LOG ]] && break; sleep 0.1; done
grep -q '^codex' "$AGENT_LOG" 2>/dev/null || fail 'better-headroom default did not launch codex'
printf 'firstmate agent picker live: OK\n'
