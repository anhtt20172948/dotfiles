local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local kitty = require("customize.kitty_palette")
local plugin = vim.env.CATPPUCCIN_TEST_RTP
if plugin then
	vim.opt.rtp:prepend(plugin)
end
local accents = {
	"rosewater",
	"flamingo",
	"pink",
	"mauve",
	"red",
	"maroon",
	"peach",
	"yellow",
	"green",
	"teal",
	"sky",
	"sapphire",
	"blue",
	"lavender",
}
for _, case in ipairs({
	{ flavour = "mocha", base = "#0d0e12", text = "#dddddd", primary = "#bedad7", expected = "#424b4d" },
	{ flavour = "latte", base = "#eff1f5", text = "#4c4f69", primary = "#7287fd", expected = "#cad1f7" },
}) do
	kitty.active = {
		flavour = case.flavour,
		colors = { base = case.base, text = case.text },
		primary = case.primary,
		selection_background = "#bedad7",
		selection_foreground = "#2c4543",
	}
	local stock = {
		surface0 = "#303030",
		surface2 = "#505050",
		pink = case.text,
		rosewater = case.text,
		maroon = case.text,
		overlay0 = case.text,
	}
	if plugin then
		stock = require("catppuccin.palettes." .. case.flavour)
	end
	local colors = kitty.colors(stock)
	local function apply()
		if plugin then
			package.loaded["plugins.themes"] = nil
			require("plugins.themes")[2].config()
			vim.cmd.colorscheme("catppuccin")
		else
			for name, hl in pairs(require("customize.transparent").highlights(colors, case.primary)) do
				vim.api.nvim_set_hl(0, name, hl)
			end
		end
	end
	local function check()
		local search = vim.api.nvim_get_hl(0, { name = "Search", link = false })
		local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
		local background = ("#%06x"):format(assert(search.bg))
		assert(background ~= case.base and search.bg ~= visual.bg, "search needs its own subtle tint")
		assert(kitty.contrast(("#%06x"):format(assert(search.fg)), background) >= 4.5)
		for _, name in ipairs({ "CurSearch", "IncSearch" }) do
			local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
			assert(
				("#%06x"):format(assert(hl.bg))
					== (plugin and kitty.ensure_contrast(case.primary, colors.base, colors.text, 4.5) or case.primary),
				name .. " must use DMS primary"
			)
			assert(kitty.contrast(("#%06x"):format(assert(hl.fg)), ("#%06x"):format(hl.bg)) >= 4.5)
		end
		for _, name in ipairs({ "Visual", "VisualNOS" }) do
			local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
			assert(hl.fg == nil and hl.bg ~= nil and not hl.reverse, name .. " must preserve syntax")
			local background = ("#%06x"):format(hl.bg)
			assert(background ~= case.base and background ~= kitty.active.selection_background)
			assert(
				kitty.contrast(colors.text, background) >= 4.5,
				case.flavour .. " " .. background .. " " .. colors.text
			)
			for _, accent in ipairs(accents) do
				assert(not colors[accent] or kitty.contrast(colors[accent], background) >= 3, accent)
			end
			if not plugin then
				assert(background == case.expected, background)
			end
		end
	end
	apply()
	-- Exercise the actual final startup overrides after the colorscheme loads.
	package.loaded.core = {}
	package.loaded["configs.lazy"] = {}
	package.loaded["current-theme"] = {}
	local palettes = package.loaded["catppuccin.palettes"]
	package.loaded["catppuccin.palettes"] = {
		get_palette = function()
			return colors
		end,
	}
	dofile(root .. "/.config/nvim/init.lua")
	package.loaded["catppuccin.palettes"] = palettes
	check()
	apply()
	check()
end
local constrained = { base = "#101010", text = "#ffffff", red = "#777777" }
local reduced = kitty.selection_background(constrained, "#ffffff")
assert(reduced ~= constrained.base and reduced ~= "#585858", "reduce the tint for low-contrast syntax")
assert(kitty.contrast(constrained.red, reduced) >= 3)
assert(constrained.red == "#777777", "never recolour syntax to accommodate selection")
kitty.active = nil
local fallback =
	require("customize.transparent").highlights({ base = "#1e1e2e", text = "#cdd6f4", surface2 = "#585b70" }, "#b4befe")
assert(fallback.Visual.bg == "#585b70" and fallback.VisualNOS.bg == "#585b70")
assert(fallback.Visual.fg == "NONE" and fallback.VisualNOS.fg == "NONE")
for _, group in ipairs({ "Search", "CurSearch", "IncSearch" }) do
	assert(kitty.contrast(fallback[group].fg, fallback[group].bg) >= 4.5, group .. " fallback contrast")
end
print("visual and search highlights: OK" .. (plugin and " (Catppuccin startup and reload)" or " (offline)"))
