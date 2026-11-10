#!/usr/bin/env bash
# dotfiles-diagnose: palette source and contrast from Neovim's resolver, tool
# versions, missing tools and configs reported (never fatal), the dotfiles
# commit, the palette followers, and valid --json. Runs under stock macOS
# /bin/bash 3.2 in CI; every case uses a throwaway HOME and a curated PATH.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/.local/bin/dotfiles-diagnose"
for tool in nvim git python3; do
	if ! command -v "$tool" >/dev/null; then
		echo "skip: dotfiles-diagnose test needs $tool"
		exit 0
	fi
done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# A PATH with the utilities the script uses and none of the managed tools, so
# which tools are "installed" is decided here, not by the host.
BIN="$TMP/bin"
mkdir -p "$BIN"
for util in bash sh env uname sed tr head grep dirname basename readlink mktemp rm wc cut cat \
	timeout perl sw_vers git nvim; do
	path=$(command -v "$util" 2>/dev/null) || continue
	case $path in /*) ln -s "$path" "$BIN/$util" ;; esac
done
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
stub() {
	printf '#!/bin/sh\ncat <<'\''OUT'\''\n%s\nOUT\n' "$2" >"$STUBS/$1"
	chmod +x "$STUBS/$1"
}
stub tmux 'tmux 3.5a'
stub lazygit 'commit=0123456, build date=2025-01-02T03:04:05Z, build source=binaryRelease, version=0.44.1, os=linux, arch=amd64, git version=2.47.0'
stub eza 'eza - A modern, maintained replacement for ls
v0.20.10 [+git]'

# Each case: a fresh HOME with XDG_CONFIG_HOME inside it and no palette variables.
new_home() {
	CASE="$TMP/$1"
	mkdir -p "$CASE/home/.config/kitty"
}
# CASE_ENV holds extra NAME=value words (no spaces), split on purpose.
diagnose() {
	# shellcheck disable=SC2086
	env -i HOME="$CASE/home" XDG_CONFIG_HOME="$CASE/home/.config" PATH="${CASE_PATH:-$STUBS:$BIN}" \
		TERM=xterm-kitty SHELL=/bin/zsh GIT_CONFIG_NOSYSTEM=1 ${CASE_ENV:-} bash "$SCRIPT" "$@"
}
# report: run both formats once for the current state; json/plain_has assert on them.
report() {
	diagnose --json >"$CASE/report.json"
	diagnose >"$CASE/report.txt"
}
# json <python expression over `d`>: assert it on the --json report.
json() {
	python3 - "$CASE/report.json" "$1" <<'PY' || fail "json assertion: $1 ($CASE/report.json: $(cat "$CASE/report.json"))"
import json, sys
d = json.load(open(sys.argv[1]))
slot = {s["name"]: s for s in d["palette"]["slots"]}
tool = {t["name"]: t for t in d["tools"]}
follower = {f["tool"]: f for f in d["followers"]}
assert eval(sys.argv[2]), sys.argv[2]
PY
}
plain_has() {
	grep -Eq -- "$1" "$CASE/report.txt" || fail "plain report lacks /$1/: $(cat "$CASE/report.txt")"
}
# A kitty palette file: background, foreground, cursor, then color0-15.
palette_file() {
	local out=$1 bg=$2 fg=$3 cursor=$4
	shift 4
	{
		printf 'background %s\nforeground %s\n' "$bg" "$fg"
		[ "$cursor" = - ] || printf 'cursor %s\n' "$cursor"
		local i=0
		for colour in "$@"; do
			printf 'color%d %s\n' "$i" "$colour"
			i=$((i + 1))
		done
	} >"$out"
}

# --- arguments ---------------------------------------------------------------
new_home args
diagnose --help | grep -q -- '--json' || fail '--help must document --json'
status=0
diagnose --bogus >/dev/null 2>&1 || status=$?
[ "$status" = 2 ] || fail "unknown argument must exit 2, got $status"

# --- DMS palette, versions, missing tools, checkout ------------------------------
new_home dms
cp "$ROOT/tests/fixtures/palettes/dms-dark.conf" "$CASE/home/.config/kitty/dank-theme.conf"
report
json 'd["palette"]["source"] == "dank-theme.conf" and d["palette"]["available"]'
json 'd["palette"]["background"] == "#0b0f11" and d["palette"]["primary"] is None'
json 'd["palette"]["path"].endswith("/.config/kitty/dank-theme.conf") and "DMS" in d["palette"]["description"]'
# dank16's ANSI 5 and 8 are no text tones: reported, never judged.
json 'slot["color5"]["ok"] is None and slot["color8"]["ok"] is None and slot["color0"]["contrast"] == 1.0'
json 'slot["color1"]["ok"] and slot["foreground"]["ok"] and slot["color6"]["role"] == "accent"'
json 'len(d["palette"]["slots"]) == 17'
json 'tool["tmux"]["version"] == "3.5a" and tool["lazygit"]["version"] == "0.44.1" and tool["eza"]["version"] == "0.20.10"'
json 'tool["nvim"]["installed"] and not tool["kitty"]["installed"] and tool["kitty"]["version"] is None'
json '[t["name"] for t in d["tools"]] == "kitty tmux nvim starship lazygit fzf bat delta yazi btop atuin eza".split()'
commit=$(git -C "$ROOT" rev-parse --short HEAD)
changes=$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')
json "d['dotfiles']['commit'] == '$commit' and d['dotfiles']['changes'] == $changes and d['dotfiles']['dirty'] == ($changes > 0)"
json 'd["host"]["ssh"] is False and d["host"]["term"] == "xterm-kitty"'
plain_has '^  kitty +missing$'
plain_has '^  tmux +3\.5a +'
plain_has 'source +DMS wallpaper palette \(dank-theme\.conf\)'
plain_has '^    color1 +#ff729d +[0-9.]+:1 +text +ok$'

# --- kitty fallback (Catppuccin Mocha) --------------------------------------------
new_home mocha
cp "$ROOT/.config/kitty/current-theme.conf" "$CASE/home/.config/kitty/current-theme.conf"
report
json 'd["palette"]["source"] == "current-theme.conf" and "Mocha" in d["palette"]["description"]'
json 'd["palette"]["flavour"] == "mocha" and all(s["ok"] is not False for s in d["palette"]["slots"])'

# --- no palette at all -------------------------------------------------------------
new_home none
report
json 'd["palette"]["source"] == "none" and not d["palette"]["available"] and d["palette"]["slots"] == []'
plain_has 'no kitty palette found: Neovim uses plain Catppuccin Mocha'

# --- low contrast: exact WCAG ratios and a warning -----------------------------------
new_home low
palette_file "$CASE/home/.config/kitty/current-theme.conf" '#000000' '#ffffff' '#808080' \
	'#000000' '#ffffff' '#222222' '#ffffff' '#ffffff' '#ffffff' '#ffffff' '#ffffff' \
	'#ffffff' '#ffffff' '#ffffff' '#ffffff' '#ffffff' '#ffffff' '#ffffff' '#ffffff'
report
json 'slot["foreground"]["contrast"] == 21.0 and slot["color1"]["contrast"] == 21.0'
json 'slot["color2"]["ok"] is False and any("color2 (#222222)" in w for w in d["warnings"])'
json 'd["palette"]["primary"] == "#808080" and slot["primary"]["ok"] is None and len(d["palette"]["slots"]) == 18'
plain_has '^  - palette color2 \(#222222\) is [0-9.]+:1 on the background #000000, below 4\.5:1$'

# --- environment and pushed palettes ---------------------------------------------------
encoded() {
	printf '%s:eeeeee' "$1"
	printf ':%s' 000000 ff8888 88ff88 ffff88 8888ff 333333 88ffff ffffff 555555 ffaaaa aaffaa ffffaa aaaaff ffaaff aaffff ffffff
}
new_home env
CASE_ENV="LC_KITTY_PALETTE=$(encoded 101010) LC_KITTY_PALETTE_SRC=arch-local"
report
json 'd["palette"]["source"] == "LC_KITTY_PALETTE" and d["palette"]["background"] == "#101010"'
plain_has 'source +LC_KITTY_PALETTE from the environment \(source arch-local\)'
# A pane started before a DMS switch to light keeps the dark snapshot; locally
# the live DMS file wins.
new_home stale-env
cp "$ROOT/tests/fixtures/palettes/dms-light.conf" "$CASE/home/.config/kitty/dank-theme.conf"
CASE_ENV="LC_KITTY_PALETTE=$(encoded 101010) LC_KITTY_PALETTE_SRC=arch-local"
report
json 'd["palette"]["source"] == "dank-theme.conf" and d["palette"]["flavour"] == "latte"'
plain_has 'source +DMS wallpaper palette \(dank-theme\.conf\)'
new_home pushed
printf '%s:abcdef\n' "$(encoded 202020)" >"$CASE/home/.config/kitty/remote-palette-arch-local.conf"
CASE_ENV="SSH_CONNECTION=127.0.0.1_1234_127.0.0.1_22 LC_KITTY_PALETTE=$(encoded 101010) LC_KITTY_PALETTE_SRC=arch-local"
report
json 'd["palette"]["source"] == "remote-palette-arch-local" and d["palette"]["background"] == "#202020"'
json 'd["palette"]["primary"] == "#abcdef" and d["host"]["ssh"] is True'
plain_has 'source +pushed by arch-local \(remote-palette-arch-local\.conf\)'
CASE_ENV=''

# --- no nvim: the palette is unavailable, the report still completes -------------------
new_home no-nvim
cp "$ROOT/tests/fixtures/palettes/dms-dark.conf" "$CASE/home/.config/kitty/dank-theme.conf"
mkdir -p "$CASE/bin"
for link in "$BIN"/*; do
	[ "${link##*/}" = nvim ] || ln -s "$(readlink "$link")" "$CASE/bin/${link##*/}"
done
CASE_PATH="$CASE/bin"
report
json 'not d["palette"]["available"] and "nvim not installed" in d["palette"]["error"]'
json 'not tool["nvim"]["installed"] and any(w.startswith("palette: nvim not installed") for w in d["warnings"])'
plain_has '^  unavailable: nvim not installed'
CASE_PATH=''

# --- followers: linked configs follow, overrides differ -----------------------------------
new_home follow
H="$CASE/home"
mkdir -p "$H/.config/bat" "$H/.config/btop" "$H/.config/yazi" "$H/.config/lazygit" "$H/.config/fzf" "$H/.config/git"
for f in kitty/kitty.conf bat/config btop/btop.conf yazi/theme.toml lazygit/config.yml fzf/fzfrc git/config starship.toml; do
	ln -s "$ROOT/.config/$f" "$H/.config/$f"
done
ln -s "$ROOT/.config/tmux" "$H/.config/tmux"
ln -s "$ROOT/.config/nvim" "$H/.config/nvim"
ln -s "$ROOT/.tmux.conf" "$H/.tmux.conf"
report
json 'all(follower[t]["status"] == "follows" for t in "kitty tmux nvim starship bat delta yazi lazygit btop".split())'
json 'follower["fzf"]["status"] == "differs" and "only the tmux pickers" in follower["fzf"]["detail"]'
# A differing config warns only when its tool is installed (fzf is not on this PATH).
json 'not any(w.startswith("fzf:") for w in d["warnings"])'
CASE_ENV="FZF_DEFAULT_OPTS_FILE=$H/.config/fzf/fzfrc BAT_THEME=Dracula STARSHIP_SHELL=zsh"
report
json 'follower["fzf"]["status"] == "follows" and follower["bat"]["status"] == "differs"'
json '"prompt active in zsh" in follower["starship"]["detail"]'
CASE_ENV=''
# install.sh links the script into ~/.local/bin; the checkout resolves through the link.
mkdir -p "$H/.local/bin"
ln -s "$SCRIPT" "$H/.local/bin/dotfiles-diagnose"
SCRIPT="$H/.local/bin/dotfiles-diagnose"
report
json "d['dotfiles']['path'] == '$(cd "$ROOT" && pwd -P)' and d['palette']['source'] == 'none'"

# --- missing configs: reported, warned only for installed tools ---------------------------
new_home bare
report
json 'follower["tmux"]["status"] == "missing" and follower["kitty"]["status"] == "missing"'
json 'any(w.startswith("tmux: no ") for w in d["warnings"]) and not any(w.startswith("kitty:") for w in d["warnings"])'

echo 'dotfiles-diagnose: OK'
