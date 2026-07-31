#!/usr/bin/env bash
# ============================================================
# monitor-lib.sh — shared helpers for monitor.sh / monitor-preview.sh
#
# Sourced, never executed. Both scripts used to carry their own copies of
# everything below; the tool->command map in particular had drifted out of
# sync between them (the preview emitted a non-executable "TERM=... ctop"
# string while the launcher used the correct "env TERM=... ctop").
# ============================================================

# --- Colors -------------------------------------------------
# Deliberately NOT readonly: load_theme uses `printf -v` to override these from
# MONITOR_COLOR_*, which fails hard under `set -e` on a readonly variable.
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[1;36m'
C_BLUE=$'\033[1;34m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_MAGENTA=$'\033[1;35m'
C_RED=$'\033[1;31m'
C_ORANGE=$'\033[38;5;214m'

have() { command -v "$1" >/dev/null 2>&1; }

color_name_to_ansi() {
  case "${1,,}" in
    black)   echo '0;30'  ;; red)     echo '1;31'  ;;
    green)   echo '1;32'  ;; yellow)  echo '1;33'  ;;
    blue)    echo '1;34'  ;; magenta) echo '1;35'  ;;
    cyan)    echo '1;36'  ;; white)   echo '1;37'  ;;
    dim)     echo '2'     ;; bold)    echo '1'     ;;
    reset)   echo '0'     ;;
    *)       echo "${1:-}" ;;
  esac
}

load_theme() {
  local ansi config_key var pair
  for pair in HEADER:MAGENTA LABEL:CYAN BAR_LABEL:BLUE GOOD:GREEN WARN:YELLOW DANGER:RED DIM:DIM; do
    config_key="MONITOR_COLOR_${pair%%:*}"
    var="C_${pair#*:}"
    if [[ -n "${!config_key:-}" ]]; then
      ansi=$(color_name_to_ansi "${!config_key}")
      [[ -n "$ansi" ]] && printf -v "$var" '\033[%sm' "$ansi"
    fi
  done
}

# --- Shared state directory ---------------------------------
# Intentionally a stable per-user path, and intentionally never deleted on exit:
# it is a cache, not a temp dir. get_cpu_fast needs the previous /proc/stat
# sample to compute a delta, and the sparkline needs the CPU history. Wiping it
# on EXIT (as monitor.sh used to) meant every run started cold and reported 0%.
MONITOR_HISTORY_DIR="${TMPDIR:-/tmp}/monitor-${UID:-$(id -u)}"

monitor_init_history_dir() {
  mkdir -p "$MONITOR_HISTORY_DIR" 2>/dev/null || return 1
}

# --- CPU ----------------------------------------------------
# Delta against the previous sample in $MONITOR_HISTORY_DIR/cpu-stat.
# Returns 0 on the very first call of a cold cache (no previous sample yet).
get_cpu_fast() {
  local stat_file="${MONITOR_HISTORY_DIR}/cpu-stat"
  local user=0 nice=0 system=0 idle=0 iowait=0 irq=0 softirq=0 steal=0 _
  if ! { read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat; } 2>/dev/null; then
    echo 0
    return
  fi
  local total=$((user+nice+system+idle+iowait+irq+softirq+steal))
  local idle_total=$((idle+iowait))
  if [[ -f "$stat_file" ]]; then
    local prev_total=0 prev_idle=0
    read -r prev_total prev_idle _ < "$stat_file" 2>/dev/null || { prev_total=0; prev_idle=0; }
    local diff_total=$((total - prev_total))
    local diff_idle=$((idle_total - prev_idle))
    if ((diff_total > 0)); then
      echo "$(( (diff_total - diff_idle) * 100 / diff_total ))"
    else
      echo 0
    fi
  else
    echo 0
  fi
  echo "$total $idle_total" > "$stat_file" 2>/dev/null || true
}

# --- Tool -> command map ------------------------------------
# Single source of truth. Every value must be a directly executable command
# line, because monitor.sh feeds it to tmux/exec and monitor-preview.sh shows
# it to the user as "the thing that will run".
tool_command() {
  case "$1" in
    htop)        echo "htop" ;;
    btop)        echo "btop" ;;
    glances)     echo "glances" ;;
    nvtop)       echo "nvtop" ;;
    nvitop)      echo "nvitop" ;;
    jtop)        echo "jtop" ;;
    lazydocker)  echo "lazydocker" ;;
    ctop)        echo "env TERM=xterm-256color ctop" ;;
    dockerstats) echo "docker stats" ;;
    bmon)        echo "bmon" ;;
    nload)       echo "nload" ;;
    iftop)       echo "sudo iftop" ;;
    iotop)       echo "sudo iotop" ;;
    dstat)       echo "dstat" ;;
    k9s)         echo "k9s" ;;
    *)           echo "" ;;
  esac
}

# --- Custom tools -------------------------------------------
# MONITOR_CUSTOM_TOOLS format: key;command;description;group;icon
# Multiple entries separated by '|'.
declare -a custom_tools=()

load_custom_tools() {
  custom_tools=()
  local tools_str="${MONITOR_CUSTOM_TOOLS:-}"
  [[ -z "$tools_str" ]] && return 0
  local entries entry
  IFS='|' read -ra entries <<< "$tools_str"
  for entry in "${entries[@]:-}"; do
    [[ -n "$entry" ]] && custom_tools+=("$entry")
  done
  return 0
}

# Look up a custom tool's command by key. Echoes nothing if not found.
custom_tool_command() {
  local want=$1 entry key c _
  for entry in "${custom_tools[@]:-}"; do
    [[ -z "$entry" ]] && continue
    IFS=';' read -r key c _ _ _ <<< "$entry"
    if [[ "$want" == "$key" ]]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Resolve a tool key to its command, builtin map first then custom tools.
resolve_tool_command() {
  local tool=$1 cmd
  cmd=$(tool_command "$tool")
  [[ -n "$cmd" ]] && { printf '%s' "$cmd"; return 0; }
  custom_tool_command "$tool"
}
