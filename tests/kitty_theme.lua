local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.env.LC_KITTY_PALETTE = nil
vim.env.SSH_CONNECTION = nil
local kitty = require("customize.kitty_palette")
-- Stub the plugin so the repository suite remains offline.
local stock = {
	base = "#1e1e2e",
	mantle = "#181825",
	crust = "#11111b",
	text = "#cdd6f4",
	peach = "#fab387",
	maroon = "#eba0ac",
	teal = "#94e2d5",
	red = "#f38ba8",
	sapphire = "#74c7ec",
	lavender = "#b4befe",
	blue = "#89b4fa",
	pink = "#f5c2e7",
	green = "#a6e3a1",
	flamingo = "#f2cdcd",
	overlay0 = "#6c7086",
}
package.preload["catppuccin.palettes.mocha"] = function()
	return stock
end
package.preload["catppuccin.palettes.latte"] = function()
	return stock
end
local options
package.preload.catppuccin = function()
	return {
		setup = function(opts)
			options = opts
		end,
	}
end
local spec = require("plugins.themes")[2]
for _, bg in ipairs({ "#0d0e12", "#eeeeee", "missing" }) do
	kitty.active = bg ~= "missing"
			and {
				flavour = bg == "#0d0e12" and "mocha" or "latte",
				colors = { base = bg, text = "#dddddd", overlay0 = "#2e576b" },
				primary = "#2e576b",
			}
		or nil
	spec.config()
	assert(options.transparent_background and options.float.transparent, "editor and floats must be transparent")
	assert(not options.float.solid)
	local colors = options.color_overrides[options.flavour]
	assert(colors.base == (bg == "missing" and stock.base or bg), "contrast must use the unmodified Kitty background")
	for key, color in pairs(colors) do
		if not vim.tbl_contains({ "base", "mantle", "crust", "surface0", "surface1", "surface2" }, key) then
			assert(kitty.contrast(color, colors.base) >= 4.5, key)
		end
	end
	for _, key in ipairs({ "functions", "types", "variables", "operators", "miscs", "properties" }) do
		assert(#options.styles[key] == 0, key .. " must be plain")
	end
	assert(options.styles.comments[1] == "italic")
	for _, key in ipairs({ "keywords", "conditionals", "loops" }) do
		assert(options.styles[key][1] == "bold")
	end
	assert(stock.base == "#1e1e2e" and stock.text == "#cdd6f4", "stock palette must remain unchanged")
	local highlights = options.highlight_overrides.all(colors)
	assert(#highlights["@keyword.operator"].style == 0)
	assert(vim.deep_equal(highlights["@string.special.url"].style, { "underline" }))
	local seen = {}
	for _, group in ipairs({
		"@variable",
		"@constant",
		"@variable.parameter",
		"@property",
		"@variable.builtin",
		"@function.builtin",
	}) do
		local hl = highlights[group]
		assert(not seen[hl.fg], group .. " must be visually distinct")
		seen[hl.fg] = true
		assert(#hl.style == 0, group .. " must be plain")
	end
	for _, group in ipairs({ "@constant.builtin", "@lsp.type.enumMember", "@lsp.typemod.variable.readonly" }) do
		assert(highlights[group].fg == colors.peach)
	end
	assert(highlights["@lsp.type.parameter"].fg == colors.maroon)
	assert(highlights["@lsp.type.property"].fg == colors.teal)
	assert(kitty.contrast(highlights.FloatBorder.fg, colors.base) >= 4.5)
end
print("kitty theme: OK")
