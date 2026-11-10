#!/usr/bin/env bash
# Lint + test for dotfiles. One entry point for humans and the no-mistakes gate
# (.no-mistakes.yaml calls `tests/run.sh lint` / `tests/run.sh test`).
#
#   tests/run.sh lint   shellcheck the clean scripts (LINT_FILES list), then
#                       actionlint, taplo and yamllint on every tracked workflow,
#                       TOML and YAML file. A linter that is not installed is
#                       SKIPped; LINT_STRICT=1 (CI) makes it fail instead.
#   tests/run.sh test   run every tests/*.lua in headless nvim, tests/*_test.sh and
#                       tests/test_material_folder_icons.py (explicit SKIP when
#                       python 3.11+/luac is missing). Failing cases print their log;
#                       TEST_LOG_DIR keeps per-case logs.
#   tests/run.sh        both
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# The no-mistakes daemon does not read .zshrc: nvim (install_neovim) lives in ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

# Only scripts that pass shellcheck. The legacy install_neovim and hypr scripts
# are not clean yet -> add them when they are fixed.
LINT_FILES=(
	.github/install-ci-tools.sh
	.config/tmux/scripts/*.sh
	docs/demo/render.sh
	.local/bin/ai-acct
	.local/bin/ai-acct-claude
	.local/bin/agent-statusline-claude
	.local/bin/dotfiles-diagnose
	.local/bin/install_agent_workflow
	.local/bin/install_zsh
	.local/bin/show
	.local/bin/download
	install.sh
	tests/*_test.sh
	tests/run.sh
	tests/smoke/*.sh
)

# Often only mason ships the linters, and they are not on PATH.
# Prints the path of a linter from PATH or Mason's bin directory.
find_tool() {
	command -v "$1" 2>/dev/null && return
	local mason="$HOME/.local/share/nvim/mason/bin/$1"
	[[ -x "$mason" ]] && printf '%s\n' "$mason" && return
	return 1
}

# A missing optional linter: SKIP locally, fail under LINT_STRICT=1.
missing_linter() {
	if [[ "${LINT_STRICT:-0}" == 1 ]]; then
		echo "lint: $1 not found (LINT_STRICT=1)" >&2
		return 1
	fi
	echo "SKIP $1 (not installed: $2)"
}

# Tracked files matching the git pathspecs, NUL-separated.
tracked() {
	git ls-files -z -- "$@"
}

run_lint() {
	local sc
	sc=$(find_tool shellcheck) || {
		echo "shellcheck not found (pacman -S shellcheck)" >&2
		return 1
	}
	# Skip missing files (older branch / unmatched glob) instead of letting shellcheck error.
	local -a files=()
	local f
	for f in "${LINT_FILES[@]}"; do
		[[ -f "$f" ]] && files+=("$f")
	done
	# Do not rely on set -e: in `run_lint && run_test` bash disables errexit for the whole
	# function body, so a failing lint would still print OK.
	"$sc" --severity=style -x "${files[@]}" || return 1
	echo "lint: shellcheck OK (${#files[@]} files)"
	run_actionlint "$sc" && run_taplo && run_yamllint
}

# Workflows, with shellcheck on their run: scripts.
run_actionlint() {
	local tool
	tool=$(find_tool actionlint) || {
		missing_linter actionlint "pacman -S actionlint"
		return
	}
	"$tool" -shellcheck "$1" -pyflakes= || return 1
	echo "lint: actionlint OK"
}

# TOML syntax and formatting (.taplo.toml). Schemas are skipped: they are
# fetched from the network and track upstream's latest release.
run_taplo() {
	local tool
	tool=$(find_tool taplo) || {
		missing_linter taplo "pacman -S taplo-cli"
		return
	}
	local -a files=()
	local f
	while IFS= read -r -d '' f; do files+=("$f"); done < <(tracked '*.toml')
	RUST_LOG=warn "$tool" fmt --check "${files[@]}" || {
		echo "lint: run \`taplo fmt\` on the files above" >&2
		return 1
	}
	RUST_LOG=warn "$tool" lint --no-schema "${files[@]}" || return 1
	echo "lint: taplo OK (${#files[@]} files)"
}

run_yamllint() {
	local tool
	tool=$(find_tool yamllint) || {
		missing_linter yamllint "pacman -S yamllint"
		return
	}
	local -a files=()
	local f
	while IFS= read -r -d '' f; do files+=("$f"); done < <(tracked '*.yml' '*.yaml')
	"$tool" --strict "${files[@]}" || return 1
	echo "lint: yamllint OK (${#files[@]} files)"
}

# macOS has no GNU timeout: perl's alarm (always present) does the same job.
with_timeout() {
	local secs=$1
	shift
	if command -v timeout >/dev/null; then
		timeout "$secs" "$@"
	else
		perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$secs" "$@"
	fi
}

# Run one case in its own HOME/XDG; the log stays at $LOG_DIR/<name>.log and prints on failure
# (on pass only the `skip:` lines are printed).
#   run_case <name> <command...>
# A case gets CASE_TIMEOUT seconds (TEST_CASE_TIMEOUT overrides). The slowest,
# claude_mod_test.sh, spends 60-100 s in `claude plugin test` on a loaded host,
# so 120 s timed it out intermittently; a timeout is reported as one.
CASE_TIMEOUT=${TEST_CASE_TIMEOUT:-300}
run_case() {
	local name=$1 status=0
	shift
	local case_dir="$CFG/$name" log="$LOG_DIR/$name.log"
	mkdir -p "$case_dir/home" "$case_dir/config" "$case_dir/cache" "$case_dir/data" "$case_dir/state"
	HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/config" XDG_CACHE_HOME="$case_dir/cache" \
		XDG_DATA_HOME="$case_dir/data" XDG_STATE_HOME="$case_dir/state" CODEX_HOME="$case_dir/home/.codex" \
		TMUX='' with_timeout "$CASE_TIMEOUT" "$@" >"$log" 2>&1 || status=$?
	if [[ $status -eq 0 ]]; then
		echo "ok   $name"
		sed -n 's/^skip:/     | skip:/p' "$log"
	else
		# GNU timeout exits 124; perl's alarm kills with SIGALRM (128 + 14).
		if [[ $status -eq 124 || $status -eq 142 ]]; then
			echo "FAIL $name (timed out after ${CASE_TIMEOUT}s; rerun: TMUX= $*)"
		else
			echo "FAIL $name (rerun: TMUX= $*)"
		fi
		sed 's/^/     | /' "$log"
		FAILED=1
	fi
}

# Cases that need extra tools: when missing, report an explicit SKIP, never a silent pass.
python_has_tomllib() {
	python3 -c 'import tomllib' >/dev/null 2>&1
}

run_test() {
	command -v nvim >/dev/null || {
		echo "nvim not found" >&2
		return 1
	}
	# Empty XDG_CONFIG_HOME: otherwise runtimepath holds ~/.config/nvim (the linked
	# copy) and require() loads code from there instead of this checkout/worktree.
	CFG=$(mktemp -d)
	# TEST_LOG_DIR lets CI upload per-case logs; defaults to a temp directory.
	LOG_DIR=${TEST_LOG_DIR:-$CFG/logs}
	mkdir -p "$LOG_DIR"
	FAILED=0
	local t
	for t in tests/*.lua; do
		# Async tests need the event loop -> luafile; -l exits before timers fire.
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
