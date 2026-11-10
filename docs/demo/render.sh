#!/usr/bin/env bash
# Render the demo tapes against the palette fixtures (see docs/demo/README.md).
#
#   docs/demo/render.sh [-o OUT_DIR] [PALETTE...]
#
# PALETTE is mocha, dms-dark or dms-light (default: all three). Every tape in
# docs/demo/tapes/ is rendered once per palette into OUT_DIR/<tape>/<palette>/,
# then OUT_DIR/hero.gif, hero.png and social.png are composed from the
# workspace tape (one palette after another, as a theme change would switch
# them).
#
# The renderer installs the committed HEAD with ./install.sh into a scratch
# HOME, restores Neovim's plugins from lazy-lock.json there (network), and
# never touches the real HOME except VHS's own browser cache.
#
# Environment:
#   DEMO_FONT_DIR        extra fonts for this render only (private fontconfig)
#   DEMO_NVIM_DATA       persistent Neovim data dir (plugins, Mason, parsers)
#   DEMO_WARMUP_TIMEOUT  seconds for the first Neovim start (default 600)
#   DEMO_KEEP=1          keep the scratch directory and print its path
set -euo pipefail

DEMO=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(cd "$DEMO/../.." && pwd -P)
OUT=$REPO/docs/demo/out
# The file the tapes open in Neovim.
DEMO_FILE=.config/nvim/lua/customize/kitty_palette.lua
PALETTES=()

while (($#)); do
	case $1 in
	-o)
		OUT=$2
		shift 2
		;;
	-h | --help)
		sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p;}' "$0"
		exit 0
		;;
	mocha | dms-dark | dms-light)
		PALETTES+=("$1")
		shift
		;;
	*)
		echo "render.sh: unknown argument: $1" >&2
		exit 2
		;;
	esac
done
((${#PALETTES[@]})) || PALETTES=(mocha dms-dark dms-light)

for tool in vhs ttyd ffmpeg git tmux nvim python3 starship yazi lazygit; do
	command -v "$tool" >/dev/null || {
		echo "render.sh: $tool is not on PATH" >&2
		exit 1
	}
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-demo.XXXXXX")
cleanup() {
	tmux -L dotfiles-demo kill-server 2>/dev/null || true
	tmux -L dotfiles-demo-warmup kill-server 2>/dev/null || true
	if [[ ${DEMO_KEEP:-0} == 1 ]]; then
		echo "render.sh: kept $WORK"
	else
		rm -rf "$WORK"
	fi
}
trap cleanup EXIT

palette_file() {
	case $1 in
	mocha) echo "$REPO/.config/kitty/current-theme.conf" ;;
	*) echo "$REPO/tests/fixtures/palettes/$1.conf" ;;
	esac
}

palette_title() {
	case $1 in
	mocha) echo "Catppuccin Mocha · fallback palette" ;;
	dms-dark) echo "DMS dank16 · dark wallpaper" ;;
	dms-light) echo "DMS dank16 · light wallpaper" ;;
	esac
}

# The demo HOME: the README's quick start, run against HEAD. The checkout is
# HEAD alone on a main branch, as a fresh clone has it, whatever branch or
# detached commit this checkout is on.
setup_home() {
	local home=$WORK/home
	mkdir -p "$home"
	git init --quiet -b main "$home/dotfiles"
	git -C "$home/dotfiles" fetch --quiet --update-shallow "$REPO" HEAD
	git -C "$home/dotfiles" reset --quiet --hard FETCH_HEAD
	git -C "$home/dotfiles" remote add origin https://github.com/anhtt20172948/dotfiles.git
	HOME=$home "$home/dotfiles/install.sh" >"$WORK/install.log"

	# tmux: plugins only add key bindings, none draws anything, so a no-op TPM
	# keeps the render offline and deterministic.
	mkdir -p "$home/.tmux/plugins/tpm"
	printf '#!/bin/sh\n' >"$home/.tmux/plugins/tpm/tpm"
	chmod +x "$home/.tmux/plugins/tpm/tpm"

	# The workflow repository renders the real shell rc; the demo needs only
	# the tracked Starship prompt from it.
	cat >"$home/.bashrc" <<-'EOF'
		export LANG=C.UTF-8 EDITOR=nvim
		eval "$(starship init bash)"
	EOF
	# tmux starts login shells, which read only the profile.
	echo '. ~/.bashrc' >"$home/.bash_profile"

	if [[ -n ${DEMO_NVIM_DATA:-} ]]; then
		mkdir -p "$DEMO_NVIM_DATA"
		mkdir -p "$home/.local/share"
		ln -s "$DEMO_NVIM_DATA" "$home/.local/share/nvim"
	fi
	# lazygit greets a new user, and an upgraded one, with popups; this user
	# has seen both.
	mkdir -p "$home/.local/state/lazygit"
	printf 'startuppopupversion: 5\nlastversion: %s\n' \
		"$(lazygit --version | sed -n 's/.*[ ,]version=\([^,]*\),.*/\1/p')" \
		>"$home/.local/state/lazygit/state.yml"

	echo "render.sh: restoring Neovim plugins from lazy-lock.json"
	(cd "$home/dotfiles" && demo_env nvim --headless "+Lazy! restore" +qa) >"$WORK/lazy.log" 2>&1 || {
		cat "$WORK/lazy.log" >&2
		return 1
	}
	warm_up_nvim
	# lazy.nvim rewrites the lockfile when it drops an entry the spec no longer
	# has; the recording shows the tree as committed.
	git -C "$home/dotfiles" checkout --quiet -- .
}

# The first Neovim start, in a detached tmux pane (see warmup.lua).
warm_up_nvim() {
	local status=$WORK/warmup.status waited=0 limit=${DEMO_WARMUP_TIMEOUT:-600}
	echo "render.sh: first Neovim start (debug adapters, Tree-sitter parsers)"
	demo_env DEMO_WARMUP_STATUS="$status" DEMO_WARMUP_TIMEOUT="$limit" \
		tmux -L dotfiles-demo-warmup -f /dev/null new-session -d -x 160 -y 45 \
		-c "$WORK/home/dotfiles" nvim -c "luafile $DEMO/warmup.lua" "$DEMO_FILE"
	while tmux -L dotfiles-demo-warmup has-session 2>/dev/null; do
		if ((waited > limit + 60)); then
			tmux -L dotfiles-demo-warmup kill-server
			break
		fi
		sleep 1
		waited=$((waited + 1))
	done
	if [[ "$(cat "$status" 2>/dev/null)" != ok ]]; then
		echo "render.sh: Neovim warm-up failed: $(cat "$status" 2>/dev/null || echo 'no status')" >&2
		return 1
	fi
}

demo_env() {
	local home=$WORK/home
	env -u LC_KITTY_PALETTE -u LC_KITTY_PALETTE_SRC -u TMUX -u SSH_CONNECTION \
		HOME="$home" SHELL="$(command -v bash)" TERM=xterm-256color \
		XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
		XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" \
		"$@"
}

# DMS writes ~/.config/kitty/dank-theme.conf from the wallpaper; kitty and
# Neovim prefer it over the Mocha fallback. Mocha is the absence of that file.
apply_palette() {
	local name=$1 theme=$WORK/home/.config/kitty/dank-theme.conf
	rm -f "$theme"
	[[ $name == mocha ]] || python3 "$DEMO/palette.py" kitty "$(palette_file "$name")" >"$theme"
}

fontconfig() {
	[[ -n ${DEMO_FONT_DIR:-} ]] || return 0
	cat >"$WORK/fonts.conf" <<-EOF
		<?xml version="1.0"?>
		<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
		<fontconfig>
		  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
		  <dir>$DEMO_FONT_DIR</dir>
		  <cachedir>$WORK/fontconfig-cache</cachedir>
		</fontconfig>
	EOF
	export FONTCONFIG_FILE=$WORK/fonts.conf
}

render_tape() {
	local tape=$1 name=$2 dir tape_name
	tape_name=$(basename "$tape" .tape)
	dir=$OUT/$tape_name/$name
	mkdir -p "$dir"
	{
		echo "Output \"$dir/$tape_name.gif\""
		echo "Set Theme $(python3 "$DEMO/palette.py" theme "$(palette_file "$name")" "$name")"
		cat "$DEMO/settings.tape"
		sed "s|@SHOTS@|$dir|g" "$tape"
	} >"$WORK/$tape_name-$name.tape"
	echo "render.sh: $tape_name / $name"
	(cd "$WORK/home/dotfiles" && demo_env vhs "$WORK/$tape_name-$name.tape")
	tmux -L dotfiles-demo kill-server 2>/dev/null || true
}

# The workspace still of each palette with its name in a strip below, in the
# palette's own colours.
label_still() {
	local name=$1 still=$2 out=$3 colours font
	read -r -a colours < <(python3 "$DEMO/palette.py" colors "$(palette_file "$name")")
	font=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font:style=Bold")
	ffmpeg -loglevel error -y -i "$still" -vf "pad=iw:ih+48:0:0:color=0x${colours[0]},\
drawtext=fontfile=$font:text='$(palette_title "$name")':fontsize=20:\
fontcolor=0x${colours[1]}:x=(w-tw)/2:y=h-34" "$out"
}

# GitHub's social preview size (1280x640): the still scaled to that height,
# centred on the palette background.
social_still() {
	local name=$1 still=$2 out=$3 colours
	read -r -a colours < <(python3 "$DEMO/palette.py" colors "$(palette_file "$name")")
	ffmpeg -loglevel error -y -i "$still" \
		-vf "scale=-2:640:flags=lanczos,pad=1280:640:(ow-iw)/2:0:color=0x${colours[0]}" "$out"
}

# hero.gif cuts between the palettes like a theme change; hero.png and
# social.png show the DMS dark still (the workstation's usual look), or the
# first rendered one.
compose_hero() {
	local name still labelled=() inputs=() streams="" i
	for name in "${PALETTES[@]}"; do
		still=$OUT/workspace/$name/workspace.png
		[[ -f $still ]] || continue
		label_still "$name" "$still" "$WORK/hero-$name.png"
		labelled+=("$WORK/hero-$name.png")
		if [[ $name == dms-dark || ! -f $OUT/hero.png ]]; then
			cp "$WORK/hero-$name.png" "$OUT/hero.png"
			social_still "$name" "$still" "$OUT/social.png"
		fi
	done
	((${#labelled[@]})) || return 0
	for i in "${!labelled[@]}"; do
		inputs+=(-loop 1 -framerate 1 -t 3 -i "${labelled[$i]}")
		streams+="[$i:v]"
	done
	ffmpeg -loglevel error -y "${inputs[@]}" -filter_complex \
		"${streams}concat=n=${#labelled[@]}:v=1:a=0,split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=none" \
		-loop 0 "$OUT/hero.gif"
}

mkdir -p "$OUT"
fontconfig
setup_home
for name in "${PALETTES[@]}"; do
	apply_palette "$name"
	for tape in "$DEMO"/tapes/*.tape; do
		render_tape "$tape" "$name"
	done
done
compose_hero
echo "render.sh: wrote $OUT"
