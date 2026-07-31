#!/usr/bin/env bash
# Grep finder: rg → fzf → nvim (jumps to the exact line)
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

for bin in rg fzf bat nvim; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'grep-finder: %s not found in PATH\n' "$bin" >&2
    read -rsn1 -p 'Press any key to close...'
    exit 1
  }
done

# --max-columns keeps minified/generated files from flooding fzf, and
# --no-messages drops the unreadable-file noise. The '.' pattern still matches
# every line by design — fzf does the actual filtering.
rg --column --line-number --no-heading --color=always --smart-case \
   --max-columns=200 --max-columns-preview --no-messages . 2>/dev/null | \
  fzf --ansi --delimiter=: --reverse \
      --prompt '🔎 ' --border-label ' Grep Finder ' \
      --preview 'bat --color=always --highlight-line {2} -- {1}' \
      --preview-window 'up,60%,border-bottom,+{2}+3/3' \
      --bind 'enter:become(nvim +{2} -- {1})'
