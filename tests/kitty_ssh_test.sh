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
check_shell 'kitten:<ssh><example><two words>' xterm-kitty '' -ic
check_shell 'kitten:<ssh><example><two words>' tmux-256color 42 -ic
check_shell 'ssh:<example><two words>' xterm-256color '' -ic
check_shell 'ssh:<example><two words>' xterm-kitty 42 -c
rm "$TMP/bin/kitten"
check_shell 'ssh:<example><two words>' xterm-kitty 42 -ic

# The generator must emit exactly one copy, including when DMS is absent.
copy_line() { "$ROOT/.config/kitty/ssh-palette.sh"; }
mac=$(copy_line)
[[ $mac == *'--dest=.config/kitty/remote-palette.conf'*'current-theme.conf'* ]]
[[ $(printf '%s\n' "$mac" | wc -l) -eq 1 ]]
ln -s "$XDG_CONFIG_HOME/kitty/current-theme.conf" "$XDG_CONFIG_HOME/kitty/dank-theme.conf"
[[ $(copy_line) == *'dank-theme.conf'* ]]
rm "$XDG_CONFIG_HOME/kitty/dank-theme.conf"
[[ $(copy_line) == "$mac" ]]
# Missing optional DMS is fine; no palette at all must fail visibly.
rm "$XDG_CONFIG_HOME/kitty/current-theme.conf"
if copy_line >"$TMP/out" 2>"$TMP/err"; then
    echo 'missing palette unexpectedly succeeded'; exit 1
fi
[[ -s $TMP/err ]]
echo 'kitty ssh: OK'
