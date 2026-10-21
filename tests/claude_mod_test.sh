#!/usr/bin/env bash
# The Claude Code mods in .config/claude-mods: install.sh links them into $HOME
# without touching ~/.claude, .zshenv loads each once, and (with claude
# installed) every mod validates and passes its own tests.
# ~/... in messages is only a label.
# shellcheck disable=SC2088
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
MODS=.config/claude-mods
NAMES=(fleet-deck pixel-pet)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
# A shell that already loaded the mods must not leak its list into the checks.
unset CLAUDE_CODE_PLUGIN_DIRS

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# The chime must stay off until someone turns it on.
[[ $(jq -r '.userConfig.sound.default' "$ROOT/$MODS/fleet-deck/.claude-plugin/plugin.json") == false ]] ||
	fail "sound must default to off"

"$ROOT/install.sh" >/dev/null
want=()
for name in "${NAMES[@]}"; do
	mod=$MODS/$name
	[[ -f "$HOME/$mod/.claude-plugin/plugin.json" ]] || fail "~/$mod is not linked"
	[[ "$(readlink -f "$HOME/$mod")" == "$ROOT/$mod" ]] || fail "~/$mod does not point into the repo"
	want+=("$HOME/$mod")
done
[[ -d "$HOME/.claude" && ! -L "$HOME/.claude" ]] || fail "~/.claude must stay a real directory"
[[ ! -e "$HOME/.claude/claude-mods" ]] || fail "the mods must not be linked under ~/.claude"
expected=$(IFS=:; echo "${want[*]}")

# .zshenv adds each path once, even when sourced again by a nested shell, and
# skips a folder that is not a mod.
mkdir -p "$ROOT/$MODS/not-a-mod"
trap 'rmdir -- "$ROOT/$MODS/not-a-mod"; rm -rf -- "$TMP"' EXIT
dirs=$(ROOT=$ROOT zsh -c 'source "$ROOT/.zshenv"; source "$ROOT/.zshenv"; print -r -- "$CLAUDE_CODE_PLUGIN_DIRS"')
[[ $dirs == "$expected" ]] || fail "CLAUDE_CODE_PLUGIN_DIRS is '$dirs', want $expected"
dirs=$(ROOT=$ROOT CLAUDE_CODE_PLUGIN_DIRS=/other zsh -c 'source "$ROOT/.zshenv"; print -r -- "$CLAUDE_CODE_PLUGIN_DIRS"')
[[ $dirs == "/other:$expected" ]] || fail "an existing CLAUDE_CODE_PLUGIN_DIRS must be kept, got '$dirs'"

if ! command -v claude >/dev/null; then
	echo "skip: claude not installed, mod validate/test not run"
	exit 0
fi
for name in "${NAMES[@]}"; do
	claude plugin validate "$ROOT/$MODS/$name" >/dev/null || fail "claude plugin validate $name"
	claude plugin test "$ROOT/$MODS/$name" >/dev/null || fail "claude plugin test $name"
done
