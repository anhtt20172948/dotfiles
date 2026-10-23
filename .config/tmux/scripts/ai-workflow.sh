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

# One source of truth for the firstmate home: ai-acct resume asks this script
# rather than reading its own variable. FM_HOME is what firstmate itself uses.
FIRSTMATE_DIR=${FIRSTMATE_DIR:-${FM_HOME:-$HOME/.local/share/firstmate}}
FIRSTMATE_WINDOW=firstmate
FIRSTMATE_SESSION=firstmate
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./firstmate-lib.sh
source "$LIB_DIR/firstmate-lib.sh"
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

# A dead pane (remain-on-exit) holds no process, so its window can be reused.
firstmate_dead_pane() {
  local window=$1 name=$2 panes=$3 dead
  [[ "$name" == "$FIRSTMATE_WINDOW" && "$panes" == 1 ]] || return 1
  dead=$(tmux list-panes -t "$window" -F '#{pane_dead}') || return 1
  [[ "$dead" == 1 ]]
}

# Only use quota-axi's interpreted all-model headroom, not model-specific limits.
# Missing tooling, unreadable quota and timeouts leave explicit unknown cells.
firstmate_quota() {
  have quota-axi && have jq || return 1
  have timeout || have gtimeout || have perl || return 1
  local quota
  quota=$(ai_run_limited 5 quota-axi --json 2>/dev/null) || return 1
  jq -er '
    def remaining($provider):
      [.providers[]? | select(.provider == $provider)
       | .quotaSemantics.effectiveAvailability[]?
       | select(.scope == "all_models") | .effectivePercentRemaining
       | select(type == "number" and . >= 0 and . <= 100)][0] // "unknown";
    [remaining("claude"), remaining("codex")] | @tsv
  ' <<<"$quota" 2>/dev/null
}

firstmate_installed_agents() {
  local agent agents=''
  for agent in claude codex; do
    have "$agent" && agents="${agents:+${agents} }${agent}"
  done
  printf '%s\n' "$agents"
}

FIRSTMATE_PICK_KEYS='Ctrl-j/k move  •  Enter select  •  Esc cancel'

# fzf action run in the background once the Agent picker is open: show quota
# in the header and, while the cursor is still on the first row, move it to
# the better headroom. The rows never change, so the list stays usable while
# the lookup runs; fzf 0.67 cannot reload rows from a background action.
firstmate_agent_quota_action() {
  local quota claude_remaining=unknown codex_remaining=unknown agent percent header='Quota'
  quota=$(firstmate_quota) || quota=$'unknown\tunknown'
  IFS=$'\t' read -r claude_remaining codex_remaining <<<"$quota"
  for agent in claude codex; do
    case "$agent" in claude) percent=$claude_remaining ;; codex) percent=$codex_remaining ;; esac
    if [[ "$percent" == unknown ]]; then
      header="${header}  ${agent} quota ?"
    else
      header="${header}  ${agent} ${percent}% left"
    fi
  done
  if [[ "$claude_remaining" != unknown && "$codex_remaining" != unknown ]] \
    && awk -v c="$claude_remaining" -v x="$codex_remaining" 'BEGIN { exit !(x > c) }'; then
    printf '%s' "transform~[ {n} = 0 ] && echo 'pos(2)'~+"
  fi
  printf 'change-header:%s\n%s\n' "$header" "$FIRSTMATE_PICK_KEYS"
}

firstmate_choose_agent() {
  if [[ -n "${AI_FIRSTMATE_AGENT:-}" ]]; then
    need "$AI_FIRSTMATE_AGENT"
    printf '%s\n' "$AI_FIRSTMATE_AGENT"
    return
  fi
  local agent agents count=0 quota_action
  agents=$(firstmate_installed_agents)
  for agent in $agents; do count=$((count + 1)); done
  [[ "$count" != 0 ]] || fail 'neither claude nor codex found - run install_agent_workflow'
  if [[ "$count" == 1 ]]; then printf '%s\n' "$agents"; return; fi
  need fzf
  printf -v quota_action 'start:bg-transform:bash %q _agent-quota' "$LIB_DIR/ai-workflow.sh"
  firstmate_pick Agent $'claude\tclaude\ncodex\tcodex\n' \
    --bind "$quota_action" --header=$'Quota …\n'"$FIRSTMATE_PICK_KEYS"
}

# No per-account config directories: token selection keeps Claude history shared.
firstmate_choose_account() {
  local listing account state active_entry='' entries=''
  listing=$(ai-acct list) || fail 'could not list Claude accounts'
  # The active account comes first so Enter keeps the current token.
  while IFS=$'\t' read -r account state; do
    [[ -n "$account" ]] || continue
    if [[ "$state" == active ]]; then
      active_entry="${account}"$'\t'"Claude account ${account} (active)"$'\n'
    else
      entries="${entries}${account}"$'\t'"Claude account ${account}"$'\n'
    fi
  done <<<"$listing"
  entries="${active_entry}${entries}"
  [[ -n "$entries" ]] \
    || fail 'no Claude accounts - add one with prefix E or ai-acct add NAME'
  firstmate_pick Account "$entries"
}

# All launch pickers use the same style and validate selections against the
# offered values. Cancellation exits before any tmux mutation. Extra fzf
# arguments come last, so they can override the defaults.
firstmate_pick() {
  local label=$1 entries=$2 selection status value _display offered=''
  shift 2
  need fzf
  selection=$(printf '%s' "$entries" | fzf --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
    --no-sort --cycle --layout=reverse --margin=1,2 --border=rounded \
    --border-label=" Firstmate $label " --info=hidden \
    --header="$FIRSTMATE_PICK_KEYS" --prompt="$label › " \
    --pointer='' --bind='ctrl-j:down,ctrl-k:up' \
    --color='bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,header:#89b4fa,fg+:#cdd6f4,prompt:#cba6f7,border:#6c7086,label:#cba6f7' "$@")
  status=$?
  case "$status" in 0) ;; 1|130) return 0 ;; *) return "$status" ;; esac
  while IFS=$'\t' read -r value _display; do
    [[ -n "$value" ]] || continue
    if [[ "$value" == "$selection" ]]; then
      printf '%s\n' "$selection"
      return
    fi
    offered="${offered:+$offered, }$value"
  done <<<"$entries"
  fail "invalid firstmate $label selection '$selection' (offered: $offered)"
}

# Read only the top-level model string, without evaluating TOML as shell code.
firstmate_config_model() {
  [[ -r "$HOME/.codex/config.toml" ]] || return 0
  awk '
    /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*model[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      quote = substr($0, 1, 1)
      if (quote != "\"" && quote != "\047") exit
      value = substr($0, 2); end = index(value, quote)
      if (end) print substr(value, 1, end - 1)
      exit
    }' "$HOME/.codex/config.toml"
}

firstmate_models() {
  local agent=$1 catalog=$2 model
  printf 'default\tdefault (CLI config)\n'
  if [[ "$agent" == claude ]]; then
    printf '%s\t%s\n' opus opus sonnet sonnet haiku haiku
  else
    model=$(jq -er '.models[]? | select((.visibility // "list") != "hide") | .slug
      | select(type == "string")
      | select(test("^[A-Za-z0-9][A-Za-z0-9._:/-]*$"))' <<<"$catalog" 2>/dev/null) || model=$(firstmate_config_model)
    while IFS= read -r model; do
      [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ && "$model" != default ]] || continue
      printf '%s\t%s\n' "$model" "$model"
    done <<<"$model"
  fi
}

firstmate_efforts() {
  local agent=$1 model=$2 catalog=$3 levels level
  printf 'default\tdefault\n'
  if [[ "$agent" == claude ]]; then
    levels=$'low\nmedium\nhigh\nxhigh\nmax'
  else
    [[ "$model" != default ]] || model=$(firstmate_config_model)
    levels=$(jq -er --arg model "$model" '
      .models[]? | select(.slug == $model) | .supported_reasoning_levels[]?
      | if type == "object" then .effort else . end
      | select(type == "string" and test("^[a-z]+$"))' <<<"$catalog" 2>/dev/null) \
      || levels=$'low\nmedium\nhigh\nxhigh'
  fi
  while IFS= read -r level; do
    [[ -n "$level" && "$level" != default ]] && printf '%s\t%s\n' "$level" "$level"
  done <<<"$levels"
}

# Print the pane command's agent part once the session is chosen.
firstmate_launch_command() {
  local agent=$1 mode=$2 session=$3 model=${4:-default} effort=${5:-default} cmd flag
  printf -v cmd 'exec %q' "$agent"
  if [[ "$mode" == resume ]]; then
    case "$agent" in
      claude) printf -v cmd '%s --resume %q' "$cmd" "$session" ;;
      codex) printf -v cmd 'exec codex resume -C %q %q' "$FIRSTMATE_DIR" "$session" ;;
    esac
    printf '%s\n' "$cmd"
    return
  fi
  if [[ "$model" != default ]]; then
    case "$agent" in claude) flag=--model ;; codex) flag=-m ;; esac
    printf -v cmd '%s %q %q' "$cmd" "$flag" "$model"
  fi
  if [[ "$effort" != default ]]; then
    case "$agent" in
      claude) printf -v cmd '%s --effort %q' "$cmd" "$effort" ;;
      codex) printf -v cmd '%s -c %q' "$cmd" "model_reasoning_effort=$effort" ;;
    esac
  fi
  printf '%s\n' "$cmd"
}

firstmate_focus() {
  tmux switch-client -t "${1%%:*}" \; select-window -t "$1"
}

# Make the account picked for the primary the default for crews and new panes.
firstmate_commit_account() {
  [[ -n "$1" ]] || return 0
  ai-acct use "$1" >&2 && return 0
  tmux display-message "Firstmate runs as $1, but new panes keep the old account; run ai-acct use $1."
}

action_firstmate() {
  [[ -d "$FIRSTMATE_DIR/.git" ]] \
    || fail "firstmate not found at $FIRSTMATE_DIR - run install_agent_workflow"
  [[ -n "${TMUX:-}" ]] || fail 'firstmate needs tmux (its crewmates are tmux windows)'

  local target cmd windows index window name panes agent account='' model='' effort='' catalog='' entries first='' mode session=''
  target=$(firstmate_target) || target=''
  if [[ -n "$target" ]]; then
    firstmate_focus "$target"
    return
  fi
  if firstmate_live_primary; then
    tmux display-message 'Firstmate lock is held by a live primary; refusing to start another.'
    return 0
  fi
  agent=$(firstmate_choose_agent) || return $?
  [[ -n "$agent" ]] || return 0
  # fzf emits only the installed agent names offered above.
  [[ "$agent" == claude || "$agent" == codex ]] \
    || fail 'invalid firstmate agent selection'
  entries=$'new\tNew Firstmate session\n'
  if ! have jq; then
    info 'Install jq to enable Firstmate resume; New session is available.'
  elif session=$(firstmate_session_id "$agent"); then
    # Resume comes first: it is what the picker offers by default.
    entries=$'resume\tResume last Firstmate session\n'"$entries"
  else
    info "No $agent transcript to resume in $FIRSTMATE_DIR. Choose New Firstmate session."
  fi
  mode=$(firstmate_pick Session "$entries") || return $?
  [[ -n "$mode" ]] || return 0
  if [[ "$agent" == claude ]]; then
    account=$(firstmate_choose_account) || return $?
    [[ -n "$account" ]] || return 0
  fi
  if [[ "$mode" == new ]]; then
    if [[ "$agent" == codex ]] && have jq \
      && { have timeout || have gtimeout || have perl; }; then
      catalog=$(ai_run_limited 5 codex debug models 2>/dev/null) || catalog=''
    fi
    entries=$(firstmate_models "$agent" "$catalog")
    model=$(firstmate_pick Model "$entries") || return $?
    [[ -n "$model" ]] || return 0
    entries=$(firstmate_efforts "$agent" "$model" "$catalog")
    effort=$(firstmate_pick Effort "$entries") || return $?
    [[ -n "$effort" ]] || return 0
  fi
  cmd=$(firstmate_launch_command "$agent" "$mode" "$session" "${model:-default}" "${effort:-default}")
  # Recheck after the pickers in case another launcher acquired the lock.
  target=$(firstmate_target) || target=''
  if [[ -n "$target" ]] || firstmate_live_primary; then
    tmux display-message 'Firstmate lock is held by a live primary; refusing to start another.'
    [[ -z "$target" ]] || firstmate_focus "$target"
    return 0
  fi
  if [[ "$agent" == claude ]]; then
    need ai-acct
    # Bind the picked account to the pane by name: the child reads that token
    # itself, so a concurrent switch cannot change it. The shared selector and
    # tmux token follow only once the pane exists, so crews use the same account
    # and a failed launch leaves every default untouched.
    ai-acct check "$account" >&2 || fail 'could not load Claude account'
    printf -v cmd 'exec ai-acct exec --account %q %s' "$account" "${cmd#exec }"
  fi
  target="=$FIRSTMATE_SESSION:1"
  if tmux has-session -t "=$FIRSTMATE_SESSION" 2>/dev/null; then
    windows=$(tmux list-windows -t "=$FIRSTMATE_SESSION" \
      -F $'#{window_index}\t#{window_id}\t#{window_name}\t#{window_panes}') \
      || fail 'could not inspect firstmate session'
    while IFS=$'\t' read -r index window name panes; do
      [[ "$index" == 1 ]] || continue
      first=$window
      if firstmate_idle_shell "$window" "$name" "$panes" \
        || firstmate_dead_pane "$window" "$name" "$panes"; then
        tmux respawn-window -k -t "$window" -c "$FIRSTMATE_DIR" "$cmd" \
          || fail 'could not reuse firstmate shell window'
        tmux rename-window -t "$window" "$FIRSTMATE_WINDOW" \
          || fail 'could not name firstmate window'
        firstmate_commit_account "$account"
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
  firstmate_commit_account "$account"
  tmux switch-client -t "$target"
}

# Machine interface for ai-acct resume: apply the launcher's guards and print
# the physical home and the explicit Claude session id, one per line. Needs no
# tmux, and never pauses for a key.
action_resume_session() {
  local pid session cwd
  [[ -d "$FIRSTMATE_DIR" ]] || { err "firstmate home not found: $FIRSTMATE_DIR"; exit 1; }
  have jq || { err 'jq is required to find the Firstmate session'; exit 1; }
  if pid=$(firstmate_live_primary_pid); then
    err "Firstmate lock is held by live primary $pid; refusing to start another."
    exit 1
  fi
  session=$(firstmate_session_id claude) \
    || { err "no Claude transcript to resume in $FIRSTMATE_DIR"; exit 1; }
  cwd=$(cd "$FIRSTMATE_DIR" && pwd -P) || exit 1
  printf '%s\n%s\n' "$cwd" "$session"
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
    # Internal entry points (fzf quota action, ai-acct resume); not in the menu.
    _agent-quota) firstmate_agent_quota_action ;;
    resume-session) action_resume_session ;;
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
    firstmate) printf '%s  firstmate: new / resume / jump' '󰚩' ;;
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
        printf '%s' "${AI_FIRSTMATE_AGENT:-claude}"
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
