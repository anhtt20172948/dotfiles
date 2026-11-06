-- put this in your main init.lua file ( before lazy setup )
require("core")
require("configs.lazy")
require("current-theme")

-- to fix notice.nvim
vim.o.lazyredraw = false

local palette = require("customize.kitty_palette").palette()
local kitty = require("customize.kitty_palette").active
vim.api.nvim_set_hl(0, "Search", { bg = palette.pink, fg = palette.base })
vim.api.nvim_set_hl(0, "CurSearch", { bg = palette.rosewater, fg = palette.base })
vim.api.nvim_set_hl(0, "IncSearch", { bg = palette.maroon, fg = palette.base })
vim.api.nvim_set_hl(0, "CursorLine", { bg = palette.surface0 })
vim.api.nvim_set_hl(0, "CursorColumn", { bg = palette.surface0 })
vim.api.nvim_set_hl(0, "Visual", {
	bg = kitty and kitty.selection_background or palette.surface2,
	fg = kitty and kitty.selection_foreground or palette.text,
})
vim.api.nvim_set_hl(0, "LineNr", { fg = palette.pink, bold = true })
vim.api.nvim_set_hl(0, "LineNrAbove", { fg = palette.overlay0 })
vim.api.nvim_set_hl(0, "LineNrBelow", { fg = palette.overlay0 })
