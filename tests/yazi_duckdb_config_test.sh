#!/usr/bin/env bash
# Static checks for the duckdb.yazi setup: JSON stays on Yazi's code previewer,
# keymaps pass `-` args through `--`, every setup option is explicit, and the
# managed ~/.duckdbrc is linked by install.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
CFG="$ROOT/.config/yazi"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Previewers and preloaders for duckdb must not claim json.
if grep -E '^url *= *".*duckdb|^url *= *"\*\.\{csv' "$CFG/yazi.toml" | grep -q json; then
	fail "json is routed to duckdb in yazi.toml"
fi

for opt in 'mode = "standard"' 'row_id = "dynamic"' 'cache_size = 1000' \
	'minmax_column_width = 21' 'column_fit_factor = '; do
	grep -q "$opt" "$CFG/init.lua" || fail "init.lua is missing: $opt"
done

# Yazi 26 parses a bare leading `-` as a flag, so plugin args need `--`.
if grep -E 'plugin duckdb +[-+]' "$CFG/keymap.toml" | grep -v -- '-- ' | grep -q .; then
	fail "duckdb keymap passes a - or + arg without --"
fi
for key in '"<A-h>"' '"<A-l>"' '"M"'; do
	grep -q "on *= *$key" "$CFG/keymap.toml" || fail "keymap.toml is missing $key"
done

grep -q '^\.highlight_colors column_name brightblue bold$' "$ROOT/.duckdbrc" || fail ".duckdbrc highlight colours missing"

# install.sh must link .duckdbrc into $HOME (dry run, empty HOME).
plan=$(HOME=$(mktemp -d) "$ROOT/install.sh" -n)
grep -q '^link    ~/.duckdbrc ' <<<"$plan" || fail "install.sh does not link ~/.duckdbrc"
echo "yazi duckdb config OK"
