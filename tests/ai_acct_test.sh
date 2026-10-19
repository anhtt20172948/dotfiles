#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home space" FM_HOME="$TMP/first mate" LOG="$TMP/log"
export PATH="$TMP/bin:$PATH"
mkdir -p "$HOME/.claude" "$TMP/bin"
ACCT="$ROOT/.local/bin/ai-acct"
cat > "$TMP/bin/claude" <<'MOCK'
#!/bin/sh
[ "${CLAUDE_CODE_OAUTH_TOKEN+x}" != x ] || exit 80
[ "${ANTHROPIC_API_KEY+x}" != x ] || exit 81
printf '%s|%s|%s\n' "$CLAUDE_CONFIG_DIR" "$*" "$PWD" >> "$LOG"
exit "${AUTH_RC:-0}"
MOCK
cat > "$TMP/bin/tmux" <<'MOCK'
#!/bin/sh
printf 'tmux|%s\n' "$*" >> "$LOG"
MOCK
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/bin/sh
printf '%s|%s\n' "$QUOTA_AXI_CLAUDE_PROFILES" "$*" >> "$LOG"
MOCK
chmod +x "$TMP/bin/"*
fail() { echo "FAIL: $*" >&2; exit 1; }
"$ACCT" setup b
"$ACCT" setup b
for item in projects todos plans file-history settings.json CLAUDE.md agents skills rules commands plugins; do
  [ "$(readlink "$HOME/.claude-b/$item")" = "$HOME/.claude/$item" ] || fail "link $item"
done
[ -z "$(ls -A "$HOME/.claude")" ] || fail 'modified account A'
rm "$HOME/.claude-b/projects"
mkdir "$HOME/.claude-b/projects"
if "$ACCT" setup b; then fail 'accepted real directory'; fi
[ -d "$HOME/.claude-b/projects" ] || fail 'removed real directory'
rmdir "$HOME/.claude-b/projects"
"$ACCT" setup b
export CLAUDE_CODE_OAUTH_TOKEN=fixture ANTHROPIC_API_KEY=fixture TMUX=mock
"$ACCT" use b
[ "$(cat "$FM_HOME/config/claude-account")" = "$HOME/.claude-b" ] || fail 'pin b'
grep -Fqx "tmux|set-environment -g CLAUDE_CONFIG_DIR $HOME/.claude-b" "$LOG"
AUTH_RC=1 "$ACCT" use a && fail 'accepted unsigned account'
[ "$(cat "$FM_HOME/config/claude-account")" = "$HOME/.claude-b" ] || fail 'changed pin on failure'
"$ACCT" resume
grep -Fqx "$HOME/.claude-b|--continue|$FM_HOME" "$LOG"
"$ACCT" login b
"$ACCT" use a
[ "$(cat "$FM_HOME/config/claude-account")" = ordinary ] || fail 'pin a'
grep -Fqx 'tmux|set-environment -gu CLAUDE_CONFIG_DIR' "$LOG"
"$ACCT" resume
grep -Fqx "$HOME/.claude|--continue|$FM_HOME" "$LOG"
QUOTA_AXI_CLAUDE_PROFILES=/other "$ACCT" status
grep -Fqx "/other:$HOME/.claude-b|--provider claude,codex" "$LOG"
"$ACCT" --help
if "$ACCT" use invalid; then fail 'invalid account'; fi
printf 'ai-acct: OK\n'
