#!/usr/bin/env bash
# ============================================================
# ai-lib.sh — shared helpers for persistent-ai.sh / ai-picker.sh /
#             ai-sessions.sh / ai-status.sh
#
# Sourced, never executed. Three things live here because they were duplicated
# across the pickers and had already drifted apart:
#   * the 9-line Catppuccin palette (identical copies in ai-picker.sh and
#     ai-sessions.sh)
#   * the tool metadata tables — ai-picker.sh had tool_name/tool_icon/
#     tool_description while ai-sessions.sh had a *separate* pipe-packed
#     tool_details carrying its own copy of the names and icons
#   * PATH — the pickers PREPENDED ~/.local/bin while persistent-ai.sh
#     APPENDED it, so the picker could preview one `codex` and the controller
#     could launch a different one
#
# Everything here is bash 3.2 clean, because that is what stock macOS ships as
# /bin/bash and dotfiles get checked out before Homebrew exists. It is also
# BSD/GNU userland clean: see the AI_DATE_STYLE / AI_STAT_STYLE probes below.
# ============================================================

# File-level rather than one directive per variable: this is a sourced library,
# so from shellcheck's single-file view every AI_* it defines looks unused. The
# per-line form was tried first and silently missed AI_SERVER_DEFAULT.
# shellcheck disable=SC2034

# --- PATH: single source of truth ---------------------------
# Prepend, so a user-managed ~/.local/bin wins over a system copy and so the
# picker's preview and the controller's launch always agree on the binary.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# --- Colors (Catppuccin Mocha) ------------------------------
AI_RESET=$'\033[0m'
AI_BOLD=$'\033[1m'
AI_LAVENDER=$'\033[38;2;180;190;254m'
AI_MAUVE=$'\033[38;2;203;166;247m'
AI_BLUE=$'\033[38;2;137;180;250m'
AI_GREEN=$'\033[38;2;166;227;161m'
AI_YELLOW=$'\033[38;2;249;226;175m'
AI_RED=$'\033[38;2;243;139;168m'
AI_SUBTEXT=$'\033[38;2;166;173;200m'

# Iteration order for every "for each tool" loop, and the whitelist that
# validates a tool name coming back from a picker.
AI_TOOLS='codex opencode claude'

# Label of the dedicated tmux server that holds the agent sessions. It is a
# separate server so that killing or reloading the main one never takes the
# agents with it.
AI_SERVER_DEFAULT=ai-popup

have() { command -v "$1" >/dev/null 2>&1; }

# --- Tool metadata ------------------------------------------
tool_name() {
  case "$1" in
    codex)    printf 'Codex' ;;
    opencode) printf 'OpenCode' ;;
    claude)   printf 'Claude Code' ;;
    *)        return 1 ;;
  esac
}

tool_icon() {
  case "$1" in
    codex)    printf '󰘩' ;;
    opencode) printf '' ;;
    claude)   printf '󱑺' ;;
    *)        return 1 ;;
  esac
}

tool_color() {
  case "$1" in
    codex)    printf '%s' "$AI_LAVENDER" ;;
    opencode) printf '%s' "$AI_BLUE" ;;
    claude)   printf '%s' "$AI_MAUVE" ;;
    *)        return 1 ;;
  esac
}

tool_description() {
  case "$1" in
    codex)    printf 'OpenAI coding agent for terminal-first development' ;;
    opencode) printf 'Open-source AI coding agent with multiple providers' ;;
    claude)   printf 'Anthropic agentic coding assistant for the terminal' ;;
    *)        return 1 ;;
  esac
}

# tool_details <tool> -> "icon|name|color"
# Kept in this packed shape for the `IFS='|' read -r icon name color` callers.
tool_details() {
  local icon name color
  icon=$(tool_icon "$1") || return 1
  name=$(tool_name "$1") || return 1
  color=$(tool_color "$1") || return 1
  printf '%s|%s|%s' "$icon" "$name" "$color"
}

tool_is_valid() {
  case " $AI_TOOLS " in
    *" ${1:-} "*) return 0 ;;
    *)            return 1 ;;
  esac
}

# --- Userland probes (once, at source time) ------------------
# `--version` is the unambiguous discriminator: GNU coreutils date/stat accept
# it, the BSD ones reject it. Do NOT probe with `date -r 0` instead — BSD reads
# that as epoch->string and GNU also has -r (reference FILE), so a GNU box would
# answer the same way by accident, and the probe would flip the moment a file
# named `0` existed in the working directory.
if date --version >/dev/null 2>&1; then AI_DATE_STYLE=gnu; else AI_DATE_STYLE=bsd; fi
if stat --version >/dev/null 2>&1; then AI_STAT_STYLE=gnu; else AI_STAT_STYLE=bsd; fi

# --- Dates --------------------------------------------------
# Shown instead of a timestamp we could not derive. The point is that it looks
# wrong: the fallbacks this replaced ('now', 'unknown') fired on *every* call
# because `date -d` does not exist on BSD, so a completely broken listing still
# rendered a confident-looking column.
AI_TIME_UNKNOWN='—'

# ai_fmt_epoch <epoch> [strftime-fmt] -> display string, or AI_TIME_UNKNOWN
ai_fmt_epoch() {
  local epoch=${1:-} fmt=${2:-'%Y-%m-%d %H:%M'}
  case $epoch in
    ''|*[!0-9]*) printf '%s' "$AI_TIME_UNKNOWN"; return 0 ;;
  esac
  if [ "$AI_DATE_STYLE" = gnu ]; then
    date -d "@$epoch" "+$fmt" 2>/dev/null || printf '%s' "$AI_TIME_UNKNOWN"
  else
    date -r "$epoch" "+$fmt" 2>/dev/null || printf '%s' "$AI_TIME_UNKNOWN"
  fi
}

# ai_iso_to_epoch <iso8601> -> epoch seconds on stdout, or empty + rc 1
#
# jq first, and not as a mere convenience: it is already a hard dependency of
# this feature and it is the only one of the three candidates that reads the
# trailing Z as UTC. BSD `date -j -f` parses the string in $TZ, so it is off by
# the local offset — 7h here — and Claude and Codex both stamp UTC. Getting this
# wrong would have produced timestamps that are wrong but entirely plausible,
# which is worse than the honest 0 this replaces.
ai_iso_to_epoch() {
  local iso=${1:-} out
  [ -n "$iso" ] || return 1
  if have jq; then
    out=$(jq -rn --arg t "$iso" \
      '($t | sub("\\.[0-9]+";"")) | try fromdateiso8601 catch empty' 2>/dev/null)
    case $out in
      [0-9]*) printf '%s' "$out"; return 0 ;;
    esac
  fi
  iso=${iso%Z}; iso=${iso%%.*}
  if [ "$AI_DATE_STYLE" = gnu ]; then
    date -u -d "$iso" '+%s' 2>/dev/null && return 0
  else
    TZ=UTC date -u -j -f '%Y-%m-%dT%H:%M:%S' "$iso" '+%s' 2>/dev/null && return 0
  fi
  return 1
}

# --- Files by mtime -----------------------------------------
# ai_recent_files <dir> <maxdepth> <limit> [name-glob]
#   Newest-first absolute paths, one per line.
#
# Replaces `find -printf '%T@ %p\n'`, which is GNU-only and produced ZERO output
# on BSD. stderr was suppressed at every call site, so the whole pipeline just
# went quiet and each caller reported "nothing found" rather than "broken".
# The separator is a TAB rather than a space because the old `cut -d' ' -f2-`
# also truncated any path containing a space.
ai_recent_files() {
  local dir=$1 depth=${2:-1} limit=${3:-100} glob=${4:-'*.jsonl'}
  [ -d "$dir" ] || return 0
  {
    if [ "$AI_STAT_STYLE" = gnu ]; then
      find "$dir" -maxdepth "$depth" -type f -name "$glob" \
        -exec stat -c '%Y	%n' {} + 2>/dev/null
    else
      find "$dir" -maxdepth "$depth" -type f -name "$glob" \
        -exec stat -f '%m	%N' {} + 2>/dev/null
    fi
  } | sort -rn | cut -f2- | head -n "$limit"
}

# --- Misc ---------------------------------------------------
# ai_capitalize <word> -> Word   (replaces the bash-4 ${word^})
ai_capitalize() {
  local value=${1:-} first rest
  [ -n "$value" ] || return 0
  first=${value%"${value#?}"}
  rest=${value#?}
  printf '%s%s' "$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')" "$rest"
}

# ai_run_limited <seconds> <command> [args...]
#   Run with a wall-clock cap. Returns the command's own status, or 124 when it
#   had to be killed — the same convention GNU timeout uses.
#
# `timeout` is GNU coreutils and stock macOS has neither it nor gtimeout, which
# used to mean the opencode stats pane simply never rendered here. perl is always
# present on macOS, and a real alarm() beats a `sleep &` watchdog: there is no
# leftover process to reap, and nothing keeps the command-substitution pipe open
# after the child exits (a backgrounded sleep would make every call block for the
# full timeout even when the command returned instantly).
ai_run_limited() {
  local secs=$1
  shift
  if have timeout; then timeout "$secs" "$@"; return $?; fi
  if have gtimeout; then gtimeout "$secs" "$@"; return $?; fi
  have perl || { "$@"; return $?; }
  perl -e '
    my $secs = shift @ARGV;
    my $pid = fork();
    exit 127 if !defined $pid;
    if ($pid == 0) { exec { $ARGV[0] } @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "TERM", $pid };
    alarm $secs;
    waitpid $pid, 0;
    my $st = $?;
    alarm 0;
    exit(($st & 127) ? 124 : ($st >> 8));
  ' "$secs" "$@"
}

# ai_trash <path>... -> move to the trash with whatever this OS actually has
# `gio trash` is GVFS, i.e. Linux; macOS ships /usr/bin/trash. The Claude
# history delete used to hard-require gio and bailed out entirely without it.
ai_trash() {
  local dest
  if have trash;  then trash "$@";          return $?; fi
  if have gio;    then gio trash -- "$@";   return $?; fi
  if have gtrash; then gtrash put "$@";     return $?; fi
  dest="$HOME/.Trash"
  [ -d "$dest" ] || dest="${TMPDIR:-/tmp}"
  mv -f "$@" "$dest/" 2>&1
}
