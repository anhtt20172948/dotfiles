local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.env.SSH_CONNECTION = nil
vim.env.LC_KITTY_PALETTE_SRC = nil
local entries = { "0d0e12", "dddddd" }
for i = 0, 15 do
	entries[#entries + 1] = ("%06x"):format(i * 65793)
end
vim.env.LC_KITTY_PALETTE = table.concat(entries, ":")
local kitty = require("customize.kitty_palette")
assert(kitty.selection_background({ base = "#101010", text = "#ffffff" }, "#ffffff") ~= "#101010")
local plugin = vim.env.CATPPUCCIN_TEST_RTP
if plugin then
	vim.opt.rtp:prepend(plugin)
	require("plugins.themes")[2].config()
	vim.cmd.colorscheme("catppuccin")
else
	-- Offline suite checks the same overrides using Neovim's highlight resolver.
	local colors = kitty.colors({})
	for name, hl in pairs(require("customize.transparent").highlights(colors, colors.text)) do
		vim.api.nvim_set_hl(0, name, hl)
	end
end
for _, name in ipairs({ "Visual", "VisualNOS" }) do
	assert(vim.api.nvim_get_hl(0, { name = name, link = false }).fg == nil, name .. " must preserve syntax colours")
end
local function highlight(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
for _, name in ipairs({
	"Normal",
	"NormalNC",
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
	"Pmenu",
	"PmenuSbar",
	"SignColumn",
	"EndOfBuffer",
	"StatusLine",
	"StatusLineNC",
	"TabLineFill",
	"BlinkCmpMenu",
	"BlinkCmpMenuBorder",
	"BlinkCmpDoc",
	"BlinkCmpDocBorder",
	"BlinkCmpSignatureHelp",
	"CmpDocumentation",
	"CmpDocumentationBorder",
	"SagaNormal",
	"SagaBorder",
	"SagaTitle",
	"NoicePopup",
	"NoiceCmdlinePopup",
	"NoicePopupmenu",
	"NoiceMini",
	"NotifyBackground",
	"SnacksNormal",
	"SnacksNotifier",
	"SnacksInputNormal",
	"SnacksPicker",
	"SnacksPickerList",
	"SnacksPickerInput",
	"SnacksPickerPreview",
	"SnacksPickerBorder",
	"SnacksPickerTitle",
	"TelescopeNormal",
	"TelescopePromptNormal",
	"TelescopeResultsNormal",
	"TelescopePreviewNormal",
	"TelescopeBorder",
	"TelescopePromptTitle",
	"FzfLuaNormal",
	"FzfLuaPreviewNormal",
	"FzfLuaBorder",
	"WhichKeyNormal",
	"WhichKeyBorder",
	"LazyNormal",
	"MasonNormal",
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NvimTreeNormal",
	"NvimTreeNormalNC",
	"NeoTreeStatusLineNC",
	"NvimTreeStatuslineNc",
	"SnacksIndent",
	"SnacksIndentScope",
	"SnacksIndentChunk",
	"Folded",
	"FoldColumn",
	"NoiceSplitBorder",
	"NoiceCmdlinePopupTitle",
	"SnacksNotifierBorderError",
	"SnacksNotifierBorderWarn",
	"SnacksDashboardHeader",
	"Headline1Bg",
	"Headline6Fg",
	"TinyInlineDiagnosticVirtualTextError",
	"TinyInlineDiagnosticVirtualTextBg",
	"TinyInlineDiagnosticVirtualTextArrow",
	"InclineNormal",
	"InclineNormalNC",
	"NeoTreeTabActive",
	"NeoTreeTabInactive",
	"NeoTreeTabSeparatorActive",
	"NeoTreeTabSeparatorInactive",
	"SnacksNotifierHistory",
}) do
	assert(highlight(name).bg == nil, name .. " must have no background")
	assert(highlight(name).fg ~= nil, name .. " must have a visible foreground")
end
for _, name in ipairs({ "CursorLine", "Visual", "PmenuSel", "BlinkCmpMenuSelection", "SnacksPickerSelected" }) do
	assert(highlight(name).bg ~= nil, name .. " must retain a visible selection background")
end
assert(highlight("FloatBorder").fg ~= nil, "borders must stay visible")
if plugin then
	assert(kitty.contrast(("#%06x"):format(highlight("FloatBorder").fg), "#0d0e12") >= 4.5)
	local _, win = vim.lsp.util.open_floating_preview({ "Hover documentation" }, "markdown", { border = "rounded" })
	assert(vim.api.nvim_win_is_valid(win), "native LSP hover must open")
	assert(highlight("NormalFloat").bg == nil and highlight("FloatBorder").bg == nil)
	vim.api.nvim_win_close(win, true)
	local bufferline = require("catppuccin.special.bufferline").get_theme()()
	for name, hl in pairs(bufferline) do
		assert(hl.bg == "NONE", "bufferline " .. name .. " must be transparent")
	end
	-- Reapplying the colorscheme must preserve the policy.
	vim.cmd.colorscheme("catppuccin")
	assert(highlight("NormalFloat").bg == nil)
end
-- Lualine creates highlights after the colorscheme, from its own options.
local options
package.loaded.lualine = {
	setup = function(opts)
		options = opts
	end,
}
package.loaded["lazy.status"] = {}
package.loaded["customize.aiterm_ecc"] = {}
package.loaded["catppuccin.palettes"] = {
	get_palette = function()
		return kitty.colors({})
	end,
}
require("plugins.lualine").config()
assert(options.options.globalstatus == false, "filenames must stay with each split")
for _, mode in pairs(options.options.theme) do
	for _, section in pairs(mode) do
		assert(section.bg:upper() == "NONE", "every lualine section must be transparent")
	end
end
assert(options.sections.lualine_c[3].color.bg == "NONE", "filename component must be transparent")
local snacks = require("plugins.snacks")[1].opts
assert(snacks.styles.float.backdrop == false and snacks.styles.float.wo.winblend == 0)
assert(snacks.styles.notification.wo.winblend == 0)
print("nvim transparency: OK" .. (plugin and " (Catppuccin integration)" or " (offline overrides)"))
