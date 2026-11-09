local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local ui = require("customize.ui")
for _, width in ipairs({ 0, 1, 8, 34 }) do
	for _, text in ipairs({ "a long session name", "漢字かな session", "école", "👩‍💻 session" }) do
		local result = ui.truncate(text, width)
		assert(vim.fn.strdisplaywidth(result) <= width, result)
		assert(not result:find("�", 1, true), "truncation must preserve UTF-8")
	end
end
assert(ui.truncate("short", 20) == "short")
local saved_ascii = vim.env.NVIM_ASCII
vim.env.NVIM_ASCII = "1"
package.loaded["lib.icons"] = nil
local icons = require("lib.icons")
assert(icons.diagnostics.Error == "E" and icons.git.Add == "+")
assert(icons.diagnostics.Warn == icons.diagnostics.Warning and icons.diagnostics.Info == icons.diagnostics.Information)
vim.env.NVIM_ASCII = saved_ascii
package.loaded["lib.icons"] = nil
local kitty = require("customize.kitty_palette")
for _, case in ipairs({
	{ base = "#101010", text = "#ffffff", primary = "#222222" },
	{ base = "#ffffff", text = "#101010", primary = "#dddddd" },
}) do
	local colors = kitty.colors({ base = case.base, text = case.text, overlay0 = case.primary })
	local primary = kitty.ensure_contrast(case.primary, colors.base, colors.text, 4.5)
	local groups = require("customize.transparent").decorations(colors, primary)
	for name, hl in pairs(groups) do
		assert(hl.bg == "NONE", name)
		assert(kitty.contrast(hl.fg, colors.base) >= 4.5, name .. " needs 4.5:1 contrast")
	end
	assert(groups.SnacksIndentScope.fg == primary and groups.FoldColumn.fg == colors.overlay0)
end
vim.bo.filetype = "no_parser_for_this_filetype"
ui.folds()
assert(vim.wo.foldmethod == "manual", "missing parser needs manual folding")
assert(vim.wo.foldlevel == 99, "files start unfolded")
vim.bo.filetype = "bigfile"
vim.wo.statuscolumn = "test-gutter"
ui.folds()
assert(vim.wo.foldmethod == "manual" and vim.wo.statuscolumn == "")
vim.bo.filetype = "no_parser_for_this_filetype"
ui.folds()
assert(vim.wo.statuscolumn == "test-gutter", "restore the gutter after leaving a big file")
print("nvim UI fallbacks: OK")
