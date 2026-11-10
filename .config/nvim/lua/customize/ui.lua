local M = {}

function M.primary()
	local kitty = require("customize.kitty_palette")
	local colors = kitty.palette()
	return kitty.ensure_contrast(
		kitty.active and kitty.active.primary or colors.lavender or colors.text,
		colors.base,
		colors.text,
		4.5
	)
end

function M.truncate(text, width)
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	if width < 1 then
		return ""
	end
	local result = ""
	for _, char in ipairs(vim.fn.split(text, "\\zs")) do
		if vim.fn.strdisplaywidth(result .. char .. "~") > width then
			break
		end
		result = result .. char
	end
	return result .. "~"
end

function M.folds()
	vim.opt_local.fillchars:append({ foldopen = "-", foldclose = "+", foldsep = " " })
	local key = vim.api.nvim_get_current_buf() .. ":" .. vim.bo.filetype
	if vim.w.dotfiles_fold_buffer == key then
		return
	end
	vim.w.dotfiles_fold_buffer = key
	vim.wo.foldlevel = 99
	vim.wo.foldmethod = "manual"
	vim.wo.foldexpr = "0"
	if vim.bo.filetype == "bigfile" then
		vim.b.snacks_scope = false
		vim.b.snacks_indent = false
		vim.w.dotfiles_statuscolumn = vim.w.dotfiles_statuscolumn or vim.wo.statuscolumn
		vim.wo.statuscolumn = ""
		return
	end
	if vim.w.dotfiles_statuscolumn then
		vim.wo.statuscolumn = vim.w.dotfiles_statuscolumn
		vim.w.dotfiles_statuscolumn = nil
	end
	if vim.bo.buftype ~= "" or not vim.treesitter.foldexpr then
		return
	end
	local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
	if not lang then
		return
	end
	local ok, query = pcall(vim.treesitter.query.get, lang, "folds")
	if ok and query and vim.treesitter.get_parser(0, lang, { error = false }) then
		vim.wo.foldmethod = "expr"
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	end
end

local icon_sources, default_icon_source

function M.icons()
	local devicons = package.loaded["nvim-web-devicons"]
	if not devicons then
		return
	end
	local kitty = require("customize.kitty_palette")
	local colors = kitty.palette()
	-- Always start from the provider colours, not a previous palette's adjustment.
	icon_sources = icon_sources or vim.deepcopy(devicons.get_icons())
	default_icon_source = default_icon_source or vim.deepcopy(devicons.get_default_icon())
	local overrides = {}
	for key, icon in pairs(icon_sources) do
		overrides[key] = vim.tbl_extend("force", icon, {
			color = kitty.ensure_contrast(icon.color, colors.base, colors.text, 4.5),
			icon = vim.env.NVIM_ASCII == "1" and "." or icon.icon,
		})
	end
	devicons.set_icon(overrides)
	local default = default_icon_source
	devicons.set_default_icon(
		vim.env.NVIM_ASCII == "1" and "." or default.icon,
		kitty.ensure_contrast(default.color, colors.base, colors.text, 4.5),
		default.cterm_color
	)
end

function M.snacks_icons()
	local util = require("snacks.util")
	local fallback = util.icon
	util.icon = function(name, category, opts)
		if category == "directory" then
			return fallback(name, category, opts)
		end
		local devicons = require("nvim-web-devicons")
		if category == "filetype" then
			return devicons.get_icon_by_filetype(name, { default = true })
		elseif category == "extension" then
			return devicons.get_icon(nil, name, { default = true })
		end
		return devicons.get_icon(vim.fn.fnamemodify(name, ":t"), nil, { default = true })
	end
end

function M.decorations()
	local colors = require("customize.kitty_palette").palette()
	for name, hl in pairs(require("customize.transparent").decorations(colors, M.primary())) do
		vim.api.nvim_set_hl(0, name, hl)
	end
end

-- Rules, guides and lualine's separator glyphs, not text: they stay quiet on purpose.
local decorative = { "Separator", "Split", "Indent", "Whitespace", "VirtLine", "lualine_transitional_" }

local function is_decorative(name)
	for _, part in ipairs(decorative) do
		if name:find(part, 1, true) then
			return true
		end
	end
	return false
end

-- Text highlight groups below floor against their own background (the terminal
-- background when transparent): { name, hl, fg, bg, ratio } records.
function M.low_contrast(floor)
	local kitty = require("customize.kitty_palette")
	local base = kitty.palette().base
	local result = {}
	for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
		if hl.fg and not hl.link and not hl.reverse and not is_decorative(name) then
			local fg = ("#%06x"):format(hl.fg)
			local bg = hl.bg and ("#%06x"):format(hl.bg) or base
			-- fg == bg hides text on purpose (EndOfBuffer tildes, borderless titles).
			local ratio = kitty.contrast(fg, bg)
			if fg ~= bg and ratio < floor then
				result[#result + 1] = { name = name, hl = hl, fg = fg, bg = bg, ratio = ratio }
			end
		end
	end
	return result
end

-- Catppuccin, its integrations and plugins derive some text colours for dark
-- backgrounds (selection, match, blame text, lspsaga's black-on-accent pills).
-- On a light palette, lift every text group below 4.5:1 against its own
-- background. Dark palettes keep their colours.
function M.light_contrast()
	local kitty = require("customize.kitty_palette")
	if kitty.background() ~= "light" then
		return
	end
	local text = kitty.palette().text
	for _, low in ipairs(M.low_contrast(kitty.TEXT_FLOOR)) do
		local lifted = kitty.ensure_contrast(low.fg, low.bg, text, kitty.TEXT_FLOOR)
		-- A kept `default` would leave the plugin's own definition in place.
		vim.api.nvim_set_hl(0, low.name, vim.tbl_extend("force", low.hl, { fg = lifted, default = false }))
	end
end

-- Plugins loaded after the colorscheme define their own groups. One pass at
-- VeryLazy covers everything loaded during startup; after that, one pass per
-- burst of lazy loads (lspsaga on LspAttach, ...).
local lift_pending, lift_started = false, false
local function queue_light_contrast(event)
	if event.match == "VeryLazy" then
		lift_started = true
	end
	if lift_pending or not lift_started then
		return
	end
	lift_pending = true
	vim.schedule(function()
		lift_pending = false
		M.light_contrast()
	end)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("DotfilesUI", { clear = true })
	vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, { group = group, callback = M.folds })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			-- Providers register their own reload hooks after the theme is loaded.
			vim.schedule(function()
				M.decorations()
				M.icons()
				M.light_contrast()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "VeryLazy", "LazyLoad" },
		callback = queue_light_contrast,
	})
end

return M
