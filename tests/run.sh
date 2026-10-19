#!/usr/bin/env bash
# Lint + test cho dotfiles. Một lối vào cho cả người và gate no-mistakes
# (.no-mistakes.yaml gọi `tests/run.sh lint` / `tests/run.sh test`).
#
#   tests/run.sh lint   shellcheck các script đã sạch (danh sách LINT_FILES)
#   tests/run.sh test   chạy mọi tests/*.lua trong nvim headless và tests/*_test.sh
#   tests/run.sh        cả hai
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Daemon no-mistakes không đọc .zshrc: nvim (install_neovim) nằm ở ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

# Chỉ các script đang qua shellcheck. Script cũ ở .local/bin (download, show,
# install_neovim, install_linux_x86_64) và hypr chưa sạch -> thêm vào khi sửa.
LINT_FILES=(
	.config/tmux/scripts/*.sh
	.local/bin/ai-acct
	.local/bin/ai-acct-claude
	.local/bin/agent-statusline-claude
	.local/bin/install_agent_workflow
	.local/bin/install_zsh
	install.sh
	tests/*_test.sh
	tests/run.sh
)

# Bản shellcheck thường chỉ có của mason, không nằm trên PATH.
find_shellcheck() {
	command -v shellcheck 2>/dev/null && return
	local mason="$HOME/.local/share/nvim/mason/bin/shellcheck"
	[[ -x "$mason" ]] && printf '%s\n' "$mason" && return
	echo "shellcheck not found (pacman -S shellcheck)" >&2
	return 1
}

run_lint() {
	local sc
	sc=$(find_shellcheck) || return 1
	# Bỏ file chưa có (nhánh cũ / glob không khớp) thay vì để shellcheck báo lỗi.
	local -a files=()
	local f
	for f in "${LINT_FILES[@]}"; do
		[[ -f "$f" ]] && files+=("$f")
	done
	# Không dựa vào set -e: trong `run_lint && run_test` bash tắt errexit cho cả
	# thân hàm, lint fail vẫn in OK.
	"$sc" --severity=style -x "${files[@]}" || return 1
	echo "lint: OK (${#files[@]} files)"
}

run_test() {
	command -v nvim >/dev/null || {
		echo "nvim not found" >&2
		return 1
	}
	# XDG_CONFIG_HOME rỗng: nếu không, runtimepath chứa ~/.config/nvim (bản đã
	# link) và require() nạp code ở đó thay vì code của checkout/worktree này.
	local cfg
	cfg=$(mktemp -d)
	local failed=0 t case_dir
	for t in tests/*.lua; do
		local -a cmd
		# Test bất đồng bộ cần event loop -> luafile; -l thoát trước khi timer chạy.
		if grep -q 'luafile' "$t"; then
			cmd=(nvim --headless -u NONE -i NONE -c "luafile $t")
		else
			cmd=(nvim --headless -u NONE -i NONE -l "$t" "$ROOT")
		fi
		case_dir="$cfg/lua-${t##*/}"
		mkdir -p "$case_dir/home" "$case_dir/config" "$case_dir/cache" "$case_dir/data" "$case_dir/state"
		if HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/config" XDG_CACHE_HOME="$case_dir/cache" \
			XDG_DATA_HOME="$case_dir/data" XDG_STATE_HOME="$case_dir/state" CODEX_HOME="$case_dir/home/.codex" \
			TMUX='' timeout 120 "${cmd[@]}" >/dev/null 2>&1; then
			echo "ok   $t"
		else
			echo "FAIL $t (rerun: TMUX= ${cmd[*]})"
			failed=1
		fi
	done
	for t in tests/*_test.sh; do
		[[ -f "$t" ]] || continue
		case_dir="$cfg/shell-${t##*/}"
		mkdir -p "$case_dir/home" "$case_dir/config" "$case_dir/cache" "$case_dir/data" "$case_dir/state"
		if HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/config" XDG_CACHE_HOME="$case_dir/cache" \
			XDG_DATA_HOME="$case_dir/data" XDG_STATE_HOME="$case_dir/state" CODEX_HOME="$case_dir/home/.codex" \
			timeout 120 bash "$t" >/dev/null 2>&1; then
			echo "ok   $t"
		else
			echo "FAIL $t (rerun: bash $t)"
			failed=1
		fi
	done
	rm -rf "$cfg"
	return "$failed"
}

case "${1:-all}" in
lint) run_lint ;;
test) run_test ;;
all) run_lint && run_test ;;
*)
	echo "usage: tests/run.sh [lint|test]" >&2
	exit 2
	;;
esac
