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
# The first mate runs on Claude Code by default: it is the harness whose Stop
# hook firstmate verifies first. Override with AI_FIRSTMATE_AGENT=codex etc.
FIRSTMATE_AGENT=${AI_FIRSTMATE_AGENT:-claude}
# gnhf has no iteration cap by default; an unattended loop without one can burn
# a whole quota window. Override per shell with AI_GNHF_MAX_ITERATIONS.
GNHF_MAX_ITERATIONS=${AI_GNHF_MAX_ITERATIONS:-20}
NM_REMOTE=no-mistakes

ACTIONS='treehouse worktrees push pipelines gnhf firstmate'

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

action_firstmate() {
  [[ -d "$FIRSTMATE_DIR/.git" ]] \
    || fail "firstmate not found at $FIRSTMATE_DIR - run install_agent_workflow"
  need "$FIRSTMATE_AGENT"
  [[ -n "${TMUX:-}" ]] || fail 'firstmate needs tmux (its crewmates are tmux windows)'

  local target
  target=$(firstmate_target)
  if [[ -n "$target" ]]; then
    tmux switch-client -t "${target%%:*}" \; select-window -t "$target"
    return
  fi
  local cmd
  printf -v cmd 'exec %q' "$FIRSTMATE_AGENT"
  new_window "$FIRSTMATE_WINDOW" "$FIRSTMATE_DIR" "$cmd"
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
  esac
}

action_tool() {
  case "$1" in
    treehouse|worktrees) printf 'treehouse' ;;
    push|pipelines)      printf 'no-mistakes' ;;
    gnhf)                printf 'gnhf' ;;
    firstmate)           printf '%s' "$FIRSTMATE_AGENT" ;;
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
