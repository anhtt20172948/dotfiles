#!/usr/bin/env bash
# Read-only firstmate overview and worker picker (prefix C / prefix F -> crew).
# bash 3.2, BSD/GNU clean; UI on stderr, main tmux server only.
set -uo pipefail
LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"
FIRSTMATE_DIR=${FIRSTMATE_DIR:-$HOME/.local/share/firstmate}

pause() {
  printf '\n%sPress any key to close...%s' "$AI_SUBTEXT" "$AI_RESET" >&2
  read -rsn1 || true
  printf '\n' >&2
}
fail() {
  printf '%screw-view:%s %s\n' "$AI_RED" "$AI_RESET" "$1" >&2
  pause
  exit 1
}
show_message() {
  printf '%s\n\n%s\n' "$overview" "$1" >&2
  pause
}

[[ -x "$FIRSTMATE_DIR/bin/fm-fleet-view.sh" ]] \
  || fail "firstmate not found at $FIRSTMATE_DIR - run install_agent_workflow"
overview=$(FM_HOME="$FIRSTMATE_DIR" "$FIRSTMATE_DIR/bin/fm-fleet-view.sh") \
  || fail 'could not read firstmate fleet overview'
have tmux || fail "'tmux' not found in PATH"
if ! tmux has-session -t '=firstmate' 2>/dev/null; then
  show_message 'No firstmate session. No workers running.'
  exit 0
fi

# Match the exact session; retain numeric indexes so names never become shell
# commands or ambiguous tmux targets. fzf substitutions shell-quote {1}.
windows=$(tmux list-windows -t '=firstmate' -F $'#{window_index}\t#{window_name}') \
  || fail 'could not list workers in the firstmate session'
workers=$(printf '%s\n' "$windows" | awk -F '\t' '$1 ~ /^[0-9]+$/ && $2 ~ /^fm-/')
if [[ -z "$workers" ]]; then
  show_message 'No workers running.'
  exit 0
fi
have fzf || fail "'fzf' not found in PATH"
# The overview lives in the preview, not the header, so it never crowds out
# the worker list; fzf runs preview commands with $SHELL, which may be zsh.
export CREW_OVERVIEW="$overview"
selection=$(
  printf '%s\n' "$workers" | fzf \
    --ansi --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
    --no-sort --cycle --layout=reverse --margin=1,2 \
    --border=rounded --border-label=' Firstmate crew ' \
    --header='Ctrl-j/k move • Enter jump • Ctrl-o overview • Ctrl-p peek • Esc close' \
    --prompt='Crew › ' --bind='ctrl-j:down,ctrl-k:up' \
    --preview='printf "%s\n" "$CREW_OVERVIEW"' \
    --bind='ctrl-o:change-preview(printf "%s\n" "$CREW_OVERVIEW")' \
    --bind='ctrl-p:change-preview(tmux capture-pane -p -t "=firstmate:"{1} -S -80)' \
    --preview-window='down:60%:wrap' \
    --color='bg+:#313244,bg:#1e1e2e,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7'
) || exit 0
[[ -n "$selection" ]] || exit 0
case "$selection" in *[!0-9]*) fail 'invalid worker selection' ;; esac
printf '%s\n' "$workers" | awk -F '\t' -v selected="$selection" \
  '$1 == selected { found=1 } END { exit !found }' || fail 'invalid worker selection'
tmux switch-client -t "=firstmate:$selection" || fail 'could not switch to worker (window closed?)'
