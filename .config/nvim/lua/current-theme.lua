-- load theme
vim.opt.termguicolors = true
-- vim.cmd('colorscheme bluloco')

vim.cmd("colorscheme catppuccin")

-- custome highlight
vim.cmd([[
  highlight LineNr guifg=white
  highlight LineNrAbove guifg=gray
  highlight LineNrBelow guifg=gray
]])
