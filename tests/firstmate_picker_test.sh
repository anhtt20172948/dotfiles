#!/usr/bin/env bash
# Launch the real workflow entry point with no live tmux, quota or home access.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap '/bin/rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" FIRSTMATE_DIR="$TMP/firstmate" TMUX=mock
export LOG="$TMP/tmux.log" PICKER="$TMP/picker" QUOTA_LOG="$TMP/quota.log"
mkdir -p "$TMP/bin" "$HOME" "$FIRSTMATE_DIR/.git"
for tool in bash dirname readlink realpath awk jq timeout cat sleep; do
  ln -s "$(command -v "$tool")" "$TMP/bin/$tool"
done
cat > "$TMP/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s|' "$@" >> "$LOG"
printf '\n' >> "$LOG"
case "$1" in
  list-windows) [[ ${EXISTING:-0} != 1 ]] || printf 'firstmate:1\tfirstmate\n' ;;
  has-session) exit 1 ;;
  new-session|switch-client) ;;
  *) exit 90 ;;
esac
MOCK
cat > "$TMP/bin/fzf" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PICKER.args"
cat > "$PICKER"
[[ ${CANCEL:-0} != 1 ]] || exit 130
if [[ -n ${CHOICE:-} ]]; then printf '%s\n' "$CHOICE"; else
  IFS=$'\t' read -r agent rest < "$PICKER"
  printf '%s\n' "$agent"
fi
MOCK
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QUOTA_LOG"
case "${QUOTA_MODE:-ok}" in
  fail) exit 1 ;;
  slow) sleep 15; exit 1 ;;
  invalid) printf 'not json'; exit 0 ;;
  empty) exit 0 ;;
esac
printf '%s\n' "$QUOTA_JSON"
MOCK
chmod +x "$TMP/bin/"{tmux,fzf,quota-axi}
export PATH="$TMP/bin"
unset AI_FIRSTMATE_AGENT
agent() { printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/$1"; /bin/chmod +x "$TMP/bin/$1"; }
agent claude
agent codex
quota() {
  export QUOTA_JSON="{\"providers\":[{\"provider\":\"claude\",\"quotaSemantics\":{\"effectiveAvailability\":[{\"scope\":\"all_models\",\"effectivePercentRemaining\":$1},{\"scope\":\"sonnet\",\"effectivePercentRemaining\":0}]}},{\"provider\":\"codex\",\"quotaSemantics\":{\"effectiveAvailability\":[{\"scope\":\"all_models\",\"effectivePercentRemaining\":$2}]}}]}"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; /bin/cat "$LOG" "$PICKER" >&2; exit 1; }
run() {
  : > "$LOG"; : > "$QUOTA_LOG"; : > "$PICKER"; : > "$PICKER.args"
  bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" firstmate </dev/null
}
started() { /bin/grep -Fq "|exec $1|" "$LOG" || fail "did not start $1"; }
first() { local line; IFS= read -r line < "$PICKER" || line=; [[ $line == "$1"* ]] || fail "default is not $1"; }
no_start() { if /bin/grep -Fq 'new-session|' "$LOG"; then fail 'unexpected launch'; fi; }
quota 20 80
run; first codex; started codex
/bin/grep -Fxq $'codex\tcodex  80% remaining' "$PICKER" || fail 'missing codex quota'
/bin/grep -Fxq $'claude\tclaude  20% remaining' "$PICKER" || fail 'missing claude quota'
/bin/grep -Fxq -- '--no-sort' "$PICKER.args" || fail 'picker would reorder default'
export CHOICE=claude
run; started claude
unset CHOICE
quota 80 20
run; first claude; started claude
quota 50 50
run; first claude
quota 0 0
run; first claude
quota 12.5 60.25
run; first codex
export CANCEL=1
run; no_start
unset CANCEL
export AI_FIRSTMATE_AGENT=claude
run; started claude; [[ ! -s $PICKER && ! -s $QUOTA_LOG ]] || fail 'override prompted'
export AI_FIRSTMATE_AGENT=codex
run; started codex
unset AI_FIRSTMATE_AGENT
export EXISTING=1
/bin/rm "$TMP/bin/claude" "$TMP/bin/codex"
run; no_start; [[ ! -s $PICKER && ! -s $QUOTA_LOG ]] || fail 'existing window prompted'
unset EXISTING
agent codex
run; started codex; [[ ! -s $PICKER && ! -s $QUOTA_LOG ]] || fail 'single CLI prompted'
/bin/rm "$TMP/bin/codex"
agent claude
run; started claude
/bin/rm "$TMP/bin/claude"
if run; then fail 'no installed agents succeeded'; fi
no_start
agent claude; agent codex
for QUOTA_MODE in fail invalid empty slow; do
  export QUOTA_MODE
  SECONDS=0
  run; first claude; started claude
  [[ $SECONDS -lt 7 ]] || fail 'quota lookup was not bounded'
  /bin/grep -Fxq $'claude\tclaude' "$PICKER" || fail 'fallback shows a percentage'
done
unset QUOTA_MODE
/bin/mv "$TMP/bin/quota-axi" "$TMP/quota-axi"
run; first claude
/bin/mv "$TMP/quota-axi" "$TMP/bin/quota-axi"
quota null 90
run; first claude
quota 101 90
run; first claude
export QUOTA_JSON='{"providers":[{"provider":"claude","windows":[{"percentRemaining":90}],"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"unknown"}]}},{"provider":"codex","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":10}]}}]}'
run; first claude
/bin/grep -Fxq $'claude\tclaude' "$PICKER" || fail 'unknown headroom displayed as raw quota'
export QUOTA_JSON='{"providers":[]}'
run; first claude
/bin/rm "$TMP/bin/jq"
run; first claude; [[ ! -s $QUOTA_LOG ]] || fail 'quota fetched without parser'
printf 'firstmate picker: OK\n'
