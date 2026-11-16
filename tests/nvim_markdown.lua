local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local kitty = require("customize.kitty_palette")
local plugin = vim.env.CATPPUCCIN_TEST_RTP
if plugin then
	vim.opt.rtp:prepend(plugin)
else
	package.preload["catppuccin.palettes"] = function()
		return {
			get_palette = function()
				return kitty.colors({})
			end,
		}
	end
end
local spec = require("plugins.render-markdown")
assert(vim.deep_equal(spec.ft, { "markdown" }), "markdown must remain filetype lazy-loaded")
local renderer
if vim.env.RENDER_MARKDOWN_TEST_RTP then
	vim.opt.rtp:prepend(vim.env.RENDER_MARKDOWN_TEST_RTP)
	renderer = require("render-markdown.core.colors")
	renderer.init()
end

local function highlight(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
local function hex(value)
	return ("#%06x"):format(assert(value))
end
local function readable(name, colors, quiet)
	local hl = highlight(name)
	local background = hl.bg and hex(hl.bg) or kitty.backdrop(colors.base)
	assert(kitty.contrast(hex(hl.fg), background) >= kitty.text_floor(quiet) - 0.01, name .. " must remain readable")
end
local previous
local dark_headings
for _, fixture in ipairs({ "dms-dark.conf", "dms-light-recorded.conf", "dms-dark.conf" }) do
	local values = {}
	for _, line in ipairs(vim.fn.readfile(root .. "/tests/fixtures/palettes/" .. fixture)) do
		local key, color = line:match("^([%w_]+)%s+(#%x+)")
		if key then
			values[key] = color
		end
	end
	kitty.active = kitty.from_values(values)
	local colors = kitty.colors({})
	if plugin then
		require("plugins.themes")[2].config()
		vim.cmd.colorscheme("catppuccin")
		colors = kitty.palette()
	else
		for name, hl in pairs(require("customize.transparent").decorations(colors, kitty.primary(colors))) do
			vim.api.nvim_set_hl(0, name, hl)
		end
	end
	local headings = {}
	local heading_surfaces = {}
	local heading_groups = {}
	for level = 1, 6 do
		local foreground = spec.opts.heading.foregrounds and spec.opts.heading.foregrounds[level]
			or "RenderMarkdownH" .. level
		local background = spec.opts.heading.backgrounds and spec.opts.heading.backgrounds[level]
			or "RenderMarkdownH" .. level .. "Bg"
		readable(foreground, colors)
		readable(background, colors)
		headings[highlight(foreground).fg] = true
		assert(highlight(foreground).bold, "headings must retain emphasis")
		local band = highlight(background).bg
		heading_groups[level] = { highlight(foreground), highlight(background) }
		assert((band ~= nil) == (kitty.background() == "light" or level == 1), "light headings need visible bands")
		if band then
			heading_surfaces[band] = true
		end
	end
	assert(vim.tbl_count(headings) == 6, "heading levels must be distinct")
	if kitty.background() == "light" then
		assert(vim.tbl_count(heading_surfaces) == 6, "light heading bands must differentiate all six levels")
	elseif dark_headings then
		assert(vim.deep_equal(heading_groups, dark_headings), "returning to dark mode must restore heading styles")
	else
		dark_headings = heading_groups
	end
	local code = highlight("RenderMarkdownCode")
	assert(code.bg and code.fg == nil, "fenced code must have a surface and preserve syntax foregrounds")
	assert(highlight("RenderMarkdownCodeBorder").fg == nil, "borders must preserve the language label foreground")
	assert(hex(code.bg) == colors.surface0, "code must follow the palette surface")
	assert(highlight("RenderMarkdownCodeBorder").bg == code.bg, "fence borders must share the code surface")
	assert(highlight("RenderMarkdownCodeInfo").bg == code.bg, "fence language rows must share the code surface")
	-- render-markdown draws thin borders and language padding with this generated
	-- foreground. Exercise the later UI pass, not just the source highlight groups.
	local border = "RenderMarkdown_RenderMarkdownCodeBorder_bg_as_fg"
	if renderer then
		border = renderer.bg_as_fg("RenderMarkdownCodeBorder", true)
	else
		vim.api.nvim_set_hl(0, border, { fg = code.bg })
	end
	vim.api.nvim_set_hl(0, "MarkdownContrastProbe", { fg = code.bg })
	require("customize.ui").light_contrast()
	assert(highlight(border).fg == code.bg, "contrast correction must not darken fence decoration into bars")
	if kitty.background() == "light" then
		assert(highlight("MarkdownContrastProbe").fg ~= code.bg, "ordinary text still needs contrast correction")
	end
	assert(highlight("RenderMarkdownCodeInline").bg == code.bg, "inline code must share the code surface")
	readable("RenderMarkdownCodeInline", colors)
	readable("RenderMarkdownCodeInfo", colors)
	for _, name in ipairs({
		"RenderMarkdownQuote",
		"RenderMarkdownTableHead",
		"RenderMarkdownTableRow",
		"RenderMarkdownInfo",
		"RenderMarkdownHint",
		"RenderMarkdownWarn",
		"RenderMarkdownError",
		"RenderMarkdownChecked",
		"RenderMarkdownUnchecked",
	}) do
		readable(name, colors, true)
	end
	if previous then
		assert(previous ~= code.bg, "switching palettes must rebuild markdown surfaces")
	end
	previous = code.bg
end
print("nvim markdown: OK" .. (plugin and " (Catppuccin reload)" or " (offline overrides)"))
