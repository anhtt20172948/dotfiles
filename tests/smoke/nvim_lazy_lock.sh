#!/usr/bin/env bash
# End-to-end check that lazy.nvim on a server never writes the tracked
# .config/nvim/lazy-lock.json (configs/lazy_lock.lua), while the workstation
# keeps updating it.
#
#   tests/smoke/nvim_lazy_lock.sh
#
# Runs the checkout's lazy.nvim loader (configs/) with the real lazy.nvim at its
# locked commit (the only network access: one clone from GitHub) and a fixture
# plugin served from a local git repository with two commits. The config sits in
# its own git repository, linked into a throwaway HOME like install.sh does, so
# "the checkout stays clean" is checked with `git status`.
# Exit status: 0 pass, 1 failure.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for tool in nvim git jq; do
	command -v "$tool" >/dev/null || {
		echo "$tool not found" >&2
		exit 1
	}
done

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data"
export XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.invalid
export GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.invalid
unset DOTFILES_HOST_ROLE SSH_CONNECTION
SSH='10.0.0.1 51234 10.0.0.2 22'

# Fixture plugins served from local repositories. fixture.nvim gets commits
# OLD, NEW and NEWER as the scenario moves on; extra.nvim is added by a pull.
SRC="$WORK/src"
commit_fixture() {
	mkdir -p "$SRC/$1/lua"
	[[ -d "$SRC/$1/.git" ]] || git -C "$SRC/$1" init --quiet --initial-branch=main
	echo "return \"$2\"" >"$SRC/$1/lua/${1%.nvim}.lua"
	git -C "$SRC/$1" add -A && git -C "$SRC/$1" commit --quiet -m "$2"
	git -C "$SRC/$1" rev-parse HEAD
}
OLD=$(commit_fixture fixture.nvim old)
NEW=$(commit_fixture fixture.nvim new)
EXTRA=$(commit_fixture extra.nvim extra)

# lazy.nvim at the locked commit, where configs/lazy.lua looks for it (no bootstrap clone).
LAZY_COMMIT=$(jq -r '."lazy.nvim".commit' "$ROOT/.config/nvim/lazy-lock.json")
LAZY="$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
git clone --quiet --filter=blob:none https://github.com/folke/lazy.nvim.git "$LAZY"
git -C "$LAZY" checkout --quiet "$LAZY_COMMIT"

# The checkout: the real loader, a plugin spec with only fixture plugins
# (lazy.nvim is pinned so updates stay offline) and a tracked lock.
CHECKOUT="$WORK/checkout"
CONFIG="$CHECKOUT/.config/nvim"
mkdir -p "$CONFIG/lua/plugins"
cp -R "$ROOT/.config/nvim/lua/configs" "$CONFIG/lua/"
echo 'require("configs.lazy")' >"$CONFIG/init.lua"
cat >"$CONFIG/lua/plugins/fixture.lua" <<EOF
return {
	{ "folke/lazy.nvim", pin = true },
	{ name = "fixture.nvim", url = "$SRC/fixture.nvim" },
}
EOF
# lazy.nvim's own lockfile format, so a rewrite with the same pins is a no-op.
write_lock() {
	{
		echo '{'
		[[ -n "${2:-}" ]] && printf '  "extra.nvim": { "branch": "main", "commit": "%s" },\n' "$2"
		printf '  "fixture.nvim": { "branch": "main", "commit": "%s" },\n' "$1"
		printf '  "lazy.nvim": { "branch": "main", "commit": "%s" }\n' "$LAZY_COMMIT"
		echo '}'
	} >"$CONFIG/lazy-lock.json"
}
write_lock "$OLD"
git -C "$CHECKOUT" init --quiet --initial-branch=main
git -C "$CHECKOUT" add -A && git -C "$CHECKOUT" commit --quiet -m checkout
ln -s "$CONFIG" "$XDG_CONFIG_HOME/nvim"
TRACKED="$CONFIG/lazy-lock.json"
PRIVATE="$XDG_STATE_HOME/nvim/lazy-lock.json"
INSTALLED="$XDG_DATA_HOME/nvim/lazy/fixture.nvim"
cd "$WORK"

# nvim headless with the role environment given as NAME=VALUE arguments.
run_nvim() {
	local -a envs=()
	while [[ $# -gt 0 && "$1" =~ ^[A-Z_]+= ]]; do
		envs+=("$1")
		shift
	done
	env ${envs[@]+"${envs[@]}"} nvim --headless "$@" +qa >>"$WORK/nvim.log" 2>&1 ||
		fail "nvim $* exited non-zero: $(cat "$WORK/nvim.log")"
}
head_of() {
	git -C "$INSTALLED" rev-parse HEAD
}
lock_commit() {
	jq -r '."fixture.nvim".commit' "$1"
}
assert_checkout_clean() {
	local status
	status=$(git -C "$CHECKOUT" status --porcelain)
	[[ -z "$status" ]] || fail "$1: the checkout is dirty: $status
$(git -C "$CHECKOUT" diff)"
}

# The lockfile and update checker lazy.nvim runs with, for the given role environment.
options() {
	local probe="local o = require('lazy.core.config').options"
	probe+="; local f = assert(io.open('$WORK/options', 'w'))"
	probe+="; f:write(o.lockfile .. ' checker=' .. tostring(o.checker.enabled)); f:close()"
	rm -f "$WORK/options"
	run_nvim "$@" "+lua $probe"
	cat "$WORK/options"
}

# Server, first start: installs the missing fixture at the tracked pin.
run_nvim SSH_CONNECTION="$SSH"
[[ "$(head_of)" == "$OLD" ]] || fail "server install did not follow the tracked lock"
assert_checkout_clean "server first start"
got=$(options SSH_CONNECTION="$SSH")
[[ "$got" == "$PRIVATE checker=false" ]] || fail "server options: $got"
echo "ok   server: private lock, no update checker, install at the tracked pin"

# A pull bumps fixture.nvim and adds extra.nvim. The next start installs
# extra.nvim while fixture.nvim is still at OLD on disk; lazy.nvim then
# rewrites the lockfile with OLD, which used to dirty the tracked lock.
cat >"$CONFIG/lua/plugins/extra.lua" <<EOF
return { { name = "extra.nvim", url = "$SRC/extra.nvim" } }
EOF
write_lock "$NEW" "$EXTRA"
git -C "$CHECKOUT" add -A && git -C "$CHECKOUT" commit --quiet -m pull
run_nvim SSH_CONNECTION="$SSH"
[[ -d "$XDG_DATA_HOME/nvim/lazy/extra.nvim" ]] || fail "server start did not install extra.nvim"
[[ "$(head_of)" == "$OLD" ]] || fail "server start moved fixture.nvim without a restore"
assert_checkout_clean "server install after a pull"
echo "ok   server: installing a new plugin after a pull leaves the checkout clean"

# :Lazy restore moves the installed plugins to the pulled pins.
run_nvim SSH_CONNECTION="$SSH" '+Lazy! restore'
[[ "$(head_of)" == "$NEW" ]] || fail "server restore did not reach the tracked pin"
assert_checkout_clean "server restore"
echo "ok   server: restore follows the tracked lock"

# Upstream moves on; :Lazy sync updates, and only the private lock records it.
NEWER=$(commit_fixture fixture.nvim newer)
run_nvim SSH_CONNECTION="$SSH" '+Lazy! sync'
[[ "$(head_of)" == "$NEWER" ]] || fail "server sync did not update the fixture"
assert_checkout_clean "server sync"
[[ "$(lock_commit "$PRIVATE")" == "$NEWER" ]] || fail "server sync did not write the private lock"
echo "ok   server: sync writes only the private lock"

# The next start replaces the private lock; restore returns to the tracked pin.
run_nvim SSH_CONNECTION="$SSH" '+Lazy! restore'
[[ "$(head_of)" == "$NEW" ]] || fail "server restore did not return to the tracked lock"
assert_checkout_clean "server restore after sync"
echo "ok   server: the next start drops the private bump"

# Workstation: lazy.nvim's defaults, and :Lazy sync bumps the tracked lock.
got=$(options)
[[ "$got" == "$XDG_CONFIG_HOME/nvim/lazy-lock.json checker=true" ]] || fail "workstation options: $got"
run_nvim '+Lazy! sync'
[[ "$(head_of)" == "$NEWER" ]] || fail "workstation sync did not update the fixture"
[[ "$(lock_commit "$TRACKED")" == "$NEWER" ]] || fail "workstation sync did not bump the tracked lock"
echo "ok   workstation: sync bumps the tracked lock"
