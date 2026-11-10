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
	surface0 = "#313244",
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
			surface0 = base == "#f5eff7" and "#ded8e1" or stock.surface0,
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
			for _, section in ipairs({ "c", "x" }) do
				assert(theme[section].bg == "NONE", "central sections must stay transparent")
				readable(theme[section].fg, base)
			end
			for _, section in ipairs({ "b", "y" }) do
				assert(theme[section].bg == palette.surface0, "stepped sections need a palette surface")
				readable(theme[section].fg, theme[section].bg)
			end
		end
		assert(config.options.padding.left >= 1 and config.options.padding.right >= 1)
		for _, section in pairs(config.options.theme.inactive) do
			assert(section.bg == "NONE")
			readable(section.fg, base)
		end
		local branch = component("lualine_b", "branch")
		readable(branch.color.fg, palette.surface0)
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
		for name, section in pairs(config.sections) do
			local background = (name == "lualine_b" or name == "lualine_y") and palette.surface0 or base
			for _, item in ipairs(section) do
				if item.color then
					assert(item.color.bg == (background == base and "NONE" or background))
					readable(item.color.fg, background)
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
		assert(component("lualine_y", "encoding").color.fg == component("lualine_y", "fileformat").color.fg)
		assert(component("lualine_y", "encoding").color.fg ~= filename.color.fg, "secondary text must be dimmed")
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
	assert(component("lualine_y", "encoding").cond() == (width >= 100))
	assert(component("lualine_y", "fileformat").cond() == (width >= 100))
	assert(component("lualine_y", "searchcount").cond() == (width >= 80))
end
assert(component("lualine_a", "mode").fmt("NORMAL") == "NORMAL")
current_width = 60
assert(component("lualine_a", "mode").fmt("NORMAL") == "N")
vim.api.nvim_win_get_width = window_width
print("lualine mode pills, contrast, split widths, ASCII separators and reloads: OK")

-- Opt in to the real renderer without making the offline CI suite download plugins.
if vim.env.LUALINE_TEST_RTP then
	vim.opt.rtp:prepend(vim.env.LUALINE_TEST_RTP)
	package.loaded.lualine = nil
	package.loaded["lualine.components.branch.git_branch"] = {
		init = function() end,
		get_branch = function()
			return "main"
		end,
	}
	local get_clients = vim.lsp.get_clients
	vim.lsp.get_clients = function()
		return { {
			name = "lua_ls",
			flags = {},
			is_stopped = function()
				return true
			end,
		} }
	end
	vim.o.termguicolors = true
	vim.api.nvim_buf_set_name(0, "ui.lua")
	vim.bo.filetype = "lua"
	vim.bo.fileencoding = "utf-8"
	vim.bo.fileformat = "unix"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "needle needle" })
	vim.fn.setreg("/", "needle")
	vim.o.hlsearch = true
	vim.v.hlsearch = 1
	local function highlight_at(rendered, position)
		local group
		for _, highlight in ipairs(rendered.highlights) do
			if highlight.start <= position then
				group = highlight.group
			end
		end
		return vim.api.nvim_get_hl(0, { name = assert(group), link = false })
	end
	local render_width
	vim.api.nvim_win_get_width = function()
		return render_width or 80
	end
	for _, ascii in ipairs({ "0", "1" }) do
		vim.env.NVIM_ASCII = ascii
		package.loaded["lib.icons"] = nil
		require("plugins.lualine").config()
		for _, width in ipairs({ 80, 120, 200 }) do
			render_width = width
			local statusline = require("lualine").statusline(true)
			local rendered = vim.api.nvim_eval_statusline(
				statusline,
				{ winid = vim.api.nvim_get_current_win(), highlights = true, maxwidth = width }
			)
			assert((rendered.str:find("utf-8", 1, true) ~= nil) == (width >= 100), "encoding follows width")
			assert((rendered.str:find("unix", 1, true) ~= nil) == (width >= 100), "fileformat follows width")
			assert((rendered.str:find("NORMAL", 1, true) ~= nil) == (width >= 120), "mode follows width")
			assert(rendered.str:find("main", 1, true), "branch must populate b")
			assert(rendered.str:find("[1/2]", 1, true), "search count must populate y even at 80 columns")
			local component_count, section_count = 0, 0
			for _, glyph in ipairs(ascii == "1" and { "|" } or { "", "", "", "" }) do
				local offset = 1
				while true do
					local first, last = rendered.str:find(glyph, offset, true)
					if not first then
						break
					end
					assert(
						rendered.str:sub(first - 1, first - 1) == " " and rendered.str:sub(last + 1, last + 1) == " ",
						"separator touches text at width " .. width .. ": " .. rendered.str
					)
					if glyph == "" or glyph == "" then
						section_count = section_count + 1
						local edge = highlight_at(rendered, first - 1)
						local left = highlight_at(rendered, first - 2)
						local right = highlight_at(rendered, last)
						local foreground, background
						if glyph == "" then
							foreground, background = left.bg, right.bg
						else
							foreground, background = right.bg, left.bg
						end
						assert(
							edge.fg == foreground and edge.bg == background and not edge.reverse,
							"slanted edge must pair adjacent section backgrounds: "
								.. vim.inspect({ edge, left, right })
						)
					else
						component_count = component_count + 1
					end
					offset = last + 1
				end
			end
			assert(component_count >= 2, "exercise separators on both sides")
			if ascii == "1" then
				assert(not rendered.str:find("[\128-\255]"), "ASCII statusline must contain no glyphs")
			else
				assert(section_count == 4, "both staircases need two visible slanted edges")
			end
			print(("rendered width=%d ascii=%s: %s"):format(width, ascii, rendered.str))
		end
	end
	vim.api.nvim_win_get_width = window_width
	vim.lsp.get_clients = get_clients
	print("rendered spacing and adjacent separator highlight pairs: OK")
end
