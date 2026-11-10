#!/usr/bin/env bash
# Tests install.sh against a fake repo and a temp $HOME.
# ~/... in strings is only a display label, no expansion needed.
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

# The target must be a symlink to the matching entry in the repo.
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

# Every entry under $HOME with its type and symlink target; find -printf is GNU-only.
snapshot() {
	(cd "$HOME" && find . | LC_ALL=C sort | while IFS= read -r p; do
		if [[ -L "$p" ]]; then
			echo "$p l $(readlink "$p")"
		elif [[ -d "$p" ]]; then
			echo "$p d"
		else
			echo "$p f"
		fi
	done)
}

# The fake repo mirrors the real layout, including repo-only entries.
mkdir -p "$REPO"/.config/{nvim/lua,tmux,yazi} "$REPO"/.local/bin "$REPO"/.no-mistakes \
	"$REPO"/{docs,tests,.claude,.git,.github,.superpowers}
cp "$ROOT/install.sh" "$REPO/install.sh"
echo init >"$REPO/.config/nvim/init.lua"
echo mod >"$REPO/.config/nvim/lua/mod.lua"
echo tmux >"$REPO/.config/tmux/tmux.conf"
echo yazi >"$REPO/.config/yazi/yazi.toml"
echo show >"$REPO/.local/bin/show"
echo cfg >"$REPO/.no-mistakes/config.yaml"
echo conf >"$REPO/.tmux.conf"
echo zsh >"$REPO/.zshrc"
for f in README.md LICENSE .gitignore .no-mistakes.yaml .config/nvim/init.lua~; do
	echo x >"$REPO/$f"
done

# $HOME state already present on the target machine.
# ~/.config is a symlink to another disk: keep it and link inside it.
mkdir -p "$TMP/xdg/nvim" "$HOME/.local/share/app" "$TMP/elsewhere"
ln -s "$TMP/xdg" "$HOME/.config"
echo mine >"$HOME/.config/nvim/local.lua"
echo old >"$HOME/.tmux.conf"
ln -s "$TMP/elsewhere" "$HOME/.config/yazi"
# Relative symlink as stow used to make: must count as already linked.
ln -s ../dotfiles/.zshrc "$HOME/.zshrc"
# NO_FOLD directory folded into the repo by old stow: must be split back into a real directory.
mkdir -p "$HOME/.local"
ln -s ../../dotfiles/.local/bin "$HOME/.local/bin"

# Dry-run must not touch $HOME.
before=$(snapshot)
out=$("$REPO/install.sh" --dry-run)
after=$(snapshot)
[[ "$before" == "$after" ]] || fail "dry-run changed \$HOME"
grep -q '^link    ~/.config/tmux ' <<<"$out" || fail "dry-run did not report links: $out"
grep -q '^unfold  ~/.local/bin$' <<<"$out" || fail "dry-run did not report unfold: $out"
grep -q '^link    ~/.local/bin/show ' <<<"$out" || fail "dry-run did not link unfolded child: $out"
! grep -q '^backup  ~/.local/bin/' <<<"$out" || fail "dry-run reported backup of unfolded child: $out"
! grep -q '~/.github' <<<"$out" || fail "dry-run linked repo-only .github: $out"

out=$("$REPO/install.sh")

# Missing target -> link the whole directory.
assert_link .config/tmux
assert_link .tmux.conf
[[ "$(readlink "$HOME/.config")" == "$TMP/xdg" ]] || fail "~/.config symlink replaced"
# Target is a real directory -> descend, keeping machine-local files.
assert_real_dir .config/nvim
assert_link .config/nvim/init.lua
assert_link .config/nvim/lua
[[ "$(cat "$HOME/.config/nvim/local.lua")" == mine ]] || fail "local file in ~/.config/nvim lost"
# ~/.local is always a real directory, even when missing.
assert_real_dir .local
assert_real_dir .local/bin
assert_link .local/bin/show
[[ "$(ls -A "$REPO/.local/bin")" == show ]] || fail "repo .local/bin changed: $(ls -A "$REPO/.local/bin")"
[[ -d "$HOME/.local/share/app" ]] || fail "~/.local/share lost"
# Agent tool state directories are not folded either (DBs/run logs stay out of the repo).
assert_real_dir .no-mistakes
assert_link .no-mistakes/config.yaml
# Unknown files and symlinks -> backup, no content lost.
assert_link .config/yazi
backup=$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1)
[[ $(wc -l <<<"$backup") -eq 1 ]] || fail "want one backup dir, got: $backup"
[[ "$(cat "$backup/.tmux.conf")" == old ]] || fail "~/.tmux.conf not backed up"
[[ "$(readlink "$backup/.config/yazi")" == "$TMP/elsewhere" ]] || fail "foreign symlink not backed up"
# Stow-style links are kept.
[[ "$(readlink "$HOME/.zshrc")" == ../dotfiles/.zshrc ]] || fail "stow-style link was replaced"
# Repo-only entries do not reach $HOME.
for f in docs tests .claude .git .github .superpowers README.md LICENSE .gitignore \
	.no-mistakes.yaml install.sh; do
	assert_absent "$f"
done
assert_absent .config/nvim/init.lua~
grep -q '^done: .* 1 already linked, 0 untracked skipped$' <<<"$out" || fail "summary: $out"

# Re-run: nothing changes, no new backup.
out=$("$REPO/install.sh")
grep -q '^done: 0 linked, 0 backed up, ' <<<"$out" || fail "re-run not idempotent: $out"
[[ $(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] ||
	fail "re-run created another backup"

# The repo is a git checkout: only what git tracks (or has been git added) is linked. An
# untracked clone inside the repo (firstmate) is not linked into $HOME file by file.
REPO="$TMP/tracked"
export HOME="$TMP/home-tracked"
mkdir -p "$HOME" "$REPO"/.config/app "$REPO"/.local/share/firstmate/{bin,config,data,state}
cp "$ROOT/install.sh" "$REPO/install.sh"
git -C "$REPO" init -q
echo app >"$REPO/.config/app/app.conf"
echo new >"$REPO/.config/new.conf"
echo crew >"$REPO/.local/share/firstmate/config/crew-dispatch.json"
echo zsh >"$REPO/.zshrc"
git -C "$REPO" add .config/app/app.conf .config/new.conf .local/share/firstmate/config/crew-dispatch.json .zshrc
for f in .DS_Store .config/app/local.conf .local/share/firstmate/AGENTS.md \
	.local/share/firstmate/bin/fm-watch.sh .local/share/firstmate/config/startup-memory-budget \
	.local/share/firstmate/data/backlog.md .local/share/firstmate/state/.lock; do
	echo untracked >"$REPO/$f"
done

out=$("$REPO/install.sh" --dry-run)
grep -q '^skip    ~/.DS_Store (untracked)$' <<<"$out" || fail "dry-run did not report untracked skip: $out"
grep -q '^skip    ~/.local/share/firstmate/bin (untracked)$' <<<"$out" ||
	fail "dry-run did not skip the untracked clone: $out"

out=$("$REPO/install.sh")
assert_link .config/app
assert_link .config/new.conf
assert_link .zshrc
assert_real_dir .local/share/firstmate
assert_real_dir .local/share/firstmate/config
assert_link .local/share/firstmate/config/crew-dispatch.json
for f in .DS_Store .local/share/firstmate/AGENTS.md .local/share/firstmate/bin .local/share/firstmate/data \
	.local/share/firstmate/state .local/share/firstmate/config/startup-memory-budget; do
	assert_absent "$f"
done
grep -q '^done: 4 linked, 0 backed up, 0 already linked, 6 untracked skipped$' <<<"$out" || fail "summary: $out"

# A repo that ships ~/.config/git/config and bat themes: install.sh creates an
# empty ~/.gitconfig (so `git config --global` never writes into the repo) and
# builds bat's theme cache only when it is missing or older than a theme.
REPO="$TMP/extras"
export HOME="$TMP/home-extras"
STUB="$TMP/stub-bin"
mkdir -p "$HOME" "$STUB" "$REPO"/.config/{git,bat/themes}
cp "$ROOT/install.sh" "$REPO/install.sh"
echo '[core]' >"$REPO/.config/git/config"
echo theme >"$REPO/.config/bat/themes/ansi.tmTheme"
cat >"$STUB/bat" <<'EOF'
#!/bin/sh
case "$1" in
--cache-dir) echo "$HOME/.cache/bat" ;;
cache) echo "$*" >>"$HOME/bat-calls"; mkdir -p "$HOME/.cache/bat" && : >"$HOME/.cache/bat/themes.bin" ;;
esac
EOF
chmod +x "$STUB/bat"
before=$(snapshot)
out=$(PATH="$STUB:$PATH" "$REPO/install.sh" --dry-run)
[[ "$before" == "$(snapshot)" ]] || fail "dry-run changed \$HOME (extras)"
grep -q '^create  ~/.gitconfig ' <<<"$out" || fail "dry-run did not report ~/.gitconfig: $out"
grep -q '^build   bat cache ' <<<"$out" || fail "dry-run did not report the bat cache: $out"
PATH="$STUB:$PATH" "$REPO/install.sh" >/dev/null
[[ -f "$HOME/.gitconfig" && ! -s "$HOME/.gitconfig" ]] || fail "~/.gitconfig not created empty"
[[ "$(cat "$HOME/bat-calls")" == "cache --build" ]] || fail "bat cache not built: $(cat "$HOME/bat-calls")"
echo '[user]' >"$HOME/.gitconfig"
out=$(PATH="$STUB:$PATH" "$REPO/install.sh")
[[ "$(cat "$HOME/.gitconfig")" == '[user]' ]] || fail "existing ~/.gitconfig changed"
! grep -q '^create  ~/.gitconfig' <<<"$out" || fail "re-run recreated ~/.gitconfig: $out"
[[ $(wc -l <"$HOME/bat-calls") -eq 1 ]] || fail "fresh bat cache rebuilt"
touch -t 203001010000 "$REPO/.config/bat/themes/ansi.tmTheme"
PATH="$STUB:$PATH" "$REPO/install.sh" >/dev/null
[[ $(wc -l <"$HOME/bat-calls") -eq 2 ]] || fail "stale bat cache not rebuilt"

echo "install.sh: OK"
