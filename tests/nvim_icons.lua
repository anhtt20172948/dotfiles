local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local ui = require("customize.ui")
local kitty = require("customize.kitty_palette")
local palette
package.loaded["catppuccin.palettes"] = {
	get_palette = function()
		return palette
	end,
}
local sources = {
	cpp = { icon = "C", name = "Cpp", color = "#519aba", cterm_color = "74" },
	h = { icon = "H", name = "H", color = "#a074c4", cterm_color = "140" },
	lua = { icon = "L", name = "Lua", color = "#51a0cf", cterm_color = "74" },
	dark = { icon = "D", name = "Dark", color = "#222222", cterm_color = "235" },
}
local default_source = { icon = "?", name = "Default", color = "#6d8086", cterm_color = "66" }
local icons, default = vim.deepcopy(sources), vim.deepcopy(default_source)
local devicons = {
	get_icons = function()
		return icons
	end,
	get_default_icon = function()
		return default
	end,
	set_icon = function(overrides)
		icons = vim.tbl_extend("force", icons, overrides)
	end,
	set_default_icon = function(icon, color, cterm)
		default = { icon = icon, color = color, cterm_color = cterm }
	end,
}
package.loaded["nvim-web-devicons"] = devicons
ui.setup()
for _, ascii in ipairs({ "0", "1", "0" }) do
	vim.env.NVIM_ASCII = ascii
	for _, current in ipairs({
		{ base = "#141218", text = "#e6e0e9" }, -- DMS-like.
		{ base = "#1e1e2e", text = "#cdd6f4" }, -- Mocha.
		{ base = "#f5eff7", text = "#1d1b20" }, -- Light to dark reloads must be reversible.
		{ base = "#141218", text = "#e6e0e9" },
	}) do
		palette = current
		for _, reload in ipairs({ false, true }) do
			if reload then
				vim.api.nvim_exec_autocmds("ColorScheme", {})
				vim.wait(20)
			else
				ui.icons()
			end
			local colors = {}
			for key, source in pairs(sources) do
				local icon = icons[key]
				assert(icon.color == kitty.ensure_contrast(source.color, palette.base, palette.text, 4.5))
				assert(kitty.contrast(icon.color, palette.base) >= 4.5)
				assert(icon.icon == (ascii == "1" and "." or source.icon))
				assert(icon.cterm_color == source.cterm_color)
				colors[icon.color] = true
			end
			assert(vim.tbl_count(colors) > 1, "file icons must retain distinct colours")
			assert(icons.cpp.color ~= icons.h.color, "C++ blue and header purple must differ")
			assert(default.color == kitty.ensure_contrast(default_source.color, palette.base, palette.text, 4.5))
			assert(default.icon == (ascii == "1" and "." or default_source.icon))
		end
	end
end
local calls = {}
devicons.get_icon = function(name, ext, opts)
	assert(opts.default)
	calls[#calls + 1] = { name = name, ext = ext }
	return "file", "DevIconFile"
end
devicons.get_icon_by_filetype = function(name, opts)
	assert(name == "cpp" and opts.default)
	return "type", "DevIconCpp"
end
package.loaded["snacks.util"] = {
	icon = function(name, category)
		assert(name == "src" and category == "directory", "only directories should use mini.icons")
		return "folder", "MiniIconsPurple"
	end,
}
local configured
package.loaded["snacks"] = {
	setup = function(opts)
		configured = opts
	end,
}
local opts = {}
require("plugins.snacks")[1].config(nil, opts)
assert(configured == opts)
local util = require("snacks.util")
assert(select(2, util.icon("src", "directory")) == "MiniIconsPurple")
assert(select(2, util.icon("/tmp/main.cpp", "file")) == "DevIconFile")
assert(calls[#calls].name == "main.cpp")
assert(select(2, util.icon("cpp", "extension")) == "DevIconFile")
assert(calls[#calls].name == nil and calls[#calls].ext == "cpp")
assert(select(2, util.icon("cpp", "filetype")) == "DevIconCpp")
local statusline
package.loaded["lualine"] = {
	setup = function(config)
		statusline = config
	end,
}
package.loaded["customize.aiterm_ecc"] = { account_status = function() end }
package.loaded["lazy.status"] = { updates = function() end }
require("plugins.lualine").config()
assert(statusline.sections.lualine_c[2].colored, "Lualine icon colours disabled")
assert(statusline.options.icons_enabled, "Nerd Font icons should be enabled outside ASCII mode")
vim.env.NVIM_ASCII = "1"
require("plugins.lualine").config()
assert(not statusline.options.icons_enabled, "ASCII mode should disable Lualine glyphs")
print("devicon colour fallbacks and reloads: OK")
