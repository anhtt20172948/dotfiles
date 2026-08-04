#!/usr/bin/env bash
set -euo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./monitor-lib.sh
source "$LIB_DIR/monitor-lib.sh"

: "${MONITOR_PLATFORM_LABEL:=Linux}"
: "${MONITOR_HISTORY_SIZE:=20}"
: "${MONITOR_HISTORY_ENABLED:=true}"
: "${MONITOR_PREVIEW_PROCESSES:=6}"
: "${MONITOR_DANGER_CPU:=85}"
: "${MONITOR_DANGER_MEM:=85}"
: "${MONITOR_DANGER_DISK:=85}"
: "${MONITOR_WARN_CPU:=65}"
: "${MONITOR_WARN_MEM:=65}"
: "${MONITOR_WARN_DISK:=65}"
: "${MONITOR_PREVIEW_REFRESH_MS:=0}"

# color_name_to_ansi / load_theme / MONITOR_HISTORY_DIR come from monitor-lib.sh
load_theme

clamp_percent() {
  local v=${1:-0}
  ((v < 0)) && v=0
  ((v > 100)) && v=100
  echo "$v"
}

level_color() {
  local v=${1:-0} warn=${2:-65} danger=${3:-85}
  if ((v >= danger)); then
    echo "$C_RED"
  elif ((v >= warn)); then
    echo "$C_YELLOW"
  else
    echo "$C_GREEN"
  fi
}

bar() {
  local p=${1:-0}
  local color=${2:-$C_GREEN}
  local f=$((p/5))
  local e=$((20-f))
  printf "%b[" "$color"
  for ((i=0;i<f;i++)); do printf "█"; done
  for ((i=0;i<e;i++)); do printf "░"; done
  printf "] %3s%%%b" "$p" "$C_RESET"
}

update_history() {
  # MONITOR_HISTORY_ENABLED was previously documented in monitor.conf but never
  # actually consulted — history was always written. Now it is honoured.
  [[ "$MONITOR_HISTORY_ENABLED" == "true" ]] || return 0
  local val=$1
  monitor_init_history_dir || return 0
  printf '%s\n' "$val" >> "$MONITOR_HISTORY_DIR/cpu"
  local tmp
  tmp=$(tail -n "$MONITOR_HISTORY_SIZE" "$MONITOR_HISTORY_DIR/cpu" 2>/dev/null)
  printf '%s\n' "$tmp" > "$MONITOR_HISTORY_DIR/cpu"
}

sparkline() {
  local file=$1 n=${2:-$MONITOR_HISTORY_SIZE}
  [[ ! -f $file ]] && return
  local vals
  vals=$(tail -n "$n" "$file" 2>/dev/null) || return
  [[ -z "$vals" ]] && return
  local max=1 min=100
  while IFS= read -r v; do
    ((v > max)) && max=$v
    ((v < min)) && min=$v
  done <<< "$vals"
  ((max == min)) && max=$((min + 1))
  local range=$((max - min))
  local blocks=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
  local idx
  while IFS= read -r v; do
    idx=$(( (v - min) * 8 / range ))
    printf '%s' "${blocks[$idx]}"
  done <<< "$vals"
}

# get_cpu_fast comes from monitor-lib.sh (shared with monitor.sh).

get_cpu_usage() {
  if [[ "$MONITOR_PREVIEW_REFRESH_MS" -gt 0 ]]; then
    get_cpu_fast
    return
  fi
  if [[ -f /proc/stat ]]; then
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    local prev_idle=$((idle + iowait))
    local prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    sleep 0.05
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    local idle_now=$((idle + iowait))
    local total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local total_diff=$((total_now - prev_total))
    local idle_diff=$((idle_now - prev_idle))
    if ((total_diff > 0)); then
      echo "$(( (total_diff - idle_diff) * 100 / total_diff ))"
      return
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    top -l 2 -n 0 -s 0 2>/dev/null | awk '/CPU usage/ {gsub(/%/,""); print int($3+$5); exit}'
    return
  fi
  echo "0"
}

get_cpu_count() {
  if [[ -f /proc/cpuinfo ]]; then
    grep -c ^processor /proc/cpuinfo 2>/dev/null || nproc 2>/dev/null || echo "?"
  elif [[ "$(uname)" == "Darwin" ]]; then
    sysctl -n hw.ncpu 2>/dev/null || echo "?"
  else
    echo "?"
  fi
}

get_mem_usage() {
  if have free; then
    free | awk '/Mem:/ {if ($2 > 0) printf("%.0f", $3/$2*100); else print "0"}'
  elif [[ "$(uname)" == "Darwin" ]]; then
    vm_stat | awk '/Pages active/ {a=$NF} /Pages wired/ {w=$NF} /Pages free/ {f=$NF} /page size/ {s=$NF} END {total=a+w+f; if(total>0) printf("%.0f", (a+w)/total*100)}'
  else
    echo "0"
  fi
}

get_mem_human() {
  if have free; then
    free -h | awk '/Mem:/ {printf "%s / %s", $3, $2}'
  elif [[ "$(uname)" == "Darwin" ]]; then
    local memtotal memused
    memtotal=$(sysctl -n hw.memsize 2>/dev/null)
    memused=$(vm_stat | awk '/Pages active/ {a=$NF} /Pages wired/ {w=$NF} END {printf "%.0f", (a+w)*4096}')
    if [[ -n "$memtotal" && -n "$memused" && "$memtotal" -gt 0 ]]; then
      local used_mb=$((memused / 1048576))
      local total_mb=$((memtotal / 1048576))
      printf "%dM / %dM" "$used_mb" "$total_mb"
    fi
  fi
}

get_disk_usage() {
  df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}' || echo "0"
}

get_disk_human() {
  df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s", $3, $2}'
}

get_top_processes() {
  local count=${1:-6}
  if [[ "$(uname)" == "Darwin" ]]; then
    ps -axo pid=,pcpu=,pmem=,comm= -r 2>/dev/null | head -n "$count"
  else
    ps -axo pid=,pcpu=,pmem=,cputime=,comm= --sort=-pcpu 2>/dev/null | head -n "$count"
  fi
}

get_gpu_info() {
  if have nvidia-smi; then
    nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -4
  fi
}

get_container_count() {
  if have docker; then
    docker ps -q 2>/dev/null | wc -l
  fi
}

get_temperature() {
  if have sensors; then
    sensors -u 2>/dev/null | awk '/temp1_input/ {print $2; exit}'
  elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null
  fi
}

# The builtin tool->command map lives in monitor-lib.sh so this preview shows
# exactly what monitor.sh will run. This wrapper only adds the display-only
# cases and resolves MONITOR_CUSTOM_TOOLS entries.
display_command() {
  local tool=$1 cmd
  [[ "$tool" == "__GROUP__" ]] && { echo "Section Header"; return; }
  load_custom_tools
  cmd=$(resolve_tool_command "$tool" || true)
  printf '%s' "${cmd:-N/A}"
}

preview() {
  local line="${1:-}"
  local tool
  tool=$(awk -F"\t" '{print $2}' <<< "$line")

  local platform="${MONITOR_PLATFORM_LABEL:-Linux}"
  local host="${HOST:-$(hostname 2>/dev/null || echo "localhost")}"
  local uptime_h
  uptime_h=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "n/a")
  local loadavg
  loadavg=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "n/a")
  local cpu_cores
  cpu_cores=$(get_cpu_count)
  local cmd
  cmd=$(display_command "$tool")

  local cpu
  cpu=$(get_cpu_usage)
  local mem
  mem=$(get_mem_usage)
  local disk
  disk=$(get_disk_usage)

  cpu=$(clamp_percent "$cpu")
  mem=$(clamp_percent "$mem")
  disk=$(clamp_percent "$disk")

  local cpu_color
  cpu_color=$(level_color "$cpu")
  local mem_color
  mem_color=$(level_color "$mem")
  local disk_color
  disk_color=$(level_color "$disk")

  update_history "$cpu"

  printf "%b╔══════════════════════════════╗%b\n" "$C_MAGENTA" "$C_RESET"
  printf "%b║      MONITOR CENTER V3       ║%b\n" "$C_MAGENTA" "$C_RESET"
  printf "%b╚══════════════════════════════╝%b\n" "$C_MAGENTA" "$C_RESET"
  echo
  printf "%b󰒋 Host%b      : %s\n" "$C_CYAN" "$C_RESET" "$host"
  printf "%b󰌽 Platform%b  : %s\n" "$C_CYAN" "$C_RESET" "$platform"
  printf "%b󰔠 Uptime%b    : %s\n" "$C_CYAN" "$C_RESET" "$uptime_h"
  printf "%b󰘚 Load Avg%b  : %s  (%s cores)\n" "$C_CYAN" "$C_RESET" "$loadavg" "$cpu_cores"
  printf "%b󱓞 Command%b   : %b%s%b\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$cmd" "$C_RESET"
  echo
  printf "%bCPU%b  %s" "$C_BLUE" "$C_RESET" "$(bar "$cpu" "$cpu_color")"
  local spk
  spk=$(sparkline "$MONITOR_HISTORY_DIR/cpu" 10)
  [[ -n "$spk" ]] && printf "  %b%s%b" "$C_DIM" "$spk" "$C_RESET"
  echo
  local mem_human
  mem_human=$(get_mem_human)
  if [[ -n "$mem_human" ]]; then
    printf "%bRAM%b  %s  %b(%s)%b\n" "$C_BLUE" "$C_RESET" "$(bar "$mem" "$mem_color")" "$C_DIM" "$mem_human" "$C_RESET"
  else
    printf "%bRAM%b  %s\n" "$C_BLUE" "$C_RESET" "$(bar "$mem" "$mem_color")"
  fi
  local disk_human
  disk_human=$(get_disk_human)
  if [[ -n "$disk_human" ]]; then
    printf "%bDSK%b  %s  %b(%s)%b\n" "$C_BLUE" "$C_RESET" "$(bar "$disk" "$disk_color")" "$C_DIM" "$disk_human" "$C_RESET"
  else
    printf "%bDSK%b  %s\n" "$C_BLUE" "$C_RESET" "$(bar "$disk" "$disk_color")"
  fi
  echo

  local temp
  temp=$(get_temperature)
  if [[ -n "$temp" ]]; then
    local temp_color
    if awk "BEGIN {exit !($temp >= 70)}" 2>/dev/null; then
      temp_color=$C_RED
    elif awk "BEGIN {exit !($temp >= 50)}" 2>/dev/null; then
      temp_color=$C_YELLOW
    else
      temp_color=$C_GREEN
    fi
    printf "%b󰔄 Temp%b      : %b%.1f°C%b\n" "$C_CYAN" "$C_RESET" "$temp_color" "$temp" "$C_RESET"
  fi

  local gpu_info
  gpu_info=$(get_gpu_info)
  if [[ -n "$gpu_info" ]]; then
    while IFS=, read -r idx name temp_gpu util_gpu mem_used mem_total; do
      name="${name# }"
      printf "%b󰢮 GPU %s%b   : %s  %b|%b  %s°C  %b|%b  %d%%  %b|%b  %dM/%dM\n" \
        "$C_GREEN" "$idx" "$C_RESET" \
        "$name" \
        "$C_RED" "$C_RESET" "$temp_gpu" \
        "$C_YELLOW" "$C_RESET" "$util_gpu" \
        "$C_BLUE" "$C_RESET" "$mem_used" "$mem_total"
    done <<< "$gpu_info"
  fi

  local container_count
  container_count=$(get_container_count)
  if [[ -n "$container_count" && "$container_count" -gt 0 ]]; then
    printf "%b󰡨 Containers%b : %s active\n" "$C_GREEN" "$C_RESET" "$container_count"
  fi

  echo

  local top_procs_raw
  top_procs_raw=$(get_top_processes "$MONITOR_PREVIEW_PROCESSES")
  if [[ -n "$top_procs_raw" ]]; then
    printf "%b── Top Processes ──%b\n" "$C_BOLD" "$C_RESET"
    if [[ "$(uname)" == "Darwin" ]]; then
      printf "  %-7s %5s %5s  %s\n" "PID" "CPU%" "MEM%" "COMMAND"
      while IFS= read -r proc_line; do
        read -r pid pcpu pmem comm <<< "$proc_line"
        printf "  %-7s %b%5s%%%b %b%5s%%%b  %s\n" \
          "$pid" \
          "$(level_color "${pcpu%%.*}" 50 80)" "${pcpu}" "$C_RESET" \
          "$(level_color "${pmem%%.*}" 50 80)" "${pmem}" "$C_RESET" \
          "$(basename "$comm")"
      done <<< "$top_procs_raw"
    else
      printf "  %-7s %5s %5s %6s  %s\n" "PID" "CPU%" "MEM%" "TIME" "COMMAND"
      while IFS= read -r proc_line; do
        read -r pid pcpu pmem cputime comm <<< "$proc_line"
        printf "  %-7s %b%5s%%%b %b%5s%%%b %6s  %s\n" \
          "$pid" \
          "$(level_color "${pcpu%%.*}" 50 80)" "${pcpu}" "$C_RESET" \
          "$(level_color "${pmem%%.*}" 50 80)" "${pmem}" "$C_RESET" \
          "$cputime" \
          "$(basename "$comm")"
      done <<< "$top_procs_raw"
    fi
    echo
  fi

  printf "%b── Tool Preview ──%b\n" "$C_BOLD" "$C_RESET"
  case "$tool" in
    jtop)
      if have jetson_release; then
        jetson_release 2>/dev/null
      else
        printf "  %bJetson Stats%b — run jtop for interactive monitoring\n" "$C_MAGENTA" "$C_RESET"
      fi
      ;;
    nvtop|nvitop)
      if have nvidia-smi; then
        nvidia-smi 2>/dev/null | tail -n +3 | head -10
      else
        printf "  %bNo NVIDIA GPU detected%b\n" "$C_YELLOW" "$C_RESET"
      fi
      ;;
    dockerstats|lazydocker|ctop)
      # `have docker` first: this branch is reachable whenever lazydocker or ctop
      # is installed, and without the guard a missing docker binary reported
      # "daemon not responding", which points at the wrong problem.
      if ! have docker; then
        printf "  %bdocker CLI not installed%b\n" "$C_DIM" "$C_RESET"
      elif ! docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -10; then
        printf "  %bDocker daemon not responding%b\n" "$C_RED" "$C_RESET"
      fi
      ;;
    k9s)
      local ctx
      ctx=$(kubectl config current-context 2>/dev/null) || ctx=""
      if [[ -n "$ctx" ]]; then
        printf "  %bKubernetes context%b: %s\n" "$C_YELLOW" "$C_RESET" "$ctx"
        kubectl config get-contexts 2>/dev/null | head -6
      else
        printf "  %bNo Kubernetes context active%b\n" "$C_DIM" "$C_RESET"
      fi
      ;;
    nload|bmon|iftop)
      ip -brief address 2>/dev/null | head -10 || \
        printf "  %bNetwork interfaces unavailable%b\n" "$C_DIM" "$C_RESET"
      ;;
    btop|htop|glances|iotop|dstat)
      printf "  %bInteractive system monitor — launches on selection%b\n" "$C_DIM" "$C_RESET"
      ;;
    __GROUP__)
      printf "  %bSelect a specific monitoring tool from the list above%b\n" "$C_DIM" "$C_RESET"
      ;;
    *)
      if [[ "$(uname)" == "Darwin" ]]; then
        ps -axo pid=,pcpu=,pmem=,comm= -r 2>/dev/null | head -8
      else
        ps -axo pid=,pcpu=,pmem=,cputime=,comm= --sort=-pcpu 2>/dev/null | head -10
      fi
      ;;
  esac
}

# --- Main Execution ---
if [[ "$MONITOR_PREVIEW_REFRESH_MS" -gt 0 ]]; then
  interval=$(( MONITOR_PREVIEW_REFRESH_MS / 1000 ))
  (( interval < 1 )) && interval=1
  while true; do
    printf '\033[2J\033[H'
    preview "$@" || true
    sleep "$interval"
  done
else
  preview "$@"
fi
