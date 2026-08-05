#!/usr/bin/env bash
# Tool-scoped picker for new, live and saved AI coding sessions.
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

reset=$AI_RESET
bold=$AI_BOLD
lavender=$AI_LAVENDER
mauve=$AI_MAUVE
green=$AI_GREEN
yellow=$AI_YELLOW
red=$AI_RED
subtext=$AI_SUBTEXT

# Where the tools run. Inherited from persistent-ai.sh via the environment and
# passed through into the fzf preview child. A container location lists only New
# + live-attach entries: resume and saved history are host-only in v1.
location=${AI_POPUP_LOCATION:-host}
container=${AI_POPUP_CONTAINER:-}
container_path=${AI_POPUP_CONTAINER_PATH:-}

# ------------------------------------------------------------
# On-screen prompts. Every byte of these goes to stderr, and that is not a
# style choice — it is required.
#
# This script's stdout is a machine-readable channel: the caller runs it as
# `selection=$(ai-sessions.sh --tool X)` and parses the single
# "action<TAB>tool<TAB>value" line it prints. Anything else written to stdout is
# captured into that variable instead of being displayed.
#
# These three functions used to printf to stdout, which broke the delete flow
# outright: the screen clears and messages disappeared into $selection (only the
# `read -p` prompts showed, since read writes its prompt to stderr — hence the
# telltale "Continue? [y/N]   Press any key to return..." on one line), and the
# escape sequences then parsed as the action field, so the next selection died
# with "invalid AI session selection". Keep the >&2.
# ------------------------------------------------------------
pause_with_message() {
  printf '\n  %s%s%s\n' "$yellow" "$1" "$reset" >&2
  read -rsn1 -p '  Press any key to return...'
  printf '\n' >&2
  exit 0
}

wait_with_message() {
  printf '\033[2J\033[H\n  %s%s%s\n\n' "$yellow" "$1" "$reset" >&2
  read -rsn1 -p '  Press any key to return...'
  printf '\n' >&2
}

confirm_action() {
  local prompt=$1 answer
  printf '\033[2J\033[H\n  %s%s%s\n\n' "$red$bold" "$prompt" "$reset" >&2
  read -rsn1 -p '  Continue? [y/N] ' answer
  printf '\n' >&2
  [[ "$answer" == y || "$answer" == Y ]]
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

# ------------------------------------------------------------
# Saved-session listings. Each emits "id<TAB>epoch<TAB>title".
#
# All three used to walk their files one at a time and spawn one or two jq per
# file for up to 100 files, i.e. a couple of hundred processes before the popup
# could paint. They now make a single batched pass, attributing each row to its
# session by the filename awk prefixes onto it (see below for why awk and not
# jq's own input_filename).
#
# -R plus `try fromjson catch empty`, rather than plain -n: a transcript that is
# being appended to right now can end mid-line, and in non-raw mode that one
# parse error aborts jq and takes every other row with it (verified: rc=5, zero
# output). -r is what keeps @tsv unquoted.
#
# awk prefixes each line with its filename instead of letting jq read the files
# directly, and that is load-bearing rather than stylistic: given a file with no
# trailing newline — exactly what a transcript being written right now looks
# like — jq -R joins its last line to the *next* file's first line, so both rows
# fail to parse and that whole next session silently disappears. Since the file
# list is newest-first, the live transcript is always first, so the bug would
# eat the second-newest session every time. awk terminates every record and
# never joins across files.
#
# The epoch is computed inside jq because `fromdateiso8601` reads the trailing Z
# as UTC. `date -d` is GNU-only and used to fail on every call here, silently
# collapsing every epoch to 0 and making the recency sort meaningless.
# ------------------------------------------------------------
# list_codex_sessions [root] [cwd]
#   root defaults to $HOME and cwd to $PWD (the host case); the container case
#   passes a temp dir holding the container's copied ~/.codex and the CONTAINER
#   project path, so the same parser serves both.
# Every lister emits "id<TAB>epoch<TAB>title<TAB>dir", where dir is the session's
# OWN recorded directory. all=1 lists every session regardless of directory
# (the "show all" scope); all=0 keeps only those whose directory is cwd. The dir
# column is what lets resume launch in the session's real directory even in
# all-mode, where it may differ from the currently scoped one.
list_codex_sessions() {
  local root=${1:-$HOME} cwd=${2:-$PWD} all=${3:-0}
  local files id epoch title dir file
  have jq || return 0
  [ -d "$root/.codex/sessions" ] || return 0

  files=()
  while IFS= read -r file; do
    [ -n "$file" ] && files+=("$file")
  done < <(ai_recent_files "$root/.codex/sessions" 6 100)
  [ ${#files[@]} -gt 0 ] || return 0

  while IFS=$'\t' read -r id epoch title dir; do
    [ -n "$id" ] || continue
    title=$(clean_title "$title")
    [ -n "$title" ] || title="Codex session ${id:0:8}"
    printf '%s\t%s\t%s\t%s\n' "$id" "$epoch" "$title" "$dir"
  done < <(awk '{ printf "%s\t%s\n", FILENAME, $0 }' "${files[@]}" 2>/dev/null \
    | jq -nRr --arg cwd "$cwd" --arg all "$all" '
    reduce ( inputs
             | index("\t") as $i
             | select($i != null)
             | {f: .[0:$i], r: (.[$i + 1:] | try fromjson catch empty)}
             | select(.r | type == "object") ) as $e
      ({};
        $e.f as $f | $e.r as $r
        | .[$f] = ( (.[$f] // {id:null, ts:null, title:null, cwd:null})
            | (if ($r.type // "") == "session_meta"
               then .id = (.id // $r.payload.id)
                  | .ts = (.ts // $r.payload.timestamp)
                  | .cwd = (.cwd // $r.payload.cwd)
               else . end)
            | (if (.title // "") == ""
                  and ($r.type // "") == "event_msg"
                  and ($r.payload.type // "") == "user_message"
               then .title = ($r.payload.message // null) else . end) ) )
    | to_entries[] | .value | select(.id != null)
    | select($all == "1" or (.cwd // "") == $cwd)
    | [ .id,
        (if .ts == null then 0
         else (try (.ts | sub("\\.[0-9]+";"") | fromdateiso8601) catch 0) end),
        ((.title // "") | gsub("[\\n\\r\\t]+"; " ") | .[0:110]),
        (.cwd // "") ] | @tsv
  ' 2>/dev/null)
}

list_opencode_sessions() {
  local root=${1:-$HOME} cwd=${2:-$PWD} all=${3:-0}
  local database sql_dir where id epoch title dir
  database="$root/.local/share/opencode/opencode.db"
  have sqlite3 || return 0
  [ -r "$database" ] || return 0
  sql_dir=${cwd//\'/\'\'}
  if [ "$all" = 1 ]; then where=''; else where="WHERE directory = '$sql_dir'"; fi

  while IFS=$'\t' read -r id epoch title dir; do
    [ -n "$id" ] || continue
    title=$(clean_title "$title")
    [ -n "$title" ] || title="OpenCode session ${id:0:12}"
    printf '%s\t%s\t%s\t%s\n' "$id" "$epoch" "$title" "$dir"
  done < <(sqlite3 -readonly -tabs "$database" "
    SELECT id, CAST(time_updated / 1000 AS INTEGER),
           substr(replace(replace(title, char(9), ' '), char(10), ' '), 1, 110),
           directory
      FROM session
     $where
     ORDER BY time_updated DESC
     LIMIT 100;" 2>/dev/null)
}

list_claude_sessions() {
  local root=${1:-$HOME} cwd=${2:-$PWD} all=${3:-0}
  local scan_dir depth files id epoch title dir file
  have jq || return 0
  # Scoped: the one project's slug dir (files one level down). All: the whole
  # projects tree (slug dir + its files, so two levels down).
  if [ "$all" = 1 ]; then
    scan_dir="$root/.claude/projects"; depth=2
  else
    scan_dir="$root/.claude/projects/${cwd//\//-}"; depth=1
  fi
  [ -d "$scan_dir" ] || return 0

  files=()
  while IFS= read -r file; do
    [ -n "$file" ] && files+=("$file")
  done < <(ai_recent_files "$scan_dir" "$depth" 100)
  [ ${#files[@]} -gt 0 ] || return 0

  while IFS=$'\t' read -r id epoch title dir; do
    [ -n "$id" ] || continue
    title=$(clean_title "$title")
    [ -n "$title" ] || title="Claude session ${id:0:8}"
    printf '%s\t%s\t%s\t%s\n' "$id" "$epoch" "$title" "$dir"
  done < <(awk '{ printf "%s\t%s\n", FILENAME, $0 }' "${files[@]}" 2>/dev/null \
    | jq -nRr --arg cwd "$cwd" --arg all "$all" '
    reduce ( inputs
             | index("\t") as $i
             | select($i != null)
             | {f: .[0:$i], r: (.[$i + 1:] | try fromjson catch empty)}
             | select(.r | type == "object") ) as $e
      ({};
        $e.f as $f | $e.r as $r
        | .[$f] = ( (.[$f] // {id:null, ts:null, slug:null, custom:null, prompt:null, dir:null})
            | (if ($r.sessionId // "") != ""
               then .id = (.id // $r.sessionId)
                  | .ts = (.ts // $r.timestamp)
                  | .dir = (.dir // $r.cwd)
                  | .slug = (.slug // (if ($r.slug // "") != "" then $r.slug else null end))
               else . end)
            | (if ($r.customTitle // "") != "" then .custom = $r.customTitle else . end)
            | (if (.prompt // "") == "" and ($r.type // "") == "user"
               then .prompt = ($r.message.content
                     | if type == "array" then (map(select(.type == "text") | .text) | join(" "))
                       elif type == "string" then . else null end)
               else . end) ) )
    | to_entries[] | .value | select(.id != null)
    | select($all == "1" or (.dir // "") == $cwd)
    | [ .id,
        (if .ts == null then 0
         else (try (.ts | sub("\\.[0-9]+";"") | fromdateiso8601) catch 0) end),
        ( ((.custom // "") as $c | (.slug // "") as $s | (.prompt // "") as $p
           | if $c != "" then $c elif $s != "" then $s else $p end)
          | gsub("[\\n\\r\\t]+"; " ") | .[0:110] ),
        (.dir // "") ] | @tsv
  ' 2>/dev/null)
}

saved_has_id() {
  local wanted=$1 id _epoch _title
  while IFS=$'\t' read -r id _epoch _title; do
    [[ "$id" == "$wanted" ]] && return 0
  done <<<"${saved_rows:-}"
  return 1
}

# Link a live "New session" to the conversation the tool created for it.
#
# The list is joined from two independent sources — tmux for live sessions, the
# tool's own store for saved ones — on @ai_popup_session_id. persistent-ai.sh
# cannot set that for a new session: only the agent knows its conversation id and
# it is assigned after launch. So until they are paired, one conversation appears
# twice, as `● running` from tmux and `○ saved` from the store. That is not just
# cosmetic — picking the saved copy resolves to a different tmux session name and
# would start a SECOND agent on the same conversation.
#
# Pairing rule: act only when exactly one live session is unlinked AND exactly one
# unclaimed conversation is at least as new as it. Anything ambiguous is left
# alone, because a wrong pairing would aim Ctrl-d at someone else's history — a
# visible duplicate is much cheaper than that.
link_new_session() {
  local name row_tool row_path id created _label
  local unlinked='' unlinked_created=0 unlinked_count=0
  local claimed=' ' cand_id cand_epoch _t pick='' pick_count=0

  while IFS='|' read -r name row_tool row_path id created _label row_loc; do
    [[ -n "$name" ]] || continue
    [[ "$row_tool" == "$tool" && "$row_path" == "$PWD" ]] || continue
    location_matches "$location" "$row_loc" || continue
    if [[ -n "$id" ]]; then
      claimed="${claimed}${id} "
      continue
    fi
    unlinked=$name
    unlinked_created=$created
    unlinked_count=$((unlinked_count + 1))
  done <<<"${running_rows:-}"

  [[ "$unlinked_count" -eq 1 ]] || return 0
  case $unlinked_created in ''|*[!0-9]*) return 0 ;; esac

  while IFS=$'\t' read -r cand_id cand_epoch _t; do
    [[ -n "$cand_id" ]] || continue
    case "$claimed" in *" $cand_id "*) continue ;; esac
    case $cand_epoch in ''|*[!0-9]*) continue ;; esac
    # A few seconds of slack: the agent writes its row moments after tmux starts
    # the session, and the two clocks are not sampled at the same instant.
    [[ "$cand_epoch" -ge "$((unlinked_created - 10))" ]] || continue
    pick=$cand_id
    pick_count=$((pick_count + 1))
  done <<<"${saved_rows:-}"

  [[ "$pick_count" -eq 1 && -n "$pick" ]] || return 0
  # No '=' exact-match prefix here: set-option rejects it outright ("no such
  # session: =name") even though has-session and kill-session accept it. The
  # names are unique so plain -t is unambiguous, and this matches how
  # persistent-ai.sh writes the same option.
  tmux -L "$server_name" set-option -t "$unlinked" \
    @ai_popup_session_id "$pick" || return 0

  # Re-read so the entry builders below see the link we just made.
  running_rows=$(tmux -L "$server_name" list-sessions \
    -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}|#{@ai_popup_session_id}|#{session_created}|#{@ai_popup_label}|#{@ai_popup_location}' \
    2>/dev/null || true)
  return 0
}

running_name_for_id() {
  local wanted=$1 name row_tool row_path id _created _label row_loc
  while IFS='|' read -r name row_tool row_path id _created _label row_loc; do
    [[ "$row_tool" == "$tool" && "$row_path" == "$PWD" && "$id" == "$wanted" ]] || continue
    location_matches "$location" "$row_loc" || continue
    printf '%s' "$name"
    return
  done <<<"${running_rows:-}"
}

stop_running_session() {
  local target=$1
  tmux -L "$server_name" has-session -t "=${target}" 2>/dev/null || return 1
  tmux -L "$server_name" kill-session -t "=${target}"
}

delete_saved_session() {
  local delete_tool=$1 session_id=$2 output project_dir session_file session_dir
  local trash_targets=()

  case "$delete_tool" in
    codex)
      [[ "$session_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
        printf 'invalid session ID'
        return 2
      }
      have codex || { printf 'codex command not found'; return 3; }
      output=$(codex delete --force "$session_id" 2>&1) || {
        printf '%s' "$output"
        return 1
      }
      ;;
    opencode)
      [[ "$session_id" =~ ^ses_[[:alnum:]_-]+$ ]] || {
        printf 'invalid session ID'
        return 2
      }
      have opencode || { printf 'opencode command not found'; return 3; }
      output=$(opencode session delete "$session_id" 2>&1) || {
        printf '%s' "$output"
        return 1
      }
      ;;
    claude)
      [[ "$session_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
        printf 'invalid session ID'
        return 2
      }
      project_dir="$HOME/.claude/projects/${PWD//\//-}"
      session_file="$project_dir/${session_id}.jsonl"
      session_dir="$project_dir/$session_id"
      [[ -f "$session_file" ]] && trash_targets+=("$session_file")
      [[ -d "$session_dir" ]] && trash_targets+=("$session_dir")
      # Guard before expanding: in bash 3.2, expanding an empty array under
      # `set -u` is itself an unbound-variable error.
      (( ${#trash_targets[@]} > 0 )) || {
        printf 'saved history was not found'
        return 4
      }
      # ai_trash, not `gio trash`: gio is GVFS, i.e. Linux. macOS ships
      # /usr/bin/trash, and this branch used to bail out entirely without gio.
      output=$(ai_trash "${trash_targets[@]}" 2>&1) || {
        printf '%s' "$output"
        return 1
      }
      ;;
    *) return 2 ;;
  esac
}

preview_session() {
  local action=${1:-} preview_tool=${2:-} value=${3:-} session_id=${4:-}
  local epoch=${5:-0} title=${6:-} dir=${7:-}
  local details icon name color status command updated shown_dir
  details=$(tool_details "$preview_tool") || exit 1
  IFS='|' read -r icon name color <<<"$details"
  updated=$(ai_fmt_epoch "$epoch" '%Y-%m-%d %H:%M %Z')

  local in_container=false
  [[ "$(location_kind "$location")" == container ]] && in_container=true

  case "$action" in
    new)
      status="${green}${bold}＋ Create a new conversation${reset}"
      if [[ "$in_container" == true ]]; then
        command="docker exec ${container} ${preview_tool}"
      else
        command="$preview_tool"
      fi
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
      [[ "$in_container" == true ]] && command="docker exec ${container} ${command}"
      ;;
    *) exit 1 ;;
  esac

  printf '\n  %s%s%s  %s%s%s\n' "$color$bold" "$icon" "$reset" "$bold" "$name" "$reset"
  printf '  %s%s%s\n\n' "$subtext" "$title" "$reset"
  printf '%s%sSESSION%s\n' "$mauve" "$bold" "$reset"
  printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
  printf '  %s%-11s%s %s\n' "$subtext" 'Status' "$reset" "$status"
  if [[ "$in_container" == true ]]; then
    printf '  %s%-11s%s %scontainer · %s%s\n' "$subtext" 'Location' "$reset" "$green" "$container" "$reset"
  else
    printf '  %s%-11s%s %s\n' "$subtext" 'Location' "$reset" 'host'
  fi
  if [[ "$action" != new ]]; then
    printf '  %s%-11s%s %s\n' "$subtext" 'Updated' "$reset" "$updated"
  fi
  # For a container session the meaningful cwd is the one inside the container
  # (the session's own dir, or the scoped one for a new session), not the host.
  if [[ "$in_container" == true ]]; then
    shown_dir=${dir:-?}
  else
    shown_dir=$PWD
  fi
  printf '  %s%-11s%s %s\n' "$subtext" 'Directory' "$reset" "$shown_dir"
  [[ -n "$session_id" && "$session_id" != - ]] && \
    printf '  %s%-11s%s %s\n' "$subtext" 'Session ID' "$reset" "$session_id"
  printf '  %s%-11s%s %s\n' "$subtext" 'Command' "$reset" "$command"

  printf '\n%s%sACTIONS%s\n' "$mauve" "$bold" "$reset"
  printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
  if [[ "$action" == attach ]]; then
    printf '  %sCtrl-x%s      Stop running session\n' "$yellow$bold" "$reset"
  else
    printf '  %sCtrl-x%s      Stop unavailable\n' "$subtext" "$reset"
  fi
  if [[ "$in_container" == true ]]; then
    printf '  %sCtrl-d%s      Delete host-only for now\n' "$subtext" "$reset"
  elif [[ -n "$session_id" && "$session_id" != - ]]; then
    printf '  %sCtrl-d%s      Delete saved session\n' "$red$bold" "$reset"
  else
    printf '  %sCtrl-d%s      Delete unavailable\n' "$subtext" "$reset"
  fi
}

if [[ ${1:-} == '--preview' ]]; then
  preview_session "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-0}" "${7:-}" "${8:-}"
  exit
fi

[[ ${1:-} == '--tool' && -n ${2:-} ]] || pause_with_message 'Select an AI tool first.'
tool=$2
details=$(tool_details "$tool") || pause_with_message "Unknown AI tool: $tool"
IFS='|' read -r icon name color <<<"$details"
have fzf || pause_with_message 'fzf is required for the session picker.'

server_name=${AI_POPUP_SERVER_NAME:-$AI_SERVER_DEFAULT}

# Container scope, adjustable from inside the picker:
#   scope_dir  the directory a NEW session launches in, and — unless scope_all —
#              the one saved sessions are filtered to. Starts at the path the
#              controller resolved; Ctrl-w changes it.
#   scope_all  1 = list saved sessions from EVERY directory in the container
#              (Ctrl-a toggles). New sessions still launch in scope_dir.
scope_dir=$container_path
scope_all=0

# prompt_for_dir -> read a new scope_dir from the user (Ctrl-w). All prompts go
# to stderr; stdout stays the machine channel.
prompt_for_dir() {
  local ans
  printf '\033[2J\033[H\n  %sSet the container working directory%s\n\n' "$yellow$bold" "$reset" >&2
  printf '  %sCurrent:%s %s\n\n' "$subtext" "$reset" "${scope_dir:-/}" >&2
  read -r -p '  Directory (blank to cancel): ' ans
  printf '\n' >&2
  if [[ -n "$ans" ]]; then
    scope_dir=$ans
    scope_all=0
  fi
}

while :; do
  # Saved history lives in the tool's data dirs. On the host those are read in
  # place. For a container the store is inside the container, so copy just this
  # tool's data out to a throwaway dir and parse it on the host with the SAME
  # functions, pointed at that dir and filtered by the CONTAINER project path.
  # Copied fresh on every open (no cache), then removed.
  if [[ "$(location_kind "$location")" == container ]]; then
    saved_rows=''
    extract_dir=$(mktemp -d 2>/dev/null || true)
    if [[ -n "$extract_dir" ]]; then
      if extract_container_sessions "$container" "$tool" "$scope_dir" "$extract_dir" "$scope_all"; then
        case "$tool" in
          codex)    saved_rows=$(list_codex_sessions    "$extract_dir" "$scope_dir" "$scope_all" | sort -t $'\t' -k2,2nr) ;;
          opencode) saved_rows=$(list_opencode_sessions "$extract_dir" "$scope_dir" "$scope_all" | sort -t $'\t' -k2,2nr) ;;
          claude)   saved_rows=$(list_claude_sessions   "$extract_dir" "$scope_dir" "$scope_all" | sort -t $'\t' -k2,2nr) ;;
        esac
      fi
      rm -rf "$extract_dir"
    fi
  else
    case "$tool" in
      codex) saved_rows=$(list_codex_sessions | sort -t $'\t' -k2,2nr) ;;
      opencode) saved_rows=$(list_opencode_sessions | sort -t $'\t' -k2,2nr) ;;
      claude) saved_rows=$(list_claude_sessions | sort -t $'\t' -k2,2nr) ;;
    esac
  fi

  running_rows=$(tmux -L "$server_name" list-sessions \
    -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}|#{@ai_popup_session_id}|#{session_created}|#{@ai_popup_label}|#{@ai_popup_location}' \
    2>/dev/null || true)

  # Must run after both lists are loaded and before any entry is built: it is
  # what stops a freshly created session from being listed twice.
  link_new_session

  now=$(date '+%s')
  # Entry columns: 1 action  2 tool  3 value  4 session_id  5 epoch  6 title
  #                7 dir      8 display   (1-7 are returned; 8 is what fzf shows)
  # dir carries the launch directory: scope_dir for a new session, the session's
  # own recorded directory for resume (so all-mode resumes land correctly).
  printf -v entries 'new\t%s\t-\t-\t%s\tNew %s session\t%s\t%s%s＋  New session%s  %sStart a new %s conversation%s' \
    "$tool" "$now" "$name" "$scope_dir" "$green" "$bold" "$reset" "$subtext" "$name" "$reset"

  # Live sessions without a corresponding saved row get their own attach entry.
  while IFS='|' read -r session_name row_tool row_path session_id created label row_loc; do
    [[ "$row_tool" == "$tool" && "$row_path" == "$PWD" ]] || continue
    location_matches "$location" "$row_loc" || continue
    [[ -n "$session_id" ]] && saved_has_id "$session_id" && continue
    [[ -n "$label" ]] || label="Live ${name} session"
    updated=$(ai_fmt_epoch "$created" '%m-%d %H:%M')
    printf -v entry 'attach\t%s\t%s\t%s\t%s\t%s\t\t%s%s%s  %s● running%s  %s  %s' \
      "$tool" "$session_name" "${session_id:--}" "$created" "$label" \
      "$color$bold" "$icon" "$reset" "$green$bold" "$reset" "$updated" "$label"
    entries+=$'\n'"$entry"
  done <<<"$running_rows"

  while IFS=$'\t' read -r session_id epoch title dir; do
    [[ -n "$session_id" ]] || continue
    running_name=$(running_name_for_id "$session_id")
    updated=$(ai_fmt_epoch "$epoch" '%m-%d %H:%M')
    if [[ -n "$running_name" ]]; then
      action=attach
      value=$running_name
      status="${green}${bold}● running${reset}"
    else
      action=resume
      value=$session_id
      status="${subtext}○ saved${reset}"
    fi
    # In all-mode, show which directory each session belongs to.
    dir_tag=''
    [[ "$scope_all" == 1 && -n "$dir" ]] && dir_tag="  ${subtext}${dir}${reset}"
    printf -v entry '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s%s%s  %s  %s  %s%s' \
      "$action" "$tool" "$value" "$session_id" "$epoch" "$title" "$dir" \
      "$color$bold" "$icon" "$reset" "$status" "$updated" "$title" "$dir_tag"
    entries+=$'\n'"$entry"
  done <<<"$saved_rows"

  if [[ "$(location_kind "$location")" == container ]]; then
    if [[ "$scope_all" == 1 ]]; then scope_desc='all directories'
    else scope_desc="dir ${scope_dir:-/}"; fi
    border_label=" ${name} Sessions ·  ${container} "
    header_loc="Container: ${container}  •  Scope: ${scope_desc}"
    key_hint='Ctrl-x stop  •  Ctrl-a all-dirs  •  Ctrl-w set-dir  •  Esc back'
    expect_keys='ctrl-x,ctrl-d,ctrl-a,ctrl-w'
  else
    border_label=" ${name} Sessions "
    header_loc="Current project: ${PWD}"
    key_hint='Ctrl-x stop  •  Ctrl-d delete  •  Esc back'
    expect_keys='ctrl-x,ctrl-d'
  fi

  printf -v preview_command 'bash %q --preview {1} {2} {3} {4} {5} {6} {7}' "${BASH_SOURCE[0]}"
  fzf_output=$(printf '%s\n' "$entries" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=8 \
    --accept-nth=1,2,3,4,5,6,7 \
    --expect="$expect_keys" \
    --no-sort \
    --cycle \
    --layout=reverse \
    --margin=1,2 \
    --border=rounded \
    --border-label="$border_label" \
    --info=inline-right \
    --header-first \
    --header=$'Ctrl-j/k move  •  Enter select  •  '"$key_hint"$'\n'"$header_loc" \
    --prompt="${icon}  ${name} › " \
    --pointer='' \
    --preview-window='right,48%,wrap,border-left' \
    --preview-label=' Session Details ' \
    --bind='ctrl-j:down,ctrl-k:up' \
    --color='bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,info:#cba6f7,pointer:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7' \
    --preview="$preview_command")
  fzf_status=$?
  case "$fzf_status" in 0) ;; 1|130) exit 0 ;; *) exit "$fzf_status" ;; esac

  if [[ "$fzf_output" == *$'\n'* ]]; then
    pressed_key=${fzf_output%%$'\n'*}
    selected=${fzf_output#*$'\n'}
  else
    pressed_key=''
    selected=$fzf_output
  fi
  IFS=$'\t' read -r action selected_tool value selected_id _epoch _title selected_dir <<<"$selected"

  case "$pressed_key" in
    ctrl-a)
      # Container only: toggle "all directories". No-op elsewhere.
      [[ "$(location_kind "$location")" == container ]] && \
        { [[ "$scope_all" == 1 ]] && scope_all=0 || scope_all=1; }
      continue
      ;;
    ctrl-w)
      [[ "$(location_kind "$location")" == container ]] && prompt_for_dir
      continue
      ;;
  esac

  # ctrl-a/ctrl-w already handled and looped; everything past here needs a row.
  [[ -n "$selected" ]] || continue

  case "$pressed_key" in
    ctrl-x)
      if [[ "$action" != attach ]]; then
        wait_with_message 'Only a running session can be stopped.'
        continue
      fi
      confirm_action "Stop this ${name} session? Saved history will be kept." || continue
      if stop_running_session "$value"; then
        wait_with_message "Stopped ${name} session."
      else
        wait_with_message 'The session already stopped.'
      fi
      ;;
    ctrl-d)
      # Deleting a container session would need the tool's delete run inside the
      # container (and claude's host path trashes files, which has no container
      # analogue). Listing + resume are supported; delete stays host-only for now
      # rather than risking a destructive command in the wrong place.
      if [[ "$(location_kind "$location")" == container ]]; then
        wait_with_message 'Delete is host-only for now. Stop the session with Ctrl-x, or delete from inside the tool.'
        continue
      fi
      if [[ -z "$selected_id" || "$selected_id" == - ]]; then
        wait_with_message 'This entry has no saved history to delete. Use Ctrl-x to stop a running session.'
        continue
      fi
      confirm_action "Delete this ${name} session and its saved history?" || continue
      if [[ "$action" == attach ]] && ! stop_running_session "$value"; then
        wait_with_message 'Could not stop the running session; saved history was not deleted.'
        continue
      fi
      delete_error=''
      if delete_error=$(delete_saved_session "$tool" "$selected_id"); then
        wait_with_message "Deleted ${name} session ${selected_id:0:12}."
      else
        wait_with_message "Delete failed${delete_error:+: ${delete_error%%$'\n'*}}"
      fi
      ;;
    '')
      printf '%s\t%s\t%s\t%s\n' "$action" "$selected_tool" "$value" "$selected_dir"
      exit 0
      ;;
  esac
done
