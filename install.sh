#!/usr/bin/env bash
# Link dotfiles vào $HOME, không cần sudo hay stow (chỉ ln/mkdir/mv/readlink).
#
#   ./install.sh            tạo symlink
#   ./install.sh -n         dry-run: chỉ in việc sẽ làm
#
# Gập thư mục như stow: đích chưa có -> link nguyên thư mục
# (~/.config/nvim -> repo/.config/nvim); đích là thư mục thật -> đi vào trong
# và link từng con. File/symlink lạ đang chiếm chỗ được chuyển vào
# ~/.dotfiles-backup/<thời điểm>/, không bao giờ xoá. Chạy lại an toàn.
# ~/... trong chuỗi chỉ là nhãn hiển thị, không cần expand.
# shellcheck disable=SC2088
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd -P)
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

# Chỉ thuộc repo, không phải dotfile: không link ra $HOME. So với tên ở root repo
# (một .config/x/docs vẫn được link bình thường).
ROOT_IGNORE=(
	.git .gitignore .gitmodules
	docs tests .superpowers
	# Config Claude CẤP REPO (project skill, settings.local.json) - link ra
	# ~/.claude sẽ biến nó thành config toàn cục.
	.claude
	.no-mistakes.yaml
	install.sh
)

# Thư mục ứng dụng tự ghi vào (~/.local/bin nhận binary của install_*, DB/run
# log của no-mistakes, gnhf, treehouse): luôn là thư mục thật, không gập thành
# một symlink vào repo.
NO_FOLD=(
	.config .local .local/bin .local/share .local/state
	.local/share/firstmate .local/share/firstmate/config
	.no-mistakes .gnhf .config/treehouse
)

linked=0 backed_up=0 unchanged=0

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

# Mặc định ignore của stow (VCS, file backup của editor) ở mọi cấp, cộng
# README/LICENSE/COPYING và ROOT_IGNORE ở root.
is_ignored() {
	local rel=$1 name=${1##*/}
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

# Symlink đã trỏ đúng entry trong repo (tuyệt đối hay tương đối như stow tạo).
points_to_repo() {
	local dst=$1 src=$2
	[[ -L "$dst" && -e "$dst" ]] || return 1
	[[ "$(readlink -f -- "$dst")" == "$(readlink -f -- "$src")" ]]
}

# Thư mục chung (NO_FOLD) có thể là symlink tới chỗ khác ngoài repo, vd ~/.config
# trên ổ khác: đi vào trong thay vì chuyển cả nó vào backup.
is_foreign_dir() {
	local dst=$1
	[[ -L "$dst" && -d "$dst" ]] || return 1
	case "$(readlink -f -- "$dst")/" in
	"$REPO"/*) return 1 ;;
	esac
	return 0
}

# Dọn chỗ cho thư mục NO_FOLD: gỡ link stow cũ gập vào repo, file lạ vào backup.
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

# fresh: thư mục đích vừa được tạo (hoặc sẽ được tạo, khi dry-run) nên rỗng.
link_children() {
	local rel=$1 fresh=${2:-} path child
	for path in "$REPO${rel:+/$rel}"/* "$REPO${rel:+/$rel}"/.[!.]* "$REPO${rel:+/$rel}"/..?*; do
		[[ -e "$path" || -L "$path" ]] || continue
		child="${rel:+$rel/}${path##*/}"
		is_ignored "$child" && continue
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

	[[ $DRY_RUN -eq 1 ]] && echo "(dry-run: không thay đổi gì)"
	link_children ""
	# Global Claude instructions live outside the repo-only .claude directory.
	if [[ -f "$REPO/.config/agents/CLAUDE.md" ]]; then
		link_entry .claude/CLAUDE.md "" "$REPO/.config/agents/CLAUDE.md"
	fi
	echo "done: $linked linked, $backed_up backed up, $unchanged already linked"
	if [[ $backed_up -gt 0 ]]; then
		echo "backups in $BACKUP_DIR"
	fi
}

main "$@"
