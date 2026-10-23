#!/usr/bin/env bash
# Account binding and ai-acct resume: real ai-acct and launcher, synthetic
# accounts and homes, fake tmux/fzf/claude. Never touches a live server or token.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" LOG="$TMP/log" PANE="$TMP/pane" TMUX=mock
export CODEX_HOME="$HOME/.codex" AI_FIRSTMATE_AGENT=claude
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$TMP/cache"
unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CONFIG_DIR FM_HOME
FM="$TMP/first mate"
mkdir -p "$HOME/.config/claude-accounts" "$TMP/bin" "$FM/.git" "$FM/state" "$TMP/other"
export FIRSTMATE_DIR="$FM"
FM=$(cd "$FM" && pwd -P)
ACCT="$ROOT/.local/bin/ai-acct"
WORKFLOW="$ROOT/.config/tmux/scripts/ai-workflow.sh"
ln -s "$ACCT" "$TMP/bin/ai-acct"
export PATH="$TMP/bin:$PATH"
fail() { echo "FAIL: $*" >&2; cat "$LOG" >&2 2>/dev/null || :; exit 1; }

cat > "$TMP/bin/claude" <<'MOCK'
#!/bin/sh
printf 'claude|%s|%s|%s\n' "$CLAUDE_CODE_OAUTH_TOKEN" "$PWD" "$*" >> "$LOG"
MOCK
# The pane command is only captured; the test runs it later, like tmux would.
cat > "$TMP/bin/tmux" <<'MOCK'
#!/bin/sh
case "$1" in
  list-panes) exit 0 ;;
  has-session) exit 1 ;;
  display-message) printf 'message|%s\n' "$*" >> "$LOG" ;;
  new-session) for last; do :; done; printf '%s\n' "$last" > "$PANE"; [ -z "${FAIL_NEW:-}" ] || exit 1 ;;
esac
exit 0
MOCK
cat > "$TMP/bin/fzf" <<'MOCK'
#!/bin/sh
rows=$(cat)
case "$*" in
  *'Session › '*) echo resume ;;
  *'Account › '*) echo "${ACCOUNT_CHOICE:-alpha}" ;;
  *) printf '%s\n' "$rows" | head -n 1 | cut -f1 ;;
esac
MOCK
chmod +x "$TMP/bin/"*

printf 'synthetic-alpha\n' > "$HOME/.config/claude-accounts/alpha.token"
printf 'synthetic-beta\n' > "$HOME/.config/claude-accounts/beta.token"
chmod 600 "$HOME/.config/claude-accounts/"*.token
printf '{"hasCompletedOnboarding":true}\n' > "$HOME/.claude.json"
printf 'beta\n' > "$HOME/.config/claude-accounts/active"
selector() { cat "$HOME/.config/claude-accounts/active"; }

slug=$(printf '%s' "$FM" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$HOME/.claude/projects/$slug"
printf '{"type":"user","cwd":"%s","message":{"role":"user","content":"x"}}\n' "$FM" \
  > "$HOME/.claude/projects/$slug/old-session.jsonl"
# A newer session of another home must not be the one that resumes.
printf '{"type":"user","cwd":"%s","message":{"role":"user","content":"x"}}\n' "$TMP/other" \
  > "$HOME/.claude/projects/$slug/newest-other.jsonl"
touch -d '2 minutes ago' "$HOME/.claude/projects/$slug/old-session.jsonl" 2>/dev/null \
  || touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$HOME/.claude/projects/$slug/old-session.jsonl"

# --- the picked account survives a concurrent selector switch ---------------
: > "$LOG"
bash "$WORKFLOW" firstmate </dev/null 2>"$TMP/err" || fail "launcher failed: $(cat "$TMP/err")"
cmd=$(cat "$PANE")
[ "$cmd" = 'exec ai-acct exec --account alpha claude --resume old-session' ] || fail "pane command: $cmd"
case "$cmd" in *synthetic-*) fail 'token in the pane command' ;; esac
[ "$(selector)" = beta ] || fail 'launching changed the shared selector'
ai-acct use beta >/dev/null   # another client switches before the pane starts
(cd "$FM" && sh -c "$cmd")
grep -Fqx "claude|synthetic-alpha|$FM|--resume old-session" "$LOG" || fail 'child did not keep the picked account'

# A failed pane creation leaves the default untouched.
printf 'beta\n' > "$HOME/.config/claude-accounts/active"
if FAIL_NEW=1 bash "$WORKFLOW" firstmate </dev/null 2>/dev/null; then fail 'failed pane creation succeeded'; fi
[ "$(selector)" = beta ] || fail 'failed launch changed the selector'

# An account that cannot be loaded stops the launch before any pane exists.
rm "$PANE"
chmod 644 "$HOME/.config/claude-accounts/alpha.token"
if bash "$WORKFLOW" firstmate </dev/null 2>/dev/null; then fail 'unreadable token launched'; fi
[ ! -e "$PANE" ] || fail 'pane created for a bad account'
chmod 600 "$HOME/.config/claude-accounts/alpha.token"

# --- ai-acct exec --account ---------------------------------------------------
: > "$LOG"
ai-acct exec --account alpha claude one
ai-acct exec --account beta -- claude two
ai-acct exec claude three
grep -Fqx "claude|synthetic-alpha|$PWD|one" "$LOG" || fail 'exec --account alpha'
grep -Fqx "claude|synthetic-beta|$PWD|two" "$LOG" || fail 'exec --account beta --'
grep -Fqx "claude|synthetic-beta|$PWD|three" "$LOG" || fail 'plain exec follows selector'
if ai-acct exec --account missing claude 2>/dev/null; then fail 'unknown account ran'; fi
if ai-acct exec --account ../alpha claude 2>/dev/null; then fail 'invalid account name ran'; fi
if ai-acct exec --account alpha 2>/dev/null; then fail 'exec without command ran'; fi
printf 'broken name\n' > "$HOME/.config/claude-accounts/active"
ai-acct exec --account alpha claude bound >/dev/null
printf 'beta\n' > "$HOME/.config/claude-accounts/active"

# --- ai-acct resume goes through the launcher's guards ---------------------
export TMUX=''
: > "$LOG"
ai-acct resume
grep -Fqx "claude|synthetic-beta|$FM|--resume old-session" "$LOG" || fail 'resume not explicit/in home'
# A live primary refuses the resume, even outside tmux.
mkdir -p "$TMP/live"
ln -s "$(command -v sleep)" "$TMP/live/claude"
"$TMP/live/claude" 30 & holder=$!
trap 'kill "$holder" 2>/dev/null || :; rm -rf -- "$TMP"' EXIT
printf '%s\n' "$holder" > "$FM/state/.lock"
: > "$LOG"
if ai-acct resume 2>"$TMP/err"; then fail 'resume ignored live primary'; fi
grep -Fq 'live primary' "$TMP/err" || fail "no refusal reason: $(cat "$TMP/err")"
[ ! -s "$LOG" ] || fail 'claude ran despite live primary'
kill "$holder"; wait "$holder" 2>/dev/null || :
rm "$FM/state/.lock"
# No transcript: nothing to resume.
if FIRSTMATE_DIR="$TMP/other" ai-acct resume 2>"$TMP/err"; then fail 'resumed without transcript'; fi
grep -Fq 'no Claude transcript' "$TMP/err" || fail 'missing-transcript message'
# One home variable decides both paths: FIRSTMATE_DIR wins, FM_HOME is the fallback.
: > "$LOG"
(unset FIRSTMATE_DIR; FM_HOME="$FM" ai-acct resume)
grep -Fqx "claude|synthetic-beta|$FM|--resume old-session" "$LOG" || fail 'FM_HOME not honoured'
if (unset FIRSTMATE_DIR; FM_HOME="$TMP/other" ai-acct resume 2>/dev/null); then fail 'FM_HOME ignored'; fi
if FIRSTMATE_DIR="$TMP/other" FM_HOME="$FM" ai-acct resume 2>/dev/null; then fail 'FIRSTMATE_DIR did not win'; fi
printf 'firstmate account: OK\n'
