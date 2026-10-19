#!/usr/bin/env bash
# ============================================================
# ai-account.sh - Claude account manager (prefix E, nvim <leader>au)
#
#   use      select the token for future launches and tmux panes
#   add      new account; ai-acct reads its token hidden from the terminal
#   edit     replace an account token
#   rename   rename an account (it stays active if it was)
#   remove   delete an account token after confirmation
#
# Usage: ai-account.sh [menu | use NAME | add | edit | rename | remove]
#   No action opens the fzf menu, which returns after each action until Esc.
#
# Tokens go from the terminal straight to ai-acct's stdin: never into argv,
# fzf input or a variable of this script.
# Same contract as the other ai-* scripts: bash 3.2, BSD/GNU clean, UI on stderr.
# ============================================================
set -uo pipefail

LIB_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")
readonly LIB_DIR
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./ai-lib.sh
source "$LIB_DIR/ai-lib.sh"

err() { printf '%sai-account:%s %s\n' "$AI_RED" "$AI_RESET" "$1" >&2; }
info() { printf '%s%s%s\n' "$AI_SUBTEXT" "$1" "$AI_RESET" >&2; }

# Only an interactive popup waits; piped input (names, tokens) is never consumed.
pause() {
  [[ -t 0 ]] || return 0
  printf '\n%sPress any key to continue...%s' "$AI_SUBTEXT" "$AI_RESET" >&2
  read -rsn1 || true
  printf '\n' >&2
}

# Prints the chosen value, or nothing on Esc. Selections are validated against
# the offered values.
pick() {
  local label=$1 entries=$2 selection status value _display
  have fzf || { err "'fzf' not found"; return 1; }
  selection=$(printf '%s' "$entries" | fzf --ansi --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
    --no-sort --cycle --layout=reverse --margin=1,2 --border=rounded \
    --border-label=" Claude $label " --info=hidden \
    --header='Ctrl-j/k move  •  Enter select  •  Esc close' --prompt="$label › " \
    --pointer='' --bind='ctrl-j:down,ctrl-k:up' \
    --color='bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,header:#89b4fa,fg+:#cdd6f4,prompt:#cba6f7,border:#6c7086,label:#cba6f7')
  status=$?
  case "$status" in 0) ;; 1|130) return 0 ;; *) return "$status" ;; esac
  while IFS=$'\t' read -r value _display; do
    if [[ -n "$value" && "$value" == "$selection" ]]; then
      printf '%s\n' "$selection"
      return 0
    fi
  done <<<"$entries"
  err "unexpected selection: $selection"
  return 1
}

# NAME<TAB>NAME [(active)] [QUOTA] lines, from ai-acct so the name rules live
# in one place. Quota is optional: switching must work without it. Names are
# padded so the quota bars line up; the quota keeps its ANSI colors for fzf.
account_entries() {
  local listing name state quota label rows='' width=0
  if have timeout || have gtimeout || have perl; then
    listing=$(ai_run_limited 1 env AI_ACCT_COLOR=1 ai-acct list --quota 2>/dev/null) || listing=$(ai-acct list) || return 1
  else
    listing=$(ai-acct list) || return 1
  fi
  while IFS='|' read -r name state quota; do
    [[ -n "$name" ]] || continue
    label=$name
    [[ "$state" != active ]] || label+=' (active)'
    rows+="$name|$label|${quota:-◌ unknown}"$'\n'
    (( ${#label} <= width )) || width=${#label}
  done <<<"${listing//$'\t'/|}"
  while IFS='|' read -r name label quota; do
    [[ -n "$name" ]] || continue
    printf '%s\t%-*s  %s\n' "$name" "$width" "$label" "$quota"
  done <<<"$rows"
}

pick_account() {
  local entries
  entries=$(account_entries) || return 1
  if [[ -z "$entries" ]]; then
    err 'no Claude accounts yet - add one first'
    return 1
  fi
  pick Account "$entries"
}

# ai-acct prints its own result or error; keep it on screen either way.
acct() {
  ai-acct "$@"
  local status=$?
  pause
  return "$status"
}

# --- actions ------------------------------------------------
action_use() {
  local name=${1:-}
  if [[ -z "$name" ]]; then
    name=$(pick_account) || { pause; return 1; }
    [[ -n "$name" ]] || return 0
  fi
  acct use "$name"
}

action_add() {
  local name
  read -r -p 'New account name (lowercase, digits, - _): ' name || return 0
  [[ -n "$name" ]] || return 0
  acct add "$name"
}

action_edit() {
  local name
  name=$(pick_account) || { pause; return 1; }
  [[ -n "$name" ]] || return 0
  acct edit "$name"
}

action_rename() {
  local name new
  name=$(pick_account) || { pause; return 1; }
  [[ -n "$name" ]] || return 0
  read -r -p "New name for $name: " new || return 0
  [[ -n "$new" ]] || return 0
  acct rename "$name" "$new"
}

action_remove() {
  local name answer
  name=$(pick_account) || { pause; return 1; }
  [[ -n "$name" ]] || return 0
  read -r -p "Remove account $name and its token? [y/N] " answer || answer=''
  case "$answer" in
    y|Y|yes) acct remove "$name" ;;
    *) info 'Kept.' ;;
  esac
}

action_menu() {
  local accounts name label entries choice
  while :; do
    # The previous action's output would otherwise push the menu down.
    [[ ! -t 2 ]] || printf '\033[H\033[2J' >&2
    accounts=$(account_entries) || { pause; return 1; }
    entries=''
    while IFS=$'\t' read -r name label; do
      [[ -n "$name" ]] || continue
      entries="${entries}use:${name}"$'\t'"Use ${label}"$'\n'
    done <<<"$accounts"
    entries="${entries}add"$'\t'$'+ Add account\n'
    if [[ -n "$accounts" ]]; then
      entries="${entries}edit"$'\t'$'Replace token\n'
      entries="${entries}rename"$'\t'$'Rename account\n'
      entries="${entries}remove"$'\t'$'Remove account\n'
    fi
    choice=$(pick Accounts "$entries") || return 1
    [[ -n "$choice" ]] || return 0
    case "$choice" in
      use:*) action_use "${choice#use:}" ;;
      add) action_add ;;
      edit) action_edit ;;
      rename) action_rename ;;
      remove) action_remove ;;
    esac
  done
}

main() {
  have ai-acct || { err "'ai-acct' not found - run ./install.sh"; pause; exit 1; }
  local action=${1:-menu}
  [[ $# -eq 0 ]] || shift
  case "$action" in
    menu|use|add|edit|rename|remove) "action_$action" "$@" ;;
    *) err "unknown action: $action"; exit 2 ;;
  esac
}

main "$@"
