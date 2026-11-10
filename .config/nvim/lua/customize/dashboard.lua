-- Snacks dashboard content and geometry. Every size follows the dashboard
-- window at render time (Snacks re-renders on resize), never the terminal
-- size captured when the plugin spec was loaded.
local M = {}

M.MAX_WIDTH = 56
M.GUTTER = 2 -- blank columns kept on each side of the dashboard
M.SESSION_LIMIT = 3
M.COMPACT_HEADER = "MAI ANH"
M.HEADER = [[
███╗   ███╗ █████╗ ██╗     █████╗ ███╗   ██╗██╗  ██╗
████╗ ████║██╔══██╗██║    ██╔══██╗████╗  ██║██║  ██║
██╔████╔██║███████║██║    ███████║██╔██╗ ██║███████║
██║╚██╔╝██║██╔══██║██║    ██╔══██║██║╚██╗██║██╔══██║
██║ ╚═╝ ██║██║  ██║██║    ██║  ██║██║ ╚████║██║  ██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝    ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝]]

-- Session rows: "<tool> <age>  <title>"; tool names are at most 8 columns.
local TOOL_COLUMNS, AGE_COLUMNS = 8, 3
local SESSION_INDENT = 2

local function ascii()
	return vim.env.NVIM_ASCII == "1"
end

-- Nerd Font glyphs, or no icon at all in ASCII mode (the generic ASCII icon
-- table maps every glyph to the first letter of its name).
local function icon(glyph)
	return not ascii() and glyph or nil
end

function M.width(columns)
	return math.max(1, math.min(M.MAX_WIDTH, columns - 2 * M.GUTTER))
end

---@return snacks.dashboard.Item[]
function M.keys()
	local icons = require("lib.icons")
	-- stylua: ignore
	return {
		{ icon = icon(icons.ui.Search), key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
		{ icon = icon(icons.ui.NewFile), key = "n", desc = "New File", action = ":ene | startinsert" },
		{ icon = icon(icons.ui.List), key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
		{ icon = icon(icons.documents.Files), key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
		{ icon = icon(icons.ui.Gear), key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
		{ icon = icon(icons.ui.History), key = "s", desc = "Select Session", action = ":SessionSearch" },
		{ icon = icon(icons.ui.Robot), key = "a", desc = "AI Sessions", action = ":lua require('customize.aiterm').pick()" },
		{ icon = icon(icons.documents.Folder), key = "e", desc = "File Explorer", action = ":Neotree filesystem reveal" },
		{ icon = icon(icons.ui.Sleep), key = "l", desc = "Lazy", action = ":Lazy" },
		{ icon = icon(icons.ui.SignOut), key = "q", desc = "Quit", action = ":qa" },
	}
end

-- Rows below the header: keys, the session block and the startup line, plus
-- the one-row padding after the header, keys and sessions sections.
function M.body_rows(sessions)
	local session_rows = sessions > 0 and sessions + 2 or 0
	return 1 + #M.keys() + 1 + session_rows + 1
end

local function header_lines()
	return vim.split(M.HEADER, "\n", { trimempty = true })
end

-- The artwork needs room on both axes; otherwise keep the name on one line so
-- the actions and sessions stay visible in small terminals and splits.
function M.header(columns, rows)
	local lines = header_lines()
	local art_width = 0
	for _, line in ipairs(lines) do
		art_width = math.max(art_width, vim.fn.strdisplaywidth(line))
	end
	local fits = columns >= art_width + 2 * M.GUTTER and rows >= #lines + M.body_rows(M.SESSION_LIMIT)
	return (fits and not ascii()) and M.HEADER or M.COMPACT_HEADER
end

function M.age(seconds)
	seconds = math.max(0, seconds)
	for _, unit in ipairs({ { 365 * 86400, "y" }, { 7 * 86400, "w" }, { 86400, "d" }, { 3600, "h" }, { 60, "m" } }) do
		if seconds >= unit[1] then
			return math.floor(seconds / unit[1]) .. unit[2]
		end
	end
	return "now"
end

-- Columns left for the title once Snacks lays out indent, icon, key and the
-- fixed tool/age columns inside a dashboard of `width` columns.
function M.title_width(width)
	local left = SESSION_INDENT + (icon("x") and 3 or 0) -- icon (2) + padding (1)
	local right = 2 -- key (1) + padding (1)
	return math.max(1, width - left - right - (TOOL_COLUMNS + 1 + AGE_COLUMNS + 2))
end

---@param entries {tool:string, title?:string, id:string, time?:number}[] newest first
---@param width number dashboard width
---@param now number epoch seconds
---@param resume fun(entry:table)
---@return snacks.dashboard.Item[]
function M.session_items(entries, width, now, resume)
	local truncate = require("customize.ui").truncate
	local title_width = M.title_width(width)
	local items = {}
	for i, entry in ipairs(entries) do
		if i > M.SESSION_LIMIT then
			break
		end
		local age = entry.time and M.age(now - entry.time) or ""
		local title = truncate(entry.title or entry.id, title_width)
		items[#items + 1] = {
			icon = icon(require("lib.icons").ui.Comment),
			key = tostring(i),
			indent = SESSION_INDENT,
			desc = ("%-" .. TOOL_COLUMNS .. "s %" .. AGE_COLUMNS .. "s  %s"):format(entry.tool, age, title),
			action = function()
				resume(entry)
			end,
		}
	end
	return items
end

---@param self snacks.dashboard.Class
local function header_section(self)
	local columns = vim.api.nvim_win_get_width(self.win)
	local rows = vim.api.nvim_win_get_height(self.win)
	-- Snacks reads opts.width when it lays out the resolved items, after this
	-- first section runs, so a resize re-renders at the new width.
	self.opts.width = M.width(columns)
	-- Keep `f` for Find File: eyeliner (VeryLazy) maps f/t/F/T buffer-locally
	-- unless the buffer opts out, and its filetype filter never sees this
	-- buffer because Snacks sets the filetype with all events ignored.
	vim.b[self.buf].eyelinerDisabled = true
	return { header = M.header(columns, rows), padding = 1 }
end

---@param self snacks.dashboard.Class
local function sessions_section(self)
	local ok, history = pcall(require, "customize.aiterm_history")
	if not ok then
		return {}
	end
	local entries = history.list(history.project_cwd(), M.SESSION_LIMIT)
	return M.session_items(entries, self.opts.width, os.time(), function(entry)
		require("customize.aiterm").resume(entry)
	end)
end

function M.config()
	local icons = require("lib.icons")
	return {
		width = M.MAX_WIDTH,
		preset = { header = M.HEADER, keys = M.keys() },
		sections = {
			header_section,
			{ section = "keys", gap = 0, padding = 1 },
			{ title = "Recent AI Sessions", icon = icon(icons.ui.Robot), padding = 1, sessions_section },
			{ section = "startup", icon = icon(icons.ui.Time) or "" },
		},
	}
end

return M
