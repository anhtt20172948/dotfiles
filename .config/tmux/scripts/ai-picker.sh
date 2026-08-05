#!/usr/bin/env bash
# Interactive AI coding CLI picker (runs inside a tmux display-popup).
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

SCRIPT_PATH=${BASH_SOURCE[0]}

# Where the tools run. Inherited from persistent-ai.sh through the environment,
# and passed on into the fzf preview child. Defaults keep this script usable
# stand-alone (host only).
location=${AI_POPUP_LOCATION:-host}
container=${AI_POPUP_CONTAINER:-}

reset=$AI_RESET
bold=$AI_BOLD
lavender=$AI_LAVENDER
mauve=$AI_MAUVE
blue=$AI_BLUE
green=$AI_GREEN
yellow=$AI_YELLOW
red=$AI_RED
subtext=$AI_SUBTEXT

pause_with_error() {
  printf '%sai-picker:%s %s\n' "$red" "$reset" "$1" >&2
  read -rsn1 -p 'Press any key to close...'
  printf '\n'
  exit 1
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
  local exec_location=$1 executable=$2 output

  [[ -n "$executable" ]] || {
    printf 'not installed'
    return
  }

  output=$(location_run "$exec_location" "$executable" --version 2>/dev/null || true)
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

# ISO8601 -> local display string. Falls back to echoing the raw value so a
# format we cannot parse is still visible rather than silently blanked.
format_iso() {
  local value=${1:-} epoch
  [[ -n "$value" ]] || return 0
  epoch=$(ai_iso_to_epoch "$value") || { printf '%s' "$value"; return 0; }
  ai_fmt_epoch "$epoch" '%Y-%m-%d %H:%M %Z'
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

# ------------------------------------------------------------
# Usage panes.
#
# Both used to spawn jq per file — up to three per file across eighty files for
# Codex — which is a few hundred processes before the preview could paint. Each
# is now a single batched pass that emits one TSV row of every field the pane
# needs, so the whole pane costs one awk plus one jq.
#
# awk prefixes each line with its file's index rather than letting jq read the
# files itself: a transcript with no trailing newline (i.e. one being written
# right now) makes jq splice its last line onto the next file's first line,
# which loses rows in raw mode and aborts the entire program in JSON mode.
# The index is what makes "newest file that has this field" resolvable, since
# the file list is already newest-first.
# ------------------------------------------------------------
print_codex_usage() {
  local files file row
  local has_usage total input cached output context updated_epoch
  local has_rate percent window_minutes reset_at plan remaining

  print_section 'LIVE USAGE'
  if ! have jq; then
    printf '  %sjq is required to read Codex usage.%s\n' "$yellow" "$reset"
    return
  fi
  # Codex creates sessions/ lazily, on the first real conversation, so a missing
  # directory means "nothing recorded yet" rather than a broken path. Say that
  # instead of the old flat "unavailable", which read like a fault.
  if [[ ! -d $HOME/.codex/sessions ]]; then
    printf '  %sNo Codex history on this machine yet.%s\n' "$yellow" "$reset"
    printf '  Use %s/status%s inside Codex for live context and limits.\n' \
      "$bold" "$reset"
    return
  fi

  files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(ai_recent_files "$HOME/.codex/sessions" 6 80)
  if (( ${#files[@]} == 0 )); then
    printf '  %sNo Codex session history found.%s\n' "$yellow" "$reset"
    return
  fi

  row=$(awk 'FNR == 1 { n++ } { printf "%d\t%s\n", n, $0 }' "${files[@]}" 2>/dev/null \
    | jq -nRr --arg cwd "$PWD" '
    reduce ( inputs
             | index("\t") as $i
             | select($i != null)
             | {k: .[0:$i], r: (.[$i + 1:] | try fromjson catch empty)}
             | select(.r | type == "object") ) as $e
      ({};
        $e.k as $k | $e.r as $r
        | .[$k] = ( (.[$k] // {cwdok: false, usage: null, rate: null})
            | (if ($r.type // "") == "session_meta" and ($r.payload.cwd // "") == $cwd
               then .cwdok = true else . end)
            | (if ($r.type // "") == "event_msg"
                  and ($r.payload.type // "") == "token_count"
               then (if ($r.payload.info // null) != null
                     then .usage = {timestamp: $r.timestamp,
                                    usage: $r.payload.info.total_token_usage,
                                    context: $r.payload.info.model_context_window}
                     else . end)
                  | (if ($r.payload.rate_limits // null) != null
                     then .rate = {timestamp: $r.timestamp,
                                   rate: $r.payload.rate_limits}
                     else . end)
               else . end) ) )
    | [ to_entries[] | select(.value.cwdok) ] | sort_by(.key | tonumber) as $f
    | { u: ([$f[] | .value.usage | select(. != null)] | first),
        r: ([$f[] | .value.rate  | select(. != null)] | first) }
    | [ (if .u == null then 0 else 1 end),
        (.u.usage.total_tokens // 0),
        (.u.usage.input_tokens // 0),
        (.u.usage.cached_input_tokens // 0),
        (.u.usage.output_tokens // 0),
        (.u.context // 0),
        (if (.u.timestamp // null) == null then 0
         else (try (.u.timestamp | sub("\\.[0-9]+";"") | fromdateiso8601) catch 0) end),
        (if .r == null then 0 else 1 end),
        (.r.rate.primary.used_percent // ""),
        (.r.rate.primary.window_minutes // 0),
        ((.r.rate.primary.resets_at // 0) | try (tonumber | floor) catch 0),
        (.r.rate.plan_type // "") ] | @tsv
  ' 2>/dev/null)

  IFS=$'\t' read -r has_usage total input cached output context updated_epoch \
    has_rate percent window_minutes reset_at plan <<<"$row"

  if [[ "${has_usage:-0}" == 1 ]]; then
    print_field 'Session' "$(format_count "$total") tokens"
    print_field 'Input' "$(format_count "$input") ($(format_count "$cached") cached)"
    print_field 'Output' "$(format_count "$output") tokens"
    print_field 'Context' "$(format_count "$context") tokens"
    print_field 'Updated' "$(ai_fmt_epoch "$updated_epoch" '%Y-%m-%d %H:%M %Z')"
  else
    printf '  %sNo completed Codex turn found for this directory.%s\n' "$yellow" "$reset"
  fi

  [[ "${has_rate:-0}" == 1 && -n "${percent:-}" ]] || return
  remaining=$((100 - ${percent%.*}))

  printf '\n  %s%-12s%s %s %s%% used · %s%% left\n' \
    "$subtext" "$(format_window "$window_minutes") limit" "$reset" \
    "$(usage_bar "$percent")" "${percent%.*}" "$remaining"
  [[ "${reset_at:-0}" != 0 ]] && print_field 'Resets' "$(ai_fmt_epoch "$reset_at" '%Y-%m-%d %H:%M %Z')"
  [[ -n "${plan:-}" ]] && print_field 'Plan' "$(ai_capitalize "$plan")"
  return 0
}

print_claude_usage() {
  local project_dir files file row
  local messages input output cache_read cache_write first last

  print_section 'LOCAL USAGE'
  project_dir="$HOME/.claude/projects/${PWD//\//-}"
  if ! have jq || [[ ! -d "$project_dir" ]]; then
    printf '  %sNo local Claude usage data found for this directory.%s\n' "$yellow" "$reset"
    printf '  Use %s/usage%s inside Claude Code for subscription limits.\n' "$bold" "$reset"
    return
  fi

  files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(ai_recent_files "$project_dir" 1 200)
  # Guard before expanding: in bash 3.2, expanding an empty array under `set -u`
  # is itself an unbound-variable error.
  if (( ${#files[@]} == 0 )); then
    printf '  %sNo Claude session history found for this directory.%s\n' "$yellow" "$reset"
    return
  fi

  row=$(awk '{ printf "%s\n", $0 }' "${files[@]}" 2>/dev/null \
    | jq -nRr '
    reduce ( inputs | (try fromjson catch empty) | select(type == "object") ) as $r
      ({messages: 0, input: 0, output: 0, cache_read: 0, cache_write: 0,
        first: null, last: null};
        if ($r.message.usage? // null) != null then
          .messages += 1
          | .input += ($r.message.usage.input_tokens // 0)
          | .output += ($r.message.usage.output_tokens // 0)
          | .cache_read += ($r.message.usage.cache_read_input_tokens // 0)
          | .cache_write += ($r.message.usage.cache_creation_input_tokens // 0)
          | .first = (if .first == null or ($r.timestamp // "") < .first
                      then ($r.timestamp // .first) else .first end)
          | .last = (if .last == null or ($r.timestamp // "") > .last
                     then ($r.timestamp // .last) else .last end)
        else . end)
    | [ .messages, .input, .output, .cache_read, .cache_write,
        (if .first == null then 0
         else (try (.first | sub("\\.[0-9]+";"") | fromdateiso8601) catch 0) end),
        (if .last == null then 0
         else (try (.last | sub("\\.[0-9]+";"") | fromdateiso8601) catch 0) end)
      ] | @tsv
  ' 2>/dev/null)

  if [[ -z "$row" ]]; then
    printf '  %sClaude usage history could not be parsed.%s\n' "$yellow" "$reset"
    return
  fi

  IFS=$'\t' read -r messages input output cache_read cache_write first last <<<"$row"

  print_field 'Messages' "$(format_count "$messages") assistant responses"
  print_field 'Input' "$(format_count "$input") tokens"
  print_field 'Output' "$(format_count "$output") tokens"
  print_field 'Cache read' "$(format_count "$cache_read") tokens"
  print_field 'Cache write' "$(format_count "$cache_write") tokens"
  [[ "${first:-0}" != 0 ]] && print_field 'Since' "$(ai_fmt_epoch "$first" '%Y-%m-%d %H:%M %Z')"
  [[ "${last:-0}" != 0 ]] && print_field 'Updated' "$(ai_fmt_epoch "$last" '%Y-%m-%d %H:%M %Z')"
  printf '\n  %sLocal project totals; use %s/usage%s for subscription limits.%s\n' \
    "$yellow" "$bold" "$reset$yellow" "$reset"
  return 0
}

print_opencode_stats() {
  local executable=$1 stats status

  print_section 'USAGE STATISTICS'
  # ai_run_limited caps the wall clock without needing coreutils `timeout`,
  # which stock macOS does not ship — this pane used to be unreachable here.
  stats=$(NO_COLOR=1 ai_run_limited 6 "$executable" stats \
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
  local in_container=false container_path=''

  name=$(tool_name "$tool") || exit 1
  icon=$(tool_icon "$tool") || exit 1
  description=$(tool_description "$tool") || exit 1

  if [[ "$(location_kind "$location")" == container ]]; then
    in_container=true
    executable=$(locate_tool "$location" "$tool" || true)
    # Prefer the path the controller already resolved; fall back to computing it.
    container_path=${AI_POPUP_CONTAINER_PATH:-$(map_host_path_to_container "$container" "$PWD")}
  else
    executable=$(command -v "$tool" 2>/dev/null || true)
  fi
  version=$(tool_version "$location" "$executable")

  printf '\n  %s%s%s  %s%s%s\n' "$mauve$bold" "$icon" "$reset" "$bold" "$name" "$reset"
  printf '  %s%s%s\n' "$subtext" "$description" "$reset"

  print_section 'ENVIRONMENT'
  if tool_is_running "$tool"; then
    print_field 'Status' "${green}${bold}● Running — Enter to attach${reset}"
  else
    print_field 'Status' "${subtext}○ Not running — Enter to create${reset}"
  fi
  if [[ "$in_container" == true ]]; then
    print_field 'Location' "${green}container · ${container}${reset}"
  else
    print_field 'Location' 'host'
  fi
  print_field 'Version' "$version"
  print_field 'Executable' "${executable:-not found}"
  if [[ "$in_container" == true ]]; then
    print_field 'Directory' "${container_path:-?}  ${subtext}(${PWD})${reset}"
    print_field 'Launch' "docker exec ${container} ${tool}"
  else
    print_field 'Directory' "$PWD"
    print_field 'Launch' "$tool"
  fi

  print_section 'QUICK START'
  case "$tool" in
    codex)
      printf '  %s/%-12s%s Show model, permissions and context usage\n' "$blue" 'status' "$reset"
      printf '  %s/%-12s%s Review the current working tree\n' "$blue" 'review' "$reset"
      printf '  %s%-13s%s Resume an earlier conversation\n' "$blue" 'codex resume' "$reset"
      [[ "$in_container" == true ]] || print_codex_usage
      ;;
    opencode)
      printf '  %s/%-12s%s Open the command palette\n' "$blue" 'help' "$reset"
      printf '  %s/%-12s%s Start or switch sessions\n' "$blue" 'sessions' "$reset"
      printf '  %s%-13s%s Show token and cost statistics\n' "$blue" 'opencode stats' "$reset"
      [[ "$in_container" == false && -n "$executable" ]] && print_opencode_stats "$executable"
      ;;
    claude)
      printf '  %s/%-12s%s View plan limits and current usage\n' "$blue" 'usage' "$reset"
      printf '  %s/%-12s%s Show session and account status\n' "$blue" 'status' "$reset"
      printf '  %s/%-12s%s Inspect available commands\n' "$blue" 'help' "$reset"
      [[ "$in_container" == true ]] || print_claude_usage
      ;;
  esac

  # Usage/history panes read host state; they do not apply to a container tool.
  if [[ "$in_container" == true ]]; then
    print_section 'NOTE'
    printf '  %sLaunch + attach only. Resume, saved history and usage are\n' "$subtext"
    printf '  host-only for now.%s\n' "$reset"
  fi

  if [[ -z "$executable" ]]; then
    if [[ "$in_container" == true ]]; then
      printf '\n  %s⚠ %s was not found inside container %s.%s\n' \
        "$red$bold" "$name" "$container" "$reset"
    else
      printf '\n  %s⚠ %s is not installed or is missing from PATH.%s\n' \
        "$red$bold" "$name" "$reset"
    fi
  fi
}

if [[ ${1:-} == '--preview' ]]; then
  preview_tool "${2:-}"
  exit
fi

select_only=false
[[ ${1:-} == '--select' ]] && select_only=true

for bin in tmux fzf; do
  have "$bin" || pause_with_error "'$bin' not found in PATH"
done

# Built from the shared tool tables rather than hand-written ANSI literals, so
# the icons and names cannot drift from the session picker's copies again.
newline=$'\n'
tab=$'\t'
entries=''
for candidate in $AI_TOOLS; do
  label="$(tool_color "$candidate")$(tool_icon "$candidate")  $(tool_name "$candidate")${reset}"
  label="${label}  $(tool_menu_status "$candidate")"
  line="${candidate}${tab}${label}${tab}$(tool_description "$candidate")"
  entries="${entries:+${entries}${newline}}${line}"
done

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
    --pointer='' \
    --marker='' \
    --preview-window='right,60%,wrap,border-left' \
    --preview-label=' Details & Usage ' \
    --bind='ctrl-j:down,ctrl-k:up' \
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

tool_is_valid "$tool" || pause_with_error "invalid tool selection: $tool"

if [[ "$select_only" == true ]]; then
  printf '%s\n' "$tool"
  exit 0
fi

# Standalone fallback: invoked without --select (i.e. not from the controller),
# just open the tool in a new window on the current server.
executable=$(command -v "$tool" 2>/dev/null || true)
[[ -n "$executable" ]] || pause_with_error "'$tool' not found in PATH"

printf -v launch_command 'exec %q' "$executable"
tmux new-window -n "$tool" -c "$PWD" "$launch_command"
