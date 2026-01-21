-- put this in your main init.lua file ( before lazy setup )
require("core")
require("configs.lazy")
require("current-theme")

-- to fix notice.nvim
vim.o.lazyredraw = false

-- transparent background
-- vim.api.nvim_set_hl(0, 'Normal', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'Terminal', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'EndOfBuffer', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'FoldColumn', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'Folded', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'SignColumn', { bg = 'none' })

-- vim.api.nvim_set_hl(0, "Search", { bg = "#8BCD5B", fg = "#202020" })
-- vim.api.nvim_set_hl(0, "CurSearch", { bg = "#EFBD5D", fg = "#000000" })
-- vim.api.nvim_set_hl(0, "IncSearch", { bg = "#F15664", fg = "#000000" })

-- set cursorline color
-- vim.api.nvim_set_hl(0, "CursorLine", { bg = "#1b2f3b" })
-- vim.api.nvim_set_hl(0, "CursorColumn", { bg = "#1A1A1F" })

-- set visual highlight
-- vim.api.nvim_set_hl(0, "Visual", { bg = "#103070" })

-- vim.cmd([[
--   highlight LineNr guifg=white
--   highlight LineNrAbove guifg=gray
--   highlight LineNrBelow guifg=gray
-- ]])
--
-- Search highlights (pink-focused)
vim.api.nvim_set_hl(0, "Search", { bg = "#FF79C6", fg = "#1E1E2E" }) -- bright pink
vim.api.nvim_set_hl(0, "CurSearch", { bg = "#FF92D0", fg = "#1E1E2E" }) -- lighter pink
vim.api.nvim_set_hl(0, "IncSearch", { bg = "#FF5C8A", fg = "#1E1E2E" }) -- strong hot pink

-- Cursor line / column (soft pink, not overpowering)
vim.api.nvim_set_hl(0, "CursorLine", { bg = "#2A1F2E" }) -- muted pink tint
vim.api.nvim_set_hl(0, "CursorColumn", { bg = "#241A26" })

-- Visual selection (dark pink / magenta)
vim.api.nvim_set_hl(0, "Visual", { bg = "#5A1E4A" })

vim.cmd([[
  highlight LineNr        guifg=#FF2E88 gui=bold
  highlight LineNrAbove   guifg=#6B6F8E
  highlight LineNrBelow   guifg=#6B6F8E
]])
