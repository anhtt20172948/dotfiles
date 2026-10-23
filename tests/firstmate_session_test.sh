#!/usr/bin/env bash
# Exercise the public launcher with tmux and process inspection isolated.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
export PATH="$TMP/bin:$PATH"
export AI_FIRSTMATE_AGENT=claude
export TMUX=mock
export FIRSTMATE_DIR="$TMP/first mate"
export LOG="$TMP/tmux.log"
mkdir -p "$TMP/bin" "$HOME" "$FIRSTMATE_DIR/.git" "$TMP/live"
PHYSICAL_DIR=$(cd "$FIRSTMATE_DIR" && pwd -P)
REAL_PS=$(command -v ps)
# A live harness-shaped process stands in for the primary in the existing window.
ln -s "$(command -v sleep)" "$TMP/live/claude"
"$TMP/live/claude" 60 & LIVE_PID=$!
trap 'kill "$LIVE_PID" 2>/dev/null || :; rm -rf -- "$TMP"' EXIT
export PHYSICAL_DIR REAL_PS LIVE_PID
cat >"$TMP/bin/claude" <<'MOCK'
#!/usr/bin/env bash
if [[ ${VERIFY_TOKEN:-0} == 1 ]]; then
  [[ $CLAUDE_CODE_OAUTH_TOKEN == synthetic-b && -z ${CLAUDE_CONFIG_DIR+x} && -z ${ANTHROPIC_API_KEY+x} ]] || exit 91
  [[ $PWD == "$FIRSTMATE_DIR" ]] || exit 92
  printf 'claude token verified\n' >> "$LOG"
fi
exit 0
MOCK
cat >"$TMP/bin/fzf" <<'MOCK'
#!/usr/bin/env bash
IFS=$'\t' read -r value _
printf '%s\n' "$value"
MOCK
cat >"$TMP/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
# Real tmux reads commands from stdin only via `source-file -`.
[[ $# -ne 0 ]] || exit 97
if [[ $* == 'source-file -' ]]; then
  command=$(cat)
  printf 'tmux|stdin\n' >>"$LOG"
  case "$command" in
    *"set-environment -g CLAUDE_CODE_OAUTH_TOKEN '"*"'"*)
      token=$(printf '%s\n' "$command" | sed -n "s/.*CLAUDE_CODE_OAUTH_TOKEN '\([^']*\)'.*/\1/p")
      [[ $token == synthetic-b ]] || exit 93 ;;
  esac
  exit 0
fi
printf '%s|' "$@" >>"$LOG"
printf '\n' >>"$LOG"
case "$1" in
list-windows)
  case "$SCENARIO" in
    idle|busy|worker|multi|unknown|command|inspection) printf '1\t@7\t%s\t%s\n' "${WINDOW_NAME:-zsh}" "${PANES:-1}" ;;
  esac ;;
has-session) [[ $SCENARIO != new ]] ;;
list-panes)
  if [[ $2 == -a ]]; then
    [[ $SCENARIO != existing ]] || printf 'dotfiles:4\t%s\t0\t%s\tfirstmate\n' "$LIVE_PID" "$PHYSICAL_DIR"
  else
    printf '123\t%s\t/dev/pts/9\n' "${PANE_COMMAND:-zsh}"
  fi ;;
new-session|new-window|respawn-window)
  [[ $SCENARIO != failure ]] || exit 1
  [[ ${VERIFY_TOKEN:-0} != 1 ]] || (cd "$FIRSTMATE_DIR" && bash -c "${!#}") ;;
set-environment)
  [[ $4 == synthetic-b ]] || exit 93 ;;
rename-window|switch-client) ;;
*) echo "unexpected tmux command: $*" >&2; exit 90 ;;
esac
MOCK
cat >"$TMP/bin/ps" <<'MOCK'
#!/usr/bin/env bash
# The existing-window scenario inspects a real process.
[[ $SCENARIO != existing ]] || exec "$REAL_PS" "$@"
if [[ $1 == -p ]]; then
  [[ $SCENARIO != unknown ]] || exit 1
  printf '%s\n' "${PROCESS_NAME:-zsh}"
else
  [[ $SCENARIO != inspection ]] || exit 1
  [[ $SCENARIO != busy ]] || printf '124\n'
  printf '123\n'
fi
MOCK
chmod +x "$TMP/bin/"*
fail() { echo "FAIL: $*" >&2; cat "$LOG" >&2; exit 1; }
has() { grep -Fqx -- "$1" "$LOG" || fail "missing: $1"; }
lacks() { if grep -Fq -- "$1" "$LOG"; then fail "unexpected: $1"; fi; }
run() {
  export SCENARIO=$1
  : >"$LOG"
  bash "$ROOT/.config/tmux/scripts/ai-workflow.sh" firstmate </dev/null
}
# Claude launches require a local token; every scenario binds account B to the pane.
ln -s "$ROOT/.local/bin/ai-acct" "$TMP/bin/ai-acct"
mkdir -p "$HOME/.config/claude-accounts"
printf 'synthetic-b\n' > "$HOME/.config/claude-accounts/b.token"
chmod 600 "$HOME/.config/claude-accounts/b.token"
run new
has "new-session|-d|-s|firstmate|-n|firstmate|-c|$FIRSTMATE_DIR|exec ai-acct exec --account b claude|"
has 'switch-client|-t|=firstmate:1|'
lacks 'new-window|'
run existing
has 'switch-client|-t|dotfiles|;|select-window|-t|dotfiles:4|'
lacks 'has-session|'
run empty
has "new-window|-d|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec ai-acct exec --account b claude|"
run idle
has "respawn-window|-k|-t|@7|-c|$FIRSTMATE_DIR|exec ai-acct exec --account b claude|"
has 'rename-window|-t|@7|firstmate|'
lacks 'new-window|'
run busy
has "new-window|-d|-b|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec ai-acct exec --account b claude|"
lacks 'respawn-window|'
export WINDOW_NAME=fm-task
run worker
lacks 'respawn-window|'
has "new-window|-d|-b|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec ai-acct exec --account b claude|"
unset WINDOW_NAME
export PANES=2
run multi
lacks 'respawn-window|'
unset PANES
run unknown
lacks 'respawn-window|'
run inspection
lacks 'respawn-window|'
export PANE_COMMAND=vim
run command
lacks 'respawn-window|'
unset PANE_COMMAND
export PROCESS_NAME=vim
run command
lacks 'respawn-window|'
unset PROCESS_NAME
if run failure; then fail 'creation failure succeeded'; fi
lacks 'switch-client|'
# Execute the emitted launch command through bash, without zsh startup.
export VERIFY_TOKEN=1
export CLAUDE_CODE_OAUTH_TOKEN=stale CLAUDE_CONFIG_DIR=/stale ANTHROPIC_API_KEY=stale
for scenario in new empty idle; do
  run "$scenario"
  has 'claude token verified'
  [[ $(cat "$HOME/.config/claude-accounts/active") == b ]] || fail 'selector not saved'
  has 'tmux|stdin'
  jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null
  lacks synthetic-b
done
echo 'firstmate session: OK'
