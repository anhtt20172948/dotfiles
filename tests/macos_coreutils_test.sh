#!/usr/bin/env bash
# Exercise macOS setup without Homebrew, downloads, or changes to the real HOME.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" COREUTILS_PROBE="$TMP/coreutils-installed"
mkdir -p "$HOME"
uname() {
  case "${1:-}" in -s) echo Darwin ;; -m) echo arm64 ;; *) command uname "$@" ;; esac
}
realpath() { [[ -f $COREUTILS_PROBE ]] && echo .; }
brew() {
  [[ $* == 'install coreutils' ]] || return 1
  touch "$COREUTILS_PROBE"
}
export -f uname realpath brew
bash "$ROOT/install.sh" -n >"$TMP/dry-run"
[[ ! -e $COREUTILS_PROBE ]] || { echo 'dry-run installed coreutils' >&2; exit 1; }
grep -q 'brew install coreutils' "$TMP/dry-run"
bash "$ROOT/install.sh" >"$TMP/install"
[[ -f $COREUTILS_PROBE ]] || { echo 'macOS setup did not install coreutils' >&2; exit 1; }
rm "$COREUTILS_PROBE"
# Workflow-only setup must satisfy the same prerequisite before installing tools.
# shellcheck disable=SC2329 # These stubs are invoked by the sourced check_deps.
(
  # shellcheck source=/dev/null
  source "$ROOT/.local/bin/install_agent_workflow"
  gh() { return 0; }
  node() { echo 24; }
  npm() { return 0; }
  npx() { return 0; }
  check_deps
)
[[ -f $COREUTILS_PROBE ]] || { echo 'workflow setup did not install coreutils' >&2; exit 1; }
echo 'macOS coreutils setup: OK'
