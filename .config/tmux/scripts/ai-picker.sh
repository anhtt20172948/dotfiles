#!/usr/bin/env bash
# Interactive AI coding CLI picker (runs inside a tmux display-popup).
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

SCRIPT_PATH=${BASH_SOURCE[0]}

reset=$'\033[0m'
bold=$'\033[1m'
lavender=$'\033[38;2;180;190;254m'
mauve=$'\033[38;2;203;166;247m'
blue=$'\033[38;2;137;180;250m'
green=$'\033[38;2;166;227;161m'
yellow=$'\033[38;2;249;226;175m'
red=$'\033[38;2;243;139;168m'
subtext=$'\033[38;2;166;173;200m'

pause_with_error() {
  printf '%sai-picker:%s %s\n' "$red" "$reset" "$1" >&2
  read -rsn1 -p 'Press any key to close...'
  printf '\n'
  exit 1
}

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
    opencode) printf '' ;;
    claude)   printf '󱑺' ;;
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

tool_is_running() {
  [[ " ${AI_POPUP_RUNNING_TOOLS:-} " == *" $1 "* ]]
}

tool_running_count() {
  local tool=$1 item
  for item in ${AI_POPUP_RUNNING_COUNTS:-}; do
    [[ "${item%%=*}" == "$tool" ]] && {
      printf '%s' "${item#*=}"
      return
    }
  done
  printf '0'
}

tool_menu_status() {
  local count
  count=$(tool_running_count "$1")
  if (( count > 0 )); then
    printf '%s● %d running%s' "$green$bold" "$count" "$reset"
  else
    printf '%s○ idle%s' "$subtext" "$reset"
  fi
}

tool_version() {
  local executable=$1 output

  [[ -n "$executable" ]] || {
    printf 'not installed'
    return
  }

  output=$("$executable" --version 2>/dev/null || true)
  printf '%s' "${output%%$'\n'*}"
}

print_field() {
  printf '  %s%-12s%s %s\n' "$subtext" "$1" "$reset" "$2"
}

print_section() {
  printf '\n%s%s%s\n' "$mauve$bold" "$1" "$reset"
  printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
}

format_count() {
  local number=${1:-0} grouped=''

  while (( ${#number} > 3 )); do
    grouped=",${number: -3}${grouped}"
    number=${number:0:${#number}-3}
  done
  printf '%s%s' "$number" "$grouped"
}

format_time() {
  local value=${1:-}

  [[ -n "$value" ]] || return
  date -d "$value" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || printf '%s' "$value"
}

format_window() {
  local minutes=${1:-0}

  if (( minutes >= 1440 && minutes % 1440 == 0 )); then
    printf '%dd' "$((minutes / 1440))"
  elif (( minutes >= 60 && minutes % 60 == 0 )); then
    printf '%dh' "$((minutes / 60))"
  else
    printf '%dm' "$minutes"
  fi
}

usage_bar() {
  local percent=${1:-0} width=18 filled empty bar=''

  percent=${percent%.*}
  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  filled=$((percent * width / 100))
  empty=$((width - filled))

  (( filled > 0 )) && printf -v bar '%*s' "$filled" ''
  bar=${bar// /█}
  printf '%s%s' "$green" "$bar"
  printf -v bar '%*s' "$empty" ''
  bar=${bar// /░}
  printf '%s%s%s' "$subtext" "$bar" "$reset"
}

print_codex_usage() {
  local usage_json='' rate_json='' file file_cwd candidate
  local timestamp total input cached output context percent remaining
  local window_minutes reset_at plan

  print_section 'LIVE USAGE'
  if ! command -v jq >/dev/null 2>&1 || [[ ! -d $HOME/.codex/sessions ]]; then
    printf '  %sLocal Codex usage data is unavailable.%s\n' "$yellow" "$reset"
    return
  fi

  while IFS= read -r file; do
    file_cwd=$(jq -r 'select(.type == "session_meta") | .payload.cwd // empty' \
      "$file" 2>/dev/null | head -n 1)
    [[ "$file_cwd" == "$PWD" ]] || continue

    if [[ -z "$usage_json" ]]; then
      candidate=$(jq -c '
        select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)
        | {timestamp, usage: .payload.info.total_token_usage,
           context: .payload.info.model_context_window}' \
        "$file" 2>/dev/null | tail -n 1)
      [[ -n "$candidate" ]] && usage_json=$candidate
    fi

    if [[ -z "$rate_json" ]]; then
      candidate=$(jq -c '
        select(.type == "event_msg" and .payload.type == "token_count"
               and .payload.rate_limits != null)
        | {timestamp, rate: .payload.rate_limits}' \
        "$file" 2>/dev/null | tail -n 1)
      [[ -n "$candidate" ]] && rate_json=$candidate
    fi

    [[ -n "$usage_json" && -n "$rate_json" ]] && break
  done < <(find "$HOME/.codex/sessions" -type f -name '*.jsonl' \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -n 80)

  if [[ -n "$usage_json" ]]; then
    timestamp=$(jq -r '.timestamp // empty' <<<"$usage_json")
    total=$(jq -r '.usage.total_tokens // 0' <<<"$usage_json")
    input=$(jq -r '.usage.input_tokens // 0' <<<"$usage_json")
    cached=$(jq -r '.usage.cached_input_tokens // 0' <<<"$usage_json")
    output=$(jq -r '.usage.output_tokens // 0' <<<"$usage_json")
    context=$(jq -r '.context // 0' <<<"$usage_json")
    print_field 'Session' "$(format_count "$total") tokens"
    print_field 'Input' "$(format_count "$input") ($(format_count "$cached") cached)"
    print_field 'Output' "$(format_count "$output") tokens"
    print_field 'Context' "$(format_count "$context") tokens"
    print_field 'Updated' "$(format_time "$timestamp")"
  else
    printf '  %sNo completed Codex turn found for this directory.%s\n' "$yellow" "$reset"
  fi

  [[ -n "$rate_json" ]] || return
  percent=$(jq -r '.rate.primary.used_percent // empty' <<<"$rate_json")
  window_minutes=$(jq -r '.rate.primary.window_minutes // 0' <<<"$rate_json")
  reset_at=$(jq -r '.rate.primary.resets_at // empty' <<<"$rate_json")
  plan=$(jq -r '.rate.plan_type // empty' <<<"$rate_json")
  [[ -n "$percent" ]] || return
  remaining=$((100 - ${percent%.*}))

  printf '\n  %s%-12s%s %s %s%% used · %s%% left\n' \
    "$subtext" "$(format_window "$window_minutes") limit" "$reset" \
    "$(usage_bar "$percent")" "${percent%.*}" "$remaining"
  [[ -n "$reset_at" ]] && print_field 'Resets' "$(format_time "@$reset_at")"
  [[ -n "$plan" ]] && print_field 'Plan' "${plan^}"
}

print_claude_usage() {
  local project_dir usage_json messages input output cache_read cache_write first last
  local -a files=()

  print_section 'LOCAL USAGE'
  project_dir="$HOME/.claude/projects/${PWD//\//-}"
  if ! command -v jq >/dev/null 2>&1 || [[ ! -d "$project_dir" ]]; then
    printf '  %sNo local Claude usage data found for this directory.%s\n' "$yellow" "$reset"
    printf '  Use %s/usage%s inside Claude Code for subscription limits.\n' "$bold" "$reset"
    return
  fi

  mapfile -d '' files < <(find "$project_dir" -maxdepth 1 -type f -name '*.jsonl' -print0)
  if (( ${#files[@]} == 0 )); then
    printf '  %sNo Claude session history found for this directory.%s\n' "$yellow" "$reset"
    return
  fi

  usage_json=$(jq -n '
    reduce inputs as $row (
      {messages: 0, input: 0, output: 0, cache_read: 0, cache_write: 0,
       first: null, last: null};
      if ($row.message.usage? != null) then
        .messages += 1
        | .input += ($row.message.usage.input_tokens // 0)
        | .output += ($row.message.usage.output_tokens // 0)
        | .cache_read += ($row.message.usage.cache_read_input_tokens // 0)
        | .cache_write += ($row.message.usage.cache_creation_input_tokens // 0)
        | .first = (if .first == null or $row.timestamp < .first then $row.timestamp else .first end)
        | .last = (if .last == null or $row.timestamp > .last then $row.timestamp else .last end)
      else . end
    )' "${files[@]}" 2>/dev/null) || usage_json=''

  if [[ -z "$usage_json" ]]; then
    printf '  %sClaude usage history could not be parsed.%s\n' "$yellow" "$reset"
    return
  fi

  messages=$(jq -r '.messages // 0' <<<"$usage_json")
  input=$(jq -r '.input // 0' <<<"$usage_json")
  output=$(jq -r '.output // 0' <<<"$usage_json")
  cache_read=$(jq -r '.cache_read // 0' <<<"$usage_json")
  cache_write=$(jq -r '.cache_write // 0' <<<"$usage_json")
  first=$(jq -r '.first // empty' <<<"$usage_json")
  last=$(jq -r '.last // empty' <<<"$usage_json")

  print_field 'Messages' "$(format_count "$messages") assistant responses"
  print_field 'Input' "$(format_count "$input") tokens"
  print_field 'Output' "$(format_count "$output") tokens"
  print_field 'Cache read' "$(format_count "$cache_read") tokens"
  print_field 'Cache write' "$(format_count "$cache_write") tokens"
  [[ -n "$first" ]] && print_field 'Since' "$(format_time "$first")"
  [[ -n "$last" ]] && print_field 'Updated' "$(format_time "$last")"
  printf '\n  %sLocal project totals; use %s/usage%s for subscription limits.%s\n' \
    "$yellow" "$bold" "$reset$yellow" "$reset"
}

print_opencode_stats() {
  local executable=$1 stats status

  print_section 'USAGE STATISTICS'
  if ! command -v timeout >/dev/null 2>&1; then
    printf '  %sRun %sopencode stats%s in a shell to view tokens and cost.%s\n' \
      "$yellow" "$bold" "$reset$yellow" "$reset"
    return
  fi

  stats=$(NO_COLOR=1 timeout 4 "$executable" stats \
    --project '' --models 5 --tools 5 2>&1)
  status=$?
  if (( status == 0 )) && [[ -n "$stats" ]]; then
    printf '%s\n' "$stats" | sed 's/^/  /'
  else
    printf '  %sStatistics are unavailable from the picker.%s\n' "$yellow" "$reset"
    printf '  Run %sopencode stats --project ""%s in a shell to inspect this project.\n' \
      "$bold" "$reset"
  fi
}

preview_tool() {
  local tool=${1:-} name icon description executable version

  name=$(tool_name "$tool") || exit 1
  icon=$(tool_icon "$tool") || exit 1
  description=$(tool_description "$tool") || exit 1

  executable=$(command -v "$tool" 2>/dev/null || true)
  version=$(tool_version "$executable")

  printf '\n  %s%s%s  %s%s%s\n' "$mauve$bold" "$icon" "$reset" "$bold" "$name" "$reset"
  printf '  %s%s%s\n' "$subtext" "$description" "$reset"

  print_section 'ENVIRONMENT'
  if tool_is_running "$tool"; then
    print_field 'Status' "${green}${bold}● Running — Enter to attach${reset}"
  else
    print_field 'Status' "${subtext}○ Not running — Enter to create${reset}"
  fi
  print_field 'Version' "$version"
  print_field 'Executable' "${executable:-not found in PATH}"
  print_field 'Directory' "$PWD"
  print_field 'Launch' "$tool"

  print_section 'QUICK START'
  case "$tool" in
    codex)
      printf '  %s/%-12s%s Show model, permissions and context usage\n' "$blue" 'status' "$reset"
      printf '  %s/%-12s%s Review the current working tree\n' "$blue" 'review' "$reset"
      printf '  %s%-13s%s Resume an earlier conversation\n' "$blue" 'codex resume' "$reset"
      print_codex_usage
      ;;
    opencode)
      printf '  %s/%-12s%s Open the command palette\n' "$blue" 'help' "$reset"
      printf '  %s/%-12s%s Start or switch sessions\n' "$blue" 'sessions' "$reset"
      printf '  %s%-13s%s Show token and cost statistics\n' "$blue" 'opencode stats' "$reset"
      [[ -n "$executable" ]] && print_opencode_stats "$executable"
      ;;
    claude)
      printf '  %s/%-12s%s View plan limits and current usage\n' "$blue" 'usage' "$reset"
      printf '  %s/%-12s%s Show session and account status\n' "$blue" 'status' "$reset"
      printf '  %s/%-12s%s Inspect available commands\n' "$blue" 'help' "$reset"
      print_claude_usage
      ;;
  esac

  if [[ -z "$executable" ]]; then
    printf '\n  %s⚠ %s is not installed or is missing from PATH.%s\n' \
      "$red$bold" "$name" "$reset"
  fi
}

if [[ ${1:-} == '--preview' ]]; then
  preview_tool "${2:-}"
  exit
fi

select_only=false
[[ ${1:-} == '--select' ]] && select_only=true

for bin in tmux fzf; do
  command -v "$bin" >/dev/null 2>&1 || pause_with_error "'$bin' not found in PATH"
done

codex_status=$(tool_menu_status codex)
opencode_status=$(tool_menu_status opencode)
claude_status=$(tool_menu_status claude)
entries=$(printf '%s\n' \
  $'codex\t\033[38;2;180;190;254m󰘩  Codex\033[0m  '"$codex_status"$'\tOpenAI coding agent' \
  $'opencode\t\033[38;2;137;180;250m  OpenCode\033[0m  '"$opencode_status"$'\tOpen-source, provider-agnostic' \
  $'claude\t\033[38;2;203;166;247m󱑺  Claude Code\033[0m  '"$claude_status"$'\tAnthropic agentic coding assistant')

printf -v preview_command 'bash %q --preview {1}' "$SCRIPT_PATH"

selection=$(
  printf '%s\n' "$entries" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=2,3 \
    --accept-nth=1 \
    --no-sort \
    --cycle \
    --layout=reverse \
    --margin=1,2 \
    --border=rounded \
    --border-label=' AI Coding ' \
    --info=inline-right \
    --header-first \
    --header=$'Ctrl-j/k move  •  Enter select  •  Esc close  •  ● running  ○ idle\nWorking directory: '"$PWD" \
    --prompt='󱒜  Select › ' \
    --pointer='' \
    --marker='' \
    --preview-window='right,60%,wrap,border-left' \
    --preview-label=' Details & Usage ' \
    --bind='ctrl-j:down,ctrl-k:up,tab:down,btab:up,ctrl-r:refresh-preview' \
    --color='bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,info:#cba6f7,pointer:#f5e0dc,marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7' \
    --preview="$preview_command"
) || {
  fzf_status=$?
  case "$fzf_status" in
    1|130) exit 0 ;;
    *)     exit "$fzf_status" ;;
  esac
}

[[ -n "$selection" ]] || exit 0
tool=$selection

case "$tool" in
  codex|opencode|claude) ;;
  *) pause_with_error "invalid tool selection: $tool" ;;
esac

if [[ "$select_only" == true ]]; then
  printf '%s\n' "$tool"
  exit 0
fi

executable=$(command -v "$tool" 2>/dev/null || true)
[[ -n "$executable" ]] || pause_with_error "'$tool' not found in PATH"

printf -v launch_command 'exec %q' "$executable"
tmux new-window -n "$tool" -c "$PWD" "$launch_command"
