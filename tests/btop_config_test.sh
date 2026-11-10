#!/usr/bin/env bash
# The tracked .config/btop/btop.conf must already be in the format the
# installed btop writes. btop rewrites its config on exit when the header
# version differs or a value fails to parse, which leaves the dotfiles
# checkout dirty on every host that runs it. Starts btop in a scratch HOME
# on a copy of the file, quits it, and requires the copy to be untouched.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONF=$ROOT/.config/btop/btop.conf

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Older btop wrote True/False; current btop writes true/false.
if grep -nE '^[a-z_0-9]+ = (True|False)$' "$CONF"; then
	fail "btop.conf has capitalised booleans (old btop format)"
fi

for tool in btop tmux; do
	command -v "$tool" >/dev/null || {
		echo "skip: $tool not installed"
		exit 0
	}
done

TMP=$(mktemp -d)
SOCK="btop-conf-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home/.config/btop"
cp "$CONF" "$TMP/home/.config/btop/btop.conf"

tmux -L "$SOCK" -f /dev/null new-session -d -s t -x 160 -y 50 \
	"env HOME='$TMP/home' XDG_CONFIG_HOME='$TMP/home/.config' TERM=xterm-256color btop"

# Wait for the first frame, then quit and wait for btop to exit (which ends the session).
for _ in $(seq 100); do
	tmux -L "$SOCK" capture-pane -p -t t 2>/dev/null | grep -q 'cpu' && break
	sleep 0.1
done
tmux -L "$SOCK" send-keys -t t q
for _ in $(seq 100); do
	tmux -L "$SOCK" has-session -t t 2>/dev/null || break
	sleep 0.1
done
tmux -L "$SOCK" has-session -t t 2>/dev/null && fail "btop did not exit after q"

if ! cmp -s "$CONF" "$TMP/home/.config/btop/btop.conf"; then
	diff -u "$CONF" "$TMP/home/.config/btop/btop.conf" >&2 || true
	fail "btop $(btop --version | sed -n '1s/\x1b\[[0-9;]*m//g; 1s/.*: *//p') rewrites the tracked btop.conf; regenerate it with this btop"
fi
echo "OK: btop leaves the tracked btop.conf unchanged"
