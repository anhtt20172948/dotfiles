#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home space" FM_HOME="$TMP/first mate" LOG="$TMP/log"
export PATH="$TMP/bin:$PATH"
mkdir -p "$HOME/.config/claude-accounts" "$TMP/bin" "$FM_HOME"
ACCT="$ROOT/.local/bin/ai-acct"
export ACCT
cat > "$TMP/bin/claude" <<'MOCK'
#!/bin/sh
[ "${CLAUDE_CONFIG_DIR+x}" != x ] || exit 80
[ "${ANTHROPIC_API_KEY+x}" != x ] || exit 81
[ "$CLAUDE_CODE_OAUTH_TOKEN" = "${EXPECTED_TOKEN:-synthetic-b}" ] || exit 82
printf '%s|%s\n' "$*" "$PWD" >> "$LOG"
MOCK
cat > "$TMP/bin/tmux" <<'MOCK'
#!/bin/sh
if [ "$#" -ne 0 ]; then
  case "$*" in
    *synthetic-*) printf 'tmux|argv|%s\n' "$*" >> "$LOG"; exit 95 ;;
  esac
  printf 'tmux|%s\n' "$*" >> "$LOG"
  exit 0
fi
command=$(cat)
printf 'tmux|stdin\n' >> "$LOG"
case "$command" in
  *"set-environment -g CLAUDE_CODE_OAUTH_TOKEN '"*"'"*)
    token=$(printf '%s\n' "$command" | sed -n "s/.*CLAUDE_CODE_OAUTH_TOKEN '\([^']*\)'.*/\1/p")
    [ "$token" = "${EXPECTED_TOKEN:-synthetic-b}" ] || exit 83
    printf 'tmux|token updated\n' >> "$LOG" ;;
esac
MOCK
cat > "$TMP/bin/quota-axi" <<'MOCK'
#!/bin/sh
[ "${CLAUDE_CONFIG_DIR+x}" != x ] || exit 84
[ "$CLAUDE_CODE_OAUTH_TOKEN" = "${EXPECTED_TOKEN:-synthetic-b}" ] || exit 85
printf 'quota|%s\n' "$*" >> "$LOG"
MOCK
chmod +x "$TMP/bin/"*
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'synthetic-a\n' > "$HOME/.config/claude-accounts/a.token"
printf 'synthetic-b\n' > "$HOME/.config/claude-accounts/b.token"
chmod 600 "$HOME/.config/claude-accounts/"*.token
printf '{"existing":42,"hasCompletedOnboarding":false}\n' > "$HOME/.claude.json"
export CLAUDE_CODE_OAUTH_TOKEN=stale ANTHROPIC_API_KEY=stale CLAUDE_CONFIG_DIR=/stale TMUX=mock
"$ACCT" use b > "$TMP/out"
[ "$(cat "$HOME/.config/claude-accounts/active")" = b ] || fail 'selector b'
[ ! -e "$FM_HOME/config/claude-account" ] || fail 'created pin'
[ ! -e "$HOME/.claude-b" ] || fail 'created separate profile'
jq -e '.existing == 42 and .hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null
[ "$(stat -c %a "$HOME/.claude.json")" = 600 ] || fail 'onboarding permissions'
grep -Fqx 'tmux|token updated' "$LOG"
"$ACCT" resume
grep -Fqx -- "--continue|$FM_HOME" "$LOG"
"$ACCT" exec claude --model opus
grep -Fqx -- "--model opus|$PWD" "$LOG"
"$ACCT" status >> "$TMP/out"
grep -Fq 'Claude account: B' "$TMP/out"
grep -Fqx 'quota|--provider claude,codex' "$LOG"
EXPECTED_TOKEN=synthetic-a "$ACCT" use a
[ "$(cat "$HOME/.config/claude-accounts/active")" = a ] || fail 'selector a'
EXPECTED_TOKEN=synthetic-a "$ACCT" resume
# Non-interactive startup reloads the selector, replacing inherited credentials.
ZDOTDIR="$TMP/zdot"; export ZDOTDIR
mkdir -p "$ZDOTDIR"
ln -s "$ROOT/.zshenv" "$ZDOTDIR/.zshenv"
zsh -c '[[ $CLAUDE_CODE_OAUTH_TOKEN == synthetic-a && -z ${CLAUDE_CONFIG_DIR+x} && -z ${ANTHROPIC_API_KEY+x} ]]' || fail 'zsh startup a'
printf 'b\n' > "$HOME/.config/claude-accounts/active"
zsh -c '[[ $CLAUDE_CODE_OAUTH_TOKEN == synthetic-b ]]' || fail 'zsh startup b'
for bad in invalid ../a; do
  if "$ACCT" use "$bad"; then fail 'accepted invalid name'; fi
done
rm "$HOME/.config/claude-accounts/a.token"
if "$ACCT" use a; then fail 'accepted missing token'; fi
[ "$(cat "$HOME/.config/claude-accounts/active")" = b ] || fail 'changed selector on failure'
printf '\n' > "$HOME/.config/claude-accounts/a.token"
chmod 600 "$HOME/.config/claude-accounts/a.token"
if "$ACCT" use a; then fail 'accepted empty token'; fi
printf 'synthetic-a\n' > "$HOME/.config/claude-accounts/a.token"
chmod 644 "$HOME/.config/claude-accounts/a.token"
if "$ACCT" use a; then fail 'accepted public token'; fi
chmod 600 "$HOME/.config/claude-accounts/a.token"
printf 'not json\n' > "$HOME/.claude.json"
if "$ACCT" use a; then fail 'overwrote malformed config'; fi
[ "$(cat "$HOME/.claude.json")" = 'not json' ] || fail 'damaged config'
[ "$(cat "$HOME/.config/claude-accounts/active")" = b ] || fail 'changed selector on config failure'
rm "$HOME/.claude.json"
EXPECTED_TOKEN=synthetic-a "$ACCT" use a
jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null
# Nothing configured: preserve ordinary shell behavior and report it explicitly.
rm "$HOME/.config/claude-accounts/active"
zsh -c '[[ $CLAUDE_CODE_OAUTH_TOKEN == stale ]]' || fail 'changed unconfigured shell'
"$ACCT" --help >/dev/null
if "$ACCT" login b; then fail 'legacy login accepted'; fi
if grep -Eq 'synthetic-[ab]' "$LOG" "$TMP/out"; then fail 'token leaked'; fi
printf 'ai-acct: OK\n'
