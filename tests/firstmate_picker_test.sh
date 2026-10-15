#!/usr/bin/env bash
# Launch the real workflow entry point with no live tmux, quota or home access.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
JQ_BIN=$(command -v jq)
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
stage=Agent
for arg in "$@"; do
  case "$arg" in '--prompt=Model › ') stage=Model ;; '--prompt=Effort › ') stage=Effort ;; esac
done
file=$PICKER
[[ $stage == Agent ]] || file="$PICKER.$stage"
printf '%s\n' "$@" > "$file.args"
cat > "$file"
[[ ${CANCEL_STAGE:-} != "$stage" && ${CANCEL:-0} != 1 ]] || exit 130
case "$stage" in
  Agent) choice=${CHOICE:-} ;;
  Model) choice=${MODEL_CHOICE:-} ;;
  Effort) choice=${EFFORT_CHOICE:-} ;;
esac
if [[ -n $choice ]]; then printf '%s\n' "$choice"; else
  IFS=$'\t' read -r value rest < "$file"
  printf '%s\n' "$value"
fi
MOCK
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QUOTA_LOG"
case "${QUOTA_MODE:-ok}" in
  fail) exit 1 ;;
  slow) sleep 15; exit 1 ;;
  cold) sleep 3 ;;
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
cat > "$TMP/bin/codex" <<'MOCK'
#!/usr/bin/env bash
[[ $* == 'debug models' ]] || exit 99
case ${MODELS_MODE:-ok} in
  fail) exit 1 ;;
  invalid) printf 'invalid'; exit 0 ;;
  slow) sleep 15; exit 1 ;;
esac
printf '%s\n' "$MODELS_JSON"
MOCK
/bin/chmod +x "$TMP/bin/codex"
/bin/cp "$TMP/bin/codex" "$TMP/codex-mock"
export MODELS_JSON='{"models":[{"slug":"gpt-test","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},{"slug":"gpt-other","supported_reasoning_levels":[{"effort":"medium"},{"effort":"xhigh"}]},{"slug":"gpt-hidden","visibility":"hide","supported_reasoning_levels":[{"effort":"low"}]}]}'
quota() {
  export QUOTA_JSON="{\"providers\":[{\"provider\":\"claude\",\"quotaSemantics\":{\"effectiveAvailability\":[{\"scope\":\"all_models\",\"effectivePercentRemaining\":$1},{\"scope\":\"sonnet\",\"effectivePercentRemaining\":0}]}},{\"provider\":\"codex\",\"quotaSemantics\":{\"effectiveAvailability\":[{\"scope\":\"all_models\",\"effectivePercentRemaining\":$2}]}}]}"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; /bin/cat "$LOG" "$PICKER" >&2; exit 1; }
run() {
  : > "$LOG"; : > "$QUOTA_LOG"; : > "$PICKER"; : > "$PICKER.args"; : > "$PICKER.Model"; : > "$PICKER.Effort"
  bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" firstmate </dev/null
}
started() { /bin/grep -Fq "|exec $1|" "$LOG" || fail "did not start $1"; }
first() { local line; IFS= read -r line < "$PICKER" || line=; [[ $line == "$1"* ]] || fail "default is not $1"; }
no_start() { if /bin/grep -Fq 'new-session|' "$LOG"; then fail 'unexpected launch'; fi; }
quota 20 80
run; first codex; started codex
/bin/grep -Fxq $'codex\tcodex  80% left' "$PICKER" || fail 'missing codex quota'
/bin/grep -Fxq $'claude\tclaude  20% left' "$PICKER" || fail 'missing claude quota'
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
run; started claude; [[ ! -s $PICKER && ! -s $QUOTA_LOG && -s $PICKER.Model && -s $PICKER.Effort ]] || fail 'agent override skipped wrong steps'
export AI_FIRSTMATE_AGENT=codex
run; started codex
unset AI_FIRSTMATE_AGENT
export EXISTING=1
/bin/rm "$TMP/bin/claude" "$TMP/bin/codex"
run; no_start; [[ ! -s $PICKER && ! -s $QUOTA_LOG && ! -s $PICKER.Model && ! -s $PICKER.Effort ]] || fail 'existing window prompted'
unset EXISTING
agent codex
run; started codex; [[ ! -s $PICKER && ! -s $QUOTA_LOG && -s $PICKER.Model && -s $PICKER.Effort ]] || fail 'single CLI skipped wrong steps'
/bin/rm "$TMP/bin/codex"
agent claude
run; started claude
/bin/rm "$TMP/bin/claude"
if run; then fail 'no installed agents succeeded'; fi
no_start
agent claude; /bin/cp "$TMP/codex-mock" "$TMP/bin/codex"
for QUOTA_MODE in fail invalid empty slow; do
  export QUOTA_MODE
  SECONDS=0
  run; first claude; started claude
  [[ $SECONDS -lt 7 ]] || fail 'quota lookup was not bounded'
  /bin/grep -Fxq $'claude\tclaude  quota ?' "$PICKER" || fail 'fallback shows a percentage'
done
export QUOTA_MODE=cold
quota 10 90
run; first codex; started codex
/bin/grep -Fxq $'codex\tcodex  90% left' "$PICKER" || fail 'cold quota lost'
unset QUOTA_MODE
/bin/mv "$TMP/bin/quota-axi" "$TMP/quota-axi"
run; first claude
/bin/grep -Fxq $'codex\tcodex  quota ?' "$PICKER" || fail 'missing tooling hid quota cell'
/bin/mv "$TMP/quota-axi" "$TMP/bin/quota-axi"
quota null 90
run; first claude
quota 101 90
run; first claude
export QUOTA_JSON='{"providers":[{"provider":"claude","windows":[{"percentRemaining":90}],"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"unknown"}]}},{"provider":"codex","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":10}]}}]}'
run; first claude
/bin/grep -Fxq $'claude\tclaude  quota ?' "$PICKER" || fail 'unknown headroom displayed as raw quota'
export QUOTA_JSON='{"providers":[]}'
run; first claude
/bin/rm "$TMP/bin/jq"
run; first claude; [[ ! -s $QUOTA_LOG ]] || fail 'quota fetched without parser'
/bin/ln -s "$JQ_BIN" "$TMP/bin/jq"
export AI_FIRSTMATE_AGENT=claude MODEL_CHOICE=opus EFFORT_CHOICE=max
run; started 'claude --model opus --effort max'
/bin/grep -Fxq $'default\tdefault (CLI config)' "$PICKER.Model" || fail 'missing model default'
for model in opus sonnet haiku; do
  export MODEL_CHOICE=$model
  for effort in low medium high xhigh max default; do
    export EFFORT_CHOICE=$effort
    run
    if [[ $effort == default ]]; then started "claude --model $model"; else
      started "claude --model $model --effort $effort"
    fi
  done
done
for CANCEL_STAGE in Model Effort; do
  export CANCEL_STAGE
  run; no_start
done
unset CANCEL_STAGE MODEL_CHOICE EFFORT_CHOICE
export AI_FIRSTMATE_AGENT=codex MODEL_CHOICE=gpt-test EFFORT_CHOICE=high
run; started 'codex -m gpt-test -c model_reasoning_effort=high'
/bin/grep -Fxq $'gpt-other\tgpt-other' "$PICKER.Model" || fail 'missing listed codex model'
if /bin/grep -Fq gpt-hidden "$PICKER.Model"; then fail 'hidden codex model offered'; fi
if /bin/grep -Fq xhigh "$PICKER.Effort"; then fail 'unsupported catalog effort'; fi
export MODEL_CHOICE=gpt-other EFFORT_CHOICE=xhigh
run; started 'codex -m gpt-other -c model_reasoning_effort=xhigh'
/bin/mkdir -p "$HOME/.codex"
printf 'model = "gpt-config"\n[profile]\nmodel = "wrong"\n' > "$HOME/.codex/config.toml"
export MODEL_CHOICE=gpt-config EFFORT_CHOICE=medium
for MODELS_MODE in fail invalid slow; do
  export MODELS_MODE
  SECONDS=0
  run; started 'codex -m gpt-config -c model_reasoning_effort=medium'
  [[ $SECONDS -lt 8 ]] || fail 'model discovery unbounded'
done
unset MODELS_MODE
printf 'model = "gpt-test"\n' > "$HOME/.codex/config.toml"
export MODEL_CHOICE=default EFFORT_CHOICE=high
run; started 'codex -c model_reasoning_effort=high'
export MODEL_CHOICE=gpt-test EFFORT_CHOICE=xhigh
if run 2>"$TMP/err"; then fail 'unsupported picker effort accepted'; fi
no_start
/bin/grep -Fq "invalid firstmate Effort selection 'xhigh' (offered: default, low, high)" "$TMP/err" \
  || fail 'invalid selection not explained'
/bin/grep -Fq 'Press any key' "$TMP/err" || fail 'invalid selection did not pause popup'
unset EFFORT_CHOICE
# shellcheck disable=SC2016
export MODEL_CHOICE='$(touch /tmp/unsafe)'
if run 2>/dev/null; then fail 'unoffered picker model accepted'; fi
no_start
unset MODEL_CHOICE AI_FIRSTMATE_AGENT
export CHOICE='bash'
if run; then fail 'unoffered agent accepted'; fi
no_start
unset CHOICE
for AI_FIRSTMATE_AGENT in '' codex; do
  export AI_FIRSTMATE_AGENT CANCEL=1
  : > "$PICKER"
  bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" </dev/null 2>"$TMP/err" || fail 'menu failed'
  /bin/grep '^firstmate' "$PICKER" | /bin/grep -Fq '●' || fail 'menu marked installed firstmate missing'
  if [[ -s $TMP/err ]]; then fail "menu errored: $(/bin/cat "$TMP/err")"; fi
done
unset AI_FIRSTMATE_AGENT CANCEL
printf 'firstmate picker: OK\n'
