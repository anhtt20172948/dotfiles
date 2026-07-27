#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"

# Chọn session qua fzf-tmux
target=$(
  sesh list --icons | fzf-tmux --reverse -p 60%,65% \
    --no-sort --ansi --border-label ' sesh ' --prompt '⚡ ' \
    --header ' ^a all ^t tmux ^g configs ^x zoxide ^d kill ^f find' \
    --bind 'tab:down,btab:up' \
    --bind 'ctrl-a:change-prompt(⚡ )+reload(sesh list --icons)' \
    --bind 'ctrl-t:change-prompt(🪟 )+reload(sesh list -t --icons)' \
    --bind 'ctrl-g:change-prompt(⚙️ )+reload(sesh list -c --icons)' \
    --bind 'ctrl-x:change-prompt(📁 )+reload(sesh list -z --icons)' \
    --bind 'ctrl-f:change-prompt(🔎 )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
    --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡ )+reload(sesh list --icons)' \
    --preview-window 'right:60%' \
    --preview 'sesh preview {}'
)

# Nếu hủy chọn (bấm ESC) thì thoát an toàn
[[ -z "$target" ]] && exit 0

# Kết nối tới session/thư mục đã chọn
sesh connect "$target"
