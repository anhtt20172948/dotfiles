local plugin_path = assert(arg[1], "neo-tree plugin path is required")
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
}))
