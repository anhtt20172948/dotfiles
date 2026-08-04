#!/usr/bin/env bash
# Select a tool, then create, attach or resume a persistent AI coding session.
set -uo pipefail

export PATH="$PATH:$HOME/.local/bin:$HOME/.opencode/bin"

quick_latest=false
case ${1:-} in
  '') ;;
  --latest) quick_latest=true ;;
  *) printf 'persistent-ai: unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

pause_with_error() {
  printf 'persistent-ai: %s\n' "$1" >&2
  read -rsn1 -p 'Press any key to close...'
  printf '\n'
  exit 1
}

[[ -n ${TMUX:-} ]] || pause_with_error 'must be launched from inside tmux'

# Keep the original server label so sessions from the earlier Codex-only
# implementation remain attachable.
server_name=${AI_POPUP_SERVER_NAME:-codex-popup}
server_config="$HOME/.config/tmux/ai-popup.conf"
picker="$HOME/.config/tmux/scripts/ai-picker.sh"
session_picker="$HOME/.config/tmux/scripts/ai-sessions.sh"
[[ -r "$server_config" ]] || pause_with_error 'dedicated tmux config is missing'
[[ -x "$picker" ]] || pause_with_error 'AI picker is missing or not executable'
[[ -x "$session_picker" ]] || pause_with_error 'AI session picker is missing or not executable'

project_dir=$PWD
project_name=${project_dir##*/}
[[ -n "$project_name" ]] || project_name=root
safe_name=$(printf '%s' "$project_name" | tr -cs '[:alnum:]_-' '-')
safe_name=${safe_name#-}
safe_name=${safe_name%-}
[[ -n "$safe_name" ]] || safe_name=project

if command -v sha256sum >/dev/null 2>&1; then
  path_hash=$(printf '%s' "$project_dir" | sha256sum | cut -c1-10)
else
  path_hash=$(printf '%s' "$project_dir" | cksum | awk '{print $1}')
fi

set_compat_metadata() {
  local session=$1 compat_tool=$2
  tmux -L "$server_name" has-session -t "=${session}" 2>/dev/null || return
  tmux -L "$server_name" set-option -t "$session" @ai_popup_path "$project_dir"
  tmux -L "$server_name" set-option -t "$session" @ai_popup_tool "$compat_tool"
  current_label=$(tmux -L "$server_name" show-option -qv -t "$session" @ai_popup_label)
  [[ -n "$current_label" ]] || tmux -L "$server_name" set-option \
    -t "$session" @ai_popup_label "Live ${compat_tool} session"
}

# Backfill metadata on all session names produced by earlier implementations.
for candidate in codex opencode claude; do
  set_compat_metadata "ai-${candidate}-${safe_name:0:24}-${path_hash}" "$candidate"
done

generic_name="ai-${safe_name:0:24}-${path_hash}"
if tmux -L "$server_name" has-session -t "=${generic_name}" 2>/dev/null; then
  generic_tool=$(tmux -L "$server_name" show-option -qv \
    -t "$generic_name" @ai_popup_tool)
  [[ -n "$generic_tool" ]] || generic_tool=$(tmux -L "$server_name" \
    display-message -p -t "$generic_name" '#{pane_current_command}')
  case "$generic_tool" in
    codex|opencode|claude) set_compat_metadata "$generic_name" "$generic_tool" ;;
  esac
fi

legacy_name="codex-${safe_name:0:24}-${path_hash}"
set_compat_metadata "$legacy_name" codex

declare -A running_seen=()
declare -A running_count=([codex]=0 [opencode]=0 [claude]=0)
while IFS='|' read -r session_name session_tool session_path; do
  [[ "$session_path" == "$project_dir" ]] || continue
  case "$session_tool" in codex|opencode|claude) ;; *) continue ;; esac
  [[ -n ${running_seen[$session_name]:-} ]] && continue
  running_seen[$session_name]=1
  running_count[$session_tool]=$((running_count[$session_tool] + 1))
done < <(tmux -L "$server_name" list-sessions \
  -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}' 2>/dev/null || true)

running_tools=''
running_counts=''
for candidate in codex opencode claude; do
  count=${running_count[$candidate]}
  running_counts+="${running_counts:+ }${candidate}=${count}"
  (( count > 0 )) && running_tools+="${running_tools:+ }${candidate}"
done

action=''
tool=''
value=''

if [[ "$quick_latest" == true ]]; then
  latest_session=''
  latest_tool=''
  latest_score=-1
  latest_created=-1

  while IFS='|' read -r candidate_name candidate_tool candidate_path \
      last_attached activity created; do
    [[ "$candidate_path" == "$project_dir" ]] || continue
    case "$candidate_tool" in codex|opencode|claude) ;; *) continue ;; esac
    [[ "$last_attached" =~ ^[0-9]+$ ]] || last_attached=''
    [[ "$activity" =~ ^[0-9]+$ ]] || activity=''
    [[ "$created" =~ ^[0-9]+$ ]] || created=0
    score=${last_attached:-${activity:-$created}}

    if (( score > latest_score \
          || (score == latest_score && created > latest_created) )); then
      latest_session=$candidate_name
      latest_tool=$candidate_tool
      latest_score=$score
      latest_created=$created
    fi
  done < <(tmux -L "$server_name" list-sessions \
    -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}|#{@ai_popup_last_attached_at}|#{session_activity}|#{session_created}' \
    2>/dev/null || true)

  if [[ -n "$latest_session" ]]; then
    action=attach
    tool=$latest_tool
    value=$latest_session
  fi
fi

if [[ "$action" != attach ]]; then
  # Escape in the tool-specific submenu returns here; Escape in the main
  # picker closes the popup.
  while :; do
    tool=$(AI_POPUP_RUNNING_TOOLS="$running_tools" \
      AI_POPUP_RUNNING_COUNTS="$running_counts" "$picker" --select)
    [[ -n "$tool" ]] || exit 0
    case "$tool" in codex|opencode|claude) ;; *) pause_with_error 'invalid AI tool' ;; esac

    selection=$(AI_POPUP_SERVER_NAME="$server_name" \
      "$session_picker" --tool "$tool")
    [[ -n "$selection" ]] || continue
    IFS=$'\t' read -r action selected_tool value <<<"$selection"
    [[ "$selected_tool" == "$tool" ]] || pause_with_error 'invalid AI session selection'
    break
  done
fi

resume_id=''
created_at=''
session_kind=''
session_label=''

case "$action" in
  new)
    created_at=$(date '+%s')
    session_kind=new
    session_label="New ${tool} · $(date '+%Y-%m-%d %H:%M')"
    session_name="ai-${tool}-new-${safe_name:0:12}-${created_at}-$$"
    ;;
  attach)
    session_name=$value
    if ! tmux -L "$server_name" has-session -t "=${session_name}" 2>/dev/null; then
      [[ "$quick_latest" == true ]] && exec "$0" --latest
      pause_with_error 'the selected AI session is no longer running'
    fi
    attached_tool=$(tmux -L "$server_name" show-option -qv \
      -t "$session_name" @ai_popup_tool)
    attached_path=$(tmux -L "$server_name" show-option -qv \
      -t "$session_name" @ai_popup_path)
    [[ "$attached_tool" == "$tool" && "$attached_path" == "$project_dir" ]] || \
      pause_with_error 'the selected AI session does not belong to this project'
    ;;
  resume)
    resume_id=$value
    [[ -n "$resume_id" ]] || pause_with_error 'saved session ID is missing'
    if command -v sha256sum >/dev/null 2>&1; then
      resume_hash=$(printf '%s' "$resume_id" | sha256sum | cut -c1-10)
    else
      resume_hash=$(printf '%s' "$resume_id" | cksum | awk '{print $1}')
    fi
    session_kind=resume
    session_label="Resumed ${tool} · ${resume_id:0:12}"
    session_name="ai-${tool}-resume-${safe_name:0:12}-${resume_hash}"
    ;;
  *) pause_with_error 'invalid AI session action' ;;
esac

session_target="=${session_name}"

if [[ "$action" != attach ]] \
    && ! tmux -L "$server_name" has-session -t "$session_target" 2>/dev/null; then
  executable=$(command -v "$tool" 2>/dev/null || true)
  [[ -n "$executable" ]] || pause_with_error "'$tool' not found in PATH"
  [[ -x "$executable" ]] || pause_with_error "AI executable is not runnable: $executable"

  if [[ "$action" == resume ]]; then
    case "$tool" in
      codex)
        printf -v launch_command 'exec %q resume -C %q %q' \
          "$executable" "$project_dir" "$resume_id"
        ;;
      opencode)
        printf -v launch_command 'exec %q --session %q %q' \
          "$executable" "$resume_id" "$project_dir"
        ;;
      claude)
        printf -v launch_command 'exec %q --resume %q' \
          "$executable" "$resume_id"
        ;;
    esac
  else
    printf -v launch_command 'exec %q' "$executable"
  fi

  if ! tmux -L "$server_name" -f "$server_config" new-session -d \
    -s "$session_name" -n "$tool" -c "$project_dir" "$launch_command" 2>/dev/null; then
    tmux -L "$server_name" has-session -t "$session_target" 2>/dev/null || \
      pause_with_error 'could not create the persistent AI session'
  fi
fi

tmux -L "$server_name" set-option -t "$session_name" destroy-unattached off
tmux -L "$server_name" set-option -t "$session_name" @ai_popup_path "$project_dir"
tmux -L "$server_name" set-option -t "$session_name" @ai_popup_tool "$tool"
[[ -n "$session_kind" ]] && tmux -L "$server_name" set-option \
  -t "$session_name" @ai_popup_kind "$session_kind"
[[ -n "$created_at" ]] && tmux -L "$server_name" set-option \
  -t "$session_name" @ai_popup_created_at "$created_at"
[[ -n "$session_label" ]] && tmux -L "$server_name" set-option \
  -t "$session_name" @ai_popup_label "$session_label"
[[ -n "$resume_id" ]] && tmux -L "$server_name" set-option \
  -t "$session_name" @ai_popup_session_id "$resume_id"
tmux -L "$server_name" set-option -t "$session_name" \
  @ai_popup_last_attached_at "$(date '+%s')"

exec env -u TMUX -u TMUX_PANE \
  tmux -L "$server_name" attach-session -t "$session_target"
