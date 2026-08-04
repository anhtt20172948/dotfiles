#!/usr/bin/env bash
# Tool-scoped picker for new, live and saved AI coding sessions.
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

reset=$'\033[0m'
bold=$'\033[1m'
lavender=$'\033[38;2;180;190;254m'
mauve=$'\033[38;2;203;166;247m'
blue=$'\033[38;2;137;180;250m'
green=$'\033[38;2;166;227;161m'
yellow=$'\033[38;2;249;226;175m'
subtext=$'\033[38;2;166;173;200m'

pause_with_message() {
  printf '\n  %s%s%s\n' "$yellow" "$1" "$reset"
  read -rsn1 -p '  Press any key to return...'
  printf '\n'
  exit 0
}

clean_title() {
  local value=${1:-}
  value=${value//$'\t'/ }
  value=${value//$'\r'/ }
  value=${value//$'\n'/ }
  while [[ "$value" == *'  '* ]]; do value=${value//  / }; done
  value=${value# }
  value=${value% }
  printf '%s' "${value:0:110}"
}

tool_details() {
  case "$1" in
    codex)    printf '󰘩|Codex|%s' "$lavender" ;;
    opencode) printf '|OpenCode|%s' "$blue" ;;
    claude)   printf '󱑺|Claude Code|%s' "$mauve" ;;
    *)        return 1 ;;
  esac
}

list_codex_sessions() {
  local file meta id timestamp epoch title
  command -v jq >/dev/null 2>&1 || return
  [[ -d $HOME/.codex/sessions ]] || return

  while IFS= read -r file; do
    meta=$(jq -r --arg cwd "$PWD" '
      select(.type == "session_meta" and .payload.cwd == $cwd)
      | [.payload.id, .payload.timestamp] | @tsv' "$file" 2>/dev/null | head -n 1)
    [[ -n "$meta" ]] || continue
    IFS=$'\t' read -r id timestamp <<<"$meta"
    [[ -n "$id" ]] || continue
    epoch=$(date -d "$timestamp" '+%s' 2>/dev/null || printf '0')
    title=$(jq -r '
      select(.type == "event_msg" and .payload.type == "user_message")
      | .payload.message // empty' "$file" 2>/dev/null | head -n 1)
    title=$(clean_title "$title")
    [[ -n "$title" ]] || title="Codex session ${id:0:8}"
    printf '%s\t%s\t%s\n' "$id" "$epoch" "$title"
  done < <(find "$HOME/.codex/sessions" -type f -name '*.jsonl' \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -n 100)
}

list_opencode_sessions() {
  local database sql_dir id epoch title
  database="$HOME/.local/share/opencode/opencode.db"
  command -v sqlite3 >/dev/null 2>&1 || return
  [[ -r "$database" ]] || return
  sql_dir=${PWD//\'/\'\'}

  while IFS=$'\t' read -r id epoch title; do
    [[ -n "$id" ]] || continue
    title=$(clean_title "$title")
    [[ -n "$title" ]] || title="OpenCode session ${id:0:12}"
    printf '%s\t%s\t%s\n' "$id" "$epoch" "$title"
  done < <(sqlite3 -readonly -tabs "$database" "
    SELECT id, CAST(time_updated / 1000 AS INTEGER),
           substr(replace(replace(title, char(9), ' '), char(10), ' '), 1, 110)
      FROM session
     WHERE directory = '$sql_dir'
     ORDER BY time_updated DESC
     LIMIT 100;" 2>/dev/null)
}

list_claude_sessions() {
  local project_dir file row id timestamp epoch title
  command -v jq >/dev/null 2>&1 || return
  project_dir="$HOME/.claude/projects/${PWD//\//-}"
  [[ -d "$project_dir" ]] || return

  while IFS= read -r file; do
    row=$(jq -sr --arg cwd "$PWD" '
      map(select(.sessionId != null and .cwd == $cwd))[0] as $first
      | if $first == null then empty else
          (map(select(.customTitle? != null and .customTitle != "")) | last
             | .customTitle // "") as $custom
          | (map(select(.type == "user")
              | .message.content
              | if type == "array" then
                  map(select(.type == "text") | .text) | join(" ")
                else . end)
             | map(select(. != null and . != "")) | first // "") as $prompt
          | [$first.sessionId, ($first.timestamp // ""),
             (if $custom != "" then $custom
              elif ($first.slug // "") != "" then $first.slug
              else $prompt end)] | @tsv
        end' "$file" 2>/dev/null)
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r id timestamp title <<<"$row"
    [[ -n "$id" ]] || continue
    epoch=$(date -d "$timestamp" '+%s' 2>/dev/null || printf '0')
    title=$(clean_title "$title")
    [[ -n "$title" ]] || title="Claude session ${id:0:8}"
    printf '%s\t%s\t%s\n' "$id" "$epoch" "$title"
  done < <(find "$project_dir" -maxdepth 1 -type f -name '*.jsonl' \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -n 100)
}

saved_has_id() {
  local wanted=$1 id _epoch _title
  while IFS=$'\t' read -r id _epoch _title; do
    [[ "$id" == "$wanted" ]] && return 0
  done <<<"${saved_rows:-}"
  return 1
}

running_name_for_id() {
  local wanted=$1 name row_tool row_path id _created _label
  while IFS='|' read -r name row_tool row_path id _created _label; do
    [[ "$row_tool" == "$tool" && "$row_path" == "$PWD" && "$id" == "$wanted" ]] || continue
    printf '%s' "$name"
    return
  done <<<"${running_rows:-}"
}

preview_session() {
  local action=${1:-} preview_tool=${2:-} value=${3:-} epoch=${4:-0} title=${5:-}
  local details icon name color status command updated
  details=$(tool_details "$preview_tool") || exit 1
  IFS='|' read -r icon name color <<<"$details"
  updated=$(date -d "@$epoch" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || printf 'now')

  case "$action" in
    new)
      status="${green}${bold}＋ Create a new conversation${reset}"
      command="$preview_tool"
      ;;
    attach)
      status="${green}${bold}● Running — Enter to attach${reset}"
      command="tmux attach · $value"
      ;;
    resume)
      status="${subtext}○ Saved — Enter to resume${reset}"
      case "$preview_tool" in
        codex) command="codex resume $value" ;;
        opencode) command="opencode --session $value" ;;
        claude) command="claude --resume $value" ;;
      esac
      ;;
    *) exit 1 ;;
  esac

  printf '\n  %s%s%s  %s%s%s\n' "$color$bold" "$icon" "$reset" "$bold" "$name" "$reset"
  printf '  %s%s%s\n\n' "$subtext" "$title" "$reset"
  printf '%s%sSESSION%s\n' "$mauve" "$bold" "$reset"
  printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
  printf '  %s%-11s%s %s\n' "$subtext" 'Status' "$reset" "$status"
  printf '  %s%-11s%s %s\n' "$subtext" 'Updated' "$reset" "$updated"
  printf '  %s%-11s%s %s\n' "$subtext" 'Directory' "$reset" "$PWD"
  [[ "$action" == resume ]] && printf '  %s%-11s%s %s\n' "$subtext" 'Session ID' "$reset" "$value"
  printf '  %s%-11s%s %s\n' "$subtext" 'Command' "$reset" "$command"
}

if [[ ${1:-} == '--preview' ]]; then
  preview_session "${2:-}" "${3:-}" "${4:-}" "${5:-0}" "${6:-}"
  exit
fi

[[ ${1:-} == '--tool' && -n ${2:-} ]] || pause_with_message 'Select an AI tool first.'
tool=$2
details=$(tool_details "$tool") || pause_with_message "Unknown AI tool: $tool"
IFS='|' read -r icon name color <<<"$details"
command -v fzf >/dev/null 2>&1 || pause_with_message 'fzf is required for the session picker.'

case "$tool" in
  codex) saved_rows=$(list_codex_sessions | sort -t $'\t' -k2,2nr) ;;
  opencode) saved_rows=$(list_opencode_sessions | sort -t $'\t' -k2,2nr) ;;
  claude) saved_rows=$(list_claude_sessions | sort -t $'\t' -k2,2nr) ;;
esac

server_name=${AI_POPUP_SERVER_NAME:-codex-popup}
running_rows=$(tmux -L "$server_name" list-sessions \
  -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}|#{@ai_popup_session_id}|#{session_created}|#{@ai_popup_label}' \
  2>/dev/null || true)

now=$(date '+%s')
printf -v entries 'new\t%s\t-\t%s\tNew %s session\t%s%s＋  New session%s  %sStart a new %s conversation%s' \
  "$tool" "$now" "$name" "$green" "$bold" "$reset" "$subtext" "$name" "$reset"

# Live sessions without a corresponding saved row get their own attach entry.
while IFS='|' read -r session_name row_tool row_path session_id created label; do
  [[ "$row_tool" == "$tool" && "$row_path" == "$PWD" ]] || continue
  [[ -n "$session_id" ]] && saved_has_id "$session_id" && continue
  [[ -n "$label" ]] || label="Live ${name} session"
  updated=$(date -d "@$created" '+%m-%d %H:%M' 2>/dev/null || printf 'now')
  printf -v entry 'attach\t%s\t%s\t%s\t%s\t%s%s%s  %s● running%s  %s  %s' \
    "$tool" "$session_name" "$created" "$label" "$color$bold" "$icon" "$reset" \
    "$green$bold" "$reset" "$updated" "$label"
  entries+=$'\n'"$entry"
done <<<"$running_rows"

while IFS=$'\t' read -r session_id epoch title; do
  [[ -n "$session_id" ]] || continue
  running_name=$(running_name_for_id "$session_id")
  updated=$(date -d "@$epoch" '+%m-%d %H:%M' 2>/dev/null || printf 'unknown')
  if [[ -n "$running_name" ]]; then
    action=attach
    value=$running_name
    status="${green}${bold}● running${reset}"
  else
    action=resume
    value=$session_id
    status="${subtext}○ saved${reset}"
  fi
  printf -v entry '%s\t%s\t%s\t%s\t%s\t%s%s%s  %s  %s  %s' \
    "$action" "$tool" "$value" "$epoch" "$title" "$color$bold" "$icon" "$reset" \
    "$status" "$updated" "$title"
  entries+=$'\n'"$entry"
done <<<"$saved_rows"

printf -v preview_command 'bash %q --preview {1} {2} {3} {4} {5}' "${BASH_SOURCE[0]}"
selection=$(printf '%s\n' "$entries" | fzf \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=6 \
  --accept-nth=1,2,3 \
  --no-sort \
  --cycle \
  --layout=reverse \
  --margin=1,2 \
  --border=rounded \
  --border-label=" ${name} Sessions " \
  --info=inline-right \
  --header-first \
  --header=$'Ctrl-j/k move  •  Enter select  •  Esc back\nCurrent project: '"$PWD" \
  --prompt="${icon}  ${name} › " \
  --pointer='' \
  --preview-window='right,48%,wrap,border-left' \
  --preview-label=' Session Details ' \
  --bind='ctrl-j:down,ctrl-k:up,tab:down,btab:up' \
  --color='bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,info:#cba6f7,pointer:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7' \
  --preview="$preview_command") || {
    status=$?
    case "$status" in 1|130) exit 0 ;; *) exit "$status" ;; esac
  }

[[ -n "$selection" ]] && printf '%s\n' "$selection"
