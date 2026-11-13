#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./fzf-colors.sh
source "$LIB_DIR/fzf-colors.sh"

for bin in sesh fzf fd; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'sesh-picker: %s not found in PATH\n' "$bin" >&2
    read -rsn1 -p 'Press any key to close...'
    exit 1
  }
done

# Pick a session. Plain fzf, not fzf-tmux: this script already runs inside a
# tmux display-popup (see popup.conf), and popup-in-popup does not work.
target=$(
  sesh list --icons | fzf --height=100% --reverse \
    --no-sort --ansi --border-label ' sesh ' --prompt '⚡ ' \
    --color="$PICKER_FZF_COLORS" \
    --header ' ^a all ^t tmux ^g configs ^x zoxide ^d kill ^f find' \
    --bind 'tab:down,btab:up' \
    --bind 'ctrl-a:change-prompt(⚡ )+reload(sesh list --icons)' \
    --bind 'ctrl-t:change-prompt(🪟 )+reload(sesh list -t --icons)' \
    --bind 'ctrl-g:change-prompt(⚙️ )+reload(sesh list -c --icons)' \
    --bind 'ctrl-x:change-prompt(📁 )+reload(sesh list -z --icons)' \
    --bind 'ctrl-f:change-prompt(🔎 )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
    --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡ )+reload(sesh list --icons)' \
    --preview-window 'right:60%' \
    --preview 'sesh preview {}'
)

# Cancelled with ESC — exit cleanly
[[ -z "$target" ]] && exit 0

# Connect to the chosen session/directory
sesh connect "$target"
