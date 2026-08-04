#!/usr/bin/env bash
# Status-bar segment: how many AI agents are live for this user right now.
#
# The point of detached persistent agents is that they keep working while you do
# something else, which is worthless if the only way to learn an agent finished
# is to open the popup and look. This is that missing signal.
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

server=${AI_POPUP_SERVER_NAME:-$AI_SERVER_DEFAULT}

count=$(tmux -L "$server" list-sessions -F '#{@ai_popup_tool}' 2>/dev/null \
  | grep -c -E '^(codex|opencode|claude)$') || count=0

# Print nothing at all when idle, so the segment disappears instead of leaving a
# bare icon behind — status.conf documents the same trap for other segments.
case ${count:-0} in
  ''|0|*[!0-9]*) exit 0 ;;
esac

# Catppuccin @thm_green / @thm_overlay0, hardcoded on purpose: tmux expands
# #[...] styles inside #() output but NOT @user-options, and those only exist
# once TPM has loaded anyway.
printf '#[fg=#a6e3a1]󰘩 %d #[fg=#6c7086,none]|' "$count"
