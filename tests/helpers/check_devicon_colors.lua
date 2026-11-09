local root = assert(arg[1], "repository root required")
local plugins = arg[2] or (vim.fn.stdpath("data") .. "/lazy")
vim.opt.rtp:prepend(root .. "/.config/nvim")
for _, plugin in ipairs({ "nvim-web-devicons", "snacks.nvim", "mini.icons" }) do
	vim.opt.rtp:append(plugins .. "/" .. plugin)
end
local palette
package.loaded["catppuccin.palettes"] = {
	get_palette = function()
		return palette
	end,
}
local kitty = require("customize.kitty_palette")
local ui = require("customize.ui")
local devicons = require("nvim-web-devicons")
devicons.setup()
local original = vim.deepcopy(devicons.get_icons())
local default = vim.deepcopy(devicons.get_default_icon())
ui.setup()
local function check()
	local colors = {}
	for key, source in pairs(original) do
		local icon = devicons.get_icons()[key]
		local expected = kitty.ensure_contrast(source.color, palette.base, palette.text, 4.5)
		assert(icon.color == expected, "original colour lost: " .. tostring(key))
		assert(kitty.contrast(icon.color, palette.base) >= 4.5, "low contrast: " .. tostring(key))
		assert(icon.icon == (vim.env.NVIM_ASCII == "1" and "." or source.icon))
		local hl = vim.api.nvim_get_hl(0, { name = "DevIcon" .. icon.name, link = false })
		-- Upstream aliases sometimes share a highlight name but have different colours.
		assert(hl.fg, "missing highlight: " .. icon.name)
		assert(kitty.contrast(("#%06x"):format(hl.fg), palette.base) >= 4.5, "low contrast highlight: " .. icon.name)
		colors[icon.color] = true
	end
	assert(vim.tbl_count(colors) > 1, "file icons are monochrome")
	local actual = devicons.get_default_icon()
	assert(actual.color == kitty.ensure_contrast(default.color, palette.base, palette.text, 4.5))
	assert(actual.icon == (vim.env.NVIM_ASCII == "1" and "." or default.icon))
	assert(devicons.get_icons().cpp.color ~= devicons.get_icons().h.color, "C++ and headers need distinct colours")
end
for _, current in ipairs({
	{ base = "#141218", text = "#e6e0e9" }, -- DMS-like dark palette.
	{ base = "#1e1e2e", text = "#cdd6f4" }, -- Catppuccin Mocha fallback.
	{ base = "#f5eff7", text = "#1d1b20" }, -- Light palette exercises reloads in both directions.
	{ base = "#141218", text = "#e6e0e9" },
}) do
	palette = current
	ui.icons()
	check()
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	vim.wait(50)
	check()
end
local specs = require("plugins.neo-tree")
local mini = require("mini.icons")
for _, dependency in ipairs(specs[2].dependencies) do
	if type(dependency) == "table" and dependency[1] == "echasnovski/mini.icons" then
		mini.setup(dependency.opts)
	end
end
local tree
package.loaded["neo-tree"] = {
	setup = function(opts)
		tree = opts
	end,
}
package.loaded["neo-tree.events"] = { FILE_MOVED = "file_moved", FILE_RENAMED = "file_renamed" }
Snacks = require("snacks")
Snacks.rename = { on_rename_file = function() end }
specs[2].config(nil, {})
local provider = tree.default_component_configs.icon.provider
local util = require("snacks.util")
local folder, folder_hl = util.icon("src", "directory")
-- Run the actual Snacks config hook without starting unrelated services.
Snacks.setup = function() end
require("plugins.snacks")[1].config(nil, {})
local after, after_hl = util.icon("src", "directory")
assert(folder == after and folder_hl == after_hl, "Snacks folder icons changed")
for _, file in ipairs({ "main.cpp", "main.h", "main.lua", "unknown.xyzabc" }) do
	local glyph, hl = devicons.get_icon(file, nil, { default = true })
	local icon = {}
	provider(icon, { type = "file", name = file }, {})
	assert(icon.text == glyph and icon.highlight == hl, "Neo-tree differs: " .. file)
	local picked, picked_hl = util.icon("/tmp/" .. file, "file")
	assert(picked == glyph and picked_hl == hl, "Snacks differs: " .. file)
	local fragments = Snacks.picker.format.filename({ file = file }, {
		opts = { icons = { files = { enabled = true } }, formatters = { file = { icon_width = 2 } } },
	})
	assert(fragments[1][2] == hl, "Snacks picker lost devicons highlight")
end
for _, category in ipairs({ "filetype", "extension" }) do
	local glyph, hl = util.icon("cpp", category)
	local expected, expected_hl
	if category == "filetype" then
		expected, expected_hl = devicons.get_icon_by_filetype("cpp", { default = true })
	else
		expected, expected_hl = devicons.get_icon(nil, "cpp", { default = true })
	end
	assert(glyph == expected and hl == expected_hl)
end
local folder_icon = {}
provider(folder_icon, { type = "directory", name = "src" }, {})
local mini_glyph, mini_hl = mini.get("directory", "src")
assert(folder_icon.text == mini_glyph and folder_icon.highlight == mini_hl)
local statusline
package.loaded["lualine"] = {
	setup = function(opts)
		statusline = opts
	end,
}
package.loaded["customize.aiterm_ecc"] = { account_status = function() end }
package.loaded["lazy.status"] = { updates = function() end }
require("plugins.lualine").config()
assert(statusline.sections.lualine_c[2].colored, "Lualine icon colours disabled")
assert(statusline.options.icons_enabled == (vim.env.NVIM_ASCII ~= "1"))
print("devicon colours and consumers: OK")
