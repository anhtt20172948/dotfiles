-- load theme
vim.opt.termguicolors = true
-- vim.cmd("colorscheme bluloco")
vim.cmd("colorscheme catppuccin")
-- vim.cmd([[colorscheme tokyonight]])

-- Follow DMS theme changes (and pushed palettes on servers) without a restart.
-- Reconfiguring Catppuccin and reloading it fires ColorScheme, which rebuilds
-- lualine, devicons and the decoration groups from the new palette.
local kitty = require("customize.kitty_palette")
kitty.follow(function()
	-- Catppuccin names itself catppuccin-<flavour> once loaded.
	if not (vim.g.colors_name or ""):match("^catppuccin") then
		vim.o.background = kitty.background()
		return
	end
	for _, spec in ipairs(require("plugins.themes")) do
		if spec.name == "catppuccin" then
			spec.config()
		end
	end
	-- Catppuccin sets 'background' from the configured flavour while loading.
	vim.cmd.colorscheme("catppuccin")
end)
