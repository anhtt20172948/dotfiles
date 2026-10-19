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
mkdir -p "$TMP/bin" "$HOME" "$FIRSTMATE_DIR/.git"
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
if [[ $1 != set-environment ]]; then printf '%s|' "$@" >>"$LOG"; fi
printf '\n' >>"$LOG"
case "$1" in
list-windows)
  if [[ $2 == -a ]]; then
    [[ $SCENARIO != existing ]] || printf 'dotfiles:4\tfirstmate\n'
  else
    case "$SCENARIO" in
      idle|busy|worker|multi|unknown|command|inspection) printf '1\t@7\t%s\t%s\n' "${WINDOW_NAME:-zsh}" "${PANES:-1}" ;;
    esac
  fi ;;
has-session) [[ $SCENARIO != new ]] ;;
list-panes) printf '123\t%s\t/dev/pts/9\n' "${PANE_COMMAND:-zsh}" ;;
new-session|new-window|respawn-window)
  [[ $SCENARIO != failure ]] || exit 1
  [[ ${VERIFY_TOKEN:-0} != 1 ]] || (cd "$FIRSTMATE_DIR" && bash -c "${!#}") ;;
set-environment)
  if [[ $3 == CLAUDE_CODE_OAUTH_TOKEN ]]; then [[ $4 == synthetic-b ]] || exit 93; fi ;;
rename-window|switch-client) ;;
*) echo "unexpected tmux command: $*" >&2; exit 90 ;;
esac
MOCK
cat >"$TMP/bin/ps" <<'MOCK'
#!/usr/bin/env bash
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
run new
has "new-session|-d|-s|firstmate|-n|firstmate|-c|$FIRSTMATE_DIR|exec claude|"
has 'switch-client|-t|=firstmate:1|'
lacks 'new-window|'
run existing
has 'switch-client|-t|dotfiles|;|select-window|-t|dotfiles:4|'
lacks 'has-session|'
run empty
has "new-window|-d|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec claude|"
run idle
has "respawn-window|-k|-t|@7|-c|$FIRSTMATE_DIR|exec claude|"
has 'rename-window|-t|@7|firstmate|'
lacks 'new-window|'
run busy
has "new-window|-d|-b|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec claude|"
lacks 'respawn-window|'
export WINDOW_NAME=fm-task
run worker
lacks 'respawn-window|'
has "new-window|-d|-b|-t|=firstmate:1|-n|firstmate|-c|$FIRSTMATE_DIR|exec claude|"
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
ln -s "$ROOT/.local/bin/ai-acct" "$TMP/bin/ai-acct"
mkdir -p "$HOME/.config/claude-accounts"
printf 'synthetic-b\n' > "$HOME/.config/claude-accounts/b.token"
chmod 600 "$HOME/.config/claude-accounts/b.token"
export AI_FIRSTMATE_ACCOUNT=b VERIFY_TOKEN=1
export CLAUDE_CODE_OAUTH_TOKEN=stale CLAUDE_CONFIG_DIR=/stale ANTHROPIC_API_KEY=stale
for scenario in new empty idle; do
  run "$scenario"
  has 'claude token verified'
  [[ $(cat "$HOME/.config/claude-accounts/active") == b ]] || fail 'selector not saved'
  jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null
  lacks synthetic-b
done
echo 'firstmate session: OK'
