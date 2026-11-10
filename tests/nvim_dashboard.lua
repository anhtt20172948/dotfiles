-- Dashboard and picker geometry: pure layout rules always, plus a real Snacks
-- render at 80/120/200 columns when NVIM_UI_PLUGIN_RTP points at the plugins.
local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")

local dashboard = require("customize.dashboard")
local picker_layout = require("customize.picker_layout")

local function with_ascii(value, fn)
	local saved = vim.env.NVIM_ASCII
	vim.env.NVIM_ASCII = value
	package.loaded["lib.icons"] = nil
	local ok, err = pcall(fn)
	vim.env.NVIM_ASCII = saved
	package.loaded["lib.icons"] = nil
	assert(ok, err)
end

-- Width follows the window and keeps a gutter on both sides.
assert(dashboard.width(200) == dashboard.MAX_WIDTH)
assert(dashboard.width(80) == dashboard.MAX_WIDTH)
assert(dashboard.width(50) == 50 - 2 * dashboard.GUTTER)
assert(dashboard.width(3) == 1)

-- The artwork only appears when it fits on both axes.
local art_rows = #vim.split(dashboard.HEADER, "\n", { trimempty = true })
local full_rows = art_rows + dashboard.body_rows(dashboard.SESSION_LIMIT)
assert(dashboard.header(200, 50) == dashboard.HEADER)
assert(dashboard.header(80, full_rows) == dashboard.HEADER)
assert(dashboard.header(80, full_rows - 1) == dashboard.COMPACT_HEADER, "short terminals keep actions visible")
assert(dashboard.header(55, 50) == dashboard.COMPACT_HEADER, "narrow terminals use the one-line header")
with_ascii("1", function()
	assert(dashboard.header(200, 50) == dashboard.COMPACT_HEADER)
end)

for seconds, age in pairs({
	[-5] = "now",
	[0] = "now",
	[59] = "now",
	[60] = "1m",
	[3599] = "59m",
	[3600] = "1h",
	[86399] = "23h",
	[86400] = "1d",
	[7 * 86400] = "1w",
	[365 * 86400] = "1y",
}) do
	assert(dashboard.age(seconds) == age, ("age(%d) = %s"):format(seconds, dashboard.age(seconds)))
end

-- Actions: unique keys, real icons and no recursive picker override.
local function check_keys()
	local seen = {}
	for _, item in ipairs(dashboard.keys()) do
		assert(not seen[item.key], "duplicate dashboard key " .. item.key)
		seen[item.key] = true
		assert(type(item.action) == "string" and item.action:sub(1, 1) == ":", item.desc)
		if vim.env.NVIM_ASCII == "1" then
			assert(item.icon == nil, "ASCII mode must not show letter icons: " .. item.desc)
		else
			assert(item.icon and vim.trim(item.icon) ~= "", "missing icon for " .. item.desc)
		end
	end
	for _, key in ipairs({ "f", "n", "g", "r", "c", "s", "a", "e", "l", "q" }) do
		assert(seen[key], "missing dashboard key " .. key)
	end
end
check_keys()
with_ascii("1", check_keys)
local config = dashboard.config()
assert(config.preset.pick == nil, "Snacks.dashboard.pick must not call itself through preset.pick")
assert(config.width == dashboard.MAX_WIDTH)

-- Session rows: newest three, sized to the dashboard so nothing overflows.
local now = 1000000
local entries = {
	{ tool = "claude", id = "a", title = "漢字かな session with a very long descriptive title", time = now - 30 },
	{ tool = "opencode", id = "b", title = "👩‍💻 pairing on the dashboard layout", time = now - 7200 },
	{ tool = "codex", id = "c-id-only" },
	{ tool = "claude", id = "d", title = "fourth", time = now },
}
local function check_sessions(width)
	local resumed
	local items = dashboard.session_items(entries, width, now, function(entry)
		resumed = entry
	end)
	assert(#items == dashboard.SESSION_LIMIT)
	for i, item in ipairs(items) do
		assert(item.key == tostring(i))
		-- Snacks lays out indent + icon (2) + padding (1) left, key + padding right.
		local left = item.indent + (item.icon and 3 or 0)
		local used = left + vim.fn.strdisplaywidth(item.desc) + 2
		assert(used <= width, ("row overflows %d columns: %s"):format(width, item.desc))
		assert(not item.desc:find("�", 1, true), "truncation must preserve UTF-8")
	end
	assert(items[1].desc:find("now", 1, true) and items[2].desc:find("2h", 1, true))
	assert(items[3].desc:find(width >= 46 and "c-id-only" or "c-", 1, true), "untitled sessions fall back to the id")
	items[2].action()
	assert(resumed == entries[2])
end
-- 24 is the narrowest dashboard that still has room for one title column.
for _, width in ipairs({ 24, 46, 56 }) do
	check_sessions(width)
	with_ascii("1", function()
		check_sessions(width)
	end)
end

-- Picker presets follow the editor size.
assert(picker_layout.preset(200, 50) == "default")
assert(picker_layout.preset(picker_layout.WIDE_COLUMNS, 10) == "default")
assert(picker_layout.preset(picker_layout.WIDE_COLUMNS - 1, 40) == "vertical")
assert(picker_layout.preset(80, picker_layout.PREVIEW_MIN_LINES) == "vertical")
assert(picker_layout.preset(80, picker_layout.PREVIEW_MIN_LINES - 1) == "vertical_list")
local layouts = picker_layout.layouts()
assert(layouts.vertical_list.preset == "vertical" and vim.tbl_contains(layouts.vertical_list.hidden, "preview"))
assert(layouts.default.layout[2].width == picker_layout.PREVIEW_WIDTH)
assert(layouts.vertical.layout[3].height == picker_layout.PREVIEW_HEIGHT)

-- Plugin specs wire the modules and keep the dashboard unobstructed.
local snacks_opts = require("plugins.snacks")[1].opts
assert(snacks_opts.dashboard.preset.pick == nil)
assert(snacks_opts.styles.dashboard.wo.foldcolumn == "0", "the fold column would off-centre the dashboard")
assert(type(snacks_opts.picker.layout.preset) == "function")
assert(snacks_opts.picker.layouts.vertical_list)
local sessions = require("plugins.sessions")[2]
assert(sessions.opts.show_auto_restore_notif == false, "a missing session must not cover the dashboard")

local rtp = vim.env.NVIM_UI_PLUGIN_RTP
if not (rtp and vim.uv.fs_stat(rtp .. "/snacks.nvim")) then
	print("skip: Snacks dashboard render (set NVIM_UI_PLUGIN_RTP to the lazy.nvim plugin directory)")
	print("nvim dashboard: OK")
	return
end

-- Real Snacks render in the current window at each width.
vim.opt.rtp:prepend(rtp .. "/snacks.nvim")
package.loaded["lazy.stats"] = {
	stats = function()
		return { startuptime = 12.5, loaded = 3, count = 9 }
	end,
}
package.loaded["customize.aiterm_history"] = {
	project_cwd = function()
		return "/project"
	end,
	list = function()
		return entries
	end,
}
require("snacks").setup({ styles = snacks_opts.styles, dashboard = { enabled = false } })
-- Without a UI the editor window keeps its size, so render into a float of
-- exactly the terminal size under test.
local function render(columns, lines)
	vim.o.columns, vim.o.lines = columns, lines
	local buf = vim.api.nvim_create_buf(false, true)
	local win =
		vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = columns, height = lines - 2 })
	vim.wo[win].foldcolumn = "1" -- the global setting from core/options.lua
	local instance = Snacks.dashboard.open(vim.tbl_extend("force", dashboard.config(), { buf = buf, win = win }))
	assert(vim.api.nvim_win_get_width(win) == columns)
	return instance, buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
for _, case in ipairs({ { 80, 24 }, { 80, 40 }, { 120, 40 }, { 200, 50 }, { 50, 30 } }) do
	local columns, lines = case[1], case[2]
	local instance, buf, text = render(columns, lines)
	local win_width = vim.api.nvim_win_get_width(instance.win)
	local joined = table.concat(text, "\n")
	local left, right = math.huge, 0
	for _, line in ipairs(text) do
		local width = vim.fn.strdisplaywidth(line)
		assert(width <= win_width, ("%dx%d: line exceeds the window: %q"):format(columns, lines, line))
		local first = line:find("%S")
		if first then
			left = math.min(left, vim.fn.strdisplaywidth(line:sub(1, first - 1)))
			right = math.max(right, vim.fn.strdisplaywidth((line:gsub("%s+$", ""))))
		end
	end
	assert(left >= dashboard.GUTTER and win_width - right >= dashboard.GUTTER, ("%dx%d: gutter"):format(columns, lines))
	assert(
		#text <= vim.api.nvim_win_get_height(instance.win),
		("%dx%d: content taller than the window"):format(columns, lines)
	)
	local art = dashboard.header(win_width, vim.api.nvim_win_get_height(instance.win)) == dashboard.HEADER
	assert(joined:find("███", 1, true) ~= nil == art, ("%dx%d: header choice"):format(columns, lines))
	assert(joined:find("MAI ANH", 1, true) ~= nil == not art)
	assert(joined:find("AI Sessions", 1, true) and joined:find("Neovim loaded", 1, true))
	assert(vim.wo[instance.win].foldcolumn == "0", "the global fold column must not reach the dashboard")
	assert(vim.b[buf].eyelinerDisabled, "eyeliner must not take over the Find File key")
	local map = vim.fn.maparg("f", "n", false, true)
	assert(map.buffer == 1 and map.desc == "Dashboard action", "f must run Find File")
	vim.api.nvim_win_close(instance.win, true)
end
print("nvim dashboard: OK")
