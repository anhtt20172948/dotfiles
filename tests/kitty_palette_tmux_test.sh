#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v tmux >/dev/null; then
	echo 'skip: kitty palette tmux integration needs tmux'
	exit 0
fi
TASK_TMP=$(mktemp -d)
SOCKET="$TASK_TMP/tmux.sock"
trap 'tmux -S "$SOCKET" kill-server 2>/dev/null || true; rm -rf "$TASK_TMP"' EXIT
export HOME="$TASK_TMP/home" XDG_CONFIG_HOME="$TASK_TMP/config"
export SSH_CONNECTION='127.0.0.1 1234 127.0.0.1 22'
export LC_KITTY_PALETTE_SRC=arch-local
LC_KITTY_PALETTE=$(printf '111111:dddddd'; printf ':000000%.0s' {1..16})
export LC_KITTY_PALETTE
mkdir -p "$HOME/.config/kitty" "$XDG_CONFIG_HOME"
# A private server models a long-lived pane without touching the user's sessions.
TMUX='' tmux -S "$SOCKET" -f /dev/null new-session -d -s palette 'sleep 120'
TMUX_PID=$(tmux -S "$SOCKET" display-message -p '#{pid}')
export TMUX="$SOCKET,$TMUX_PID,0"
printf '%s:abcdef\n' "$LC_KITTY_PALETTE" > "$HOME/.config/kitty/remote-palette-arch-local.conf"
printf '%s:fedcba\n' "$LC_KITTY_PALETTE" > "$HOME/.config/kitty/remote-palette-mac-local.conf"
tmux -S "$SOCKET" set-environment -t palette LC_KITTY_PALETTE_SRC mac-local
cat > "$TASK_TMP/check.lua" <<'LUA'
vim.opt.rtp:prepend(assert(arg[1]) .. "/.config/nvim")
local theme = require("customize.kitty_palette")
assert(theme.active.primary == arg[2], "fresh Neovim must resolve session/file palette: " .. vim.inspect(theme.active))
LUA
nvim --headless -u NONE -i NONE -l "$TASK_TMP/check.lua" "$ROOT" '#fedcba'
# Removing the session variable must fall back to the stale pane's valid source.
tmux -S "$SOCKET" set-environment -r -t palette LC_KITTY_PALETTE_SRC
nvim --headless -u NONE -i NONE -l "$TASK_TMP/check.lua" "$ROOT" '#abcdef'
# A pane with no source still gets the latest push, including the cursor accent.
unset LC_KITTY_PALETTE_SRC
rm "$HOME/.config/kitty/remote-palette-arch-local.conf"
nvim --headless -u NONE -i NONE -l "$TASK_TMP/check.lua" "$ROOT" '#fedcba'
echo 'kitty palette tmux integration: OK'
