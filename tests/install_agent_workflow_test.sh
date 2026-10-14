#!/usr/bin/env bash
# install_firstmate: clone vào $FIRSTMATE_DIR đã có sẵn link của dotfiles mà không
# xoá gì. Dùng git remote cục bộ và $HOME tạm, không đụng mạng.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
REPO="$TMP/repo"
export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

fail() { echo "FAIL: $*" >&2; exit 1; }

# Remote giả: commit đầu là bản pin, commit sau là main.
REMOTE="$TMP/remote"
git init -q "$REMOTE"
printf 'config/\ndata/\n' >"$REMOTE/.gitignore"
printf 'one\n' >"$REMOTE/AGENTS.md"
git -C "$REMOTE" add -A && git -C "$REMOTE" commit -q -m one
PIN=$(git -C "$REMOTE" rev-parse HEAD)
printf 'two\n' >"$REMOTE/AGENTS.md"
mkdir "$REMOTE/bin" && echo run >"$REMOTE/bin/tool"
git -C "$REMOTE" add -A && git -C "$REMOTE" commit -q -m two

mkdir -p "$REPO/.local/bin" "$REPO/.local/share/firstmate/config" "$REPO/.local/share/firstmate/data" "$HOME"
cp "$ROOT/.local/bin/install_agent_workflow" "$REPO/.local/bin/install_agent_workflow"
echo dispatch >"$REPO/.local/share/firstmate/config/crew-dispatch.json"
echo captain >"$REPO/.local/share/firstmate/data/captain.md"

export FIRSTMATE_DIR="$HOME/.local/share/firstmate" FIRSTMATE_REPO="$REMOTE" FIRSTMATE_REV="$PIN"
# shellcheck source=/dev/null
source "$REPO/.local/bin/install_agent_workflow"

link_dotfiles() {
	mkdir -p "$FIRSTMATE_DIR/config" "$FIRSTMATE_DIR/data"
	ln -s "$REPO/.local/share/firstmate/config/crew-dispatch.json" "$FIRSTMATE_DIR/config/crew-dispatch.json"
	ln -s ../../../../../repo/.local/share/firstmate/data/captain.md "$FIRSTMATE_DIR/data/captain.md"
}

assert_pinned() {
	[[ $(git -C "$FIRSTMATE_DIR" rev-parse HEAD) == "$PIN" ]] || fail "$1: not at pinned rev"
	[[ $(cat "$FIRSTMATE_DIR/AGENTS.md") == one ]] || fail "$1: worktree not at pinned rev"
	[[ ! -e "$FIRSTMATE_DIR/bin/tool" ]] || fail "$1: file from newer commit present"
	[[ -z $(git -C "$FIRSTMATE_DIR" status --porcelain) ]] || fail "$1: dirty tree"
}

assert_links_kept() {
	local f
	for f in config/crew-dispatch.json data/captain.md; do
		[[ -L "$FIRSTMATE_DIR/$f" ]] || fail "$1: $f is no longer a symlink"
	done
	[[ $(cat "$FIRSTMATE_DIR/config/crew-dispatch.json") == dispatch ]] || fail "$1: dispatch content"
	[[ $(cat "$FIRSTMATE_DIR/data/captain.md") == captain ]] || fail "$1: captain content"
}

reset_dir() { rm -rf "$FIRSTMATE_DIR" "$FIRSTMATE_DIR".clone.*; }

# 1. Thư mục chưa có.
reset_dir
install_firstmate >/dev/null 2>&1
assert_pinned absent

# 2. Chỉ có link của dotfiles (đúng ca lỗi gốc), link tuyệt đối và tương đối.
reset_dir
link_dotfiles
install_firstmate >/dev/null 2>&1
assert_pinned links
assert_links_kept links
[[ -z $(ls -d "$FIRSTMATE_DIR".clone.* 2>/dev/null) ]] || fail 'links: temp clone left behind'
# Chạy lại vẫn idempotent.
install_firstmate >/dev/null 2>&1
assert_pinned rerun
assert_links_kept rerun

# 3. File thật lạ: không đụng gì, cảnh báo nêu đúng đường dẫn.
reset_dir
link_dotfiles
echo mine >"$FIRSTMATE_DIR/config/private.json"
out=$(install_firstmate 2>&1) || fail 'foreign: step must not abort the installer'
[[ ! -e "$FIRSTMATE_DIR/.git" ]] || fail 'foreign: .git created'
grep -q "$FIRSTMATE_DIR/config/private.json" <<<"$out" || fail 'foreign: warning misses offending path'
[[ $(cat "$FIRSTMATE_DIR/config/private.json") == mine ]] || fail 'foreign: real file touched'
assert_links_kept foreign

# 4. Symlink trỏ chỗ khác cũng bị coi là lạ.
reset_dir
mkdir -p "$FIRSTMATE_DIR/config" "$TMP/elsewhere"
echo else >"$TMP/elsewhere/x.json"
ln -s "$TMP/elsewhere/x.json" "$FIRSTMATE_DIR/config/x.json"
out=$(install_firstmate 2>&1) || fail 'foreign link: step aborted'
[[ ! -e "$FIRSTMATE_DIR/.git" ]] || fail 'foreign link: .git created'
grep -q "$FIRSTMATE_DIR/config/x.json" <<<"$out" || fail 'foreign link: warning misses path'
[[ -L "$FIRSTMATE_DIR/config/x.json" ]] || fail 'foreign link: link touched'

# 5. Link nằm đè đường dẫn firstmate track: không clone, không mất link.
reset_dir
mkdir -p "$FIRSTMATE_DIR"
ln -s "$REPO/.local/share/firstmate/data/captain.md" "$FIRSTMATE_DIR/AGENTS.md"
out=$(install_firstmate 2>&1) || fail 'tracked path: step aborted'
[[ ! -e "$FIRSTMATE_DIR/.git" ]] || fail 'tracked path: .git created'
grep -q 'AGENTS.md' <<<"$out" || fail 'tracked path: warning misses path'
[[ -L "$FIRSTMATE_DIR/AGENTS.md" ]] || fail 'tracked path: link touched'

echo "install_agent_workflow_test: OK"
