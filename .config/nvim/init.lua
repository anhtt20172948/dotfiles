-- put this in your main init.lua file ( before lazy setup )
require("core")
require("configs.lazy")
require("current-theme")

-- to fix notice.nvim
vim.o.lazyredraw = true


-- transparent background
vim.api.nvim_set_hl(0, 'Normal', { bg = 'none' })
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })
vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Terminal', { bg = 'none' })
vim.api.nvim_set_hl(0, 'EndOfBuffer', { bg = 'none' })
vim.api.nvim_set_hl(0, 'FoldColumn', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Folded', { bg = 'none' })
vim.api.nvim_set_hl(0, 'SignColumn', { bg = 'none' })

vim.api.nvim_set_hl(0, 'Search', { bg = '#8BCD5B', fg = '#202020' })
vim.api.nvim_set_hl(0, 'CurSearch', { bg = '#EFBD5D', fg = '#000000' })
vim.api.nvim_set_hl(0, 'IncSearch', { bg = '#F15664', fg = '#000000' })

-- set cursorline color
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#1b2f3b' })
vim.api.nvim_set_hl(0, 'CursorColumn', { bg = '#1A1A1F' })

-- set visual highlight
vim.api.nvim_set_hl(0, 'Visual', { bg = '#103070' })

vim.cmd([[
  highlight LineNr guifg=white
  highlight LineNrAbove guifg=gray
  highlight LineNrBelow guifg=gray
]])
