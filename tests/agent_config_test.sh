#!/usr/bin/env bash
# Global agent config installation must preserve runtime directories and files.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
REPO="$TMP/repo"
export HOME="$TMP/home"

fail() { echo "FAIL: $*" >&2; exit 1; }
real_dir() { [[ -d "$HOME/$1" && ! -L "$HOME/$1" ]] || fail "$1 folded"; }
linked() {
	[[ -L "$HOME/$1" ]] || fail "$1 not linked"
	[[ $(readlink -f "$HOME/$1") == "$(readlink -f "$REPO/${2:-$1}")" ]] || fail "$1 wrong target"
}

mkdir -p "$REPO/.config/agents" "$REPO/.config/opencode" "$REPO/.local/bin" \
	"$REPO/.local/share/firstmate/config" "$REPO/.local/share/firstmate/data" "$REPO/.claude" "$HOME"
cp "$ROOT/install.sh" "$REPO/install.sh"
cp "$ROOT/.local/bin/install-agent-statusline" "$REPO/.local/bin/install-agent-statusline"
cp "$ROOT/.local/bin/agent-statusline-claude" "$REPO/.local/bin/agent-statusline-claude"
echo rules >"$REPO/.config/agents/AGENTS.md"
echo '@~/.config/agents/AGENTS.md' >"$REPO/.config/agents/CLAUDE.md"
ln -s ../agents/AGENTS.md "$REPO/.config/opencode/AGENTS.md"
echo dispatch >"$REPO/.local/share/firstmate/config/crew-dispatch.json"
echo repo-only >"$REPO/.claude/settings.json"

before=$(find "$HOME" -printf '%p %y %l\n' | sort)
out=$("$REPO/install.sh" --dry-run)
[[ $(find "$HOME" -printf '%p %y %l\n' | sort) == "$before" ]] || fail 'dry-run changed HOME'
grep -q '^link    ~/.local/share/firstmate/config/crew-dispatch.json ' <<<"$out" || fail 'dispatch folded in dry-run'
! grep -q 'firstmate/data/' <<<"$out" || fail 'dry-run links per-host firstmate data'
grep -q '^link    ~/.claude/CLAUDE.md ' <<<"$out" || fail 'Claude mapping missing'
"$REPO/install.sh" >/dev/null
for dir in .local/share/firstmate .local/share/firstmate/config .local/share/firstmate/data .claude; do real_dir "$dir"; done
linked .local/share/firstmate/config/crew-dispatch.json
[[ -z $(find "$HOME/.local/share/firstmate/data" -mindepth 1) ]] || fail 'firstmate data populated'
linked .claude/CLAUDE.md .config/agents/CLAUDE.md
linked .config/opencode/AGENTS.md .config/agents/AGENTS.md
jq -e '.statusLine.type == "command" and (.statusLine.command | contains("$HOME"))' "$HOME/.claude/settings.json" >/dev/null || fail 'Claude status line missing'
python3 - "$HOME/.codex/config.toml" "$ROOT/.local/bin/install-agent-statusline" <<'PY' || fail 'Codex status line missing'
import pathlib, re, sys, tomllib
items = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())['tui']['status_line']
expected = re.search(r'CODEX_ITEMS = (\[[^\]]*\])', pathlib.Path(sys.argv[2]).read_text()).group(1)
assert items == tomllib.loads(f'v = {expected}')['v'] and 'five-hour-limit' in items
PY
out=$("$REPO/install.sh")
grep -q '^done: 0 linked, 0 backed up,' <<<"$out" || fail 'not idempotent'

# Existing private content survives, including the externally managed Codex file.
export HOME="$TMP/existing"
mkdir -p "$HOME/.local/share/firstmate/config" "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"
echo private >"$HOME/.local/share/firstmate/config/private.json"
echo credential >"$HOME/.claude/credentials.json"
printf '%s\n' '{"hooks":{"Stop":[]},"theme":"dark"}' >"$HOME/.claude/settings.json"
echo ECC >"$HOME/.codex/AGENTS.md"
printf '%s\n' 'model = "gpt-6-astra"' >"$HOME/.codex/config.toml"
echo old-claude >"$HOME/.claude/CLAUDE.md"
echo old-opencode >"$HOME/.config/opencode/AGENTS.md"
echo old-dispatch >"$HOME/.local/share/firstmate/config/crew-dispatch.json"
mkdir -p "$HOME/.local/share/firstmate/data"
echo host-captain >"$HOME/.local/share/firstmate/data/captain.md"
"$REPO/install.sh" >/dev/null
[[ $(cat "$HOME/.local/share/firstmate/config/private.json") == private ]] || fail 'private config lost'
[[ -f $HOME/.local/share/firstmate/data/captain.md && ! -L $HOME/.local/share/firstmate/data/captain.md ]] || fail 'captain.md replaced'
[[ $(cat "$HOME/.local/share/firstmate/data/captain.md") == host-captain ]] || fail 'captain.md changed'
[[ ! -e $(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 -type d)/.local/share/firstmate/data ]] || fail 'captain.md backed up'
[[ $(cat "$HOME/.claude/credentials.json") == credential ]] || fail 'credentials lost'
jq -e '.hooks.Stop == [] and .theme == "dark" and .statusLine.type == "command"' "$HOME/.claude/settings.json" >/dev/null || fail 'Claude settings lost'
python3 - "$HOME/.codex/config.toml" <<'PY' || fail 'Codex settings lost'
import pathlib, sys, tomllib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert data['model'] == 'gpt-6-astra'
assert data['tui']['status_line'][0] == 'model-with-reasoning'
PY
[[ $(cat "$HOME/.codex/AGENTS.md") == ECC ]] || fail 'Codex changed'
backup=$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 -type d)
[[ $(cat "$backup/.claude/CLAUDE.md") == old-claude ]] || fail 'Claude content lost'
[[ $(cat "$backup/.config/opencode/AGENTS.md") == old-opencode ]] || fail 'OpenCode content lost'
[[ $(cat "$backup/.local/share/firstmate/config/crew-dispatch.json") == old-dispatch ]] || fail 'dispatch content lost'
linked .claude/CLAUDE.md .config/agents/CLAUDE.md
linked .config/opencode/AGENTS.md .config/agents/AGENTS.md

# Recover folded directories from an earlier install without folding config again.
export HOME="$TMP/folded"
mkdir -p "$HOME/.local/share"
ln -s "$REPO/.local/share/firstmate" "$HOME/.local/share/firstmate"
"$REPO/install.sh" >/dev/null
real_dir .local/share/firstmate
real_dir .local/share/firstmate/config
real_dir .local/share/firstmate/data
linked .local/share/firstmate/config/crew-dispatch.json
echo 'agent config: OK'
