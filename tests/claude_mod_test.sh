#!/usr/bin/env bash
# The Claude Code mods in .config/claude-mods: install.sh leaves the folder in
# the checkout, registers it through install-agent-statusline in ~/.claude/settings.json
# and enables every mod it lists, and (with claude installed) the marketplace and
# every mod validate and each mod passes its own tests.
# ~/... in messages is only a label.
# shellcheck disable=SC2088
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
MODS=.config/claude-mods
MARKET=dotfiles-mods
NAMES=(pixel-pet crew-watch)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
# A shell that still loads the mods from its environment must not leak them
# into the checks.
unset CLAUDE_CODE_PLUGIN_DIRS

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# The marketplace lists every mod folder, each by its own manifest name.
listed=$(jq -r '.plugins[] | "\(.name) \(.source)"' "$ROOT/$MODS/.claude-plugin/marketplace.json" | sort)
want=$(for name in "${NAMES[@]}"; do echo "$name ./$name"; done | sort)
[[ $listed == "$want" ]] || fail "marketplace lists '$listed', want '$want'"
for name in "${NAMES[@]}"; do
	[[ $(jq -r .name "$ROOT/$MODS/$name/.claude-plugin/plugin.json") == "$name" ]] || fail "$name manifest name"
done
folders=$(cd "$ROOT/$MODS" && for dir in */.claude-plugin/plugin.json; do echo "${dir%%/*}"; done | sort)
[[ $folders == "$(printf '%s\n' "${NAMES[@]}" | sort)" ]] || fail "mod folders '$folders' differ from the marketplace"

"$ROOT/install.sh" >/dev/null
# The mods are read in place from the checkout: a folder marketplace's plugins may not be
# links that leave it, so ~/.config/claude-mods must not exist as a second, linked copy.
[[ ! -e "$HOME/$MODS" && ! -L "$HOME/$MODS" ]] || fail "~/$MODS must not be linked"
[[ -z "$(find "$ROOT/$MODS" -type l)" ]] || fail "$MODS holds symlinks, which the engine refuses when they leave it"
[[ -d "$HOME/.claude" && ! -L "$HOME/.claude" ]] || fail "~/.claude must stay a real directory"
[[ ! -e "$HOME/.claude/claude-mods" ]] || fail "the mods must not be linked under ~/.claude"

settings=$HOME/.claude/settings.json
jq -e --arg market "$MARKET" --arg path "$ROOT/$MODS" \
	'.extraKnownMarketplaces[$market].source == {source: "directory", path: $path}' "$settings" >/dev/null ||
	fail "$ROOT/$MODS is not declared as the $MARKET marketplace"
for name in "${NAMES[@]}"; do
	jq -e --arg id "$name@$MARKET" '.enabledPlugins[$id] == true' "$settings" >/dev/null || fail "$name is not enabled"
done

# A mod turned off in /plugin stays off, and other settings stay, when install.sh
# runs again; a mod the marketplace no longer lists is dropped.
jq --arg id "pixel-pet@$MARKET" --arg gone "gone@$MARKET" \
	'.enabledPlugins[$id] = false | .enabledPlugins[$gone] = true | .enabledPlugins["other@elsewhere"] = true' \
	"$settings" >"$TMP/settings.json"
mv "$TMP/settings.json" "$settings"
"$ROOT/install.sh" >/dev/null
jq -e --arg id "pixel-pet@$MARKET" '.enabledPlugins[$id] == false and .enabledPlugins["other@elsewhere"] == true' \
	"$settings" >/dev/null || fail "install.sh overrode enabledPlugins"
jq -e --arg gone "gone@$MARKET" '.enabledPlugins | has($gone) | not' "$settings" >/dev/null ||
	fail "install.sh kept a mod the marketplace no longer lists"

# Parser tests also run on hosts without Claude Code.
for name in "${NAMES[@]}"; do
	for parser_test in "$ROOT/$MODS/$name"/tests/*_test.py; do
		[[ -f "$parser_test" ]] || continue
		python3 "$parser_test" || fail "$name parser tests"
	done
done

# crew-watch's Theme option offers the default plus exactly the palettes theme.ts defines.
crew=$ROOT/$MODS/crew-watch
offered=$(jq -r '.userConfig.theme | select(.default == "default") | .options[]' "$crew/.claude-plugin/plugin.json" | sed '/^default$/d' | sort)
defined=$(sed -n "s/^  '\{0,1\}\([a-z-]*\)'\{0,1\}: {\$/\1/p" "$crew/hooks/theme.ts" | sort)
[[ -n $offered && $offered == "$defined" ]] || fail "crew-watch Theme options '$offered' differ from theme.ts palettes '$defined'"

if ! command -v claude >/dev/null; then
	echo "skip: claude not installed, mod validate/test not run"
	exit 0
fi
claude plugin validate "$ROOT/$MODS" >/dev/null || fail "claude plugin validate the marketplace"
for name in "${NAMES[@]}"; do
	claude plugin validate "$ROOT/$MODS/$name" >/dev/null || fail "claude plugin validate $name"
	claude plugin test "$ROOT/$MODS/$name" >/dev/null || fail "claude plugin test $name"
done
