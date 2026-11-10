#!/usr/bin/env bash
# docs/demo/palette.py turns each demo palette (the Mocha fallback and the
# recorded DMS fixtures) into a complete VHS theme with the ANSI slots in
# kitty's order, and into the dank-theme.conf DMS would write, cursor included.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PALETTE=$ROOT/docs/demo/palette.py

command -v python3 >/dev/null || {
	echo "skip: python3 not installed"
	exit 0
}

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

for file in .config/kitty/current-theme.conf tests/fixtures/palettes/dms-dark.conf \
	tests/fixtures/palettes/dms-light.conf; do
	python3 "$PALETTE" theme "$ROOT/$file" demo >"$TMP/theme.json"
	python3 "$PALETTE" kitty "$ROOT/$file" >"$TMP/dank-theme.conf"
	python3 - "$ROOT/$file" "$TMP/theme.json" "$TMP/dank-theme.conf" <<-'EOF'
		import json
		import re
		import sys

		source, theme_path, kitty_path = sys.argv[1:]
		line = re.compile(r"^\s*([a-z_0-9]+)\s+(#[0-9a-fA-F]{6})\s*$")

		def colours(path):
		    with open(path, encoding="utf-8") as handle:
		        return {
		            m.group(1): m.group(2).lower()
		            for m in map(line.match, handle)
		            if m
		        }

		def fail(message):
		    sys.exit(f"FAIL {source}: {message}")

		palette = colours(source)
		with open(theme_path, encoding="utf-8") as handle:
		    theme = json.load(handle)
		names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
		expected = {"name": "demo", "background": palette["background"],
		            "foreground": palette["foreground"],
		            "cursor": palette.get("cursor", palette["color6"]),
		            "selection": palette["color8"]}
		for index, name in enumerate(names):
		    expected[name] = palette[f"color{index}"]
		    expected["bright" + name.capitalize()] = palette[f"color{index + 8}"]
		if theme != expected:
		    fail(f"VHS theme {theme} != {expected}")

		written = colours(kitty_path)
		if written.get("cursor") != expected["cursor"]:
		    fail(f"dank-theme.conf cursor {written.get('cursor')} != {expected['cursor']}")
		if {k: v for k, v in written.items() if k != "cursor"} != {
		    k: v for k, v in palette.items() if k != "cursor"
		}:
		    fail("dank-theme.conf changed colours other than the cursor")
	EOF
done

if python3 "$PALETTE" theme "$ROOT/README.md" demo >/dev/null 2>"$TMP/err"; then
	echo "FAIL: a file without a palette was accepted" >&2
	exit 1
fi
grep -q 'missing background' "$TMP/err" || {
	echo "FAIL: missing colours not reported: $(cat "$TMP/err")" >&2
	exit 1
}

bash -n "$ROOT/docs/demo/render.sh"
echo "demo palette: OK"
