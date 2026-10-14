#!/usr/bin/env bash
# ============================================================
# ai-workflow.sh - kunchenguid agent workflow menu (prefix F)
#
#   treehouse    new shell in a pooled worktree        (new tmux window)
#   worktrees    treehouse status                      (in the popup)
#   push         git push no-mistakes <branch>         (in the popup)
#   pipelines    no-mistakes TUI                       (in the popup)
#   gnhf         overnight loop on a goal, --worktree  (new tmux window)
#   firstmate    focus or start the first-mate window  (new tmux window)
#   crew         fleet overview and worker picker     (in the popup)
#
# Usage: ai-workflow.sh [action [args...]]
#   No action opens the fzf menu. An action runs directly - that is the entry
#   point aiterm_flow.lua uses, so nvim and tmux share one implementation:
#     ai-workflow.sh gnhf "<goal>"     ai-workflow.sh firstmate
#
# Everything that outlives the popup (shells, loops, the first mate) goes into a
# window on the MAIN tmux server: a popup dies with its command, and the
# ai-popup server is reserved for persistent-ai.sh's agent sessions.
#
# Same contract as the other ai-* scripts: bash 3.2, BSD/GNU clean, UI on stderr.
# ============================================================
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

FIRSTMATE_DIR=${FIRSTMATE_DIR:-$HOME/.local/share/firstmate}
FIRSTMATE_WINDOW=firstmate
FIRSTMATE_SESSION=firstmate
# An explicit override skips the launch picker; Claude is the quota fallback.
FIRSTMATE_AGENT=${AI_FIRSTMATE_AGENT:-claude}
# gnhf has no iteration cap by default; an unattended loop without one can burn
# a whole quota window. Override per shell with AI_GNHF_MAX_ITERATIONS.
GNHF_MAX_ITERATIONS=${AI_GNHF_MAX_ITERATIONS:-20}
NM_REMOTE=no-mistakes

ACTIONS='treehouse worktrees push pipelines gnhf firstmate crew'

err() { printf '%sai-workflow:%s %s\n' "$AI_RED" "$AI_RESET" "$1" >&2; }
info() { printf '%s%s%s\n' "$AI_SUBTEXT" "$1" "$AI_RESET" >&2; }

# Popups close the moment their command exits; hold so output can be read.
pause() {
  printf '\n%sPress any key to close...%s' "$AI_SUBTEXT" "$AI_RESET" >&2
  read -rsn1 || true
  printf '\n' >&2
}

fail() {
  err "$1"
  pause
  exit 1
}

need() {
  have "$1" || fail "'$1' not found - run install_agent_workflow"
}

need_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "not a git repository: $PWD"
}

# Open a window on the main server running <cmd> in <dir>. Outside tmux (nvim
# launched from a bare terminal) there is nowhere to put it, so say so.
new_window() {
  local name=$1 dir=$2 cmd=$3
  [[ -n "${TMUX:-}" ]] || fail "needs tmux: '$name' runs in its own window"
  tmux new-window -n "$name" -c "$dir" "$cmd"
}

# --- actions ------------------------------------------------
action_treehouse() {
  need treehouse
  need_git_repo
  # `treehouse get` opens a subshell and returns the worktree to the pool when
  # it exits - so it must own the window, not run inside the popup.
  new_window "wt:$(basename "$PWD")" "$PWD" 'treehouse get'
}

action_worktrees() {
  need treehouse
  need_git_repo
  treehouse status
  pause
}

has_nm_remote() {
  git remote get-url "$NM_REMOTE" >/dev/null 2>&1
}

action_push() {
  need no-mistakes
  need_git_repo

  if ! has_nm_remote; then
    info "No '$NM_REMOTE' remote in this repo yet."
    printf "Run 'no-mistakes init' now? [y/N] " >&2
    local answer
    read -r answer || answer=
    case "$answer" in
      y|Y|yes) no-mistakes init || fail 'no-mistakes init failed' ;;
      *) exit 0 ;;
    esac
  fi

  local branch
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) \
    || fail 'detached HEAD - check out a branch before pushing through the gate'
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
    || info 'Uncommitted changes are NOT pushed - only commits on this branch.'

  git push "$NM_REMOTE" "$branch" || fail "git push $NM_REMOTE $branch failed"
  info "Pipeline started. Watch it with prefix N (no-mistakes TUI)."
  pause
}

action_pipelines() {
  need no-mistakes
  # No exec: if it fails (e.g. repo not initialized) the popup must stay open.
  no-mistakes || fail "no-mistakes exited with an error (repo initialized? run 'no-mistakes init')"
}

action_gnhf() {
  need gnhf
  need_git_repo

  local goal=${1:-}
  if [[ -z "$goal" ]]; then
    printf '%sgnhf goal (empty = cancel):%s ' "$AI_MAUVE" "$AI_RESET" >&2
    read -r goal || goal=
  fi
  [[ -n "$goal" ]] || exit 0

  # --worktree keeps the loop off the checkout you are working in; gnhf refuses
  # it from a gnhf/ branch, so let gnhf itself report that.
  # tmux runs the window command through default-shell (zsh here), whose `read`
  # has no -n1/-p - so hand the whole line to bash explicitly, or the hold
  # prompt fails and the window closes taking the run's summary with it.
  local inner cmd
  printf -v inner 'gnhf --worktree --max-iterations %q %q; echo; read -rsn1 -p %q' \
    "$GNHF_MAX_ITERATIONS" "$goal" 'gnhf finished - press any key to close'
  printf -v cmd 'bash -c %q' "$inner"
  new_window "gnhf" "$PWD" "$cmd"
}

# Print "<session>:<index>" of the first-mate window on the main server.
firstmate_target() {
  tmux list-windows -a -F '#{session_name}:#{window_index}	#{window_name}' 2>/dev/null \
    | awk -F '\t' -v w="$FIRSTMATE_WINDOW" '$2 == w { print $1; exit }'
}

# Reuse only a single idle shell pane, never a crew window. Process inspection
# fails closed: a foreground command, background child, or unknown PID keeps it.
firstmate_idle_shell() {
  local window=$1 name=$2 panes=$3 pane pid current tty process processes
  [[ "$name" != fm-* && "$panes" == 1 ]] || return 1
  pane=$(tmux list-panes -t "$window" -F $'#{pane_pid}\t#{pane_current_command}\t#{pane_tty}') || return 1
  IFS=$'\t' read -r pid current tty <<<"$pane"
  [[ "$pid" =~ ^[0-9]+$ && "$tty" == /dev/* ]] || return 1
  case "$current" in sh|bash|zsh|fish|ksh|dash|csh|tcsh) ;; *) return 1 ;; esac
  process=$(ps -p "$pid" -o comm=) || return 1
  process=${process##*/}
  process=${process#-}
  [[ "$process" == "$current" ]] || return 1
  processes=$(ps -t "$tty" -o pid=) || return 1
  awk -v pid="$pid" 'NF { count++; if ($1 != pid) busy=1 }
    END { exit !(count == 1 && !busy) }' <<<"$processes"
}

# Only use quota-axi's interpreted all-model headroom, not model-specific limits.
# Missing tooling, unreadable quota and timeouts leave Claude as the default.
firstmate_quota() {
  have quota-axi && have jq || return 1
  have timeout || have gtimeout || have perl || return 1
  local quota
  quota=$(ai_run_limited 2 quota-axi --json 2>/dev/null) || return 1
  jq -er '
    def remaining($provider):
      [.providers[]? | select(.provider == $provider)
       | .quotaSemantics.effectiveAvailability[]?
       | select(.scope == "all_models") | .effectivePercentRemaining
       | select(type == "number" and . >= 0 and . <= 100)][0] // "unknown";
    [remaining("claude"), remaining("codex")] | @tsv
  ' <<<"$quota" 2>/dev/null
}

firstmate_choose_agent() {
  if [[ -n "${AI_FIRSTMATE_AGENT:-}" ]]; then
    need "$AI_FIRSTMATE_AGENT"
    printf '%s\n' "$AI_FIRSTMATE_AGENT"
    return
  fi
  local agent agents='' count=0
  for agent in claude codex; do
    have "$agent" || continue
    agents="${agents:+${agents} }${agent}"
    count=$((count + 1))
  done
  [[ "$count" != 0 ]] || fail 'neither claude nor codex found - run install_agent_workflow'
  if [[ "$count" == 1 ]]; then printf '%s\n' "$agents"; return; fi
  need fzf
  local quota claude_remaining=unknown codex_remaining=unknown percent entries=''
  quota=$(firstmate_quota) || quota=$'unknown\tunknown'
  IFS=$'\t' read -r claude_remaining codex_remaining <<<"$quota"
  if [[ "$claude_remaining" != unknown && "$codex_remaining" != unknown ]] \
    && awk -v c="$claude_remaining" -v x="$codex_remaining" 'BEGIN { exit !(x > c) }'; then
    agents='codex claude'
  fi
  for agent in $agents; do
    case "$agent" in claude) percent=$claude_remaining ;; codex) percent=$codex_remaining ;; esac
    entries="${entries}${agent}"$'\t'"${agent}"
    [[ "$percent" == unknown ]] || entries="${entries}  ${percent}% remaining"
    entries="${entries}"$'\n'
  done
  local selection status
  selection=$(printf '%s' "$entries" | fzf --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
    --no-sort --cycle --layout=reverse --margin=1,2 --border=rounded \
    --border-label=' Firstmate Agent ' --info=hidden \
    --header='Ctrl-j/k move  •  Enter start  •  Esc cancel' --prompt='Agent › ' \
    --pointer='' --bind='ctrl-j:down,ctrl-k:up' \
    --color='bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,header:#89b4fa,fg+:#cdd6f4,prompt:#cba6f7,border:#6c7086,label:#cba6f7')
  status=$?
  case "$status" in 0) printf '%s\n' "$selection" ;; 1|130) return 0 ;; *) return "$status" ;; esac
}

action_firstmate() {
  [[ -d "$FIRSTMATE_DIR/.git" ]] \
    || fail "firstmate not found at $FIRSTMATE_DIR - run install_agent_workflow"
  [[ -n "${TMUX:-}" ]] || fail 'firstmate needs tmux (its crewmates are tmux windows)'

  local target cmd windows index window name panes agent first=''
  target=$(firstmate_target)
  if [[ -n "$target" ]]; then
    tmux switch-client -t "${target%%:*}" \; select-window -t "$target"
    return
  fi
  agent=$(firstmate_choose_agent) || return $?
  [[ -n "$agent" ]] || return 0
  # fzf emits only the installed agent names offered above.
  [[ -n "${AI_FIRSTMATE_AGENT:-}" || "$agent" == claude || "$agent" == codex ]] \
    || fail 'invalid firstmate agent selection'
  printf -v cmd 'exec %q' "$agent"
  target="=$FIRSTMATE_SESSION:1"
  if tmux has-session -t "=$FIRSTMATE_SESSION" 2>/dev/null; then
    windows=$(tmux list-windows -t "=$FIRSTMATE_SESSION" \
      -F $'#{window_index}\t#{window_id}\t#{window_name}\t#{window_panes}') \
      || fail 'could not inspect firstmate session'
    while IFS=$'\t' read -r index window name panes; do
      [[ "$index" == 1 ]] || continue
      first=$window
      if firstmate_idle_shell "$window" "$name" "$panes"; then
        tmux respawn-window -k -t "$window" -c "$FIRSTMATE_DIR" "$cmd" \
          || fail 'could not reuse firstmate shell window'
        tmux rename-window -t "$window" "$FIRSTMATE_WINDOW" \
          || fail 'could not name firstmate window'
        tmux switch-client -t "$target"
        return
      fi
    done <<<"$windows"
    # Inserting before index 1 shifts occupied windows without killing processes.
    local -a args=(new-window -d)
    [[ -z "$first" ]] || args+=(-b)
    tmux "${args[@]}" -t "$target" -n "$FIRSTMATE_WINDOW" -c "$FIRSTMATE_DIR" "$cmd" \
      || fail 'could not create firstmate window'
  else
    tmux new-session -d -s "$FIRSTMATE_SESSION" -n "$FIRSTMATE_WINDOW" \
      -c "$FIRSTMATE_DIR" "$cmd" || fail 'could not create firstmate session'
  fi
  tmux switch-client -t "$target"
}

run_action() {
  local action=$1
  shift
  case "$action" in
    treehouse) action_treehouse ;;
    worktrees) action_worktrees ;;
    push)      action_push ;;
    pipelines) action_pipelines ;;
    gnhf)      action_gnhf "$@" ;;
    firstmate) action_firstmate ;;
    crew)      "$LIB_DIR/crew-view.sh" ;;
    *)         fail "unknown action: $action (one of: $ACTIONS)" ;;
  esac
}

# --- menu ---------------------------------------------------
action_label() {
  case "$1" in
    treehouse) printf '%s  New worktree shell' '󰐅' ;;
    worktrees) printf '%s  Worktree pool status' '󰙅' ;;
    push)      printf '%s  Push through no-mistakes' '󰜘' ;;
    pipelines) printf '%s  no-mistakes pipelines (TUI)' '󰑮' ;;
    gnhf)      printf '%s  gnhf: overnight loop…' '󰽥' ;;
    firstmate) printf '%s  firstmate: crew orchestrator' '󰚩' ;;
    crew)      printf '%s  firstmate: crew overview / jump' '󰚩' ;;
  esac
}

action_tool() {
  case "$1" in
    treehouse|worktrees) printf 'treehouse' ;;
    push|pipelines)      printf 'no-mistakes' ;;
    gnhf)                printf 'gnhf' ;;
    firstmate)
      if [[ -n "${AI_FIRSTMATE_AGENT:-}" ]] || have claude; then
        printf '%s' "$FIRSTMATE_AGENT"
      else
        printf 'codex'
      fi ;;
    crew)                printf '%s/bin/fm-fleet-view.sh' "$FIRSTMATE_DIR" ;;
  esac
}

menu() {
  have fzf || fail "'fzf' not found in PATH"

  local entries='' action label mark newline=$'\n' tab=$'\t'
  for action in $ACTIONS; do
    if have "$(action_tool "$action")"; then
      mark="${AI_GREEN}●${AI_RESET}"
    else
      mark="${AI_RED}○ not installed${AI_RESET}"
    fi
    label="${AI_MAUVE}$(action_label "$action")${AI_RESET}  ${mark}"
    entries="${entries:+${entries}${newline}}${action}${tab}${label}"
  done

  local selection
  selection=$(
    printf '%s\n' "$entries" | fzf \
      --ansi \
      --delimiter=$'\t' \
      --with-nth=2 \
      --accept-nth=1 \
      --no-sort \
      --cycle \
      --layout=reverse \
      --margin=1,2 \
      --border=rounded \
      --border-label=' Agent Workflow ' \
      --info=hidden \
      --header=$'Ctrl-j/k move  •  Enter run  •  Esc close\nWorking directory: '"$PWD" \
      --prompt='󱒜  Run › ' \
      --pointer='' \
      --bind='ctrl-j:down,ctrl-k:up' \
      --color='bg+:#313244,bg:#1e1e2e,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,pointer:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7'
  ) || exit 0

  [[ -n "$selection" ]] || exit 0
  run_action "$selection"
}

if (($# > 0)); then
  run_action "$@"
else
  menu
fi
