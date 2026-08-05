#!/usr/bin/env bash
# Create, attach or resume a persistent per-project AI coding session.
#
# Modes:
#   (no args)   open the tool picker, then that tool's session list. The browse
#               path, and the only route to "New session".
#   --latest    attach the most recently used live agent for this project,
#               falling back to the pickers when there is none
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

mode=pick
case ${1:-} in
  '') ;;
  --latest) mode=latest ;;
  *) printf 'persistent-ai: unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

pause_with_error() {
  printf 'persistent-ai: %s\n' "$1" >&2
  read -rsn1 -p 'Press any key to close...'
  printf '\n'
  exit 1
}

[[ -n ${TMUX:-} ]] || pause_with_error 'must be launched from inside tmux'

# Grab the outer server's socket while $TMUX is still set. The final attach
# strips TMUX from the environment, and we need this afterwards to refresh the
# outer status bar the instant the popup closes.
outer_socket=${TMUX%%,*}

server_name=${AI_POPUP_SERVER_NAME:-$AI_SERVER_DEFAULT}
server_config="$LIB_DIR/../ai-popup.conf"
picker="$LIB_DIR/ai-picker.sh"
session_picker="$LIB_DIR/ai-sessions.sh"
location_picker="$LIB_DIR/ai-location.sh"
[[ -r "$server_config" ]] || pause_with_error 'dedicated tmux config is missing'
[[ -x "$picker" ]] || pause_with_error 'AI picker is missing or not executable'
[[ -x "$session_picker" ]] || pause_with_error 'AI session picker is missing or not executable'
[[ -x "$location_picker" ]] || pause_with_error 'AI location picker is missing or not executable'

project_dir=$PWD
project_name=${project_dir##*/}
[[ -n "$project_name" ]] || project_name=root
safe_name=$(printf '%s' "$project_name" | tr -cs '[:alnum:]_-' '-')
safe_name=${safe_name#-}
safe_name=${safe_name%-}
[[ -n "$safe_name" ]] || safe_name=project

# ------------------------------------------------------------
# Optional reaping. Opt-in via AI_POPUP_TTL_DAYS because silently killing a
# long-running agent is unforgivable — the user has to ask for it. Scope is
# every project, not just this one: a stale agent is stale wherever it lives.
# Attached sessions are never touched.
# ------------------------------------------------------------
prune_stale_sessions() {
  local days=${AI_POPUP_TTL_DAYS:-0} cutoff now s_name s_last s_attached
  case $days in ''|*[!0-9]*) return 0 ;; esac
  [ "$days" -gt 0 ] || return 0

  now=$(date '+%s')
  cutoff=$((now - days * 86400))
  while IFS='|' read -r s_name s_last s_attached; do
    [ -n "$s_name" ] || continue
    [ "${s_attached:-0}" = 0 ] || continue
    case $s_last in ''|*[!0-9]*) continue ;; esac
    [ "$s_last" -lt "$cutoff" ] || continue
    tmux -L "$server_name" kill-session -t "=${s_name}" 2>/dev/null
  done < <(tmux -L "$server_name" list-sessions \
    -F '#{session_name}|#{@ai_popup_last_attached_at}|#{session_attached}' \
    2>/dev/null || true)
}

# ------------------------------------------------------------
# Live sessions for this project.
#
# Three plain integers rather than an associative array: `declare -A` is bash 4+
# and stock macOS ships bash 3.2, where the compound assignment aborts the whole
# script under `set -u` (the subscript is read as an arithmetic expression, so
# `[codex]=0` dereferences an unbound `codex`). Inside display-popup that abort
# was invisible — the popup simply closed again.
# ------------------------------------------------------------
# refresh_running [location-filter]
#   empty          -> every location (used by --latest, which is deliberately
#                     location-agnostic: it attaches the newest agent wherever
#                     it runs)
#   host           -> host sessions, plus legacy sessions with no location tag
#   container:NAME -> that container's sessions only
# Scoping the per-tool counts to the chosen location is what makes the tool
# picker say "● running" only about agents that actually live where you picked.
refresh_running() {
  local filter=${1:-}
  local s_name s_tool s_path s_last s_activity s_created s_loc score
  local latest_score=-1 latest_created=-1
  local candidate count

  running_codex=0
  running_opencode=0
  running_claude=0
  latest_name=''
  latest_tool=''

  while IFS='|' read -r s_name s_tool s_path s_last s_activity s_created s_loc; do
    [ "$s_path" = "$project_dir" ] || continue
    tool_is_valid "$s_tool" || continue
    location_matches "$filter" "$s_loc" || continue

    case "$s_tool" in
      codex)    running_codex=$((running_codex + 1)) ;;
      opencode) running_opencode=$((running_opencode + 1)) ;;
      claude)   running_claude=$((running_claude + 1)) ;;
    esac

    case $s_last in ''|*[!0-9]*) s_last='' ;; esac
    case $s_activity in ''|*[!0-9]*) s_activity='' ;; esac
    case $s_created in ''|*[!0-9]*) s_created=0 ;; esac
    score=${s_last:-${s_activity:-$s_created}}
    if [ "$score" -gt "$latest_score" ] ||
       { [ "$score" -eq "$latest_score" ] && [ "$s_created" -gt "$latest_created" ]; }; then
      latest_name=$s_name
      latest_tool=$s_tool
      latest_score=$score
      latest_created=$s_created
    fi
  done < <(tmux -L "$server_name" list-sessions \
    -F '#{session_name}|#{@ai_popup_tool}|#{@ai_popup_path}|#{@ai_popup_last_attached_at}|#{session_activity}|#{session_created}|#{@ai_popup_location}' \
    2>/dev/null || true)

  running_tools=''
  running_counts=''
  for candidate in $AI_TOOLS; do
    count=$(running_count_for "$candidate")
    running_counts="${running_counts:+$running_counts }${candidate}=${count}"
    [ "$count" -gt 0 ] && running_tools="${running_tools:+$running_tools }${candidate}"
  done
  return 0
}

running_count_for() {
  case "$1" in
    codex)    printf '%s' "$running_codex" ;;
    opencode) printf '%s' "$running_opencode" ;;
    claude)   printf '%s' "$running_claude" ;;
    *)        printf '0' ;;
  esac
}

# Choose where the tools run. Sets location/container and location_interactive.
# When no container is running the picker is skipped entirely and the host is
# selected silently, so the pre-Docker single-keystroke path is unchanged.
# Returns 1 only when the user closed the popup at the location picker.
pick_location() {
  local containers selection note=''
  containers=$(list_containers)
  # Only probe for an error when the list is empty, so the working path (docker
  # up, containers present) never pays for the second call.
  [ -z "$containers" ] && note=$(docker_note)
  if [ -z "$containers" ] && [ -z "$note" ]; then
    # Nothing to choose between: no docker, or docker is fine but idle. Skip the
    # step entirely and keep the host path a single keystroke.
    location=host
    container=''
    location_interactive=0
    return 0
  fi
  location_interactive=1
  selection=$(AI_POPUP_DOCKER_NOTE="$note" "$location_picker")
  [ -n "$selection" ] || return 1
  location=$selection
  container=$(location_container "$location")
  return 0
}

# Three-level picker: location -> tool -> session. Escape is always "back one
# level": from the session list back to the tool picker, from the tool picker
# back to the location picker (or closed, when the location picker was skipped),
# and from the location picker the popup closes. Sets action/tool/value plus
# location/container, or returns 1 when the user backed all the way out.
pick_interactive() {
  local selection selected_tool

  while :; do
    pick_location || return 1
    refresh_running "$location"

    while :; do
      tool=$(AI_POPUP_RUNNING_TOOLS="$running_tools" \
        AI_POPUP_RUNNING_COUNTS="$running_counts" \
        AI_POPUP_LOCATION="$location" \
        AI_POPUP_CONTAINER="$container" "$picker" --select)
      if [ -z "$tool" ]; then
        # Escape at the tool picker: step back to the location picker when it was
        # shown, otherwise (host-only, picker skipped) close the popup.
        [ "$location_interactive" = 1 ] && break
        return 1
      fi
      tool_is_valid "$tool" || pause_with_error 'invalid AI tool'

      selection=$(AI_POPUP_SERVER_NAME="$server_name" \
        AI_POPUP_LOCATION="$location" \
        AI_POPUP_CONTAINER="$container" "$session_picker" --tool "$tool")
      # An empty selection means Escape in the submenu: go back to the tool
      # picker.
      [ -n "$selection" ] || continue
      IFS=$'\t' read -r action selected_tool value <<<"$selection"
      [ "$selected_tool" = "$tool" ] || pause_with_error 'invalid AI session selection'
      return 0
    done
  done
}

prune_stale_sessions

action=''
tool=''
value=''
location=host
container=''
location_interactive=0

while :; do
  # No filter: --latest is location-agnostic, so this global scan finds the
  # newest agent wherever it lives. pick_interactive re-scans scoped to the
  # location once one is chosen.
  refresh_running

  # --latest with nothing running falls through to the pickers below.
  if [ "$mode" = latest ] && [ -n "$latest_name" ]; then
    action=attach; tool=$latest_tool; value=$latest_name
  fi

  if [ -z "$action" ]; then
    pick_interactive || exit 0
  fi

  if [ "$action" != attach ]; then
    break
  fi

  # Attach target still alive?
  if tmux -L "$server_name" has-session -t "=${value}" 2>/dev/null; then
    break
  fi

  # It vanished between listing and attaching. Fall through to the pickers
  # rather than re-exec'ing this script: `exec "$0" --latest` could keep picking
  # the same un-attachable session forever, and a spin inside display-popup is
  # completely invisible — no output, no exit.
  if [ "$mode" = pick ]; then
    pause_with_error 'the selected AI session is no longer running'
  fi
  mode=pick
  action=''
  tool=''
  value=''
done

resume_id=''
created_at=''
session_kind=''
session_label=''
container_path=''

# A short, tmux-safe location tag so host and container sessions for the same
# project get distinct names (and so a container name with slashes or spaces
# cannot break the session name). Host stays plain "host".
if [[ "$(location_kind "$location")" == container ]]; then
  loc_slug=$(printf '%s' "$container" | tr -cs '[:alnum:]_-' '-')
  loc_slug=${loc_slug#-}; loc_slug=${loc_slug%-}
  loc_slug="c-${loc_slug:0:14}"
else
  loc_slug=host
fi

case "$action" in
  new)
    created_at=$(date '+%s')
    session_kind=new
    if [[ "$loc_slug" == host ]]; then
      session_label="New ${tool} · $(date '+%Y-%m-%d %H:%M')"
    else
      session_label="New ${tool} @${container} · $(date '+%Y-%m-%d %H:%M')"
    fi
    session_name="ai-${tool}-new-${loc_slug}-${safe_name:0:12}-${created_at}-$$"
    ;;
  attach)
    session_name=$value
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
  if [[ "$(location_kind "$location")" == container ]]; then
    # Container: discover the tool INSIDE the container and rebase the host
    # project path onto its mount. resume is host-only in v1, so only the plain
    # `new` launch is reachable here.
    executable=$(locate_tool "$location" "$tool" || true)
    [[ -n "$executable" ]] || \
      pause_with_error "'$tool' not found in container '$container'"
    container_path=$(map_host_path_to_container "$container" "$project_dir")
    # Run the tool through an INTERACTIVE bash (bash -ic), not the bare binary: a
    # hand-installed CLI needs the PATH/env its ~/.bashrc sets up (node, API keys,
    # version-manager shims), exactly as when the user runs it after
    # `docker exec -it NAME bash`. -i is what makes bash read ~/.bashrc (a login
    # shell would not); sourcing /etc/profile as well covers a system-wide PATH.
    # sh -lc for images without bash. The inner `exec %q` still launches the
    # resolved absolute path, so PATH lookup can't pick a different binary. -it
    # gives docker the session's pty; -w sets cwd.
    if location_run "$location" sh -c 'command -v bash' >/dev/null 2>&1; then
      printf -v inner_command \
        '[ -r /etc/profile ] && . /etc/profile >/dev/null 2>&1; exec %q' "$executable"
      printf -v launch_command 'exec docker exec -it -w %q %q bash -ic %q' \
        "$container_path" "$container" "$inner_command"
    else
      printf -v inner_command 'exec %q' "$executable"
      printf -v launch_command 'exec docker exec -it -w %q %q sh -lc %q' \
        "$container_path" "$container" "$inner_command"
    fi
  else
    executable=$(command -v "$tool" 2>/dev/null || true)
    [[ -n "$executable" ]] || pause_with_error "'$tool' not found in PATH"
    [[ -x "$executable" ]] || pause_with_error "AI executable is not runnable: $executable"

    case "$action" in
      resume)
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
        ;;
      *)
        printf -v launch_command 'exec %q' "$executable"
        ;;
    esac
  fi

  # Born-at-popup-size. A detached session defaults to 80x24; on attach tmux
  # resizes the window to this popup, but for a container the tool runs behind
  # `docker exec`, whose TTY does not reliably follow that resize — so opencode
  # would paint 80x24 in the top-left of a full-size popup. Creating the session
  # at the popup's exact character size means docker exec's TTY is correct from
  # birth and the attach triggers no resize at all. `stty size` on the popup's
  # controlling terminal is that exact size; a bad read falls back to the old
  # default-size path.
  popup_size=$(stty size </dev/tty 2>/dev/null || true)
  popup_rows=${popup_size%% *}
  popup_cols=${popup_size##* }
  create_ok=1
  if [[ "$popup_cols" =~ ^[0-9]+$ && "$popup_rows" =~ ^[0-9]+$ \
        && "$popup_cols" -gt 0 && "$popup_rows" -gt 0 ]]; then
    tmux -L "$server_name" -f "$server_config" new-session -d \
      -x "$popup_cols" -y "$popup_rows" \
      -s "$session_name" -n "$tool" -c "$project_dir" "$launch_command" 2>/dev/null \
      || create_ok=0
  else
    tmux -L "$server_name" -f "$server_config" new-session -d \
      -s "$session_name" -n "$tool" -c "$project_dir" "$launch_command" 2>/dev/null \
      || create_ok=0
  fi
  if [[ "$create_ok" -eq 0 ]]; then
    tmux -L "$server_name" has-session -t "$session_target" 2>/dev/null || \
      pause_with_error 'could not create the persistent AI session'
  fi
fi

# destroy-unattached is set server-globally in ai-popup.conf; setting it again
# per session would only imply the global one does not work.
tmux -L "$server_name" set-option -t "$session_name" @ai_popup_path "$project_dir"
tmux -L "$server_name" set-option -t "$session_name" @ai_popup_tool "$tool"
# Only stamp the location when we created the session. On attach we reuse an
# existing session whose location we did NOT re-derive (latest mode defaults
# location to host), so writing it here would mislabel a container session.
if [[ "$action" != attach ]]; then
  tmux -L "$server_name" set-option -t "$session_name" @ai_popup_location "$location"
  [[ -n "$container" ]] && tmux -L "$server_name" set-option \
    -t "$session_name" @ai_popup_container "$container"
  [[ -n "$container_path" ]] && tmux -L "$server_name" set-option \
    -t "$session_name" @ai_popup_container_path "$container_path"
fi
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

# Not exec'd: once the popup closes we still want to nudge the OUTER status bar
# so the agent count updates immediately instead of up to status-interval later.
env -u TMUX -u TMUX_PANE \
  tmux -L "$server_name" attach-session -t "$session_target"
[[ -n "$outer_socket" ]] && tmux -S "$outer_socket" refresh-client -S 2>/dev/null
exit 0
