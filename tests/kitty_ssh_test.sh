#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/kitty" "$TMP/bin"
cp "$ROOT/.config/kitty/current-theme.conf" "$XDG_CONFIG_HOME/kitty/"
# No network: exercise the real interactive shell with recording commands.
printf '#!/bin/sh\nprintf "kitten:"; printf "<%%s>" "$@"\n' > "$TMP/bin/kitten"
printf '#!/bin/sh\nprintf "ssh:"; printf "<%%s>" "$@"\n' > "$TMP/bin/ssh"
chmod +x "$TMP/bin/kitten" "$TMP/bin/ssh"
printf 'ssh example "two words"\n' > "$TMP/invoke.zsh"
ZSH=$(command -v zsh) || { echo 'skip: needs zsh'; exit 0; }
check_shell() {
    local expected=$1 term=$2 window=$3 mode=$4 actual
    # shellcheck disable=SC2016 # Variables are expanded by the child zsh.
    actual=$(TEST_PATH="$TMP/bin" TERM="$term" KITTY_WINDOW_ID="$window" \
        "$ZSH" -f "$mode" 'PATH=$TEST_PATH; source "$1/.zshenv"; source "$2"' test "$ROOT" "$TMP/invoke.zsh")
    [[ $actual == "$expected" ]] || { echo "unexpected ssh dispatch: $actual"; exit 1; }
}
check_shell 'ssh:<example><two words>' xterm-kitty '' -ic
check_shell 'ssh:<example><two words>' tmux-256color 42 -ic
check_shell 'ssh:<example><two words>' xterm-256color '' -ic
check_shell 'ssh:<example><two words>' xterm-kitty 42 -c
rm "$TMP/bin/kitten"
check_shell 'ssh:<example><two words>' xterm-kitty 42 -ic

# Palette transport belongs to the workflow-managed shell and OpenSSH config.
[[ ! -e "$ROOT/.config/kitty/ssh-palette.sh" ]]
if grep -Eq '^[[:space:]]*(copy|geninclude)[[:space:]]' "$ROOT/.config/kitty/ssh.conf"; then
    echo 'kitty ssh must not copy a palette'; exit 1
fi
echo 'kitty ssh: OK'
