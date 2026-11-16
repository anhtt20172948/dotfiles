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
	highlights.Search =
		{ bg = search, fg = kitty.ensure_contrast(colors.text, search, colors.text, kitty.text_floor()) }
	local black = string.format("#%06x", 0)
	local dark = kitty.contrast(colors.base, black) < 4.5 and colors.base or black
	local foreground = kitty.ensure_contrast(dark, primary, black, kitty.text_floor())
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
	set({ "SnacksDashboardDesc", "SnacksDashboardTitle", "SnacksDashboardFile", "SnacksDashboardSpecial" }, text)
	set({ "SnacksDashboardFooter", "SnacksDashboardDir" }, quiet)
	set({ "NeoTreeTabActive", "NeoTreeTabSeparatorActive", "NeoTreeTabSeparatorInactive" }, primary)
	set({ "NeoTreeTabInactive" }, quiet)
	-- Markdown surfaces and accents follow the terminal, including live palette reloads.
	local kitty = require("customize.kitty_palette")
	local ansi = kitty.active and kitty.active.ansi or {}
	local backdrop, surface = kitty.backdrop(colors.base), colors.surface0 or colors.base
	local function readable(color, background)
		return kitty.ensure_contrast(color, background, text, kitty.text_floor())
	end
	local accents = {
		primary,
		ansi[4] or colors.blue or text,
		ansi[14] or colors.teal or text,
		ansi[2] or colors.green or text,
		ansi[3] or colors.yellow or text,
		ansi[5] or colors.mauve or text,
	}
	for level, accent in ipairs(accents) do
		local background = level == 1 and surface or "NONE"
		local foreground = readable(accent, level == 1 and surface or backdrop)
		highlights["RenderMarkdownH" .. level] = { fg = foreground, bg = "NONE", bold = true }
		highlights["RenderMarkdownH" .. level .. "Bg"] = { fg = foreground, bg = background, bold = true }
	end
	-- Background only: fenced code retains its Tree-sitter syntax colours.
	highlights.RenderMarkdownCode = { bg = surface }
	highlights.RenderMarkdownCodeInline = { fg = readable(text, surface), bg = surface }
	highlights.RenderMarkdownCodeInfo = { fg = readable(primary, surface), bg = surface }
	highlights.RenderMarkdownCodeBorder = { bg = surface }
	set({ "RenderMarkdownBullet", "RenderMarkdownTableHead", "RenderMarkdownLink" }, primary)
	set({ "RenderMarkdownTableRow", "RenderMarkdownQuote", "RenderMarkdownUnchecked", "RenderMarkdownDash" }, quiet)
	set({ "@markup.quote.markdown" }, text)
	set({ "RenderMarkdownChecked", "RenderMarkdownSuccess" }, readable(accents[4], backdrop))
	set({ "RenderMarkdownInfo" }, readable(accents[2], backdrop))
	set({ "RenderMarkdownHint" }, readable(accents[3], backdrop))
	set({ "RenderMarkdownWarn" }, readable(accents[5], backdrop))
	set({ "RenderMarkdownError" }, readable(ansi[1] or colors.red or text, backdrop))
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
