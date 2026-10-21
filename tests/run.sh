#!/usr/bin/env bash
# Lint + test cho dotfiles. Một lối vào cho cả người và gate no-mistakes
# (.no-mistakes.yaml gọi `tests/run.sh lint` / `tests/run.sh test`).
#
#   tests/run.sh lint   shellcheck các script đã sạch (danh sách LINT_FILES)
#   tests/run.sh test   chạy mọi tests/*.lua trong nvim headless, tests/*_test.sh và
#                       tests/test_material_folder_icons.py (SKIP rõ ràng nếu thiếu
#                       python 3.11+/luac). Case fail in log ngay; TEST_LOG_DIR giữ log từng case.
#   tests/run.sh        cả hai
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Daemon no-mistakes không đọc .zshrc: nvim (install_neovim) nằm ở ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

# Chỉ các script đang qua shellcheck. Script cũ ở .local/bin (download, show,
# install_neovim) và hypr chưa sạch -> thêm vào khi sửa.
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

# macOS không có GNU timeout: alarm của perl (có sẵn) làm cùng việc.
with_timeout() {
	local secs=$1
	shift
	if command -v timeout >/dev/null; then
		timeout "$secs" "$@"
	else
		perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$secs" "$@"
	fi
}

# Chạy một case trong HOME/XDG riêng; log giữ ở $LOG_DIR/<tên>.log, in ra khi fail.
#   run_case <tên> <lệnh...>
run_case() {
	local name=$1
	shift
	local case_dir="$CFG/$name" log="$LOG_DIR/$name.log"
	mkdir -p "$case_dir/home" "$case_dir/config" "$case_dir/cache" "$case_dir/data" "$case_dir/state"
	if HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/config" XDG_CACHE_HOME="$case_dir/cache" \
		XDG_DATA_HOME="$case_dir/data" XDG_STATE_HOME="$case_dir/state" CODEX_HOME="$case_dir/home/.codex" \
		TMUX='' with_timeout 120 "$@" >"$log" 2>&1; then
		echo "ok   $name"
	else
		echo "FAIL $name (rerun: TMUX= $*)"
		sed 's/^/     | /' "$log"
		FAILED=1
	fi
}

# Case cần thêm công cụ: thiếu thì báo SKIP rõ ràng, không im lặng coi như pass.
python_has_tomllib() {
	python3 -c 'import tomllib' >/dev/null 2>&1
}

run_test() {
	command -v nvim >/dev/null || {
		echo "nvim not found" >&2
		return 1
	}
	# XDG_CONFIG_HOME rỗng: nếu không, runtimepath chứa ~/.config/nvim (bản đã
	# link) và require() nạp code ở đó thay vì code của checkout/worktree này.
	CFG=$(mktemp -d)
	# TEST_LOG_DIR cho CI upload log từng case; mặc định nằm trong thư mục tạm.
	LOG_DIR=${TEST_LOG_DIR:-$CFG/logs}
	mkdir -p "$LOG_DIR"
	FAILED=0
	local t
	for t in tests/*.lua; do
		# Test bất đồng bộ cần event loop -> luafile; -l thoát trước khi timer chạy.
		if grep -q 'luafile' "$t"; then
			run_case "${t##*/}" nvim --headless -u NONE -i NONE -c "luafile $t"
		else
			run_case "${t##*/}" nvim --headless -u NONE -i NONE -l "$t" "$ROOT"
		fi
	done
	for t in tests/*_test.sh; do
		[[ -f "$t" ]] || continue
		run_case "${t##*/}" bash "$t"
	done
	t=tests/test_material_folder_icons.py
	if ! command -v python3 >/dev/null || ! python_has_tomllib; then
		echo "SKIP ${t##*/} (needs python3 >= 3.11 with tomllib)"
	elif ! command -v luac >/dev/null; then
		echo "SKIP ${t##*/} (needs luac)"
	else
		run_case "${t##*/}" python3 "$t"
	fi
	[[ -n ${TEST_LOG_DIR:-} ]] || rm -rf "$LOG_DIR"
	rm -rf "$CFG"
	return "$FAILED"
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
