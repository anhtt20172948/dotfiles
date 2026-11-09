local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")

local indent = require("plugins.snacks")[1].opts.indent
assert(type(indent.indent) == "table", "guide options must use the nested Snacks indent schema")
assert(indent.indent.only_scope and indent.indent.only_current)
assert(indent.priority == nil and indent.char == nil and indent.hl == nil)
assert(indent.scope.hl == "SnacksIndentScope" and indent.scope.only_current)
assert(indent.chunk.hl == "SnacksIndentChunk")
assert(not indent.animate.enabled)

local noice = require("plugins.noice")[1]
assert(noice.setup == nil, "Lazy never executes a setup spec hook")
assert(noice.opts.presets.bottom_search and noice.opts.presets.command_palette)
assert(noice.opts.presets.long_message_to_split and noice.opts.presets.inc_rename)
assert(not noice.opts.popupmenu.enabled, "Blink owns command completion")
assert(not noice.opts.notify.enabled, "Snacks owns notifications")
assert(not noice.opts.lsp.hover.enabled and not noice.opts.lsp.signature.enabled, "native LSP owns documentation")
assert(#noice.dependencies == 1 and noice.dependencies[1] == "MunifTanjim/nui.nvim")
assert(not noice.cond(), "headless Neovim must keep the native message UI")
assert(noice.opts.views.mini.win_options.winblend == 0)
assert(vim.tbl_contains(require("plugins.blink-cmp").event, "CmdlineEnter"), "first command must load Blink")
local blink = require("plugins.blink-cmp").opts(nil, {})
assert(
	blink.sources.providers.supermaven.kind == nil and blink.sources.providers.lsp.kind == nil,
	"Blink providers must not contain the unsupported kind field"
)
if vim.env.NVIM_UI_PLUGIN_RTP then
	vim.opt.rtp:prepend(vim.env.NVIM_UI_PLUGIN_RTP .. "/blink.cmp")
	require("blink.cmp.config").merge_with(blink)
	vim.opt.rtp:prepend(vim.env.NVIM_UI_PLUGIN_RTP .. "/noice.nvim")
	vim.opt.rtp:prepend(vim.env.NVIM_UI_PLUGIN_RTP .. "/nui.nvim")
	local config = require("noice.config")
	config.setup(noice.opts)
	assert(config.options.cmdline.format.search_down.view == "cmdline")
	assert(config.options.cmdline.format.search_up.view == "cmdline")
	assert(config.options.views.cmdline_popup.position.row == 3)
	assert(config.options.cmdline.format.IncRename.pattern ~= nil)
	assert(not config.options.popupmenu.enabled and not config.options.notify.enabled)
	local split_route = false
	for _, route in ipairs(config.options.routes) do
		if route.view == "cmdline_output" and route.filter.min_height == 20 then
			split_route = true
		end
	end
	assert(split_route, "long messages must reach the configured split route")
end
print("nvim UI configuration: OK")
