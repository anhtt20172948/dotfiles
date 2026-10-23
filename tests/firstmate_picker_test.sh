#!/usr/bin/env bash
# Launch the real workflow entry point with no live tmux, quota or home access.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
JQ_BIN=$(command -v jq)
# Not /bin/grep: macOS only has /usr/bin/grep.
GREP_BIN=$(command -v grep)
trap '/bin/rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" FIRSTMATE_DIR="$TMP/firstmate" TMUX=mock
export FIRSTMATE_PHYS; FIRSTMATE_PHYS=$(cd "$TMP" && pwd -P)/firstmate
export LOG="$TMP/tmux.log" PICKER="$TMP/picker" QUOTA_LOG="$TMP/quota.log"
mkdir -p "$TMP/bin" "$HOME" "$FIRSTMATE_DIR/.git"
for tool in bash dirname readlink realpath awk jq cat sleep mktemp stat mv rm sed perl ps; do
  path=$(command -v "$tool") || { echo "missing required tool: $tool" >&2; exit 1; }
  ln -s "$path" "$TMP/bin/$tool"
done
# Optional: stock macOS lacks timeout (perl fallback) and, before 15, sha256sum (shasum fallback).
for tool in timeout sha256sum shasum; do
  if path=$(command -v "$tool"); then ln -s "$path" "$TMP/bin/$tool"; fi
done
cat > "$TMP/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
# Real tmux reads commands from stdin only via `source-file -`.
[[ $# -ne 0 ]] || exit 97
if [[ $* == 'source-file -' ]]; then
  command=$(cat)
  printf 'tmux|stdin\n' >> "$LOG"
  case "$command" in
    *"set-environment -g CLAUDE_CODE_OAUTH_TOKEN '"*"'"*)
      token=$(printf '%s\n' "$command" | sed -n "s/.*CLAUDE_CODE_OAUTH_TOKEN '\([^']*\)'.*/\1/p")
      [[ $token == synthetic-b || $token == synthetic-a || $token == synthetic-work ]] || exit 89 ;;
  esac
  exit 0
fi
[[ $1 != set-environment ]] || exit 96
printf '%s|' "$@" >> "$LOG"
printf '\n' >> "$LOG"
case "$1" in
  list-panes) [[ ${EXISTING:-0} != 1 ]] || printf 'firstmate:1\t%s\t0\t%s\tfirstmate\n' "$PANE_PID" "$FIRSTMATE_PHYS" ;;
  has-session) exit 1 ;;
  new-session|switch-client) ;;
  *) exit 90 ;;
esac
MOCK
cat > "$TMP/bin/fzf" <<'MOCK'
#!/usr/bin/env bash
stage=Agent
for arg in "$@"; do
  case "$arg" in '--prompt=Session › ') stage=Session ;; '--prompt=Account › ') stage=Account ;; '--prompt=Model › ') stage=Model ;; '--prompt=Effort › ') stage=Effort ;; esac
done
file=$PICKER
[[ $stage == Agent ]] || file="$PICKER.$stage"
printf '%s\n' "$@" > "$file.args"
cat > "$file"
# fzf runs the start:bg-transform command once the picker is open; wait for it
# here and apply its actions: an optional move to row 2, then a new header.
row=1
for arg in "$@"; do
  case "$arg" in start:bg-transform:*)
    [[ ${NO_QUOTA_ACTION:-0} != 1 ]] || continue
    action=$(bash -c "${arg#start:bg-transform:}")
    [[ $action != "transform~[ {n} = 0 ] && echo 'pos(2)'~+"* ]] || row=2
    printf '%s\n' "${action#*change-header:}" > "$file.header" ;;
  esac
done
[[ ${CANCEL_STAGE:-} != "$stage" && ${CANCEL:-0} != 1 ]] || exit 130
case "$stage" in
  Session) choice=new ;;
  Account) choice=${ACCOUNT_CHOICE:-} ;;
  Agent) choice=${CHOICE:-} ;;
  Model) choice=${MODEL_CHOICE:-} ;;
  Effort) choice=${EFFORT_CHOICE:-} ;;
esac
if [[ -z $choice ]]; then
  choice=$(awk -F '\t' -v row="$row" 'NR == row { print $1 }' "$file")
  printf '%s\n' "$choice" > "$file.default"
fi
printf '%s\n' "$choice"
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
/bin/ln -s "$ROOT/.local/bin/ai-acct" "$TMP/bin/ai-acct"
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
  : > "$LOG"; : > "$QUOTA_LOG"; : > "$PICKER"; /bin/rm -f "$PICKER.default" "$PICKER.header"; : > "$PICKER.args"; : > "$PICKER.Model"; : > "$PICKER.Effort"; : > "$PICKER.Account"
  bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" firstmate </dev/null
}
started() { "$GREP_BIN" -Fq "|exec $1|" "$LOG" || fail "did not start $1"; }
first() { [[ $(/bin/cat "$PICKER.default" 2>/dev/null) == "$1" ]] || fail "default is not $1"; }
header() { "$GREP_BIN" -Fxq "$1" "$PICKER.header" || fail "quota header is not '$1'"; }
no_start() { if "$GREP_BIN" -Fq 'new-session|' "$LOG"; then fail 'unexpected launch'; fi; }
# Claude launches require a local token; several named accounts exist for the picker.
/bin/mkdir -p "$HOME/.config/claude-accounts"
printf 'synthetic-a\n' > "$HOME/.config/claude-accounts/a.token"
printf 'synthetic-b\n' > "$HOME/.config/claude-accounts/b.token"
printf 'synthetic-work\n' > "$HOME/.config/claude-accounts/work.token"
/bin/chmod 600 "$HOME/.config/claude-accounts/"*.token
printf 'a\n' > "$HOME/.config/claude-accounts/active"
quota 20 80
run; first codex; started codex
header 'Quota  claude 20% left  codex 80% left'
"$GREP_BIN" -Fxq -- '--no-sort' "$PICKER.args" || fail 'picker would reorder default'
export CHOICE=claude
run; started 'ai-acct exec --account a claude'
unset CHOICE
quota 80 20
run; first claude; started 'ai-acct exec --account a claude'
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
run; started 'ai-acct exec --account a claude'; [[ ! -s $PICKER && ! -s $QUOTA_LOG && -s $PICKER.Model && -s $PICKER.Effort ]] || fail 'agent override skipped wrong steps'
export AI_FIRSTMATE_AGENT=codex
run; started codex
unset AI_FIRSTMATE_AGENT
# A window only counts when a live harness runs in it, in the firstmate home.
/bin/mkdir -p "$TMP/live" && /bin/ln -s "$TMP/bin/sleep" "$TMP/live/claude"
"$TMP/live/claude" 60 & PANE_PID=$!
trap 'kill "$PANE_PID" 2>/dev/null; /bin/rm -rf -- "$TMP"' EXIT
export EXISTING=1 PANE_PID
/bin/rm "$TMP/bin/claude" "$TMP/bin/codex"
run; no_start; [[ ! -s $PICKER && ! -s $QUOTA_LOG && ! -s $PICKER.Model && ! -s $PICKER.Effort ]] || fail 'existing window prompted'
unset EXISTING
agent codex
run; started codex; [[ ! -s $PICKER && ! -s $QUOTA_LOG && -s $PICKER.Model && -s $PICKER.Effort ]] || fail 'single CLI skipped wrong steps'
/bin/rm "$TMP/bin/codex"
agent claude
run; started 'ai-acct exec --account a claude'
/bin/rm "$TMP/bin/claude"
if run; then fail 'no installed agents succeeded'; fi
no_start
agent claude; /bin/cp "$TMP/codex-mock" "$TMP/bin/codex"
for QUOTA_MODE in fail invalid empty slow; do
  export QUOTA_MODE
  SECONDS=0
  run; first claude; started 'ai-acct exec --account a claude'
  [[ $SECONDS -lt 7 ]] || fail 'quota lookup was not bounded'
  header 'Quota  claude quota ?  codex quota ?'
done
export QUOTA_MODE=cold
quota 10 90
run; first codex; started codex
header 'Quota  claude 10% left  codex 90% left'
unset QUOTA_MODE
# Quota stays off the critical path: the first picker opens at once with fixed
# rows and fzf fills in the quota header afterwards in the background.
export QUOTA_MODE=slow NO_QUOTA_ACTION=1
quota 20 80
SECONDS=0
run; started 'ai-acct exec --account a claude'
[[ $SECONDS -lt 3 && ! -s $QUOTA_LOG ]] || fail 'first picker waited for quota'
[[ $(/bin/cat "$PICKER") == $'claude\tclaude\ncodex\tcodex' ]] \
  || fail "initial rows: $(/bin/cat "$PICKER")"
"$GREP_BIN" -Fxq -- $'--header=Quota …\nCtrl-j/k move  •  Enter select  •  Esc cancel' "$PICKER.args" \
  || fail 'quota placeholder missing'
unset QUOTA_MODE NO_QUOTA_ACTION
/bin/mv "$TMP/bin/quota-axi" "$TMP/quota-axi"
run; first claude
header 'Quota  claude quota ?  codex quota ?'
/bin/mv "$TMP/quota-axi" "$TMP/bin/quota-axi"
quota null 90
run; first claude
quota 101 90
run; first claude
export QUOTA_JSON='{"providers":[{"provider":"claude","windows":[{"percentRemaining":90}],"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"unknown"}]}},{"provider":"codex","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":10}]}}]}'
run; first claude
header 'Quota  claude quota ?  codex 10% left'
export QUOTA_JSON='{"providers":[]}'
run; first claude
/bin/rm "$TMP/bin/jq"
if run 2>/dev/null; then fail 'claude launch without jq succeeded'; fi
no_start
first claude
[[ ! -s $QUOTA_LOG ]] || fail 'quota fetched without parser'
export AI_FIRSTMATE_AGENT=codex
run; started codex
unset AI_FIRSTMATE_AGENT
/bin/ln -s "$JQ_BIN" "$TMP/bin/jq"
export AI_FIRSTMATE_AGENT=claude MODEL_CHOICE=opus EFFORT_CHOICE=max
run; started 'ai-acct exec --account a claude --model opus --effort max'
"$GREP_BIN" -Fxq $'default\tdefault (CLI config)' "$PICKER.Model" || fail 'missing model default'
for model in opus sonnet haiku; do
  export MODEL_CHOICE=$model
  for effort in low medium high xhigh max default; do
    export EFFORT_CHOICE=$effort
    run
    if [[ $effort == default ]]; then started "ai-acct exec --account a claude --model $model"; else
      started "ai-acct exec --account a claude --model $model --effort $effort"
    fi
  done
done
for CANCEL_STAGE in Session Model Effort; do
  export CANCEL_STAGE
  run; no_start
done
unset CANCEL_STAGE MODEL_CHOICE EFFORT_CHOICE
export AI_FIRSTMATE_AGENT=codex MODEL_CHOICE=gpt-test EFFORT_CHOICE=high
run; started 'codex -m gpt-test -c model_reasoning_effort=high'
"$GREP_BIN" -Fxq $'gpt-other\tgpt-other' "$PICKER.Model" || fail 'missing listed codex model'
if "$GREP_BIN" -Fq gpt-hidden "$PICKER.Model"; then fail 'hidden codex model offered'; fi
if "$GREP_BIN" -Fq xhigh "$PICKER.Effort"; then fail 'unsupported catalog effort'; fi
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
"$GREP_BIN" -Fq "invalid firstmate Effort selection 'xhigh' (offered: default, low, high)" "$TMP/err" \
  || fail 'invalid selection not explained'
"$GREP_BIN" -Fq 'Press any key' "$TMP/err" || fail 'invalid selection did not pause popup'
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
  "$GREP_BIN" '^firstmate' "$PICKER" | "$GREP_BIN" -Fq '●' || fail 'menu marked installed firstmate missing'
  if [[ -s $TMP/err ]]; then fail "menu errored: $(/bin/cat "$TMP/err")"; fi
done
unset AI_FIRSTMATE_AGENT CANCEL
# The picked account is bound to the pane, then becomes the shared selector.
printf 'a\n' > "$HOME/.config/claude-accounts/active"
export AI_FIRSTMATE_AGENT=claude ACCOUNT_CHOICE=b
run; started 'ai-acct exec --account b claude'
[[ $(/bin/cat "$HOME/.config/claude-accounts/active") == b ]] || fail 'launch did not select the picked account'
[[ $(/bin/cat "$PICKER.Account") == $'a\tClaude account a (active)\nb\tClaude account b\nwork\tClaude account work' ]] \
  || fail "account entries: $(/bin/cat "$PICKER.Account")"
# Any named account can be launched; the active one is offered first.
export ACCOUNT_CHOICE=work
run; started 'ai-acct exec --account work claude'
[[ $(/bin/cat "$HOME/.config/claude-accounts/active") == work ]] || fail 'named launch did not select it'
printf 'work\n' > "$HOME/.config/claude-accounts/active"
export ACCOUNT_CHOICE=b
run
IFS= read -r line < "$PICKER.Account"
[[ $line == $'work\tClaude account work (active)' ]] || fail 'active account not first'
for CANCEL_STAGE in Session Account Model Effort; do
  printf 'a\n' > "$HOME/.config/claude-accounts/active"
  export CANCEL_STAGE
  run; no_start
  [[ $(/bin/cat "$HOME/.config/claude-accounts/active") == a ]] || fail 'cancel switched account'
done
unset CANCEL_STAGE ACCOUNT_CHOICE
export AI_FIRSTMATE_AGENT=codex
run; started codex
[[ ! -s $PICKER.Account ]] || fail 'codex prompted for Claude account'
export AI_FIRSTMATE_AGENT=claude
/bin/rm "$HOME/.config/claude-accounts/b.token"
export ACCOUNT_CHOICE=b
if run; then fail 'missing token selection accepted'; fi
no_start
unset ACCOUNT_CHOICE
run; started 'ai-acct exec --account a claude'
if "$GREP_BIN" -Fq 'Claude account b' "$PICKER.Account"; then fail 'offered missing token'; fi
/bin/rm "$HOME/.config/claude-accounts/a.token" "$HOME/.config/claude-accounts/work.token"
if run 2>"$TMP/err"; then fail 'no-token launch succeeded'; fi
no_start
"$GREP_BIN" -Fq 'no Claude accounts' "$TMP/err" || fail 'missing setup not reported'
printf 'firstmate picker: OK\n'
