#!/usr/bin/env bash
set -euo pipefail

detect_platform() {
  [[ -f /etc/nv_tegra_release ]] && { echo jetson; return; }
  command -v jtop >/dev/null 2>&1 && { echo jetson; return; }
  command -v kubectl >/dev/null 2>&1 && kubectl config current-context >/dev/null 2>&1 && { echo kubernetes; return; }
  command -v docker >/dev/null 2>&1 && { echo docker; return; }
  echo linux
}

PLATFORM=$(detect_platform)
have(){ command -v "$1" >/dev/null 2>&1; }

menu() {
  [[ "$PLATFORM" = jetson ]] && {
    have jtop && echo -e "󰤽\tjtop\tJetson Stats ★"
    have nvitop && echo -e "󰚗\tnvitop\tCUDA Processes"
    have nvtop && echo -e "󰢮\tnvtop\tGPU Dashboard"
  }

  have btop && echo -e "󰎴\tbtop\tSystem Dashboard"
  have htop && echo -e "󰍛\thtop\tCPU Processes"
  have glances && echo -e "󰢹\tglances\tSystem Analytics"

  have lazydocker && echo -e "󰡨\tlazydocker\tDocker Manager"
  have ctop && echo -e "󰕈\tctop\tContainer Top"
  have docker && echo -e "󰖂\tdockerstats\tDocker Stats"

  have bmon && echo -e "󰩟\tbmon\tBandwidth"
  have nload && echo -e "󰤨\tnload\tThroughput"

  have iotop && echo -e "󰋊\tiotop\tDisk I/O"
  have k9s && echo -e "󱃾\tk9s\tKubernetes"

  # Under set -e + pipefail, ensure this function does not fail
  # just because the last optional command is unavailable.
  return 0
}

PREVIEW='
tool=$(echo {} | cut -f2)

mem=$(free | awk "/Mem:/ {printf(\"%.0f\",\$3/\$2*100)}")
disk=$(df / | awk "NR==2{gsub(\"%\",\"\",\$5);print \$5}")
host=${HOST:-$(cat /etc/hostname 2>/dev/null)}

cpu=$(top -bn1 | awk -F"," "/Cpu/ {gsub(\"%\",\"\",\$1); gsub(\"[^0-9.]\",\"\",\$1); print int(\$1)}" | head -1)
cpu=${cpu:-0}

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
echo "󰌽 Platform  : PLATFORM"
echo "󰔠 Uptime    : $(uptime -p 2>/dev/null)"
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
 *)
   ps aux --sort=-%cpu | head -8
   ;;
esac
'
PREVIEW=${PREVIEW/PLATFORM/$PLATFORM}

have fzf || { echo "fzf is required" >&2; exit 1; }
menu_entries=$(menu | sort -u)
[[ -z "$menu_entries" ]] && { echo "No monitoring tools found in PATH" >&2; exit 1; }

sel=$(printf '%s\n' "$menu_entries" | fzf \
  --delimiter=$'\t' \
  --with-nth=1,2,3 \
  --layout=reverse \
  --height=100% \
  --border=rounded \
  --cycle \
  --info=inline-right \
  --prompt="󱂬 Monitor V3 › " \
  --pointer="▶" \
  --header="Platform: $PLATFORM" \
  --color=fg:#cdd6f4,bg:#1e1e2e,fg+:#f5e0dc,bg+:#313244,hl:#89b4fa,pointer:#f9e2af,border:#6c7086,header:#74c7ec \
  --preview-window="right,70%,wrap" \
  --preview "$PREVIEW")

[[ -z "$sel" ]] && exit 0
tool=$(echo "$sel" | cut -f2)

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
esac

