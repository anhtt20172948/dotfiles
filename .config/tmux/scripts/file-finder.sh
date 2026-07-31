#!/usr/bin/env bash
# File finder: fd → fzf → nvim (runs inside a tmux display-popup)
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

for bin in fd fzf bat nvim; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'file-finder: %s not found in PATH\n' "$bin" >&2
    read -rsn1 -p 'Press any key to close...'
    exit 1
  }
done

target=$(fd -t f -H . 2>/dev/null | fzf --reverse \
  --prompt ' ' --border-label ' File Finder ' \
  --preview 'bat --color=always --style=numbers --line-range :200 -- {}')
[[ -z "$target" ]] && exit 0
# `--` so a filename starting with '-' is not parsed as an nvim option
nvim -- "$target"
