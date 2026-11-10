# The workspace: tmux window 1 has Neovim beside a Starship shell, window 2 is
# yazi, window 3 is lazygit. Stills: workspace, which-key, yazi, lazygit.
Hide
Type "clear; tmux -L dotfiles-demo new-session -s dotfiles -n code" Enter
Sleep 1s
Ctrl+B
Type ":split-window -h -l 38%" Enter
Sleep 1s
Type "clear; git log -14 --format='%C(yellow)%h%C(reset) %<(44,trunc)%s'" Enter
Sleep 0.5s
Ctrl+B
Type ":new-window -d -n files yazi .config" Enter
Ctrl+B
Type ":new-window -d -n git lazygit" Enter
Ctrl+B
Type ":select-pane -t 1" Enter
Type "nvim +250 +'normal! zz' .config/nvim/lua/customize/kitty_palette.lua" Enter
Sleep 6s
# Dismiss the update notice lazy.nvim's checker shows for any plugin the
# lockfile keeps behind upstream (<leader>un). The first <leader> only loads
# which-key, which then pops up on the next one. Neovim never enters Insert
# mode here: that would start Supermaven, which registers the machine online.
Type " "
Sleep 1s
Escape
Type " un"
Sleep 1s
Type "0"
Show
Sleep 2.5s
Screenshot "@SHOTS@/workspace.png"
Type " "
Sleep 2s
Screenshot "@SHOTS@/which-key.png"
Escape
Sleep 1s
Ctrl+B
Type "2"
Sleep 1.5s
Down@300ms 3
Sleep 1.5s
Screenshot "@SHOTS@/yazi.png"
Ctrl+B
Type "3"
Sleep 1.5s
Type "4"
Sleep 2.5s
Screenshot "@SHOTS@/lazygit.png"
Ctrl+B
Type "1"
Sleep 2s
