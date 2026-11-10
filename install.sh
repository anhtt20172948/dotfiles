#!/usr/bin/env bash
# Link dotfiles into $HOME, without sudo or stow.
# macOS: installs Homebrew coreutils when missing (tmux-which-key needs GNU realpath).
#
#   ./install.sh            create symlinks
#   ./install.sh -n         dry-run: only print what would be done
#
# Folds directories like stow: missing target -> link the whole directory
# (~/.config/nvim -> repo/.config/nvim); target is a real directory -> descend
# and link each child. Unknown files/symlinks in the way move to
# ~/.dotfiles-backup/<timestamp>/, never deleted. Safe to re-run.
# Only links what git tracks (or what is `git add`ed): untracked things in the repo,
# such as a firstmate clone, are never linked into $HOME. A checkout without git
# (tarball download) links everything as before.
# ~/... in strings is only a display label, no expansion needed.
# shellcheck disable=SC2088
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd -P)
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

# Repo-only, not dotfiles: never linked into $HOME. Matched by name at the repo root
# (a .config/x/docs is still linked normally).
ROOT_IGNORE=(
	.git .gitignore .gitmodules .github
	docs tests .superpowers
	# REPO-LEVEL Claude config (project skill, settings.local.json) - linking it into
	# ~/.claude would turn it into global config.
	.claude
	.no-mistakes.yaml
	install.sh
)

# Read these directories directly from the checkout instead of linking into $HOME.
NEVER_LINK=(.config/claude-mods)

# Directories that apps write into (~/.local/bin takes install_* binaries, DBs/run
# logs of no-mistakes, gnhf, treehouse): always real directories, never folded into
# one symlink into the repo.
NO_FOLD=(
	.config .local .local/bin .local/share .local/state
	.local/share/firstmate .local/share/firstmate/config .local/share/firstmate/data
	.no-mistakes .gnhf .config/treehouse
)

linked=0 backed_up=0 unchanged=0 skipped=0

# Every git-tracked path, one per line, with a blank line at both ends; empty when the repo
# is not a git checkout. A string because macOS bash 3.2 has no associative arrays.
TRACKED=

usage() {
	echo "usage: ./install.sh [-n|--dry-run]" >&2
}

contains() {
	local needle=$1 x
	shift
	for x in "$@"; do
		[[ "$x" == "$needle" ]] && return 0
	done
	return 1
}

# stow's default ignores (VCS, editor backup files) at every level, plus
# README/LICENSE/COPYING and ROOT_IGNORE at the root.
is_ignored() {
	local rel=$1 name=${1##*/}
	contains "$rel" "${NEVER_LINK[@]}" && return 0
	case "$name" in
	RCS | CVS | .cvsignore | .svn | _darcs | .hg | .git | .gitignore | .gitmodules | *,v | *~ | \#*\# | .\#*)
		return 0
		;;
	esac
	[[ "$rel" == */* ]] && return 1
	case "$name" in
	README* | LICENSE* | COPYING) return 0 ;;
	esac
	contains "$name" "${ROOT_IGNORE[@]}"
}

load_tracked() {
	command -v git >/dev/null || return 0
	git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	# -z: git does not quote names with diacritics.
	TRACKED=$'\n'$(git -C "$REPO" ls-files -z | tr '\0' '\n')$'\n'
}

# rel is a tracked file, or a directory holding at least one tracked file.
is_tracked() {
	local rel=$1
	[[ -z "$TRACKED" ]] && return 0
	[[ "$TRACKED" == *$'\n'"$rel"$'\n'* || "$TRACKED" == *$'\n'"$rel"/* ]]
}

run() {
	[[ $DRY_RUN -eq 1 ]] || "$@"
}

backup() {
	local rel=$1
	echo "backup  ~/$rel -> $BACKUP_DIR/$rel"
	run mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
	run mv "$HOME/$rel" "$BACKUP_DIR/$rel"
	backed_up=$((backed_up + 1))
}

make_link() {
	local rel=$1 src=${2:-$REPO/$1}
	echo "link    ~/$rel -> $src"
	run mkdir -p "$(dirname "$HOME/$rel")"
	run ln -s "$src" "$HOME/$rel"
	linked=$((linked + 1))
}

# The symlink already points at the repo entry (absolute, or relative as stow makes it).
points_to_repo() {
	local dst=$1 src=$2
	[[ -L "$dst" && -e "$dst" ]] || return 1
	[[ "$(readlink -f -- "$dst")" == "$(readlink -f -- "$src")" ]]
}

# A shared (NO_FOLD) directory may be a symlink outside the repo, e.g. ~/.config
# on another disk: descend into it instead of moving it to backup.
is_foreign_dir() {
	local dst=$1
	[[ -L "$dst" && -d "$dst" ]] || return 1
	case "$(readlink -f -- "$dst")/" in
	"$REPO"/*) return 1 ;;
	esac
	return 0
}

# Make room for a NO_FOLD directory: remove an old stow link folded into the repo, unknown files go to backup.
clear_dir_dst() {
	local rel=$1
	if points_to_repo "$HOME/$rel" "$REPO/$rel"; then
		echo "unfold  ~/$rel"
		run rm "$HOME/$rel"
	elif [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]]; then
		backup "$rel"
	fi
}

link_entry() {
	local rel=$1 fresh=${2:-}
	local src=${3:-$REPO/$rel} dst="$HOME/$rel"

	if [[ -d "$src" && ! -L "$src" ]]; then
		if [[ -z "$fresh" && -d "$dst" && ! -L "$dst" ]]; then
			link_children "$rel"
			return
		fi
		if contains "$rel" "${NO_FOLD[@]}"; then
			if [[ -z "$fresh" ]] && is_foreign_dir "$dst"; then
				link_children "$rel"
				return
			fi
			[[ -n "$fresh" ]] || clear_dir_dst "$rel"
			echo "mkdir   ~/$rel"
			run mkdir -p "$dst"
			link_children "$rel" fresh
			return
		fi
	fi
	if [[ -z "$fresh" ]]; then
		if points_to_repo "$dst" "$src"; then
			unchanged=$((unchanged + 1))
			return
		fi
		if [[ -e "$dst" || -L "$dst" ]]; then
			backup "$rel"
		fi
	fi
	make_link "$rel" "$src"
}

# Without ~/.gitconfig, `git config --global` writes to ~/.config/git/config,
# which is a symlink into this repo: identity, credential helpers and
# safe.directory entries would land in the checkout. An empty ~/.gitconfig takes
# those writes; git reads it after ~/.config/git/config, so it changes nothing.
ensure_gitconfig() {
	[[ -f "$REPO/.config/git/config" ]] || return 0
	[[ -e "$HOME/.gitconfig" || -L "$HOME/.gitconfig" ]] && return 0
	echo "create  ~/.gitconfig (empty, takes git config --global writes)"
	run touch "$HOME/.gitconfig"
}

# bat loads ~/.config/bat/themes only from its cache, so rebuild the cache when
# there is none or a tracked theme is newer than it. A failed build only warns:
# bat then keeps its built-in themes.
build_bat_cache() {
	local themes="$REPO/.config/bat/themes" cache
	[[ -d "$themes" ]] && command -v bat >/dev/null || return 0
	cache=$(bat --cache-dir 2>/dev/null) || return 0
	if [[ -f "$cache/themes.bin" ]] &&
		[[ -z "$(find "$themes" -name '*.tmTheme' -newer "$cache/themes.bin" 2>/dev/null)" ]]; then
		return 0
	fi
	echo "build   bat cache (themes from ~/.config/bat/themes)"
	run bat cache --build >/dev/null || echo "warning: bat cache --build failed" >&2
}

# fresh: the target directory was just created (or will be, on dry-run) so it is empty.
link_children() {
	local rel=$1 fresh=${2:-} path child
	for path in "$REPO${rel:+/$rel}"/* "$REPO${rel:+/$rel}"/.[!.]* "$REPO${rel:+/$rel}"/..?*; do
		[[ -e "$path" || -L "$path" ]] || continue
		child="${rel:+$rel/}${path##*/}"
		is_ignored "$child" && continue
		if ! is_tracked "$child"; then
			[[ $DRY_RUN -eq 0 ]] || echo "skip    ~/$child (untracked)"
			skipped=$((skipped + 1))
			continue
		fi
		link_entry "$child" "$fresh"
	done
}

main() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-n | --dry-run) DRY_RUN=1 ;;
		-h | --help)
			usage
			return 0
			;;
		*)
			usage
			return 2
			;;
		esac
		shift
	done

	[[ $DRY_RUN -eq 1 ]] && echo "(dry-run: nothing changed)"
	# The which-key plugin uses GNU realpath, including --relative-to.
	# Homebrew keeps it keg-only under gnubin; use the same paths as tmux.
	if [[ $(uname -s) == Darwin ]]; then
		export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/usr/local/opt/coreutils/libexec/gnubin:$PATH"
		if ! realpath --relative-to=/ / >/dev/null 2>&1; then
			if [[ $DRY_RUN -eq 1 ]]; then
				echo "prerequisite: brew install coreutils (required by tmux-which-key)"
			elif command -v brew >/dev/null; then
				brew install coreutils
				realpath --relative-to=/ / >/dev/null 2>&1 || {
					echo "GNU realpath missing after installing coreutils; add its libexec/gnubin to PATH" >&2
					return 1
				}
			else
				echo "tmux-which-key requires GNU realpath: install Homebrew, then brew install coreutils" >&2
				return 1
			fi
		fi
	fi
	load_tracked
	link_children ""
	ensure_gitconfig
	build_bat_cache
	# Global Claude instructions live outside the repo-only .claude directory.
	if [[ -f "$REPO/.config/agents/CLAUDE.md" ]]; then
		link_entry .claude/CLAUDE.md "" "$REPO/.config/agents/CLAUDE.md"
	fi
	if [[ -x "$REPO/.local/bin/install-agent-statusline" ]]; then
		local -a status_args=(--home "$HOME")
		[[ $DRY_RUN -eq 0 ]] || status_args+=(--check)
		"$REPO/.local/bin/install-agent-statusline" "${status_args[@]}" >/dev/null
	fi
	echo "done: $linked linked, $backed_up backed up, $unchanged already linked, $skipped untracked skipped"
	if [[ $backed_up -gt 0 ]]; then
		echo "backups in $BACKUP_DIR"
	fi
}

main "$@"
