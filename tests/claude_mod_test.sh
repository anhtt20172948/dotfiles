#!/usr/bin/env bash
# The fleet-deck Claude Code mod: install.sh links it into $HOME without
# touching ~/.claude, .zshenv loads it once, and (with claude installed) the
# mod validates and passes its own tests.
# ~/... in messages is only a label.
# shellcheck disable=SC2088
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
MOD=.config/claude-mods/fleet-deck
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# The chime must stay off until someone turns it on.
[[ $(jq -r '.userConfig.sound.default' "$ROOT/$MOD/.claude-plugin/plugin.json") == false ]] ||
	fail "sound must default to off"

"$ROOT/install.sh" >/dev/null
[[ -f "$HOME/$MOD/.claude-plugin/plugin.json" ]] || fail "~/$MOD is not linked"
[[ "$(readlink -f "$HOME/$MOD")" == "$ROOT/$MOD" ]] || fail "~/$MOD does not point into the repo"
[[ -d "$HOME/.claude" && ! -L "$HOME/.claude" ]] || fail "~/.claude must stay a real directory"
[[ ! -e "$HOME/.claude/claude-mods" ]] || fail "the mod must not be linked under ~/.claude"

# .zshenv adds the path once, even when sourced again by a nested shell.
dirs=$(ROOT=$ROOT zsh -c 'source "$ROOT/.zshenv"; source "$ROOT/.zshenv"; print -r -- "$CLAUDE_CODE_PLUGIN_DIRS"')
[[ $dirs == "$HOME/$MOD" ]] || fail "CLAUDE_CODE_PLUGIN_DIRS is '$dirs', want $HOME/$MOD"
dirs=$(ROOT=$ROOT CLAUDE_CODE_PLUGIN_DIRS=/other zsh -c 'source "$ROOT/.zshenv"; print -r -- "$CLAUDE_CODE_PLUGIN_DIRS"')
[[ $dirs == "/other:$HOME/$MOD" ]] || fail "an existing CLAUDE_CODE_PLUGIN_DIRS must be kept, got '$dirs'"

if ! command -v claude >/dev/null; then
	echo "skip: claude not installed, mod validate/test not run"
	exit 0
fi
claude plugin validate "$ROOT/$MOD" >/dev/null || fail "claude plugin validate"
claude plugin test "$ROOT/$MOD" >/dev/null || fail "claude plugin test"
