local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local kitty = require("customize.kitty_palette")
local config, palette
package.loaded["catppuccin.palettes"] = {
	get_palette = function()
		return palette
	end,
}
package.loaded.lualine = {
	setup = function(opts)
		config = opts
	end,
}
local account_status = function()
	return "account"
end
package.loaded["customize.aiterm_ecc"] = { account_status = account_status }
package.loaded["lazy.status"] = {
	updates = function()
		return "updates"
	end,
	has_updates = function()
		return true
	end,
}
local function component(section, name)
	for _, item in ipairs(config.sections[section]) do
		if item[1] == name then
			return item
		end
	end
	error("missing component: " .. name)
end
local function readable(color, background)
	assert(background:match("^#%x%x%x%x%x%x$"), "pill needs a resolved background colour")
	assert(kitty.contrast(color, background) >= 4.5, color .. " lacks contrast against " .. background)
end
local stock = {
	base = "#1e1e2e",
	text = "#cdd6f4",
	subtext0 = "#a6adc8",
	green = "#a6e3a1",
	mauve = "#cba6f7",
	red = "#f38ba8",
	peach = "#fab387",
	yellow = "#f9e2af",
	blue = "#89b4fa",
	teal = "#94e2d5",
	lavender = "#b4befe",
}
for _, ascii in ipairs({ "0", "1" }) do
	vim.env.NVIM_ASCII = ascii
	package.loaded["lib.icons"] = nil
	for _, base in ipairs({ "#141218", "#1e1e2e", "#f5eff7" }) do
		palette = vim.tbl_extend("force", stock, {
			base = base,
			text = base == "#f5eff7" and "#1d1b20" or stock.text,
			-- Exercise adjustment rather than assuming the provider is readable.
			subtext0 = "#777777",
			red = "#ad3444",
		})
		kitty.active = { primary = "#8070b0" }
		require("plugins.lualine").config()
		assert(config.options.globalstatus == false)
		local seen = {}
		for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "terminal" }) do
			local theme = config.options.theme[mode]
			readable(theme.a.fg, theme.a.bg)
			assert(theme.a.bg == theme.z.bg and theme.a.fg == theme.z.fg, "both pills must track the mode")
			assert(tonumber(theme.a.fg:sub(2), 16) < 0x303030, "pill text must be dark")
			if mode ~= "terminal" then
				assert(not seen[theme.a.bg], "editing modes need distinct pill colours")
				seen[theme.a.bg] = true
			end
			for _, section in ipairs({ "b", "c", "x", "y" }) do
				assert(theme[section].bg == "NONE", "only the two pills may have backgrounds")
				readable(theme[section].fg, base)
			end
		end
		for _, section in pairs(config.options.theme.inactive) do
			assert(section.bg == "NONE")
			readable(section.fg, base)
		end
		local branch = component("lualine_b", "branch")
		assert(branch.color.fg == require("customize.ui").primary())
		local filename = component("lualine_c", "filename")
		assert(filename.color.gui == "bold" and filename.file_status and filename.symbols.modified == "[+]")
		local diff = component("lualine_c", "diff")
		local diagnostics = component("lualine_x", "diagnostics")
		for _, colors in ipairs({ diff.diff_color, diagnostics.diagnostics_color }) do
			assert(vim.tbl_count(colors) >= 3)
			for _, color in pairs(colors) do
				readable(color.fg, base)
			end
		end
		for _, section in pairs(config.sections) do
			for _, item in ipairs(section) do
				if item.color then
					assert(item.color.bg == "NONE")
					readable(item.color.fg, base)
				end
			end
		end
		assert(config.sections.lualine_x[1][1] == account_status, "account component must survive")
		local lsp = config.sections.lualine_x[2]
		assert(lsp.icon == (ascii == "1" and "" or vim.trim(require("lib.icons").ui.Code)))
		assert(lsp.fmt("lua_ls") == (ascii == "1" and "LSP lua_ls" or "lua_ls"))
		assert(lsp.fmt("") == "", "no LSP label without a client")
		local updates = component("lualine_x", require("lazy.status").updates)
		assert(updates.fmt("󰒲 3") == (ascii == "1" and "U3" or "󰒲 3"), "update glyph needs an ASCII fallback")
		assert(component("lualine_z", "location").fmt("  1:1 ") == "1:1", "compact location must avoid wasted space")
		assert(#config.extensions == 8)
		assert(component("lualine_x", "encoding").color.fg == component("lualine_x", "fileformat").color.fg)
		assert(component("lualine_x", "encoding").color.fg ~= filename.color.fg, "secondary text must be dimmed")
		assert(config.options.section_separators.left == (ascii == "1" and "" or ""))
		assert(config.options.section_separators.right == (ascii == "1" and "" or ""))
		assert(config.options.component_separators.left == (ascii == "1" and "|" or ""))
		assert(config.options.component_separators.right == (ascii == "1" and "|" or ""))
		for _, section in ipairs({ "lualine_a", "lualine_z" }) do
			assert(config.sections[section][1].separator == nil, "use the section's slanted transition")
		end
		local before = config.options.theme.normal.a.bg
		kitty.active = { primary = "#e0a060" }
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		vim.wait(20)
		assert(config.options.theme.normal.a.bg ~= before, "palette reload must rebuild resolved colours")
	end
end
local window_width = vim.api.nvim_win_get_width
local current_width
vim.api.nvim_win_get_width = function(window)
	assert(window == 0, "width predicates must use the current window, not the whole terminal")
	return current_width
end
for _, width in ipairs({ 35, 40, 60, 80, 100, 120 }) do
	current_width = width
	assert(component("lualine_b", "branch").cond() == (width >= 60))
	assert(component("lualine_c", "diff").cond() == (width >= 60))
	assert(component("lualine_c", "filetype").cond() == (width >= 80))
	assert(config.sections.lualine_x[2].cond() == (width >= 80))
	assert(component("lualine_x", "diagnostics").cond() == (width >= 40))
	assert(component("lualine_x", "encoding").cond() == (width >= 100))
	assert(component("lualine_x", "fileformat").cond() == (width >= 100))
	assert(component("lualine_x", "searchcount").cond() == (width >= 80))
end
assert(component("lualine_a", "mode").fmt("NORMAL") == "NORMAL")
current_width = 60
assert(component("lualine_a", "mode").fmt("NORMAL") == "N")
vim.api.nvim_win_get_width = window_width
print("lualine mode pills, contrast, split widths, ASCII separators and reloads: OK")

-- Opt in to rendering with the real plugin, keeping CI's offline suite independent of downloads.
if vim.env.LUALINE_TEST_RTP then
	vim.opt.rtp:prepend(vim.env.LUALINE_TEST_RTP)
	package.loaded.lualine = nil
	vim.o.termguicolors = true
	vim.api.nvim_set_hl(0, "StatusLine", { fg = stock.text, bg = "NONE" })
	for _, ascii in ipairs({ "0", "1" }) do
		vim.env.NVIM_ASCII = ascii
		package.loaded["lib.icons"] = nil
		require("plugins.lualine").config()
		for _, width in ipairs({ 35, 60, 120 }) do
			vim.o.columns = width
			local statusline = require("lualine").statusline(true)
			local rendered = vim.api.nvim_eval_statusline(statusline, { highlights = true, maxwidth = width })
			assert(not rendered.str:find("", 1, true) and not rendered.str:find("", 1, true))
			if ascii == "1" then
				assert(not rendered.str:find("[\128-\255]"), "ASCII statusline must contain no glyphs")
			else
				for _, edge in ipairs({ { "", "a" }, { "", "z" } }) do
					local position = assert(rendered.str:find(edge[1], 1, true), "missing slanted edge") - 1
					local group
					for _, highlight in ipairs(rendered.highlights) do
						if highlight.start <= position then
							group = highlight.group
						end
					end
					local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
					local section = vim.api.nvim_get_hl(0, { name = "lualine_" .. edge[2] .. "_normal", link = false })
					assert(hl.fg == section.bg, "edge must inherit the coloured section background")
					assert(hl.bg == nil and not hl.reverse, "edge background must stay transparent")
				end
			end
		end
	end
	print("rendered slanted edges and transparent highlight backgrounds: OK")
end
