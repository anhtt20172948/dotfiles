#!/usr/bin/env bash

menu() {
cat <<'EOF'
━━━━━━━━━━ SYSTEM ━━━━━━━━━━
󰍛  htop         CPU / Processes
󰎴  btop         System Dashboard
󰘚  btm          Bottom Monitor
󰢹  glances      System Analytics

━━━━━━━━━━ GPU ━━━━━━━━━━
󰢮  nvtop        GPU Dashboard
󰚗  nvitop       CUDA Processes
󰢹  nvidia-smi   NVIDIA CLI Monitor

━━━━━━━━ CONTAINERS ━━━━━━━━
󰡨  lazydocker   Docker Manager
󰕈  ctop         Container Top
󰖂  dockerstats  Docker Stats

━━━━━━━━━━ NETWORK ━━━━━━━━━
󰩟  bmon         Bandwidth Monitor
󰈀  iftop        Traffic Analyzer
󰤨  nload        Network Throughput

━━━━━━━━━━ STORAGE ━━━━━━━━━
󰋊  iotop        Disk I/O Monitor

━━━━━━━━ KUBERNETES ━━━━━━━━
󱃾  k9s          Kubernetes TUI
EOF
}

selected=$(
menu | \
fzf \
  --ansi \
  --layout=reverse \
  --height=100% \
  --border=rounded \
  --cycle \
  --header-first \
  --info=inline-right \
  --prompt="󱂬 Monitor Center › " \
  --pointer="▶" \
  --marker="✓" \
  --separator="━" \
  --color=fg:#cdd6f4,bg:#1e1e2e,fg+:#f5e0dc,bg+:#313244,hl:#89b4fa,hl+:#f38ba8,info:#a6e3a1,prompt:#89b4fa,pointer:#f9e2af,marker:#a6e3a1,border:#6c7086,header:#74c7ec \
  --header=" SYSTEM MONITORING CENTER " \
  --preview-window="right,65%,border-left,wrap" \
  --preview '
tool=$(echo {} | awk "{print \$2}")

host=${HOST:-$(cat /etc/hostname 2>/dev/null)}
kernel=$(uname -r)

cpu=$(top -bn1 | awk -F"," "/Cpu/ {gsub(\"%\",\"\",\$1); print int(\$1)}" | head -1)
mem=$(free | awk "/Mem:/ {printf(\"%.0f\",\$3/\$2*100)}")
disk=$(df / | awk "NR==2 {gsub(\"%\",\"\",\$5); print \$5}")

bar() {
  p=$1
  filled=$((p/5))
  empty=$((20-filled))

  printf "["
  for i in $(seq 1 $filled); do printf "█"; done
  for i in $(seq 1 $empty); do printf "░"; done
  printf "] %s%%" "$p"
}

echo
echo "╭──────────────────────────────╮"
echo "│      SYSTEM OVERVIEW         │"
echo "╰──────────────────────────────╯"
echo
echo "󰒋 Host    : $host"
echo "󰌽 Kernel  : $kernel"
echo
echo "CPU  $(bar ${cpu:-0})"
echo "RAM  $(bar ${mem:-0})"
echo "DISK $(bar ${disk:-0})"
echo

if command -v "$tool" >/dev/null 2>&1; then
  echo "✓ Installed"
else
  echo "✗ Not installed"
fi

echo
echo "Selected:"
echo "  $tool"

case "$tool" in

htop)
  echo
  ps aux --sort=-%cpu | head -10
  ;;

btop|btm|glances)
  echo
  uptime
  ;;

nvtop|nvitop)
  echo
  nvidia-smi 2>/dev/null | head -20
  ;;

dockerstats|lazydocker|ctop)
  echo
  docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
  ;;

bmon|iftop|nload)
  echo
  ip -brief address 2>/dev/null
  ;;

iotop)
  echo
  df -h
  ;;

k9s)
  echo
  kubectl config current-context 2>/dev/null
  ;;

esac
'
)

[[ -z "$selected" ]] && exit 0

tool=$(echo "$selected" | awk '{print $2}')

case "$tool" in
  htop)        exec htop ;;
  btop)        exec btop ;;
  btm)         exec btm ;;
  glances)     exec glances ;;

  nvtop)       exec nvtop ;;
  nvitop)      exec nvitop ;;
  nvidia-smi)  exec watch -n1 nvidia-smi ;;

  lazydocker)  exec lazydocker ;;
  ctop)        exec ctop ;;
  dockerstats) exec docker stats ;;

  bmon)        exec bmon ;;
  iftop)       exec iftop ;;
  nload)       exec nload ;;

  iotop)       exec iotop ;;

  k9s)         exec k9s ;;
esac
