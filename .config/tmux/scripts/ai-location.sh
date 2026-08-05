#!/usr/bin/env bash
# Location picker: choose WHERE the AI tool runs — this host, or inside a
# running Docker container. Runs inside a tmux display-popup, first stage of the
# `a` flow, and only shown when at least one container is running (persistent-ai
# skips it otherwise, so the host path keeps its single-keystroke feel).
#
# stdout is the machine-readable channel: exactly one token, `host` or
# `container:<name>`. Every prompt goes to stderr. Escape / no selection prints
# nothing and exits 0 — the caller reads that as "close the popup".
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
blue=$AI_BLUE
green=$AI_GREEN
yellow=$AI_YELLOW
subtext=$AI_SUBTEXT

SCRIPT_PATH=${BASH_SOURCE[0]}

# --preview <token> [image] [status]
if [[ ${1:-} == '--preview' ]]; then
  token=${2:-}
  image=${3:-}
  status=${4:-}
  if [[ "$token" == host ]]; then
    printf '\n  %s%s%s  %sHost%s\n' "$blue$bold" '' "$reset" "$bold" "$reset"
    printf '  %sRun on this machine, using tools on the host PATH.%s\n\n' "$subtext" "$reset"
    printf '%s%sDETAILS%s\n' "$mauve" "$bold" "$reset"
    printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
    printf '  %s%-11s%s %s\n' "$subtext" 'Where' "$reset" 'localhost'
    printf '  %s%-11s%s %s\n' "$subtext" 'History' "$reset" 'resume + usage panes available'
  else
    name=${token#container:}
    printf '\n  %s%s%s  %s%s%s\n' "$green$bold" '' "$reset" "$bold" "$name" "$reset"
    printf '  %sRun inside this container via docker exec.%s\n\n' "$subtext" "$reset"
    printf '%s%sDETAILS%s\n' "$mauve" "$bold" "$reset"
    printf '%s\n' "${lavender}──────────────────────────────────────────${reset}"
    printf '  %s%-11s%s %s\n' "$subtext" 'Container' "$reset" "$name"
    [[ -n "$image" ]]  && printf '  %s%-11s%s %s\n' "$subtext" 'Image' "$reset" "$image"
    [[ -n "$status" ]] && printf '  %s%-11s%s %s\n' "$subtext" 'Status' "$reset" "$status"
    printf '  %s%-11s%s %s\n' "$subtext" 'History' "$reset" 'launch + attach only (host-only history)'
  fi
  exit 0
fi

have fzf || { printf 'ai-location: fzf is required\n' >&2; exit 1; }

newline=$'\n'
tab=$'\t'

# Host is always first and pre-highlighted, so on the common path Enter selects
# it immediately and the flow is indistinguishable from the pre-Docker one.
host_label="${blue}${bold}${reset}  ${bold}Host${reset}  ${subtext}this machine${reset}"
entries="host${tab}${host_label}${tab}"

while IFS=$'\t' read -r name image status; do
  [[ -n "$name" ]] || continue
  label="${green}${bold}${reset}  ${bold}${name}${reset}  ${subtext}${image}${reset}"
  line="container:${name}${tab}${label}${tab}${image}${tab}${status}"
  entries="${entries}${newline}${line}"
done < <(list_containers)

printf -v preview_command 'bash %q --preview {1} {3} {4}' "$SCRIPT_PATH"

# A docker error (permission denied, daemon down) means the container list is
# empty for a reason worth naming, so the caller passes it here to explain why
# only Host is offered — far better than the popup silently skipping this step.
header='Ctrl-j/k move  •  Enter select  •  Esc close'
[[ -n "${AI_POPUP_DOCKER_NOTE:-}" ]] && \
  header="${header}"$'\n'"${yellow}⚠ ${AI_POPUP_DOCKER_NOTE}${reset}"

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
    --border-label=' AI Location ' \
    --info=inline-right \
    --header-first \
    --header="$header" \
    --prompt='󰡨  Where › ' \
    --pointer='' \
    --preview-window='right,55%,wrap,border-left' \
    --preview-label=' Details ' \
    --bind='ctrl-j:down,ctrl-k:up' \
    --color='bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#89b4fa,info:#cba6f7,pointer:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#6c7086,label:#cba6f7' \
    --preview="$preview_command"
) || {
  fzf_status=$?
  case "$fzf_status" in
    1|130) exit 0 ;;
    *)     exit "$fzf_status" ;;
  esac
}

[[ -n "$selection" ]] || exit 0
printf '%s\n' "$selection"
