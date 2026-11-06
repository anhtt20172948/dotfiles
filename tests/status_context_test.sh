#!/usr/bin/env bash
# status-context.sh: the git / SSH segment of the tmux status bar.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/.config/tmux/scripts/status-context.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/bin"
# A git identity of the test's own, never the developer's.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
unset SSH_CONNECTION

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  [[ $2 == "$3" ]] || fail "$1: expected '$2', got '$3'"
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  [[ $3 == *"$2"* ]] || fail "$1: expected to contain '$2', got '$3'"
}

repo="$TMP/repo with space"
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m init

# Outside any repository nothing may be printed, not even a separator.
plain="$TMP/plain"
mkdir "$plain"
assert_eq "no output outside a repo" "" "$(bash "$SCRIPT" "$plain" /dev/pts/0 zsh)"
assert_eq "no output for a missing directory" "" "$(bash "$SCRIPT" "$TMP/gone" /dev/pts/0 zsh)"
assert_eq "no output without a path" "" "$(bash "$SCRIPT" "" "" "")"

# Clean repository: branch only, no dirty marker.
out=$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh)
assert_contains "branch name" " main" "$out"
[[ $out != *●* ]] || fail "clean repo shows a dirty marker: $out"

# Untracked and modified files both count as dirty.
touch "$repo/new"
assert_contains "untracked file is dirty" "●" "$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh)"
git -C "$repo" add new
git -C "$repo" commit -q -m new
assert_eq "committed repo is clean again" "" "$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh | grep -o '●' || true)"
echo change >"$repo/new"
assert_contains "modified file is dirty" "●" "$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh)"
git -C "$repo" checkout -q -- new

# Ahead/behind counts against an upstream.
remote="$TMP/remote.git"
git init -q --bare "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin main
git -C "$repo" commit -q --allow-empty -m ahead
out=$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh)
assert_contains "ahead count" "⇡1" "$out"
[[ $out != *⇣* ]] || fail "ahead-only repo shows a behind marker: $out"

# Detached HEAD shows the short object id rather than "(detached)".
git -C "$repo" checkout -q --detach
out=$(bash "$SCRIPT" "$repo" /dev/pts/0 zsh)
short=$(git -C "$repo" rev-parse --short=7 HEAD)
assert_contains "detached short id" "$short" "$out"
[[ $out != *detached* ]] || fail "detached HEAD leaks the literal '(detached)': $out"

# A subdirectory of the repository resolves to the same branch.
git -C "$repo" checkout -q main
mkdir "$repo/sub"
assert_contains "subdirectory" " main" "$(bash "$SCRIPT" "$repo/sub" /dev/pts/0 zsh)"

# SSH destination: the first positional argument after options that take a value.
cat >"$TMP/bin/ps" <<'PS'
#!/usr/bin/env bash
printf '%s\n' "-zsh" "$FAKE_SSH_LINE"
PS
chmod +x "$TMP/bin/ps"
ssh_segment() {
  FAKE_SSH_LINE=$1 PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$plain" /dev/pts/9 "${2:-ssh}"
}
assert_contains "plain host" "󰣀 build-box" "$(ssh_segment 'ssh build-box')"
assert_contains "user@host strips the user" "󰣀 jetson.lan" "$(ssh_segment 'ssh anh@jetson.lan')"
assert_contains "options with values are skipped" "󰣀 srv" "$(ssh_segment 'ssh -p 2222 -i /k/id -o StrictHostKeyChecking=no u@srv uptime')"
assert_contains "flags without values are skipped" "󰣀 srv" "$(ssh_segment 'ssh -A -t srv')"
assert_contains "absolute ssh path" "󰣀 srv" "$(ssh_segment '/usr/bin/ssh srv')"
assert_eq "no segment when the foreground command is not ssh" "" "$(ssh_segment 'ssh srv' vim)"
assert_eq "no segment when ps finds no ssh" "" "$(ssh_segment 'vim file')"

# A tmux server that itself sits behind SSH shows this host's name.
out=$(SSH_CONNECTION='1.2.3.4 5 6.7.8.9 22' bash "$SCRIPT" "$plain" /dev/pts/0 zsh)
host=$(uname -n)
assert_contains "remote server host" "󰣀 ${host%%.*} " "$out"
echo "status_context_test: OK"
