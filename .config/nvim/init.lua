-- put this in your main init.lua file ( before lazy setup )
require("core")
require("configs.lazy")
require("current-theme")

-- to fix notice.nvim
vim.o.lazyredraw = false

local palette = require("customize.kitty_palette").palette()
vim.api.nvim_set_hl(0, "CursorLine", { bg = palette.surface0 })
vim.api.nvim_set_hl(0, "CursorColumn", { bg = palette.surface0 })
vim.api.nvim_set_hl(0, "LineNr", { fg = palette.pink, bold = true })
vim.api.nvim_set_hl(0, "LineNrAbove", { fg = palette.overlay0 })
vim.api.nvim_set_hl(0, "LineNrBelow", { fg = palette.overlay0 })
