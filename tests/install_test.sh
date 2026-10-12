#!/usr/bin/env bash
# Test install.sh trên một repo giả và một $HOME tạm.
# ~/... trong chuỗi chỉ là nhãn hiển thị, không cần expand.
# shellcheck disable=SC2088
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
REPO="$TMP/dotfiles"
export HOME="$TMP/home"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Đích phải là symlink trỏ đúng vào entry tương ứng trong repo.
assert_link() {
	[[ -L "$HOME/$1" ]] || fail "~/$1 is not a symlink"
	[[ "$(readlink -f "$HOME/$1")" == "$(readlink -f "$REPO/$1")" ]] ||
		fail "~/$1 -> $(readlink "$HOME/$1"), want $REPO/$1"
}

assert_real_dir() {
	[[ -d "$HOME/$1" && ! -L "$HOME/$1" ]] || fail "~/$1 is not a real directory"
}

assert_absent() {
	[[ ! -e "$HOME/$1" && ! -L "$HOME/$1" ]] || fail "~/$1 should not exist"
}

# Repo giả mô phỏng layout thật, gồm cả các entry chỉ thuộc repo.
mkdir -p "$REPO"/.config/{nvim/lua,tmux,yazi} "$REPO"/.local/bin \
	"$REPO"/{docs,tests,.claude,.git,.superpowers}
cp "$ROOT/install.sh" "$REPO/install.sh"
echo init >"$REPO/.config/nvim/init.lua"
echo mod >"$REPO/.config/nvim/lua/mod.lua"
echo tmux >"$REPO/.config/tmux/tmux.conf"
echo yazi >"$REPO/.config/yazi/yazi.toml"
echo show >"$REPO/.local/bin/show"
echo conf >"$REPO/.tmux.conf"
echo zsh >"$REPO/.zshrc"
for f in README.md LICENSE .gitignore .no-mistakes.yaml .config/nvim/init.lua~; do
	echo x >"$REPO/$f"
done

# Trạng thái $HOME có sẵn trên máy đích.
# ~/.config là symlink sang ổ khác: phải giữ nguyên và link vào bên trong.
mkdir -p "$TMP/xdg/nvim" "$HOME/.local/share/app" "$TMP/elsewhere"
ln -s "$TMP/xdg" "$HOME/.config"
echo mine >"$HOME/.config/nvim/local.lua"
echo old >"$HOME/.tmux.conf"
ln -s "$TMP/elsewhere" "$HOME/.config/yazi"
# Symlink tương đối kiểu stow từng tạo: phải được coi là đã link.
ln -s ../dotfiles/.zshrc "$HOME/.zshrc"

# Dry-run không được đụng tới $HOME.
before=$(cd "$HOME" && find . -printf '%p %y %l\n' | sort)
out=$("$REPO/install.sh" --dry-run)
after=$(cd "$HOME" && find . -printf '%p %y %l\n' | sort)
[[ "$before" == "$after" ]] || fail "dry-run changed \$HOME"
grep -q '^link    ~/.config/tmux ' <<<"$out" || fail "dry-run did not report links: $out"

out=$("$REPO/install.sh")

# Đích chưa có -> link nguyên thư mục.
assert_link .config/tmux
assert_link .tmux.conf
[[ "$(readlink "$HOME/.config")" == "$TMP/xdg" ]] || fail "~/.config symlink replaced"
# Đích là thư mục thật -> đi vào trong, giữ file riêng của máy.
assert_real_dir .config/nvim
assert_link .config/nvim/init.lua
assert_link .config/nvim/lua
[[ "$(cat "$HOME/.config/nvim/local.lua")" == mine ]] || fail "local file in ~/.config/nvim lost"
# ~/.local luôn là thư mục thật, kể cả khi chưa có.
assert_real_dir .local
assert_real_dir .local/bin
assert_link .local/bin/show
[[ -d "$HOME/.local/share/app" ]] || fail "~/.local/share lost"
# File và symlink lạ -> vào backup, không mất nội dung.
assert_link .config/yazi
backup=$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1)
[[ $(wc -l <<<"$backup") -eq 1 ]] || fail "want one backup dir, got: $backup"
[[ "$(cat "$backup/.tmux.conf")" == old ]] || fail "~/.tmux.conf not backed up"
[[ "$(readlink "$backup/.config/yazi")" == "$TMP/elsewhere" ]] || fail "foreign symlink not backed up"
# Link kiểu stow giữ nguyên.
[[ "$(readlink "$HOME/.zshrc")" == ../dotfiles/.zshrc ]] || fail "stow-style link was replaced"
# Entry chỉ thuộc repo không ra $HOME.
for f in docs tests .claude .git .superpowers README.md LICENSE .gitignore \
	.no-mistakes.yaml install.sh; do
	assert_absent "$f"
done
assert_absent .config/nvim/init.lua~
grep -q '^done: .* 1 already linked$' <<<"$out" || fail "summary: $out"

# Chạy lại: không đổi gì, không tạo backup mới.
out=$("$REPO/install.sh")
grep -q '^done: 0 linked, 0 backed up, ' <<<"$out" || fail "re-run not idempotent: $out"
[[ $(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] ||
	fail "re-run created another backup"

echo "install.sh: OK"
