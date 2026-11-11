-- neo-tree drawn like yazi. yazi can only name ANSI slots, so the folder
-- colours and the current row are those same slots, resolved through kitty's
-- palette here instead of taken from Catppuccin: both tools follow DMS from one
-- source and read as one system. tests/test_material_folder_icons.py keeps
-- these tables and .config/yazi/theme.toml in step.
--
-- Neovim still holds its contrast floors: on a light palette a slot below the
-- floor is darkened along OKLab lightness, keeping its hue, so neo-tree is
-- darker than yazi's raw slot there: folder names (text, 7:1) on any light
-- palette, and most of all the bright slots 11, 13 and 14, which dank16 makes
-- pale on a light background. Dark palettes clear the floor: identical colours.
--
-- The MiniIcons* groups are mini.icons' own, so which-key's icons follow too.
local M = {}

-- Folders, icon and name: yazi's [filetype] "*/" rule and dir icon (blue).
M.DIRECTORY = 4

-- Named folder icons: the mini.icons group neo-tree uses -> the slot yazi's
-- [icon] prepend_dirs entry for the same folder names.
M.ICONS = {
	MiniIconsAzure = 4, -- blue
	MiniIconsBlue = 14, -- lightcyan
	MiniIconsCyan = 6, -- cyan
	MiniIconsGreen = 2, -- green
	MiniIconsGrey = 7, -- gray
	MiniIconsOrange = 3, -- yellow
	MiniIconsPurple = 13, -- lightmagenta
	MiniIconsRed = 1, -- red
	MiniIconsYellow = 11, -- lightyellow
}

-- The current row is yazi's hovered row: black (the palette background in
-- DMS) on cyan (the DMS primary), bold. The same accent pill as the tmux
-- current window and lualine's mode, instead of a surface bar.
M.CURSOR = { fg = 0, bg = 6, bold = true }

-- Highlight groups for the active palette; empty without one (plain Catppuccin).
function M.highlights(colors)
	local kitty = require("customize.kitty_palette")
	local ansi = kitty.active and kitty.active.ansi
	if not ansi then
		return {}
	end
	local backdrop = kitty.backdrop(colors.base)
	-- Icons are glyphs and keep the muted floor, like devicons; names are text.
	local function slot(index, quiet)
		return kitty.ensure_contrast(ansi[index], backdrop, colors.text, kitty.text_floor(quiet))
	end
	local highlights = {
		NeoTreeDirectoryIcon = { fg = slot(M.DIRECTORY, true) },
		NeoTreeDirectoryName = { fg = slot(M.DIRECTORY) },
		NeoTreeRootName = { fg = slot(M.DIRECTORY), style = { "bold" } },
	}
	for group, index in pairs(M.ICONS) do
		highlights[group] = { fg = slot(index, true) }
	end
	-- A pill is opaque in kitty: its text is measured against the pill. With a
	-- foreground set, the cursor line overrides the icon and name colours, so
	-- the whole row is one pill, as in yazi.
	local pill = ansi[M.CURSOR.bg]
	highlights.NeoTreeCursorLine = {
		fg = kitty.ensure_contrast(ansi[M.CURSOR.fg], pill, colors.text, kitty.text_floor()),
		bg = pill,
		style = M.CURSOR.bold and { "bold" } or {},
	}
	return highlights
end

return M
