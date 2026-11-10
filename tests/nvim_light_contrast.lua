-- Light-mode legibility: every syntax and text highlight group keeps its floor
-- against the light background, and dark palettes keep their colours.
-- CATPPUCCIN_TEST_RTP=<catppuccin checkout> enumerates the real highlight groups
-- (tests/run.sh sets it from lazy.nvim's copy when there is one); without it
-- only the palette derivation is checked.
local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.opt.termguicolors = true
vim.env.SSH_CONNECTION = nil
vim.env.LC_KITTY_PALETTE = nil
vim.env.TMUX = nil
local plugin = vim.env.CATPPUCCIN_TEST_RTP
if plugin then
	vim.opt.rtp:prepend(plugin)
end
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
local kitty = require("customize.kitty_palette")
local ui = require("customize.ui")

-- Catppuccin's own palettes, so the offline suite derives from the real accents.
local latte = {
	rosewater = "#dc8a78",
	flamingo = "#dd7878",
	pink = "#ea76cb",
	mauve = "#8839ef",
	red = "#d20f39",
	maroon = "#e64553",
	peach = "#fe640b",
	yellow = "#df8e1d",
	green = "#40a02b",
	teal = "#179299",
	sky = "#04a5e5",
	sapphire = "#209fb5",
	blue = "#1e66f5",
	lavender = "#7287fd",
	text = "#4c4f69",
	subtext1 = "#5c5f77",
	subtext0 = "#6c6f85",
	overlay2 = "#7c7f93",
	overlay1 = "#8c8fa1",
	overlay0 = "#9ca0b0",
	surface2 = "#acb0be",
	surface1 = "#bcc0cc",
	surface0 = "#ccd0da",
	base = "#eff1f5",
	mantle = "#e6e9ef",
	crust = "#dce0e8",
}
local mocha = {
	rosewater = "#f5e0dc",
	flamingo = "#f2cdcd",
	pink = "#f5c2e7",
	mauve = "#cba6f7",
	red = "#f38ba8",
	maroon = "#eba0ac",
	peach = "#fab387",
	yellow = "#f9e2af",
	green = "#a6e3a1",
	teal = "#94e2d5",
	sky = "#89dceb",
	sapphire = "#74c7ec",
	blue = "#89b4fa",
	lavender = "#b4befe",
	text = "#cdd6f4",
	subtext1 = "#bac2de",
	subtext0 = "#a6adc8",
	overlay2 = "#9399b2",
	overlay1 = "#7f849c",
	overlay0 = "#6c7086",
	surface2 = "#585b70",
	surface1 = "#45475a",
	surface0 = "#313244",
	base = "#1e1e2e",
	mantle = "#181825",
	crust = "#11111b",
}
local layers = { base = true, mantle = true, crust = true, surface0 = true, surface1 = true, surface2 = true }
local muted = { overlay0 = true, overlay1 = true, overlay2 = true, subtext0 = true, subtext1 = true }

local function use(fixture)
	vim.fn.writefile(vim.fn.readfile(root .. "/tests/fixtures/palettes/" .. fixture), dir .. "/dank-theme.conf")
	kitty.active = kitty.read()
	return assert(kitty.active)
end

-- Palette derivation: light syntax >= LIGHT_SYNTAX_FLOOR, muted layers >= LIGHT_MUTED_FLOOR.
for _, fixture in ipairs({ "dms-light.conf", "dms-light-recorded.conf" }) do
	local active = use(fixture)
	assert(active.flavour == "latte", fixture .. " must derive a light flavour")
	local colors = kitty.colors(latte)
	for key, color in pairs(colors) do
		if not layers[key] then
			local floor = muted[key] and kitty.LIGHT_MUTED_FLOOR or kitty.LIGHT_SYNTAX_FLOOR
			local ratio = kitty.contrast(color, colors.base)
			assert(ratio >= floor, ("%s %s %s is %.2f:1, below %s:1"):format(fixture, key, color, ratio, floor))
		end
	end
end
-- Dark palettes keep the AA floor, so their colours do not change.
for _, fixture in ipairs({ "dms-dark.conf" }) do
	use(fixture)
	local colors = kitty.colors(mocha)
	for key, color in pairs(colors) do
		if not layers[key] then
			local stock = vim.tbl_extend("force", mocha, kitty.active.colors)[key]
			assert(color == kitty.ensure_contrast(stock, colors.base, colors.text, 4.5), key .. " changed in dark mode")
		end
	end
end

if not plugin then
	print("skip: light highlight groups need CATPPUCCIN_TEST_RTP")
	print("nvim light contrast: OK (palette only)")
	return
end

-- Real Catppuccin: enumerate the highlight groups it defines.
local syntax = {
	"Comment",
	"Constant",
	"String",
	"Character",
	"Number",
	"Boolean",
	"Float",
	"Identifier",
	"Function",
	"Statement",
	"Conditional",
	"Repeat",
	"Label",
	"Operator",
	"Keyword",
	"Exception",
	"PreProc",
	"Include",
	"Define",
	"Macro",
	"PreCondit",
	"Type",
	"StorageClass",
	"Structure",
	"Typedef",
	"Special",
	"SpecialChar",
	"Tag",
	"Delimiter",
	"SpecialComment",
	"Debug",
	"LspInlayHint",
	"LineNr",
	"LineNrAbove",
	"LineNrBelow",
	"CursorLineNr",
}
-- Core syntax roles must clear the stronger light floor; muted ones (comments,
-- punctuation, inlay hints, line numbers) may be quieter.
local strong = {
	"@keyword",
	"@string",
	"@function",
	"@type",
	"@constant",
	"@number",
	"@boolean",
	"@property",
	"@variable.member",
	"@variable.parameter",
	"@operator",
	"@module",
	"@constructor",
	"@tag",
}
local function hex(value)
	return ("#%06x"):format(value)
end
local function apply()
	package.loaded["plugins.themes"] = nil
	require("plugins.themes")[2].config()
	vim.cmd.colorscheme("catppuccin")
	ui.decorations()
	ui.light_contrast()
end
local function groups()
	local result = {}
	for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
		if not hl.link then
			result[name] = hl
		end
	end
	return result
end

for _, fixture in ipairs({ "dms-light.conf", "dms-light-recorded.conf" }) do
	use(fixture)
	apply()
	assert(vim.o.background == "light", fixture .. " must set background=light")
	local base = kitty.active.colors.base
	local checked = 0
	local function ratio(name)
		local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
		if not hl.fg then
			return nil
		end
		return kitty.contrast(hex(hl.fg), hl.bg and hex(hl.bg) or base), hex(hl.fg)
	end
	for name in pairs(groups()) do
		if name:sub(1, 1) == "@" then
			syntax[#syntax + 1] = name
		end
	end
	for _, name in ipairs(syntax) do
		local value, fg = ratio(name)
		if value then
			checked = checked + 1
			assert(
				value >= kitty.LIGHT_MUTED_FLOOR - 0.01,
				("%s %s %s is %.2f:1 on %s"):format(fixture, name, fg, value, base)
			)
		end
	end
	assert(checked > 100, "expected the treesitter groups to be defined, checked " .. checked)
	for _, name in ipairs(strong) do
		local value, fg = assert(ratio(name))
		assert(
			value >= kitty.LIGHT_SYNTAX_FLOOR - 0.01,
			("%s %s %s is %.2f:1, below %s:1"):format(fixture, name, fg, value, kitty.LIGHT_SYNTAX_FLOOR)
		)
	end
	-- Every other text group (popups, neo-tree, pickers, git, diagnostics)
	-- keeps AA against its own background; rules and guides stay quiet.
	local low = ui.low_contrast(kitty.TEXT_FLOOR)
	assert(#low == 0, fixture .. " low-contrast text groups: " .. vim.inspect(vim.tbl_map(function(item)
		return ("%s %s on %s %.2f:1"):format(item.name, item.fg, item.bg, item.ratio)
	end, low)))
end

-- Plugins loaded later define their own groups, often with `default = true`
-- (lspsaga's black-on-accent Diagnostic*Reverse): lifted after the load.
ui.setup()
local accent = ("#%06x"):format(vim.api.nvim_get_hl(0, { name = "DiagnosticError", link = false }).fg)
vim.api.nvim_set_hl(0, "TestPluginReverse", { fg = "Black", bg = accent, default = true })
assert(kitty.contrast("#000000", accent) < 4.5, "the stand-in must start unreadable")
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "test-plugin" })
vim.wait(50, function()
	return false
end, 10)
local early = vim.api.nvim_get_hl(0, { name = "TestPluginReverse", link = false })
assert(early.fg == 0, "startup plugin loads wait for the single VeryLazy pass")
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
assert(
	vim.wait(1000, function()
		local hl = vim.api.nvim_get_hl(0, { name = "TestPluginReverse", link = false })
		return kitty.contrast(hex(hl.fg), hex(hl.bg)) >= 4.5
	end, 10),
	"a plugin group defined after the colorscheme must be lifted"
)
vim.api.nvim_set_hl(0, "TestLaterPlugin", { fg = "Black", bg = accent, default = true })
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "later-plugin" })
assert(
	vim.wait(1000, function()
		local hl = vim.api.nvim_get_hl(0, { name = "TestLaterPlugin", link = false })
		return kitty.contrast(hex(hl.fg), hex(hl.bg)) >= 4.5
	end, 10),
	"a plugin loaded after startup must be lifted on its LazyLoad"
)

-- The light-mode lift must leave dark highlight groups untouched.
use("dms-dark.conf")
package.loaded["plugins.themes"] = nil
require("plugins.themes")[2].config()
vim.cmd.colorscheme("catppuccin")
ui.decorations()
assert(vim.o.background == "dark")
local before = groups()
ui.light_contrast()
assert(vim.deep_equal(before, groups()), "dark palettes must keep their highlight colours")
print("nvim light contrast: OK (Catppuccin highlight groups)")
