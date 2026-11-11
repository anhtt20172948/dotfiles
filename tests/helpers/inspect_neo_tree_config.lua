local plugin_path = assert(arg[1], "neo-tree plugin path is required")
vim.opt.rtp:prepend(vim.fn.fnamemodify(plugin_path, ":h:h:h"))
local setup_calls = {}

package.preload["neo-tree"] = function()
	return {
		setup = function(config)
			table.insert(setup_calls, config)
		end,
	}
end

package.preload["neo-tree.events"] = function()
	return { FILE_MOVED = "file_moved", FILE_RENAMED = "file_renamed" }
end

Snacks = { rename = { on_rename_file = function() end } }

local diagnostic_config_calls = 0
vim.diagnostic.config = function()
	diagnostic_config_calls = diagnostic_config_calls + 1
end

local function snapshot(value)
	if type(value) == "function" then
		return "<function>"
	end
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = snapshot(item)
	end
	return copy
end

local specs = assert(loadfile(plugin_path))()
local incoming = {
	sentinel = "preserved",
	event_handlers = { { event = "existing", handler = function() end } },
	nested = { marker = "nested-preserved", level = 7, values = { "alpha", "beta" } },
}
local incoming_before = snapshot(incoming)
specs[2].config(nil, incoming)
local incoming_after = snapshot(incoming)

local config = assert(setup_calls[1], "neo-tree setup was not called")
local defaults = config.default_component_configs or {}
local icon = defaults.icon or {}
local diagnostics = defaults.diagnostics or {}

local directory_glyphs, directory_hls = vim.empty_dict(), vim.empty_dict()
for _, dependency in ipairs(specs[2].dependencies) do
	if type(dependency) == "table" and dependency[1] == "echasnovski/mini.icons" then
		for name, entry in pairs(dependency.opts.directory) do
			directory_glyphs[name] = entry.glyph
			directory_hls[name] = entry.hl
		end
	end
end
-- The ANSI slots neo-tree's folders and current row are drawn in.
local tree = require("customize.tree_colors")

print(vim.json.encode({
	setup_count = #setup_calls,
	sentinel = config.sentinel,
	incoming_handler_count = #incoming.event_handlers,
	incoming_before = incoming_before,
	incoming_after = incoming_after,
	incoming_unchanged = vim.deep_equal(incoming_before, incoming_after),
	final_handler_count = #(config.event_handlers or {}),
	folder_closed = icon.folder_closed,
	folder_open = icon.folder_open,
	folder_empty = icon.folder_empty,
	folder_empty_open = icon.folder_empty_open,
	diagnostics = diagnostics.symbols,
	shared_diagnostics = require("lib.icons").diagnostics,
	diagnostic_config_calls = diagnostic_config_calls,
	directory_glyphs = directory_glyphs,
	directory_hls = directory_hls,
	tree_colors = { directory = tree.DIRECTORY, icons = tree.ICONS, cursor = tree.CURSOR },
}))
