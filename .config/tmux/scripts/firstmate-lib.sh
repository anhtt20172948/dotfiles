#!/usr/bin/env bash
# ============================================================
# firstmate-lib.sh - how the launcher recognises a running firstmate and the
# session to resume. Sourced by ai-workflow.sh; needs ai-lib.sh's `have` and
# FIRSTMATE_DIR. No side effects on source.
#
# Identity comes from the firstmate home's own read-only lock helper
# (bin/fm-session-lock-lib.sh), so version-named Claude executables, wrappers,
# other harnesses and PID reuse are judged by the one owner of that decision.
# Without the helper a narrower local check keeps the guard working.
# ============================================================

FIRSTMATE_LOCK_LIB_LOADED=0
# How many of the newest transcripts one lookup may open.
FIRSTMATE_TRANSCRIPT_LIMIT=50

firstmate_load_lock_lib() {
  [[ "$FIRSTMATE_LOCK_LIB_LOADED" == 1 ]] && return 0
  local lib="$FIRSTMATE_DIR/bin/fm-session-lock-lib.sh"
  [[ -r "$lib" ]] || return 1
  # shellcheck disable=SC1090
  source "$lib" 2>/dev/null || return 1
  declare -F fm_session_lock_inspect >/dev/null || return 1
  declare -F fm_harness_pid_alive >/dev/null || return 1
  FIRSTMATE_LOCK_LIB_LOADED=1
}

# Fallback identity: claude or codex as the executable name or as any
# component of its path (Claude's installer names the binary by version, so the
# basename says nothing while .../claude/versions/2.1.x still does).
firstmate_fallback_is_harness() {
  local pid=$1 comm args argv0
  comm=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
  args=$(ps -p "$pid" -o args= 2>/dev/null) || args=
  argv0=${args%% *}
  case "/$comm/" in */claude/*|*/codex/*) return 0 ;; esac
  case "/$argv0/" in */claude/*|*/codex/*) return 0 ;; esac
  return 1
}

firstmate_pid_is_harness() {
  local pid=$1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  if firstmate_load_lock_lib; then
    fm_harness_pid_alive "$pid"
  else
    kill -0 "$pid" 2>/dev/null && firstmate_fallback_is_harness "$pid"
  fi
}

# Print the pid holding this home's session lock when it is a live harness.
firstmate_live_primary_pid() {
  local state="$FIRSTMATE_DIR/state" pid
  if firstmate_load_lock_lib; then
    fm_session_lock_inspect "$state"
    [[ "$FM_LOCK_INSPECT_STATE" == held ]] || return 1
    printf '%s\n' "$FM_LOCK_INSPECT_PID"
    return 0
  fi
  [[ -f "$state/.lock" && ! -L "$state/.lock" ]] || return 1
  IFS= read -r pid < "$state/.lock" || [[ -n "$pid" ]] || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ && "$pid" != 1 ]] || return 1
  firstmate_pid_is_harness "$pid" || return 1
  printf '%s\n' "$pid"
}

# This is only a launch guard; the agent's startup hooks own lock acquisition.
firstmate_live_primary() {
  firstmate_live_primary_pid >/dev/null
}

# Print pid $1 and its ancestors (at most 16 hops), one per line.
firstmate_pid_lineage() {
  local pid=$1 _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || break
    printf '%s\n' "$pid"
    [[ "$pid" != 1 ]] || break
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null) || break
    pid=${pid//[[:space:]]/}
  done
}

# Print pid $1 and every descendant, one per line.
firstmate_pid_tree() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v root="$1" '
    { kids[$2] = kids[$2] " " $1 }
    END {
      todo[1] = root; head = 1; tail = 1
      while (head <= tail && tail < 500) {
        pid = todo[head++]; print pid
        n = split(kids[pid], list, " ")
        for (i = 1; i <= n; i++) todo[++tail] = list[i]
      }
    }'
}

firstmate_tree_has_harness() {
  local pid
  while IFS= read -r pid; do
    firstmate_pid_is_harness "$pid" && return 0
  done < <(firstmate_pid_tree "$1")
  return 1
}

# Print "<session>:<index>" of the window that runs this home's primary.
#   1. the window whose pane runs (or is an ancestor of) the lock owner, under
#      any name;
#   2. else a window named $FIRSTMATE_WINDOW in the home directory whose pane
#      runs a harness (a primary that has not taken the lock yet).
# A dead pane, a shell-only pane and a same-named unrelated window match
# neither, so recovery is offered for them.
firstmate_target() {
  local panes lock_pid='' lineage='' home='' target pid dead path name
  panes=$(tmux list-panes -a -F $'#{session_name}:#{window_index}\t#{pane_pid}\t#{pane_dead}\t#{pane_current_path}\t#{window_name}' 2>/dev/null) || return 1
  [[ -n "$panes" ]] || return 1
  if lock_pid=$(firstmate_live_primary_pid); then
    lineage=$'\n'$(firstmate_pid_lineage "$lock_pid")$'\n'
    while IFS=$'\t' read -r target pid dead path name; do
      [[ "$dead" == 0 && "$lineage" == *$'\n'"$pid"$'\n'* ]] || continue
      printf '%s\n' "$target"
      return 0
    done <<<"$panes"
  fi
  home=$(cd "$FIRSTMATE_DIR" 2>/dev/null && pwd -P) || return 1
  while IFS=$'\t' read -r target pid dead path name; do
    [[ "$dead" == 0 && "$name" == "$FIRSTMATE_WINDOW" && "$path" == "$home" ]] || continue
    firstmate_tree_has_harness "$pid" || continue
    printf '%s\n' "$target"
    return 0
  done <<<"$panes"
  return 1
}

# Session ids go into a command line; accept only plain tokens.
firstmate_valid_session_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# Newest-first list of the given files, at most FIRSTMATE_TRANSCRIPT_LIMIT.
firstmate_newest() {
  (($# > 0)) || return 0
  # shellcheck disable=SC2012 # ls -t is the one mtime sort BSD and GNU share.
  ls -t -- "$@" 2>/dev/null | head -n "$FIRSTMATE_TRANSCRIPT_LIMIT"
}

# Claude keeps one <session-id>.jsonl per session under the project slug of the
# physical cwd. Different paths can share a slug, so the first conversation
# record's cwd must match too.
firstmate_claude_session_id() {
  local cwd=$1 slug store file
  slug=$(printf '%s' "$cwd" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')
  store="$HOME/.claude/projects/$slug"
  [[ -d "$store" ]] || return 1
  local -a files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(shopt -s nullglob; set -- "$store"/*.jsonl; firstmate_newest "$@")
  ((${#files[@]} > 0)) || return 1
  for file in "${files[@]}"; do
    jq -ne --arg cwd "$cwd" '
      first(inputs | select((.type == "user" or .type == "assistant")
        and (.isSidechain != true))) | .cwd == $cwd' "$file" >/dev/null 2>&1 || continue
    file=${file##*/}
    file=${file%.jsonl}
    firstmate_valid_session_id "$file" || continue
    printf '%s\n' "$file"
    return 0
  done
  return 1
}

# Codex writes sessions/YYYY/MM/DD/rollout-*.jsonl whose first record is the
# session_meta naming the cwd and id. One awk pass reads only the first line of
# every file; jq then confirms the few files that mention the cwd.
firstmate_codex_session_id() {
  local cwd=$1 store="${CODEX_HOME:-$HOME/.codex}/sessions" needle matches file id
  [[ -d "$store" ]] || return 1
  needle=$(jq -nr --arg cwd "$cwd" '$cwd | @json') || return 1
  matches=$(find "$store" -type f -name '*.jsonl' -exec awk -v needle="$needle" '
    FNR == 1 { if (index($0, needle)) print FILENAME; nextfile }' {} + 2>/dev/null) || return 1
  [[ -n "$matches" ]] || return 1
  local -a files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(
    set --
    while IFS= read -r file; do set -- "$@" "$file"; done <<<"$matches"
    firstmate_newest "$@")
  ((${#files[@]} > 0)) || return 1
  for file in "${files[@]}"; do
    id=$(jq -nr --arg cwd "$cwd" '
      first(inputs | select(.type == "session_meta"))
      | select(.payload.cwd == $cwd) | .payload.id | strings' "$file" 2>/dev/null) || continue
    firstmate_valid_session_id "$id" || continue
    printf '%s\n' "$id"
    return 0
  done
  return 1
}

# Print the native session id of the newest <agent> session recorded for the
# firstmate home, resolved once so the launch resumes exactly that session.
firstmate_session_id() {
  local agent=$1 cwd
  have jq || return 1
  cwd=$(cd "$FIRSTMATE_DIR" 2>/dev/null && pwd -P) || return 1
  case "$agent" in
    claude) firstmate_claude_session_id "$cwd" ;;
    codex) firstmate_codex_session_id "$cwd" ;;
    *) return 1 ;;
  esac
}
