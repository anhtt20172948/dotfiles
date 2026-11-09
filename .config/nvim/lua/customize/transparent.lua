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
	"NoiceCmdline",
	"SnacksNormal",
	"SnacksNormalNC",
	"SnacksNotifier",
	"SnacksNotifierHistory",
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
	"NoiceSplitBorder",
	"NoiceCmdlinePopupTitle",
	"NoiceCmdlinePopupBorderSearch",
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
	local kitty = require("customize.kitty_palette")
	local background = kitty.selection_background(colors, primary)
	for _, group in ipairs({ "Visual", "VisualNOS" }) do
		highlights[group] = { fg = "NONE", bg = background }
	end
	local search = kitty.search_background(colors, primary)
	highlights.Search = { bg = search, fg = kitty.ensure_contrast(colors.text, search, colors.text, 4.5) }
	local black = string.format("#%06x", 0)
	local dark = kitty.contrast(colors.base, black) < 4.5 and colors.base or black
	local foreground = kitty.ensure_contrast(dark, primary, black, 4.5)
	for _, group in ipairs({ "CurSearch", "IncSearch" }) do
		highlights[group] = { bg = primary, fg = foreground }
	end
	return vim.tbl_extend("force", highlights, M.decorations(colors, primary))
end

function M.decorations(colors, primary)
	local highlights = {}
	local text, quiet = colors.text or primary, colors.overlay0 or colors.text or primary
	local function set(names, fg, bold)
		for _, name in ipairs(names) do
			highlights[name] = { fg = fg, bg = "NONE", bold = bold or false }
		end
	end
	set({ "SnacksIndent", "FoldColumn", "LineNrAbove", "LineNrBelow", "InclineNormalNC" }, quiet)
	set({
		"SnacksIndentScope",
		"SnacksIndentChunk",
		"SnacksStatusColumnMark",
		"SnacksDashboardHeader",
		"SnacksDashboardKey",
		"SnacksDashboardIcon",
	}, primary)
	set({
		"Folded",
		"LineNr",
		"InclineNormal",
		"TinyInlineDiagnosticVirtualTextBg",
		"TinyInlineDiagnosticVirtualTextArrow",
		"TinyInlineDiagnosticVirtualTextArrowNoBg",
	}, text)
	set({ "RenderMarkdownCode", "RenderMarkdownCodeInline" }, text)
	set({ "SnacksDashboardDesc", "SnacksDashboardTitle", "SnacksDashboardFile", "SnacksDashboardSpecial" }, text)
	set({ "SnacksDashboardFooter", "SnacksDashboardDir" }, quiet)
	set({ "NeoTreeTabActive", "NeoTreeTabSeparatorActive", "NeoTreeTabSeparatorInactive" }, primary)
	set({ "NeoTreeTabInactive" }, quiet)
	for i = 1, 6 do
		set({ "Headline" .. i .. "Fg" }, text, true)
		set({ "Headline" .. i .. "Bg" }, primary, true)
	end
	for name, color in pairs({
		Error = colors.red or text,
		Warn = colors.yellow or text,
		Info = colors.blue or text,
		Hint = colors.teal or text,
		Debug = quiet,
		Trace = quiet,
	}) do
		-- Borders share geometry and accent; severity remains in icons and labels.
		set({ "SnacksNotifierBorder" .. name, "Notify" .. name:upper() .. "Border" }, primary)
		set({
			"SnacksNotifierIcon" .. name,
			"SnacksNotifierTitle" .. name,
			"Diagnostic" .. name,
			"DiagnosticSign" .. name,
		}, color)
		for _, prefix in ipairs({ "TinyInlineDiagnosticVirtualText", "TinyInlineInvDiagnosticVirtualText" }) do
			for _, suffix in ipairs({ "", "NoBg", "CursorLine" }) do
				set({ prefix .. name .. suffix }, color)
			end
		end
	end
	return highlights
end

return M
