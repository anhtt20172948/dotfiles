#!/usr/bin/env bash
set -euo pipefail

readonly LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
# shellcheck source=./monitor-lib.sh
source "$LIB_DIR/monitor-lib.sh"

# Only resets terminal attributes. It deliberately does NOT remove
# $MONITOR_HISTORY_DIR — that is the CPU-delta / sparkline cache and must
# survive between runs, see monitor-lib.sh.
cleanup() {
  printf '%b' "$C_RESET"
}
trap cleanup EXIT INT TERM

# --- Config ---
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
readonly CONFIG_FILE="$CONFIG_DIR/monitor.conf"

load_config() {
  set -a
  # Launch-mode defaults. These are only reachable when monitor.sh is invoked
  # directly or via --popup; the tmux keybinding (prefix M) goes through
  # --popup-inner, which forces window mode below.
  : "${MONITOR_LAUNCH_MODE:=split}"
  : "${MONITOR_SPLIT_DIRECTION:=h}"
  : "${MONITOR_SPLIT_SIZE:=}"
  : "${MONITOR_WINDOW_AUTO_CLEANUP:=true}"
  : "${MONITOR_STATUS_FORMAT:=cpu mem disk temp}"
  : "${MONITOR_DANGER_CPU:=85}"
  : "${MONITOR_DANGER_MEM:=85}"
  : "${MONITOR_DANGER_DISK:=85}"
  : "${MONITOR_WARN_CPU:=65}"
  : "${MONITOR_WARN_MEM:=65}"
  : "${MONITOR_WARN_DISK:=65}"
  : "${MONITOR_PREVIEW_WIDTH:=65%}"
  : "${MONITOR_PREVIEW_PROCESSES:=6}"
  : "${MONITOR_HISTORY_ENABLED:=true}"
  : "${MONITOR_HISTORY_SIZE:=20}"
  : "${MONITOR_PREVIEW_REFRESH_MS:=0}"
  : "${MONITOR_CUSTOM_TOOLS:=}"
  set +a

  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}
load_config

# color_name_to_ansi / load_theme / load_custom_tools come from monitor-lib.sh
load_theme
load_custom_tools
monitor_init_history_dir

readonly SCRIPT_DIR="$LIB_DIR"
readonly SCRIPT_PATH="$SCRIPT_DIR/monitor.sh"
readonly PREVIEW_SCRIPT="$SCRIPT_DIR/monitor-preview.sh"

# --- Platform Detection ---
detect_platform() {
  local tags=()

  if [[ -f /etc/nv_tegra_release ]] || have jtop; then
    tags+=(jetson)
  fi

  if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
    tags+=(gpu)
  fi

  have docker && tags+=(docker)
  if have kubectl && kubectl config current-context >/dev/null 2>&1; then
    tags+=(kubernetes)
  fi

  [[ ${#tags[@]} -eq 0 ]] && tags+=(linux)
  (IFS=+; echo "${tags[*]}")
}

platform_badges() {
  local p=$1 labels=()

  [[ "$p" == *jetson* ]]     && labels+=("Jetson")
  [[ "$p" == *gpu* ]]        && labels+=("GPU")
  [[ "$p" == *docker* ]]     && labels+=("Docker")
  [[ "$p" == *kubernetes* ]] && labels+=("Kubernetes")
  [[ -z "${labels+x}" || ${#labels[@]} -eq 0 ]] && labels+=("Linux")

  # Joined manually. `local IFS=' | '` does not work here: IFS is a set of
  # delimiter *characters*, so "${labels[*]}" would join on a single space and
  # render "Docker Linux" instead of "Docker | Linux".
  local out="" label
  for label in "${labels[@]}"; do
    [[ -n "$out" ]] && out+=" | "
    out+="$label"
  done
  echo "$out"
}

readonly MONITOR_PLATFORM=$(detect_platform)
readonly MONITOR_PLATFORM_LABEL=$(platform_badges "$MONITOR_PLATFORM")

export MONITOR_PLATFORM
export MONITOR_PLATFORM_LABEL
export MONITOR_HISTORY_DIR
export MONITOR_HISTORY_SIZE
export MONITOR_PREVIEW_PROCESSES
export MONITOR_DANGER_CPU MONITOR_DANGER_MEM MONITOR_DANGER_DISK
export MONITOR_WARN_CPU MONITOR_WARN_MEM MONITOR_WARN_DISK
export MONITOR_COLOR_HEADER MONITOR_COLOR_LABEL MONITOR_COLOR_BAR_LABEL
export MONITOR_COLOR_GOOD MONITOR_COLOR_WARN MONITOR_COLOR_DANGER MONITOR_COLOR_DIM
export MONITOR_PREVIEW_REFRESH_MS

# --- Menu Generation ---
menu() {
  local gpu=() system=() container=() network=() custom=()

  have jtop        && gpu+=($' 󰤽  jtop\tjtop\tJetson Stats ★')
  have nvitop      && gpu+=($' 󰚗  nvitop\tnvitop\tCUDA Processes')
  have nvtop       && gpu+=($' 󰢮  nvtop\tnvtop\tGPU Dashboard')

  have btop        && system+=($' 󰎴  btop\tbtop\tSystem Dashboard')
  have htop        && system+=($' 󰍛  htop\thtop\tCPU Processes')
  have glances     && system+=($' 󰢹  glances\tglances\tSystem Analytics')
  have iotop       && system+=($' 󰋊  iotop\tiotop\tDisk I/O')
  have dstat       && system+=($' 󱂫  dstat\tdstat\tSystem Statistics')

  have lazydocker  && container+=($' 󰡨  lazydocker\tlazydocker\tDocker Manager')
  have ctop        && container+=($' 󰕈  ctop\tctop\tContainer Top')
  have docker      && container+=($' 󰖂  dockerstats\tdockerstats\tDocker Stats')
  have k9s          && container+=($' 󱃾  k9s \tk9s\tKubernetes')

  have bmon        && network+=($' 󰩟  bmon\tbmon\tBandwidth')
  have nload       && network+=($' 󰤨  nload\tnload\tThroughput')
  have iftop       && network+=($' 󰛳  iftop\tiftop\tInterface Bandwidth')

  local entry key desc group icon _
  for entry in "${custom_tools[@]:-}"; do
    [[ -z "$entry" ]] && continue
    IFS=';' read -r key _ desc group icon <<< "$entry"
    : "${icon:=󰞷}"
    case "${group:-custom}" in
      gpu)       gpu+=($' '"$icon $key\t$key\t$desc") ;;
      system)    system+=($' '"$icon $key\t$key\t$desc") ;;
      container) container+=($' '"$icon $key\t$key\t$desc") ;;
      network)   network+=($' '"$icon $key\t$key\t$desc") ;;
      custom|*)  custom+=($' '"$icon $key\t$key\t$desc") ;;
    esac
  done

  if ((${#gpu[@]})); then
    printf '%bGPU%b\t__GROUP__\t\n' "$C_MAGENTA" "$C_RESET"
    printf '%s\n' "${gpu[@]}"
  fi

  if ((${#system[@]})); then
    printf '%bSystem%b\t__GROUP__\t\n' "$C_CYAN" "$C_RESET"
    printf '%s\n' "${system[@]}"
  fi

  if ((${#container[@]})); then
    printf '%bContainer%b\t__GROUP__\t\n' "$C_YELLOW" "$C_RESET"
    printf '%s\n' "${container[@]}"
  fi

  if ((${#network[@]})); then
    printf '%bNetwork%b\t__GROUP__\t\n' "$C_GREEN" "$C_RESET"
    printf '%s\n' "${network[@]}"
  fi

  if ((${#custom[@]})); then
    printf '%bCustom%b\t__GROUP__\t\n' "$C_DIM" "$C_RESET"
    printf '%s\n' "${custom[@]}"
  fi
}

# --- Tmux Launch ---
launch_tool() {
  local tool=$1 cmd=""
  # Builtin map lives in monitor-lib.sh so the preview shows the same command
  # this function actually runs; falls back to MONITOR_CUSTOM_TOOLS.
  cmd=$(resolve_tool_command "$tool" || true)

  if [[ -z "$cmd" ]]; then
    echo "Error: Unknown tool ($tool)" >&2
    exit 1
  fi

  # Always run through `bash -c`: $cmd is a command *line* (e.g. "docker stats",
  # or a custom tool like "tail -f /var/log/syslog"). Bare `exec $cmd` relied on
  # word splitting and was also subject to glob expansion.
  case "$MONITOR_LAUNCH_MODE" in
    split)
      if [[ -n "${TMUX:-}" ]]; then
        local split_args=("-h")
        [[ "$MONITOR_SPLIT_DIRECTION" == "v" ]] && split_args=("-v")
        [[ -n "$MONITOR_SPLIT_SIZE" ]] && split_args+=("-l" "$MONITOR_SPLIT_SIZE")
        tmux split-window "${split_args[@]}" "$cmd"
      else
        exec bash -c "$cmd"
      fi
      ;;
    window)
      if [[ -n "${TMUX:-}" ]]; then
        local tool_name="$tool"
        case "$tool" in
          dockerstats) tool_name="docker" ;;
          *)           ;;
        esac
        if [[ "$MONITOR_WINDOW_AUTO_CLEANUP" == "true" ]]; then
          tmux new-window -n "$tool_name" "$cmd; tmux kill-window"
        else
          tmux new-window -n "$tool_name" "$cmd"
        fi
        # No explicit cleanup call here: the EXIT trap runs it, and calling it
        # directly meant it ran twice.
        exit 0
      else
        exec bash -c "$cmd"
      fi
      ;;
    replace|*)
      exec bash -c "$cmd"
      ;;
  esac
}

# --- Status Bar ---
# get_cpu_fast comes from monitor-lib.sh (shared with monitor-preview.sh).

status_output() {
  local fields="${MONITOR_STATUS_FORMAT:-cpu mem disk temp}"
  local out=()
  for f in $fields; do
    case "$f" in
      cpu)
        local v; v=$(get_cpu_fast)
        printf -v v '%3s%%' "$v"
        out+=("CPU:$v")
        ;;
      mem)
        local t u
        t=$(free -h 2>/dev/null | awk '/Mem:/{print $2}') || t="?"
        u=$(free -h 2>/dev/null | awk '/Mem:/{print $3}') || u="?"
        [[ -n "$u" && -n "$t" ]] && out+=("MEM:${u}/${t}")
        ;;
      disk)
        local p; p=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}') || p="?"
        out+=("DSK:${p}%")
        ;;
      temp)
        local t=""
        if have sensors; then
          t=$(sensors -u 2>/dev/null | awk '/temp1_input/{printf "%.0f", $2; exit}')
        elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
          t=$(awk '{printf "%.0f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        fi
        [[ -n "$t" ]] && out+=("${t}°C")
        ;;
      load)
        local l; l=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "?")
        out+=("LD:$l")
        ;;
      uptime)
        local u; u=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")
        out+=("UP:$u")
        ;;
    esac
  done
  echo "${out[*]:-}"
}

# --- Usage ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Monitor Center — interactive monitoring tool launcher.

Options:
  --menu    Print available tools as fzf-compatible menu and exit
  --status  Print one-line system status (for tmux status-right)
  --popup   Launch in a tmux floating popup window (tmux ≥ 3.2)
  --help    Show this help message and exit

Environment variables (or configure via $CONFIG_FILE):
  MONITOR_LAUNCH_MODE             replace|split|window (default: split)
  MONITOR_SPLIT_DIRECTION         h|v (default: h)
  MONITOR_WINDOW_AUTO_CLEANUP      true|false (default: true)
  MONITOR_PREVIEW_WIDTH            65% (default)
  MONITOR_POPUP_WIDTH              "80%" (default)
  MONITOR_POPUP_HEIGHT             "85%" (default)
  MONITOR_STATUS_FORMAT            space-separated: cpu mem disk temp load uptime
  MONITOR_DANGER_CPU               85
  MONITOR_DANGER_MEM               85
  MONITOR_DANGER_DISK              85
  MONITOR_COLOR_HEADER             color name: magenta (default)
  MONITOR_COLOR_LABEL              color name: cyan (default)
  MONITOR_COLOR_GOOD               color name: green (default)
  MONITOR_COLOR_WARN               color name: yellow (default)
  MONITOR_COLOR_DANGER             color name: red (default)
  MONITOR_PREVIEW_REFRESH_MS       2000 (default, 0 to disable auto-refresh)
  MONITOR_CUSTOM_TOOLS             pipe-separated tool definitions (see monitor.conf)
EOF
  exit 0
}

# --- Argument Parsing ---
case "${1:-}" in
  --help|-h)
    usage
    ;;
  --status)
    status_output
    exit 0
    ;;
  --menu)
    menu | awk '!seen[$0]++'
    exit 0
    ;;
  --popup)
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux display-popup \
        -w "${MONITOR_POPUP_WIDTH:-80%}" \
        -h "${MONITOR_POPUP_HEIGHT:-85%}" \
        -E -T " Monitor Center " \
        bash "$SCRIPT_PATH" --popup-inner
    fi
    ;;
  --popup-inner)
    MONITOR_LAUNCH_MODE="window"
    MONITOR_WINDOW_AUTO_CLEANUP="true"
    ;;
esac

# --- Prerequisites ---
have fzf || { echo "Error: 'fzf' is required but not installed." >&2; exit 1; }
[[ -x "$PREVIEW_SCRIPT" ]] || { echo "Error: Preview script not found at $PREVIEW_SCRIPT" >&2; exit 1; }

menu_entries=$(menu | awk '!seen[$0]++')
[[ -z "$menu_entries" ]] && {
  echo "Error: No supported monitoring tools found in PATH." >&2
  echo "Install one of: htop, btop, glances, nvtop, bmon, etc." >&2
  exit 1
}

# --- Interactive Loop ---
while true; do
  sel=$(
    printf '%s\n' "$menu_entries" | fzf \
      --ansi \
      --delimiter=$'\t' \
      --with-nth=1,3 \
      --layout=reverse \
      --height=95% \
      --margin=1,2 \
      --border=rounded \
      --border-label=" Monitor Center " \
      --cycle \
      --info=inline-right \
      --header-first \
      --prompt="󱂬 Monitor › " \
      --pointer="▶" \
      --header=$'Platform: '"$MONITOR_PLATFORM_LABEL"$'\n  Ctrl+R reload | F5 refresh | Ctrl+O preview | Esc quit' \
      --preview-window="right,$MONITOR_PREVIEW_WIDTH,wrap" \
      --preview-label=" Live Preview " \
      --bind "ctrl-r:reload($SCRIPT_PATH --menu)" \
      --bind "f5:reload($SCRIPT_PATH --menu)" \
      --bind "alt-p:refresh-preview" \
      --bind "ctrl-o:refresh-preview" \
      --preview "bash '$PREVIEW_SCRIPT' {}"
  )

  [[ -z "$sel" ]] && exit 0

  tool=$(echo "$sel" | cut -f2)

  [[ "$tool" == "__GROUP__" || -z "$tool" ]] && continue

  launch_tool "$tool"
done
