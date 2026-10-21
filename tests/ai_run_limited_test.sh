#!/usr/bin/env bash
# ai_run_limited's perl fallback: what stock macOS runs, with no timeout/gtimeout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d)
trap '/bin/rm -rf -- "$TMP"' EXIT
LIB="$ROOT/.config/tmux/scripts/ai-lib.sh"
export HOME="$TMP/home" PIDFILE="$TMP/pid"
mkdir -p "$TMP/bin" "$HOME"
for tool in bash sh perl ps sleep cat; do
  path=$(command -v "$tool") || { echo "missing required tool: $tool" >&2; exit 1; }
  ln -s "$path" "$TMP/bin/$tool"
done
cat > "$TMP/bin/hold" <<'MOCK'
#!/bin/sh
echo $$ > "$PIDFILE"
exec sleep 30
MOCK
cat > "$TMP/bin/wrapper" <<'MOCK'
#!/bin/sh
sleep 30 &
echo $! > "$PIDFILE"
wait
MOCK
cat > "$TMP/bin/stubborn" <<'MOCK'
#!/bin/sh
trap '' TERM
echo $$ > "$PIDFILE"
sleep 30
MOCK
/bin/chmod +x "$TMP/bin/hold" "$TMP/bin/wrapper" "$TMP/bin/stubborn"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
# shellcheck disable=SC2016
limited() { PATH="$TMP/bin" "$TMP/bin/bash" -c '. "$1"; shift; ai_run_limited "$@"' _ "$LIB" "$@"; }
gone() {
  for _ in $(seq 60); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.05
  done
  return 1
}

out=$(limited 5 sh -c 'echo hi; exit 3') && st=0 || st=$?
[[ $out == hi && $st == 3 ]] || fail "status/output not passed through: $st '$out'"
limited 5 no-such-command 2>/dev/null && st=0 || st=$?
[[ $st == 127 ]] || fail "missing command returned $st"

for cmd in wrapper stubborn; do
  : > "$PIDFILE"
  SECONDS=0
  out=$(limited 1 "$cmd") && st=0 || st=$?
  [[ $st == 124 ]] || fail "$cmd: timeout returned $st"
  ((SECONDS < 5)) || fail "$cmd: caller waited ${SECONDS}s for the output pipe"
  gone "$(/bin/cat "$PIDFILE")" || fail "$cmd: process survived the timeout"
done

# fzf replaces a preview by SIGKILLing its process group; the command must die with it.
: > "$PIDFILE"
perl -e 'setpgrp(0, 0); exec @ARGV' "$TMP/bin/bash" -c \
  'PATH="$2"; . "$1"; ai_run_limited 30 hold' _ "$LIB" "$TMP/bin" &
caller=$!
for _ in $(seq 100); do [[ -s $PIDFILE ]] && break; sleep 0.05; done
held=$(/bin/cat "$PIDFILE")
[[ -n $held ]] || fail 'limited command never started'
kill -KILL -- "-$caller"
wait "$caller" 2>/dev/null || true
if ! gone "$held"; then
  kill -KILL "$held" 2>/dev/null || true
  fail 'limited command outlived its caller process group'
fi
echo 'ai_run_limited: OK'
