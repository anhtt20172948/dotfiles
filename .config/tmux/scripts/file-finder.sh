#!/usr/bin/env bash
# File finder: fd → fzf → nvim (chạy trong display-popup)
target=$(fd -t f -H . 2>/dev/null | fzf --reverse \
  --prompt ' ' --border-label ' File Finder ' \
  --preview 'bat --color=always --style=numbers --line-range :200 {}')
[[ -z "$target" ]] && exit 0
nvim "$target"
