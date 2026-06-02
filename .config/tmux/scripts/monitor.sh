#!/usr/bin/env bash
set -euo pipefail

detect_platform() {
  local tags=()

  # Jetson detection
  if [[ -f /etc/nv_tegra_release ]] || command -v jtop >/dev/null 2>&1; then
    tags+=(jetson)
  fi

  # Generic GPU server detection
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    tags+=(gpu)
  fi

  # Container/K8s capabilities
  command -v docker >/dev/null 2>&1 && tags+=(docker)
  if command -v kubectl >/dev/null 2>&1 && kubectl config current-context >/dev/null 2>&1; then
    tags+=(kubernetes)
  fi

  [[ ${#tags[@]} -eq 0 ]] && tags+=(linux)
  (IFS=+; echo "${tags[*]}")
}

PLATFORM=$(detect_platform)
have(){ command -v "$1" >/dev/null 2>&1; }
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
  local gpu=()
  local system=()
  local container=()
  local network=()
  local reset=$'\033[0m'
  local c_gpu=$'\033[1;35m'
  local c_system=$'\033[1;36m'
  local c_container=$'\033[1;33m'
  local c_network=$'\033[1;32m'

  have jtop && gpu+=($'󰤽\tjtop\tJetson Stats ★')
  have nvitop && gpu+=($'󰚗\tnvitop\tCUDA Processes')
  have nvtop && gpu+=($'󰢮\tnvtop\tGPU Dashboard')

  have btop && system+=($'󰎴\tbtop\tSystem Dashboard')
  have htop && system+=($'󰍛\thtop\tCPU Processes')
  have glances && system+=($'󰢹\tglances\tSystem Analytics')
  have iotop && system+=($'󰋊\tiotop\tDisk I/O')

  have lazydocker && container+=($'󰡨\tlazydocker\tDocker Manager')
  have ctop && container+=($'󰕈\tctop\tContainer Top')
  have docker && container+=($'󰖂\tdockerstats\tDocker Stats')
  have k9s && container+=($'󱃾\tk9s\tKubernetes')

  have bmon && network+=($'󰩟\tbmon\tBandwidth')
  have nload && network+=($'󰤨\tnload\tThroughput')

  if [[ ${#gpu[@]} -gt 0 ]]; then
    printf '%b\t%s\t%s\n' "${c_gpu}╭─ GPU${reset}" "__group__" ""
    printf '%s\n' "${gpu[@]}"
  fi
  if [[ ${#system[@]} -gt 0 ]]; then
    printf '%b\t%s\t%s\n' "${c_system}├─ System${reset}" "__group__" ""
    printf '%s\n' "${system[@]}"
  fi
  if [[ ${#container[@]} -gt 0 ]]; then
    printf '%b\t%s\t%s\n' "${c_container}├─ Container${reset}" "__group__" ""
    printf '%s\n' "${container[@]}"
  fi
  if [[ ${#network[@]} -gt 0 ]]; then
    printf '%b\t%s\t%s\n' "${c_network}╰─ Network${reset}" "__group__" ""
    printf '%s\n' "${network[@]}"
  fi

  # Under set -e + pipefail, ensure this function does not fail
  # just because the last optional command is unavailable.
  return 0
}

PREVIEW='
tool=$(awk -F"\t" "{print \$2}" <<< "{}")

mem=$(free 2>/dev/null | awk "/Mem:/ {printf(\"%.0f\",\$3/\$2*100)}")
disk=$(df -P / 2>/dev/null | awk "NR==2{gsub(\"%\",\"\",\$5);print \$5}")
host=${HOST:-$(hostname 2>/dev/null)}
uptime_h=$(uptime -p 2>/dev/null || uptime 2>/dev/null)
loadavg=$(awk "{print \$1\" \"\$2\" \"\$3}" /proc/loadavg 2>/dev/null)

cpu=$(LC_ALL=C top -bn1 2>/dev/null | awk -F"," "/Cpu/ {gsub(\"%\",\"\",\$1); gsub(\"[^0-9.]\",\"\",\$1); print int(\$1)}" | head -1)
cpu=${cpu:-0}
mem=${mem:-0}
disk=${disk:-0}
loadavg=${loadavg:-n/a}

clamp_percent() {
  local v=${1:-0}
  ((v < 0)) && v=0
  ((v > 100)) && v=100
  echo "$v"
}

cpu=$(clamp_percent "$cpu")
mem=$(clamp_percent "$mem")
disk=$(clamp_percent "$disk")

bar() {
 p=${1:-0}; f=$((p/5)); e=$((20-f))
 printf "["
 for ((i=0;i<f;i++)); do printf "█"; done
 for ((i=0;i<e;i++)); do printf "░"; done
 printf "] %s%%" "$p"
}

echo "╔══════════════════════════════╗"
echo "║      MONITOR CENTER V3       ║"
echo "╚══════════════════════════════╝"
echo
echo "󰒋 Host      : $host"
echo "󰌽 Platform  : PLATFORM_LABEL"
echo "󰔠 Uptime    : $uptime_h"
echo "󰘚 Load Avg  : $loadavg"
echo
echo "CPU  $(bar $cpu)"
echo "RAM  $(bar ${mem:-0})"
echo "DSK  $(bar ${disk:-0})"
echo

if command -v docker >/dev/null 2>&1; then
  echo "󰡨 Containers : $(docker ps -q 2>/dev/null | wc -l)"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "󰢮 GPU Present"
fi

echo
case "$tool" in
 jtop)
   command -v jetson_release >/dev/null && jetson_release
   echo
   command -v tegrastats >/dev/null && echo "tegrastats available"
   ;;
 nvtop|nvitop)
   nvidia-smi 2>/dev/null | head -15 || echo "No NVIDIA GPU"
   ;;
 dockerstats|lazydocker|ctop)
   docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
   ;;
 k9s)
   kubectl config current-context 2>/dev/null || echo "No context"
   ;;
 nload|bmon)
   ip -brief address 2>/dev/null | head -10 || echo "No network info"
   ;;
 *)
   ps aux --sort=-%cpu | head -8
   ;;
esac
'
PREVIEW=${PREVIEW/PLATFORM/$PLATFORM}
PREVIEW=${PREVIEW/PLATFORM_LABEL/$PLATFORM_LABEL}

if [[ "${1:-}" == "--menu" ]]; then
  menu | awk '!seen[$0]++'
  exit 0
fi

have fzf || { echo "fzf is required" >&2; exit 1; }
menu_entries=$(menu | awk '!seen[$0]++')
[[ -z "$menu_entries" ]] && { echo "No monitoring tools found in PATH" >&2; exit 1; }

sel=$(printf '%s\n' "$menu_entries" | fzf \
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
  --prompt="󱂬 Monitor V3 › " \
  --pointer="▶" \
  --header="Platform: $PLATFORM_LABEL  |  Ctrl-R/F5: reload list  |  Alt-P: refresh preview" \
  --color=fg:#cdd6f4,bg:#1e1e2e,fg+:#f5e0dc,bg+:#313244,hl:#89b4fa,pointer:#f9e2af,border:#6c7086,header:#74c7ec \
  --preview-window="right,70%,wrap" \
  --preview-label=" Live Preview " \
  --bind "ctrl-r:reload($SCRIPT_PATH --menu),f5:reload($SCRIPT_PATH --menu),alt-p:refresh-preview" \
  --preview "$PREVIEW")

[[ -z "$sel" ]] && exit 0
tool=$(echo "$sel" | cut -f2)
[[ -z "$tool" || "$tool" == "__group__" ]] && exit 0

case "$tool" in
  htop) exec htop ;;
  btop) exec btop ;;
  glances) exec glances ;;
  nvtop) exec nvtop ;;
  nvitop) exec nvitop ;;
  jtop) exec jtop ;;
  lazydocker) exec lazydocker ;;
  ctop) exec env TERM=xterm-256color ctop ;;
  dockerstats) exec docker stats ;;
  bmon) exec bmon ;;
  nload) exec nload ;;
  iotop) exec iotop ;;
  k9s) exec k9s ;;
  *)
    echo "Unknown tool selected: $tool" >&2
    exit 1
    ;;
esac

