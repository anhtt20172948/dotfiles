#!/usr/bin/env bash
# Grep finder: rg → fzf → nvim (nhảy đúng dòng)
rg --column --line-number --no-heading --color=always --smart-case . 2>/dev/null | \
  fzf --ansi --delimiter=: --reverse \
      --prompt '🔎 ' --border-label ' Grep Finder ' \
      --preview 'bat --color=always --highlight-line {2} {1}' \
      --preview-window 'up,60%,border-bottom,+{2}+3/3' \
      --bind 'enter:become(nvim +{2} {1})'
