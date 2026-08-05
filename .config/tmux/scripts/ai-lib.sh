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
    opencode) printf '' ;;
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

# --- Location: host vs Docker container ----------------------
# A "location" is WHERE an AI tool actually runs, and it is threaded through the
# whole pipeline exactly like the tool name. Two forms:
#   host              the machine tmux runs on (the original, only behavior)
#   container:<name>  inside a running Docker container, reached via docker exec
#
# The point of the container form is the workflow where the CLIs (codex, claude,
# opencode) are installed BY HAND inside a container and do not exist on the
# host at all: host `command -v` finds nothing, and even a host copy would run
# against the host filesystem rather than the project as mounted in the
# container. Every docker call here is wrapped in ai_run_limited because a stale
# DOCKER_HOST or an unreachable remote context makes the CLI hang, and some of
# this runs on the `a` hot path.

# location_kind <location> -> host | container
location_kind() {
  case "${1:-host}" in
    container:*) printf 'container' ;;
    *)           printf 'host' ;;
  esac
}

# location_container <location> -> container name, or empty for the host
location_container() {
  case "${1:-}" in
    container:*) printf '%s' "${1#container:}" ;;
  esac
}

# location_matches <filter> <session-location>
# An empty filter matches everything; an empty session location counts as host,
# so sessions created before locations existed keep showing on the host.
location_matches() {
  local filter=${1:-} s_loc=${2:-}
  [ -z "$filter" ] && return 0
  [ -n "$s_loc" ] || s_loc=host
  [ "$filter" = "$s_loc" ]
}

# list_containers -> "name<TAB>image<TAB>status", one row per running container.
# Empty output (no containers, no docker, or a dead daemon) is the signal the
# callers use to skip the location picker entirely, so the host path is never
# taxed with an extra step.
list_containers() {
  have docker || return 0
  ai_run_limited 5 docker ps \
    --format '{{.Names}}	{{.Image}}	{{.Status}}' 2>/dev/null || true
}

# docker_note -> a short human explanation when docker IS installed but a
# `docker ps` fails (permission denied, daemon down). Empty when docker is
# absent or working. Callers use it to distinguish "no reason to show the
# location picker" (host-only, silent) from "you wanted containers but docker
# is broken" (show the picker with this note), instead of a baffling silent
# skip. Only invoke it when list_containers came back empty, so the working
# path pays nothing.
docker_note() {
  have docker || return 0
  local err
  err=$(ai_run_limited 5 docker ps --format '{{.Names}}' 2>&1 >/dev/null)
  [ -n "$err" ] || return 0
  case $err in
    *"permission denied"*)
      printf 'Docker: permission denied — add your user to the docker group, then re-login' ;;
    *"Cannot connect"*|*"daemon"*|*"connect:"*)
      printf 'Docker: daemon not reachable' ;;
    *)
      printf 'Docker: %s' "${err%%$'\n'*}" ;;
  esac
}

# _container_locate_script <tool> -> a POSIX-sh snippet that resolves the tool
# inside a container by every reasonable means: source the standard profiles
# (in case PATH is set there), try `command -v`, then scan the dirs hand-installs
# usually land in. Printed to stdout so callers can `docker exec sh -c "$(...)"`.
# $tool is a validated AI_TOOLS value, so interpolating it is safe.
_container_locate_script() {
  local tool=$1
  cat <<SH
for f in /etc/profile "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.bash_login"; do
  [ -r "\$f" ] && . "\$f" >/dev/null 2>&1
done
p=\$(command -v $tool 2>/dev/null)
case \$p in /*) printf '%s' "\$p"; exit 0 ;; esac
for d in "\$HOME/.local/bin" "\$HOME/bin" "\$HOME/.$tool/bin" "\$HOME/.opencode/bin" \\
         "\$HOME/.bun/bin" "\$HOME/.npm-global/bin" "\$HOME/.deno/bin" \\
         "\$HOME/.cargo/bin" /usr/local/bin /usr/bin /bin /opt/$tool/bin \\
         /usr/local/lib/node_modules/.bin; do
  [ -x "\$d/$tool" ] && { printf '%s' "\$d/$tool"; exit 0; }
done
exit 1
SH
}

# locate_tool <location> <tool> -> absolute path of the tool, or empty + rc 1.
# Host: the `command -v` builtin.
# Container: a hand-installed CLI usually sits on a PATH the user set up in
# ~/.bashrc, which only an INTERACTIVE shell reads — a login shell does not. So
# try, in order:
#   1. `bash -ic` — reproduces `docker exec -it NAME bash` then typing the tool,
#      the exact context the user installed it for. grep keeps only a path line,
#      discarding any banner/MOTD the rc files print.
#   2. a login-sh probe that sources the profiles and scans the usual install
#      dirs — covers no-bash images and absolute installs not on any PATH.
locate_tool() {
  local location=$1 tool=$2 name out
  case "$location" in
    container:*)
      name=${location#container:}
      if ai_run_limited 5 docker exec "$name" sh -c 'command -v bash' >/dev/null 2>&1; then
        out=$(ai_run_limited 10 docker exec "$name" bash -ic "command -v $tool" 2>/dev/null \
          | grep -m1 '^/')
        case $out in /*) printf '%s' "$out"; return 0 ;; esac
      fi
      out=$(ai_run_limited 10 docker exec "$name" \
        sh -c "$(_container_locate_script "$tool")" 2>/dev/null | grep -m1 '^/')
      case $out in /*) printf '%s' "$out"; return 0 ;; esac
      return 1
      ;;
    *)
      out=$(command -v "$tool" 2>/dev/null) || return 1
      ;;
  esac
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# location_run <location> <cmd> [args...] -> run a command where the location
# points. Used for the version probe: host runs it directly, a container runs it
# under `docker exec`.
location_run() {
  local location=$1
  shift
  case "$location" in
    container:*) ai_run_limited 8 docker exec "${location#container:}" "$@" ;;
    *)           "$@" ;;
  esac
}

# _map_fallback <name> <host_path> -> a plausible container working dir when no
# bind mount matched the host path. Order matters, because this dir is used BOTH
# to launch (`-w`) and to filter saved sessions, so it must match where the user
# actually works inside the container:
#   1. the identical host path, if it happens to exist in the container
#      (mirrored-layout setups);
#   2. the container user's HOME — where `docker exec -it bash` and hand-run
#      tools land when the project is NOT mounted, which is the common "I just
#      work inside this container" case and is exactly the cwd such sessions
#      record (e.g. /root);
#   3. the image's declared WorkingDir;
#   4. /.
_map_fallback() {
  local name=$1 host_path=$2 wd home
  if ai_run_limited 5 docker exec "$name" test -d "$host_path" >/dev/null 2>&1; then
    printf '%s' "$host_path"; return 0
  fi
  home=$(container_home "$name")
  if [ -n "$home" ] \
     && ai_run_limited 5 docker exec "$name" test -d "$home" >/dev/null 2>&1; then
    printf '%s' "$home"; return 0
  fi
  wd=$(ai_run_limited 5 docker inspect \
    --format '{{.Config.WorkingDir}}' "$name" 2>/dev/null)
  case $wd in /?*) printf '%s' "$wd"; return 0 ;; esac
  printf '/'
}

# map_host_path_to_container <name> <host_path> -> the path inside the container
# that corresponds to host_path. Finds the bind/volume mount whose Source is the
# longest prefix of host_path and rebases the remainder onto its Destination.
# The resolved path is shown in the picker preview, so a wrong guess is visible
# rather than a silent launch in the wrong directory.
map_host_path_to_container() {
  local name=$1 host_path=$2 mounts src dst best_src='' best_dst='' remainder
  have jq || { _map_fallback "$name" "$host_path"; return; }
  mounts=$(ai_run_limited 6 docker inspect \
    --format '{{json .Mounts}}' "$name" 2>/dev/null) || mounts=''
  if [ -n "$mounts" ]; then
    while IFS='	' read -r src dst; do
      [ -n "$src" ] || continue
      case "$host_path" in
        "$src")
          best_src=$src; best_dst=$dst; break ;;
        "$src"/*)
          if [ "${#src}" -gt "${#best_src}" ]; then best_src=$src; best_dst=$dst; fi
          ;;
      esac
    done <<EOF
$(printf '%s' "$mounts" | jq -r '.[]? | [.Source, .Destination] | @tsv' 2>/dev/null)
EOF
  fi
  if [ -n "$best_src" ]; then
    remainder=${host_path#"$best_src"}
    printf '%s%s' "$best_dst" "$remainder"
    return 0
  fi
  _map_fallback "$name" "$host_path"
}

# container_home <name> -> the container user's $HOME (fallback /root).
# Session stores live under $HOME, and it is not always /root (a container may
# run as a non-root user), so ask rather than assume.
container_home() {
  local name=$1 h
  h=$(ai_run_limited 5 docker exec "$name" sh -c 'printf %s "$HOME"' 2>/dev/null)
  case $h in /*) printf '%s' "$h" ;; *) printf '/root' ;; esac
}

# extract_container_sessions <name> <tool> <container_path> <dest_root>
#   Copy the tool's on-disk session store OUT of the container into <dest_root>,
#   laid out at the SAME relative paths the host list_*_sessions() expect, so the
#   existing jq/sqlite parsers can read it unchanged — just pointed at <dest_root>
#   with the CONTAINER project path as the directory filter. This is what lets
#   saved container sessions appear in the picker without needing jq/sqlite inside
#   the container. rc 0 on success.
#
# Only the data actually parsed is pulled: opencode's sqlite db (+ WAL/SHM so an
# uncommitted latest session is not missed), and — for the jsonl tools — just the
# subtree that could match this project (claude keys by a path-slug directory;
# codex mixes all projects under dated dirs, so its whole sessions tree comes
# across and the cwd filter runs on the host side).
extract_container_sessions() {
  local name=$1 tool=$2 cpath=$3 dest=$4 all=${5:-0} chome cslug
  have docker || return 1
  chome=$(container_home "$name")
  case "$tool" in
    codex)
      # codex mixes every directory under dated dirs, so the whole tree comes
      # across in both modes; the cwd filter runs host-side.
      mkdir -p "$dest/.codex" || return 1
      ai_run_limited 30 docker cp \
        "$name:$chome/.codex/sessions" "$dest/.codex/sessions" >/dev/null 2>&1 || return 1
      ;;
    opencode)
      # The single sqlite db holds every directory's sessions already.
      mkdir -p "$dest/.local/share/opencode" || return 1
      ai_run_limited 20 docker cp \
        "$name:$chome/.local/share/opencode/opencode.db" \
        "$dest/.local/share/opencode/opencode.db" >/dev/null 2>&1 || return 1
      ai_run_limited 10 docker cp \
        "$name:$chome/.local/share/opencode/opencode.db-wal" \
        "$dest/.local/share/opencode/opencode.db-wal" >/dev/null 2>&1 || true
      ai_run_limited 10 docker cp \
        "$name:$chome/.local/share/opencode/opencode.db-shm" \
        "$dest/.local/share/opencode/opencode.db-shm" >/dev/null 2>&1 || true
      ;;
    claude)
      # claude keys by a path-slug directory. Scoped: copy just this dir's slug.
      # all: copy the whole projects tree so every directory's sessions parse.
      # The cp target must NOT pre-exist, or docker nests it (…/projects/projects),
      # so create only the parent and let cp create the leaf.
      if [ "$all" = 1 ]; then
        mkdir -p "$dest/.claude" || return 1
        ai_run_limited 30 docker cp \
          "$name:$chome/.claude/projects" "$dest/.claude/projects" >/dev/null 2>&1 || return 1
      else
        cslug=${cpath//\//-}
        mkdir -p "$dest/.claude/projects" || return 1
        ai_run_limited 30 docker cp \
          "$name:$chome/.claude/projects/$cslug" \
          "$dest/.claude/projects/$cslug" >/dev/null 2>&1 || return 1
      fi
      ;;
    *) return 1 ;;
  esac
  return 0
}
