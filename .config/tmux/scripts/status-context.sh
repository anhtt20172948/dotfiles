#!/usr/bin/env bash
# Status-bar segment: where the focused pane is running, beyond its directory.
#
#   status-context.sh <pane_current_path> <pane_tty> <pane_current_command>
#
# Prints tmux style markup for, in order:
#   - the SSH host: when the pane runs `ssh` (the destination it was given) or
#     when this tmux server itself lives behind SSH (the local host name);
#   - the git branch of the pane's directory, plus a dirty marker and
#     ahead/behind counts.
# Prints nothing for a segment that does not apply, so the bar never carries a
# bare icon (status.conf documents the same trap for other segments).
#
# Cost: tmux runs `#()` jobs in the background and only re-runs one per
# status-interval, so a redraw never waits on this script. Per run it forks one
# `git status` (plus one `ps` while ssh is in the foreground). ANSI colour names
# only, like the rest of the theme.
set -uo pipefail

# The destination of an ssh command line: its first positional argument after
# skipping options. Options that take a value are skipped together with it.
ssh_destination() {
  local skip=0 arg
  for arg in "$@"; do
    if ((skip)); then
      skip=0
      continue
    fi
    case $arg in
      -[bcDEeFIiJLlmOopPQRSWw]) skip=1 ;;
      -*) ;;
      *)
        printf '%s' "${arg#*@}"
        return 0
        ;;
    esac
  done
  return 1
}

# Command line of the ssh process attached to a pane's tty, newest first.
pane_ssh_args() {
  local tty=${1#/dev/}
  [[ -n $tty ]] || return 1
  ps -t "$tty" -o args= 2>/dev/null | awk '$1 == "ssh" || $1 ~ /\/ssh$/ { line = $0 } END { if (line != "") print line }'
}

host_segment() {
  local cmd=$1 tty=$2 dest='' line
  if [[ $cmd == ssh ]]; then
    line=$(pane_ssh_args "$tty") || line=''
    if [[ -n $line ]]; then
      # shellcheck disable=SC2086 # word splitting of the ps line is the point
      dest=$(ssh_destination ${line#* }) || dest=''
    fi
    [[ -n $dest ]] && printf '#[fg=brightmagenta]󰣀 %s ' "$dest"
    return 0
  fi
  if [[ -n ${SSH_CONNECTION:-} ]]; then
    local host
    host=$(uname -n)
    printf '#[fg=brightmagenta]󰣀 %s ' "${host%%.*}"
  fi
  return 0
}

git_segment() {
  local dir=$1 out branch='' oid='' ahead=0 behind=0 dirty='' line
  [[ -d $dir ]] || return 0
  out=$(git -C "$dir" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || return 0
  while IFS= read -r line; do
    case $line in
      '# branch.oid '*) oid=${line#'# branch.oid '} ;;
      '# branch.head '*) branch=${line#'# branch.head '} ;;
      '# branch.ab '*)
        read -r _ _ ahead behind <<<"$line"
        ahead=${ahead#+}
        behind=${behind#-}
        ;;
      '#'*) ;;
      ?*) dirty=1 ;;
    esac
  done <<<"$out"
  [[ -n $branch ]] || return 0
  [[ $branch == '(detached)' ]] && branch="${oid:0:7}"

  printf '#[fg=magenta] %s' "$branch"
  ((ahead > 0)) && printf ' #[fg=green]⇡%s' "$ahead"
  ((behind > 0)) && printf ' #[fg=red]⇣%s' "$behind"
  [[ -n $dirty ]] && printf ' #[fg=yellow]●'
  printf ' '
}

main() {
  local path=${1:-} tty=${2:-} cmd=${3:-}
  host_segment "$cmd" "$tty"
  [[ -n $path ]] && git_segment "$path"
  return 0
}

main "$@"
