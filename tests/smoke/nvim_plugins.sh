#!/usr/bin/env bash
# Real-plugin smoke test for the Neovim config. Unlike tests/*.lua (stubs, no
# network), this clones every plugin and boots the full config.
#
#   tests/smoke/nvim_plugins.sh [check|update]
#
#   check   Install the plugins pinned in .config/nvim/lazy-lock.json into a
#           throwaway HOME/XDG tree, boot the config headless and fail on any
#           error message. Then boot SMOKE_RUNS more times and record the median
#           lazy.nvim startup time against SMOKE_BUDGET_MS. A last boot opens
#           tests/smoke/fixtures/* (one file per configured treesitter
#           language) and fails on any parse, highlight or injection error.
#   update  Same, but run `Lazy! update` instead of restoring the lockfile. When
#           the updated plugins boot cleanly, copy the new lazy-lock.json back
#           into the repo and list the changed plugins in lock-changes.md.
#
# Output goes to SMOKE_OUT (default: a temp dir): boot-*.json probe reports,
# boot-*.log, startuptime.log, startup.json and summary.md.
# Exit status: 0 clean, 1 boot errors (or setup failure), 2 usage.
# The startup budget never changes the exit status; CI checks startup.json.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MODE=${1:-check}
case "$MODE" in
check | update) ;;
*)
	echo "usage: tests/smoke/nvim_plugins.sh [check|update]" >&2
	exit 2
	;;
esac

RUNS=${SMOKE_RUNS:-5}
BUDGET_MS=${SMOKE_BUDGET_MS:-250}
OUT=${SMOKE_OUT:-$(mktemp -d)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

for tool in nvim git jq; do
	command -v "$tool" >/dev/null || {
		echo "$tool not found" >&2
		exit 1
	}
done

# A private HOME/XDG tree. The config is copied, not linked, so lazy.nvim
# rewriting lazy-lock.json never touches the checkout.
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data"
export XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
# Workstation mode even over SSH: on a server lazy.nvim writes a private lock
# (configs/lazy_lock.lua), and `update` copies the config's lock back.
export DOTFILES_HOST_ROLE=workstation
cp -R "$ROOT/.config/nvim" "$XDG_CONFIG_HOME/nvim"
LOCK="$XDG_CONFIG_HOME/nvim/lazy-lock.json"
LAZY_DIR="$XDG_DATA_HOME/nvim/lazy"
PROBE="$ROOT/tests/smoke/nvim_probe.lua"
cd "$WORK"

# init.lua would clone lazy.nvim's stable branch, and lazy.nvim does not restore
# itself; bootstrap it at the locked commit instead.
bootstrap_lazy() {
	local commit
	commit=$(jq -r '."lazy.nvim".commit' "$LOCK")
	git clone --quiet --filter=blob:none https://github.com/folke/lazy.nvim.git "$LAZY_DIR/lazy.nvim"
	git -C "$LAZY_DIR/lazy.nvim" checkout --quiet "$commit"
}

# The first start installs missing plugins while the config is loading, so
# configs run before their plugins exist; its errors are expected and only logged.
install_plugins() {
	local cmd=restore
	[[ "$MODE" == update ]] && cmd=update
	echo "== Lazy! $cmd"
	nvim --headless "+Lazy! $cmd" +qa >"$OUT/install.log" 2>&1 || true
	nvim --headless "+Lazy! $cmd" +qa >>"$OUT/install.log" 2>&1
	# Parsers the treesitter spec ensures, compiled synchronously so boots do not
	# race their background install.
	nvim --headless \
		"+lua local P = require('lazy.core.plugin'); local p = require('lazy.core.config').plugins['nvim-treesitter']; vim.cmd('TSInstallSync! ' .. table.concat(P.values(p, 'opts', false).ensure_installed, ' '))" \
		+qa >>"$OUT/install.log" 2>&1
}

# One boot under the probe; fails on any error the probe or Neovim's own
# output reported.
boot() {
	local name=$1 status=0
	shift
	SMOKE_REPORT="$OUT/$name.json" nvim --headless "$@" --cmd "luafile $PROBE" >"$OUT/$name.log" 2>&1 || status=$?
	if [[ $status -ne 0 ]] || grep -Eq '(^|[^[:alnum:]])(E[0-9]+:|Error)' "$OUT/$name.log"; then
		echo "FAIL $name (exit $status)"
		[[ -f "$OUT/$name.json" ]] && jq -r '.errors[] | "  [\(.source)] \(.message)"' "$OUT/$name.json"
		sed 's/^/  | /' "$OUT/$name.log"
		return 1
	fi
	# A plugin calling :qa or os.exit(0) before VeryLazy ends the boot without a report.
	if [[ ! -s "$OUT/$name.json" ]]; then
		echo "FAIL $name (Neovim exited before the probe wrote its report)"
		sed 's/^/  | /' "$OUT/$name.log"
		return 1
	fi
	echo "ok   $name ($(jq -r '.lazy.startuptime_ms | floor' "$OUT/$name.json") ms)"
}

summarize() {
	local median
	median=$(jq -s 'map(.lazy.startuptime_ms) | sort | .[length / 2 | floor] | floor' "$OUT"/boot-run-*.json)
	jq -n --argjson median "$median" --argjson budget "$BUDGET_MS" --argjson runs "$RUNS" \
		--arg nvim "$(jq -r .nvim "$OUT/boot-run-1.json")" \
		--argjson loaded "$(jq .lazy.loaded "$OUT/boot-run-1.json")" \
		--argjson count "$(jq .lazy.count "$OUT/boot-run-1.json")" \
		'{nvim: $nvim, runs: $runs, median_ms: $median, budget_ms: $budget, within_budget: ($median <= $budget), loaded: $loaded, count: $count}' \
		>"$OUT/startup.json"
	{
		echo "### Neovim real-plugin smoke ($MODE)"
		echo
		echo "| Neovim | Plugins loaded at startup | Median startup ($RUNS boots) | Budget |"
		echo "| --- | --- | --- | --- |"
		jq -r '"| \(.nvim) | \(.loaded)/\(.count) | \(.median_ms) ms | \(.budget_ms) ms \(if .within_budget then "ok" else "over" end) |"' "$OUT/startup.json"
	} >"$OUT/summary.md"
	cat "$OUT/summary.md"
}

# Markdown list of plugins whose locked commit changed, with compare links.
lock_changes() {
	local old=$1 new=$2 name from to url
	jq -r --slurpfile new "$new" \
		'to_entries[] | select($new[0][.key] != null and $new[0][.key].commit != .value.commit) | "\(.key) \(.value.commit) \($new[0][.key].commit)"' \
		"$old" | while read -r name from to; do
		url=$(git -C "$LAZY_DIR/$name" remote get-url origin 2>/dev/null || true)
		url=${url%.git}
		if [[ "$url" == https://github.com/* ]]; then
			echo "- [$name]($url/compare/$from...$to) \`${from:0:7}\` -> \`${to:0:7}\`"
		else
			echo "- $name \`${from:0:7}\` -> \`${to:0:7}\`"
		fi
	done
	jq -r --slurpfile new "$new" 'keys - ($new[0] | keys) | .[] | "- \(.) removed"' "$old"
	jq -r --slurpfile old "$old" 'keys - ($old[0] | keys) | .[] | "- \(.) added"' "$new"
}

# Every installed plugin must sit at its locked commit after a restore.
# Lockfile entries without a checkout are plugins no longer in the spec.
verify_restore() {
	local name commit head bad=0
	while read -r name commit; do
		[[ -d "$LAZY_DIR/$name" ]] || continue
		head=$(git -C "$LAZY_DIR/$name" rev-parse HEAD)
		if [[ "$head" != "$commit" ]]; then
			echo "FAIL restore: $name is at $head, lazy-lock.json pins $commit"
			bad=1
		fi
	done < <(jq -r 'to_entries[] | "\(.key) \(.value.commit)"' "$ROOT/.config/nvim/lazy-lock.json")
	[[ $bad -eq 0 ]] && echo "ok   restore ($(find "$LAZY_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') plugins at their locked commits)"
	return "$bad"
}

bootstrap_lazy
install_plugins
[[ "$MODE" == update ]] || verify_restore || exit 1

# The first boot also runs lazy.nvim's update checker once; it is not timed.
failed=0
boot boot-warmup || failed=1
for i in $(seq 1 "$RUNS"); do
	extra=()
	[[ $i -eq $RUNS ]] && extra=(--startuptime "$OUT/startuptime.log")
	boot "boot-run-$i" ${extra[@]+"${extra[@]}"} || failed=1
done
# Highlight and injection queries only run on a redraw or a forced parse, and a
# boot with no file open runs neither. Open every fixture in a tab so FileType
# attaches treesitter, and let the probe force the parse (SMOKE_FILES=1).
SMOKE_FILES=1 boot boot-files -p "$ROOT"/tests/smoke/fixtures/* || failed=1
[[ $failed -eq 0 ]] || exit 1
summarize

if [[ "$MODE" == update ]]; then
	lock_changes "$ROOT/.config/nvim/lazy-lock.json" "$LOCK" >"$OUT/lock-changes.md"
	cp "$LOCK" "$ROOT/.config/nvim/lazy-lock.json"
	echo "== lazy-lock.json changes"
	cat "$OUT/lock-changes.md"
fi
