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
	if ok and query and pcall(vim.treesitter.get_parser, 0, lang) then
		vim.wo.foldmethod = "expr"
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	end
end

function M.icons()
	local devicons = package.loaded["nvim-web-devicons"]
	if not devicons then
		return
	end
	local text = require("customize.kitty_palette").palette().text
	local overrides = {}
	for key, icon in pairs(devicons.get_icons()) do
		overrides[key] = vim.tbl_extend("force", icon, {
			color = text,
			icon = vim.env.NVIM_ASCII == "1" and "." or icon.icon,
		})
	end
	devicons.set_icon(overrides)
	local default = devicons.get_default_icon()
	devicons.set_default_icon(vim.env.NVIM_ASCII == "1" and "." or default.icon, text, default.cterm_color)
end

function M.decorations()
	local colors = require("customize.kitty_palette").palette()
	for name, hl in pairs(require("customize.transparent").decorations(colors, M.primary())) do
		vim.api.nvim_set_hl(0, name, hl)
	end
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
			end)
		end,
	})
end

return M
