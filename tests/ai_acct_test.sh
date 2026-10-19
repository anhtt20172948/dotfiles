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
# Real tmux reads commands from stdin only via `source-file -`; bare `tmux`
# would try to attach a new session instead.
[ "$#" -ne 0 ] || exit 97
if [ "$*" != 'source-file -' ]; then
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
# Completed onboarding is left in place so concurrent Claude writes are not lost.
config_inode=$(stat -c %i "$HOME/.claude.json")
"$ACCT" exec claude --again
[ "$(stat -c %i "$HOME/.claude.json")" = "$config_inode" ] || fail 'rewrote completed config'
# no-mistakes only accepts a binary path; the installed symlink must use the active token.
mkdir -p "$HOME/.local/bin"
ln -s "$ACCT" "$HOME/.local/bin/ai-acct"
ln -s "$ROOT/.local/bin/ai-acct-claude" "$HOME/.local/bin/ai-acct-claude"
PATH="$TMP/bin:/usr/bin:/bin" "$HOME/.local/bin/ai-acct-claude" -p 'review this'
grep -Fqx -- "-p review this|$PWD" "$LOG"
python3 -I -c 'import sys, yaml; sys.exit(yaml.safe_load(open(sys.argv[1]))["agent_path_override"]["claude"] != "ai-acct-claude")' \
  "$ROOT/.no-mistakes/config.yaml" || fail 'no-mistakes override'
"$ACCT" status >> "$TMP/out"
grep -Fq 'Claude account: b' "$TMP/out"
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
# Managed accounts: names are validated and tokens arrive only on stdin.
dir=$HOME/.config/claude-accounts
printf 'synthetic-work\n' | "$ACCT" add work >> "$TMP/out"
[ "$(cat "$dir/work.token")" = synthetic-work ] || fail 'add token'
[ "$(stat -c %a "$dir/work.token")" = 600 ] || fail 'add permissions'
if printf 'synthetic-dup\n' | "$ACCT" add work; then fail 'add replaced account'; fi
[ "$(cat "$dir/work.token")" = synthetic-work ] || fail 'add changed existing token'
for bad in Work ../x 'a b' -x ''; do
  if printf 'synthetic-bad\n' | "$ACCT" add "$bad"; then fail "accepted name '$bad'"; fi
done
for bad_token in 'has space' "it's" 'back\slash'; do
  if printf '%s\n' "$bad_token" | "$ACCT" add spaced; then fail "accepted token '$bad_token'"; fi
done
if "$ACCT" add empty < /dev/null; then fail 'accepted empty token'; fi
[ ! -e "$dir/spaced.token" ] && [ ! -e "$dir/empty.token" ] || fail 'kept rejected token'
EXPECTED_TOKEN=synthetic-work "$ACCT" use work >> "$TMP/out"
zsh -c '[[ $CLAUDE_CODE_OAUTH_TOKEN == synthetic-work ]]' || fail 'zsh startup named account'
"$ACCT" list > "$TMP/list"
[ "$(cat "$TMP/list")" = "$(printf 'a\t\nb\t\nwork\tactive')" ] || fail 'list'
: > "$LOG"
printf 'synthetic-work2\n' | EXPECTED_TOKEN=synthetic-work2 "$ACCT" edit work >> "$TMP/out"
[ "$(cat "$dir/work.token")" = synthetic-work2 ] || fail 'edit token'
[ "$(stat -c %a "$dir/work.token")" = 600 ] || fail 'edit permissions'
grep -Fqx 'tmux|token updated' "$LOG" || fail 'edit did not refresh active tmux token'
if printf 'synthetic-x\n' | "$ACCT" edit missing; then fail 'edited missing account'; fi
[ ! -e "$dir/missing.token" ] || fail 'edit created account'
"$ACCT" rename work job >> "$TMP/out"
[ -e "$dir/job.token" ] && [ ! -e "$dir/work.token" ] || fail 'rename'
[ "$(cat "$dir/active")" = job ] || fail 'rename did not follow active account'
if "$ACCT" rename job b; then fail 'rename replaced account'; fi
if "$ACCT" rename job Bad; then fail 'rename accepted bad name'; fi
[ "$(cat "$dir/b.token")" = synthetic-b ] || fail 'rename changed other token'
: > "$LOG"
"$ACCT" remove job >> "$TMP/out"
[ ! -e "$dir/job.token" ] || fail 'remove token'
[ ! -e "$dir/active" ] || fail 'kept selector of removed account'
grep -Fqx 'tmux|set-environment -gu CLAUDE_CODE_OAUTH_TOKEN' "$LOG" || fail 'remove kept tmux token'
if "$ACCT" remove job; then fail 'removed missing account'; fi
"$ACCT" use b >> "$TMP/out"
"$ACCT" remove a >> "$TMP/out"
[ ! -e "$dir/a.token" ] && [ "$(cat "$dir/active")" = b ] || fail 'remove inactive account'
"$ACCT" --help >/dev/null
if "$ACCT" login b; then fail 'legacy login accepted'; fi
if grep -Eq 'synthetic-' "$LOG" "$TMP/out" "$TMP/list"; then fail 'token leaked'; fi
printf 'ai-acct: OK\n'
