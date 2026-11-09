local M = {}

-- Explicit groups also cover plugins loaded after the colorscheme. Selection
-- groups are intentionally separate so the active item remains visible.
local surfaces = {
	"Normal",
	"NormalNC",
	"NormalSB",
	"NormalFloat",
	"SignColumn",
	"SignColumnSB",
	"EndOfBuffer",
	"Pmenu",
	"PmenuSbar",
	"StatusLine",
	"StatusLineNC",
	"TabLine",
	"TabLineFill",
	"TabLineSel",
	"BlinkCmpMenu",
	"BlinkCmpDoc",
	"BlinkCmpSignatureHelp",
	"BlinkCmpScrollBarGutter",
	"CmpDocumentation",
	"SagaNormal",
	"RenameNormal",
	"WhichKeyNormal",
	"WhichKeyFloat",
	"LazyNormal",
	"MasonNormal",
	"NotifyBackground",
	"NoicePopup",
	"NoiceCmdlinePopup",
	"NoiceConfirm",
	"NoicePopupmenu",
	"NoiceSplit",
	"NoiceMini",
	"SnacksNormal",
	"SnacksNormalNC",
	"SnacksNotifier",
	"SnacksInputNormal",
	"SnacksPicker",
	"SnacksPickerInput",
	"SnacksPickerList",
	"SnacksPickerPreview",
	"SnacksPickerBox",
	"TelescopeNormal",
	"TelescopePromptNormal",
	"TelescopeResultsNormal",
	"TelescopePreviewNormal",
	"FzfLuaNormal",
	"FzfLuaPreviewNormal",
	"NvimTreeNormal",
	"NvimTreeNormalNC",
	"NvimTreeEndOfBuffer",
	"NvimTreeStatusLine",
	"NvimTreeStatuslineNc",
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NeoTreeEndOfBuffer",
	"NeoTreeStatusLine",
	"NeoTreeStatusLineNC",
}

local borders = {
	"FloatBorder",
	"FloatTitle",
	"BlinkCmpMenuBorder",
	"BlinkCmpDocBorder",
	"BlinkCmpDocSeparator",
	"BlinkCmpSignatureHelpBorder",
	"CmpDocumentationBorder",
	"SagaBorder",
	"SagaTitle",
	"WhichKeyBorder",
	"WhichKeyTitle",
	"LazyBorder",
	"MasonBorder",
	"NoicePopupBorder",
	"NoiceCmdlinePopupBorder",
	"NoiceConfirmBorder",
	"NoicePopupmenuBorder",
	"SnacksWinBar",
	"SnacksWinBarNC",
	"SnacksInputBorder",
	"SnacksInputTitle",
	"SnacksPickerBorder",
	"SnacksPickerTitle",
	"SnacksPickerInputBorder",
	"SnacksPickerInputTitle",
	"SnacksPickerListBorder",
	"SnacksPickerListTitle",
	"SnacksPickerPreviewBorder",
	"SnacksPickerPreviewTitle",
	"SnacksPickerBoxBorder",
	"SnacksPickerBoxTitle",
	"TelescopeBorder",
	"TelescopeTitle",
	"TelescopePromptBorder",
	"TelescopePromptTitle",
	"TelescopeResultsBorder",
	"TelescopeResultsTitle",
	"TelescopePreviewBorder",
	"TelescopePreviewTitle",
	"FzfLuaBorder",
	"FzfLuaTitle",
	"FzfLuaPreviewBorder",
	"FzfLuaPreviewTitle",
	"NvimTreeWinSeparator",
	"NeoTreeWinSeparator",
	"NeoTreeFloatBorder",
	"NeoTreeFloatTitle",
	"NeoTreeTitleBar",
}

local selections = {
	"CursorLine",
	"CursorColumn",
	"Visual",
	"VisualNOS",
	"PmenuSel",
	"BlinkCmpMenuSelection",
	"NoicePopupmenuSelected",
	"SnacksPickerSelected",
	"TelescopeSelection",
	"NeoTreeCursorLine",
	"NvimTreeCursorLine",
}

function M.highlights(colors, primary)
	local highlights = {}
	for _, group in ipairs(surfaces) do
		highlights[group] = { fg = colors.text, bg = "NONE" }
	end
	for _, group in ipairs(borders) do
		highlights[group] = { fg = primary, bg = "NONE" }
	end
	for _, group in ipairs(selections) do
		highlights[group] = { bg = colors.surface0 }
	end
	return highlights
end

return M
