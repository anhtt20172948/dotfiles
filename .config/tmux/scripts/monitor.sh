#!/usr/bin/env bash
set -euo pipefail

# Standardized ANSI Color Palette
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_DIM=$'\033[2m'
readonly C_CYAN=$'\033[1;36m'
readonly C_BLUE=$'\033[1;34m'
readonly C_GREEN=$'\033[1;32m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_MAGENTA=$'\033[1;35m'
readonly C_RED=$'\033[1;31m'

# Graceful exit handling
cleanup() {
  printf '%b' "$C_RESET"
}
trap cleanup EXIT INT TERM

have() {
  command -v "$1" >/dev/null 2>&1
}

detect_platform() {
  local tags=()

  # Jetson detection
  if [[ -f /etc/nv_tegra_release ]] || have jtop; then
    tags+=(jetson)
  fi

  # Generic GPU server detection
  if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
    tags+=(gpu)
  fi

  # Container/K8s capabilities
  have docker && tags+=(docker)
  if have kubectl && kubectl config current-context >/dev/null 2>&1; then
    tags+=(kubernetes)
  fi

  [[ ${#tags[@]} -eq 0 ]] && tags+=(linux)
  (IFS=+; echo "${tags[*]}")
}

PLATFORM=$(detect_platform)
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")

platform_badges() {
  local p="$1"
  local labels=()

  [[ "$p" == *jetson* ]] && labels+=("Jetson")
  [[ "$p" == *gpu* ]] && labels+=("GPU")
  [[ "$p" == *docker* ]] && labels+=("Docker")
  [[ "$p" == *kubernetes* ]] && labels+=("Kubernetes")
  [[ ${#labels[@]} -eq 0 ]] && labels+=("Linux")

  local IFS=' | '
  echo "${labels[*]}"
}

PLATFORM_LABEL=$(platform_badges "$PLATFORM")

menu() {
  local gpu=() system=() container=() network=()

  # Menu Data Structure: DISPLAY_TEXT \t TOOL_KEY \t DESCRIPTION
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
  have k9s         && container+=($' 󱃾  k9s\tk9s\tKubernetes')

  have bmon        && network+=($' 󰩟  bmon\tbmon\tBandwidth')
  have nload       && network+=($' 󰤨  nload\tnload\tThroughput')
  have iftop       && network+=($' 󰛳  iftop\tiftop\tInterface Bandwidth')

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
}

PREVIEW='
tool=$(awk -F"\t" "{print \$2}" <<< "{}")

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[1;36m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[1;31m"

tool_command() {
  case "$1" in
    htop) echo "htop" ;;
    btop) echo "btop" ;;
    glances) echo "glances" ;;
    nvtop) echo "nvtop" ;;
    nvitop) echo "nvitop" ;;
    jtop) echo "jtop" ;;
    lazydocker) echo "lazydocker" ;;
    ctop) echo "TERM=xterm-256color ctop" ;;
    dockerstats) echo "docker stats" ;;
    bmon) echo "bmon" ;;
    nload) echo "nload" ;;
    iftop) echo "sudo iftop" ;;
    iotop) echo "sudo iotop" ;;
    dstat) echo "dstat" ;;
    k9s) echo "k9s" ;;
    __GROUP__) echo "Section Header" ;;
    *) echo "N/A" ;;
  esac
}

# Cross-platform CPU Calculation via /proc/stat
get_cpu_usage() {
  if [[ -f /proc/stat ]]; then
    read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
    local prev_idle=$((idle + iowait))
    local prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    sleep 0.1
    read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
    local idle_now=$((idle + iowait))
    local total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local total_diff=$((total_now - prev_total))
    local idle_diff=$((idle_now - prev_idle))
    if ((total_diff > 0)); then
      echo "$(( (total_diff - idle_diff) * 100 / total_diff ))"
      return
    fi
  fi
  echo "0"
}

# Cross-platform Memory Calculation via free
get_mem_usage() {
  free 2>/dev/null | awk '\''/Mem:/ {if ($2 > 0) printf("%.0f", $3/$2*100); else print "0"}'\'' || echo "0"
}

# Cross-platform Disk Usage
get_disk_usage() {
  df -P / 2>/dev/null | awk '\''NR==2{gsub("%","",$5); print $5}'\'' || echo "0"
}

cpu=$(get_cpu_usage)
mem=$(get_mem_usage)
disk=$(get_disk_usage)
host=${HOST:-$(hostname 2>/dev/null || echo "localhost")}
uptime_h=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "n/a")
loadavg=$(awk '\''{print $1" "$2" "$3}'\'' /proc/loadavg 2>/dev/null || echo "n/a")
cmd=$(tool_command "$tool")

clamp_percent() {
  local v=${1:-0}
  ((v < 0)) && v=0
  ((v > 100)) && v=100
  echo "$v"
}

level_color() {
  local v=${1:-0}
  if ((v >= 85)); then
    echo "$C_RED"
  elif ((v >= 65)); then
    echo "$C_YELLOW"
  else
    echo "$C_GREEN"
  fi
}

cpu=$(clamp_percent "$cpu")
mem=$(clamp_percent "$mem")
disk=$(clamp_percent "$disk")
cpu_color=$(level_color "$cpu")
mem_color=$(level_color "$mem")
disk_color=$(level_color "$disk")

bar() {
  local p=${1:-0} color=${2:-$C_GREEN} f=$((p/5)) e=$((20-f))
  printf "%b[" "$color"
  for ((i=0;i<f;i++)); do printf "█"; done
  for ((i=0;i<e;i++)); do printf "░"; done
  printf "] %3s%%%b" "$p" "$C_RESET"
}

printf "%b╔══════════════════════════════╗%b\n" "$C_MAGENTA" "$C_RESET"
printf "%b║      MONITOR CENTER V3       ║%b\n" "$C_MAGENTA" "$C_RESET"
printf "%b╚══════════════════════════════╝%b\n" "$C_MAGENTA" "$C_RESET"
echo
printf "%b󰒋 Host%b      : %s\n" "$C_CYAN" "$C_RESET" "$host"
printf "%b󰌽 Platform%b  : %s\n" "$C_CYAN" "$C_RESET" "PLATFORM_LABEL_VAR"
printf "%b󰔠 Uptime%b    : %s\n" "$C_CYAN" "$C_RESET" "$uptime_h"
printf "%b󰘚 Load Avg%b  : %s\n" "$C_CYAN" "$C_RESET" "$loadavg"
printf "%b󱓞 Command%b   : %b%s%b\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$cmd" "$C_RESET"
echo
printf "%bCPU%b  %s\n" "$C_BLUE" "$C_RESET" "$(bar "$cpu" "$cpu_color")"
printf "%bRAM%b  %s\n" "$C_BLUE" "$C_RESET" "$(bar "$mem" "$mem_color")"
printf "%bDSK%b  %s\n" "$C_BLUE" "$C_RESET" "$(bar "$disk" "$disk_color")"
echo

if command -v docker >/dev/null 2>&1; then
  printf "%b󰡨 Containers%b : %s active\n" "$C_GREEN" "$C_RESET" "$(docker ps -q 2>/dev/null | wc -l | tr -d " ")"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  printf "%b󰢮 GPU%b        : Detected\n" "$C_GREEN" "$C_RESET"
fi

echo
case "$tool" in
  jtop)
    command -v jetson_release >/dev/null && jetson_release
    ;;
  nvtop|nvitop)
    nvidia-smi 2>/dev/null | head -12 || echo "No NVIDIA GPU detected"
    ;;
  dockerstats|lazydocker|ctop)
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -10 || echo "Docker daemon not responding"
    ;;
  k9s)
    kubectl config current-context 2>/dev/null || echo "No Kubernetes Context active"
    ;;
  nload|bmon|iftop)
    ip -brief address 2>/dev/null | head -10 || echo "Network interfaces unavailable"
    ;;
  __GROUP__)
    echo "Select a specific monitoring tool from the list."
    ;;
  *)
    ps aux --sort=-%cpu 2>/dev/null | head -8
    ;;
esac
'

# Global string replacement fix (using standard // operator)
PREVIEW="${PREVIEW//PLATFORM_VAR/$PLATFORM}"
PREVIEW="${PREVIEW//PLATFORM_LABEL_VAR/$PLATFORM_LABEL}"

if [[ "${1:-}" == "--menu" ]]; then
  menu | awk '!seen[$0]++'
  exit 0
fi

have fzf || { echo "Error: 'fzf' is required but not installed." >&2; exit 1; }

menu_entries=$(menu | awk '!seen[$0]++')
[[ -z "$menu_entries" ]] && { echo "Error: No supported monitoring tools found in PATH." >&2; exit 1; }

# Interactive Selection Loop
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
      --header="Platform: $PLATFORM_LABEL" \
      --preview-window="right,65%,wrap" \
      --preview-label=" Live Preview " \
      --bind "ctrl-r:reload($SCRIPT_PATH --menu)" \
      --bind "f5:reload($SCRIPT_PATH --menu)" \
      --bind "alt-p:refresh-preview" \
      --preview "$PREVIEW"
  )

  # Exit quietly on ESC / Ctrl+C inside fzf
  [[ -z "$sel" ]] && exit 0

  tool=$(echo "$sel" | cut -f2)

  # Ignore Header selections and loop back
  if [[ "$tool" == "__GROUP__" || -z "$tool" ]]; then
    continue
  fi

  # Execution mapping
  case "$tool" in
    htop)        exec htop ;;
    btop)        exec btop ;;
    glances)     exec glances ;;
    nvtop)       exec nvtop ;;
    nvitop)      exec nvitop ;;
    jtop)        exec jtop ;;
    lazydocker)  exec lazydocker ;;
    ctop)        exec env TERM=xterm-256color ctop ;;
    dockerstats) exec docker stats ;;
    bmon)        exec bmon ;;
    nload)       exec nload ;;
    iftop)       exec sudo iftop ;;
    iotop)       exec sudo iotop ;;
    dstat)       exec dstat ;;
    k9s)         exec k9s ;;
    *)
      echo "Error: Unknown tool selected ($tool)" >&2
      exit 1
      ;;
  esac
done
