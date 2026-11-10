-- Discovers old on-disk sessions of claude / codex / opencode.
-- Pure data module: NO windows, NO Snacks calls. customize/aiterm.lua consumes it.
--
-- Sources (verified on this machine):
--   codex    -> sqlite ~/.codex/state_*.sqlite                 table threads
--   opencode -> sqlite ~/.local/share/opencode/opencode.db     table session
--   claude   -> JSONL  ~/.claude/projects/<slug>/<uuid>.jsonl  (no index)
local M = {}

M.config = {
	limit = 40, -- newest sessions taken per tool (hard cost cap)
	head = 64 * 1024, -- bytes read from the START of the jsonl -> cwd / gitBranch / first prompt
	tail = 64 * 1024, -- bytes read from the END of the jsonl -> ai-title / last prompt
	title_width = 60,
	prompt_width = 400, -- prompt joined into 1 line, used for the matcher's item.text
	prompt_lines = 12, -- leading lines kept for the preview (line breaks kept)
	prompt_line_width = 120, -- each preview line is cut here
}

-- claude cache: path -> { mtime, info }; invalidated by mtime
local claude_cache = {}

-- helpers ----------------------------------------------------------------

-- Join into 1 line + truncate by CHARACTER (strcharpart) so UTF-8 is never cut mid-sequence.
-- string.sub(1, 60) can split a multibyte char (e.g. "...caf<c3>"), corrupting accents.
local function oneline(s, width)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("%s+", " "):gsub("^ +", ""):gsub(" +$", "")
	if s == "" then
		return nil
	end
	if vim.api.nvim_strwidth(s) > width then
		s = vim.fn.strcharpart(s, 0, width - 1) .. "…"
	end
	return s
end

-- First N lines, line breaks KEPT, each line cut by character. Unlike oneline():
-- oneline joins everything into 1 line, so a prompt with a code block becomes an unreadable
-- blob in the preview. Returns nil when empty; appends "…" when cut.
local function head_lines(s, max_lines, width)
	if type(s) ~= "string" or s:match("^%s*$") then
		return nil
	end
	max_lines, width = max_lines or M.config.prompt_lines, width or M.config.prompt_line_width
	local out = {}
	for line in (s .. "\n"):gmatch("([^\n]*)\n") do
		if #out >= max_lines then
			out[#out + 1] = "…"
			break
		end
		line = line:gsub("%s+$", "")
		if vim.api.nvim_strwidth(line) > width then
			line = vim.fn.strcharpart(line, 0, width - 1) .. "…"
		end
		out[#out + 1] = line
	end
	while #out > 0 and out[#out] == "" do
		table.remove(out)
	end
	return #out > 0 and out or nil
end

-- claude stuffs <ide_selection>/<system-reminder> into the first prompt -> strip them for the title.
local function strip_tags(s)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("<ide_selection>.-</ide_selection>", "")
	s = s:gsub("<system%-reminder>.-</system%-reminder>", "")
	return s
end

local function sqlite_bin()
	if vim.fn.executable("sqlite3") == 1 then
		return "sqlite3"
	end
	-- macOS always ships this one (3.43.2)
	return vim.fn.executable("/usr/bin/sqlite3") == 1 and "/usr/bin/sqlite3" or nil
end

-- SQL literal escaping: '' is the only escape SQLite understands in a single-quoted string.
local function q(s)
	return "'" .. s:gsub("'", "''") .. "'"
end

-- `-json` + vim.json.decode: fully safe with titles containing | , newlines, unicode.
-- 0 rows -> sqlite3 prints an EMPTY string (not "[]"), so guard before decoding.
local function sqlite_json(db, sql)
	local bin = sqlite_bin()
	if not bin or not db or not vim.uv.fs_stat(db) then
		return {}
	end
	local function run(readonly)
		local cmd = { bin }
		if readonly then
			cmd[#cmd + 1] = "-readonly"
		end
		vim.list_extend(cmd, { "-json", db, sql })
		local ok, res = pcall(function()
			return vim.system(cmd, { text = true }):wait(3000)
		end)
		return ok and res or nil
	end
	local r = run(true)
	if not r or r.code ~= 0 then
		r = run(false) -- WAL needs recovery -> open read-write, still SELECT only
	end
	if not r or r.code ~= 0 or (r.stdout or "") == "" then
		return {}
	end
	local ok, rows = pcall(vim.json.decode, r.stdout, { luanil = { object = true, array = true } })
	return (ok and type(rows) == "table") and rows or {}
end

-- Pick the newest file by mtime. codex bumps the version suffix (state_5 -> state_10),
-- so sorting by NAME is wrong; sorting by mtime is not.
local function newest(pattern)
	local best, best_t
	for _, p in ipairs(vim.fn.glob(pattern, false, true)) do
		local st = vim.uv.fs_stat(p)
		if st and (not best_t or st.mtime.sec > best_t) then
			best, best_t = p, st.mtime.sec
		end
	end
	return best
end

-- cwd matching -----------------------------------------------------------
-- In a container the project is bind-mounted at /app (maybe a symlink), so
-- fs_realpath(getcwd()) differs from the cwd the tool RECORDED (usually raw /app) ->
-- filtering by realpath alone drops everything. Match against a SET of candidates: raw, without
-- trailing slash, and realpath. On the host realpath == path, so it is 1 element -> as before.
local function cwd_candidates(cwd)
	local out, seen = {}, {}
	local function add(p)
		if type(p) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			out[#out + 1] = p
		end
	end
	add(cwd)
	add((cwd or ""):gsub("/+$", "")) -- gsub returns 2 values; the parens keep only 1
	add(vim.uv.fs_realpath(cwd))
	return out
end

-- Escaped "AND <col> IN ('c1','c2',...)". Empty cands -> empty string (no filter).
local function in_list(col, cands)
	if not cands or #cands == 0 then
		return ""
	end
	local parts = {}
	for _, c in ipairs(cands) do
		parts[#parts + 1] = q(c)
	end
	return ("AND %s IN (%s)"):format(col, table.concat(parts, ", "))
end

local function set_of(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[v] = true
	end
	return s
end

-- Warn once per session (e.g. missing sqlite3 for opencode).
local warned = {}
local function notify_once(key, msg, level)
	if warned[key] then
		return
	end
	warned[key] = true
	vim.notify(msg, vim.log.levels[(level or "warn"):upper()] or vim.log.levels.WARN, { title = "AI history" })
end

-- Decode 1 json LINE; nil when the line is cut or not an object. (Shared by the
-- codex jsonl fallback and the claude parser below -> declared early.)
local function decode(line)
	local ok, o = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return (ok and type(o) == "table") and o or nil
end

-- codex JSONL fallback (when sqlite3 is missing) -----------------------------
-- codex writes transcripts to ~/.codex/sessions/YYYY/MM/DD/rollout-<iso>-<uuid>.jsonl.
-- The first line is session_meta {payload:{id,cwd,timestamp}}; the first user_message
-- {payload:{type:"user_message",message}} is the title. Reads only the HEAD, so it is cheap.
local codex_jsonl_cache = {} -- path -> { mtime, info }

local function codex_head_info(path, mtime)
	local c = codex_jsonl_cache[path]
	if c and c.mtime == mtime then
		return c.info
	end
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local head = f:read(32 * 1024) or ""
	f:close()
	local info, count = {}, 0
	for line in head:gmatch("[^\n]+") do
		count = count + 1
		if not info.cwd and line:find('"session_meta"', 1, true) then
			local o = decode(line)
			local p = o and o.payload
			if p then
				info.id, info.cwd = p.id, p.cwd
			end
		elseif not info.title and line:find('"user_message"', 1, true) then
			local o = decode(line)
			local p = o and o.payload
			if p and p.type == "user_message" and type(p.message) == "string" then
				info.title = p.message
			end
		end
		if (info.cwd and info.title) or count > 200 then
			break
		end
	end
	codex_jsonl_cache[path] = { mtime = mtime, info = info }
	return info
end

local function codex_jsonl(cands, limit)
	local root = vim.fn.expand("~/.codex/sessions")
	if vim.fn.isdirectory(root) == 0 then
		return {}
	end
	local files = {}
	for _, p in ipairs(vim.fn.glob(root .. "/**/*.jsonl", false, true)) do
		local st = vim.uv.fs_stat(p)
		if st and st.type == "file" and st.size > 0 then
			files[#files + 1] = { path = p, mtime = st.mtime.sec }
		end
	end
	table.sort(files, function(a, b)
		return a.mtime > b.mtime
	end)

	local match = cands and set_of(cands) or nil
	local out = {}
	for _, e in ipairs(files) do
		if #out >= limit then
			break
		end
		local i = codex_head_info(e.path, e.mtime)
		if i and i.id and (not match or (i.cwd and match[i.cwd])) then
			out[#out + 1] = {
				tool = "codex",
				id = i.id,
				cwd = i.cwd,
				title = oneline(i.title, M.config.title_width),
				prompt = oneline(i.title, M.config.prompt_width),
				prompt_lines = head_lines(i.title),
				time = e.mtime, -- mtime instead of ISO->epoch: no TZ skew, good enough to sort
			}
		end
	end
	return out
end

-- codex ------------------------------------------------------------------
local function codex(cands, limit)
	-- Missing sqlite3 (common in minimal containers) -> read the jsonl in pure Lua.
	if not sqlite_bin() then
		return codex_jsonl(cands, limit)
	end
	local db = newest(vim.fn.expand("~/.codex/state_*.sqlite"))
	-- Extra columns for the preview: only widens the existing SELECT, no extra query.
	local sql = ([[SELECT id, cwd, title, first_user_message, git_branch, updated_at_ms,
		model, reasoning_effort, tokens_used, cli_version, created_at_ms, git_sha
		FROM threads WHERE archived = 0 %s ORDER BY updated_at_ms DESC LIMIT %d;]]):format(in_list("cwd", cands), limit)
	local out = {}
	for _, r in ipairs(sqlite_json(db, sql)) do
		out[#out + 1] = {
			tool = "codex",
			id = r.id,
			cwd = r.cwd,
			branch = r.git_branch,
			title = oneline(r.title, M.config.title_width) or oneline(r.first_user_message, M.config.title_width),
			prompt = oneline(r.first_user_message, M.config.prompt_width),
			prompt_lines = head_lines(r.first_user_message),
			time = math.floor((r.updated_at_ms or 0) / 1000),
			created = r.created_at_ms and math.floor(r.created_at_ms / 1000) or nil,
			model = r.model,
			effort = r.reasoning_effort,
			tokens = r.tokens_used,
			version = r.cli_version,
			sha = r.git_sha and r.git_sha:sub(1, 7) or nil,
		}
	end
	return out
end

-- opencode ---------------------------------------------------------------
local function opencode(cands, limit)
	-- opencode has ONLY a sqlite store (no jsonl copy) -> no fallback.
	if not sqlite_bin() then
		notify_once(
			"opencode_sqlite",
			"opencode history needs sqlite3 - install `sqlite3` in the container to enable it"
		)
		return {}
	end
	local db = vim.fn.expand("~/.local/share/opencode/opencode.db")
	-- parent_id NOT NULL = a subagent session -> filtered out.
	local sql = ([[SELECT id, directory, title, time_updated, time_created,
		model, agent, version, cost, tokens_input, tokens_output, tokens_reasoning
		FROM session
		WHERE parent_id IS NULL AND time_archived IS NULL %s
		ORDER BY time_updated DESC LIMIT %d;]]):format(in_list("directory", cands), limit)
	local out = {}
	for _, r in ipairs(sqlite_json(db, sql)) do
		-- model is JSON: {"id":"big-pickle","providerID":"opencode"}. Drop the field when malformed.
		local model
		if type(r.model) == "string" and r.model ~= "" then
			local ok, m = pcall(vim.json.decode, r.model)
			model = ok and type(m) == "table" and m.id or nil
		end
		local tok = (r.tokens_input or 0) + (r.tokens_output or 0) + (r.tokens_reasoning or 0)
		out[#out + 1] = {
			tool = "opencode",
			id = r.id,
			cwd = r.directory,
			title = oneline(r.title, M.config.title_width),
			time = math.floor((r.time_updated or 0) / 1000),
			created = r.time_created and math.floor(r.time_created / 1000) or nil,
			model = model,
			agent = r.agent,
			version = r.version,
			tokens = tok > 0 and tok or nil,
			cost = (r.cost and r.cost > 0) and r.cost or nil,
		}
	end
	return out
end

-- claude -----------------------------------------------------------------

-- (decode() is declared early in the cwd matching section so the codex jsonl fallback shares it.)

-- Cheap on a 5 MB file: only 2 reads of 64 KB, and json-decodes only SMALL lines
-- pre-filtered with string.find (ai-title ~129 B, last-prompt ~292 B).
-- vim.json.decode, NOT string.match: '"aiTitle":"([^"]*)"' breaks when the
-- title contains \" and leaves \n / \u00xx raw (the corpus has real \u00xx escapes).
local function parse_jsonl(path, size)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local info = {}

	-- HEAD: the first line with "cwd" (the 2 queue-operation lines at the top have none).
	-- cwd comes AFTER `message` in that line -> its offset drifts with prompt length, hence 64 KB.
	local head = f:read(math.min(M.config.head, size)) or ""
	for line in head:gmatch("[^\n]+") do
		if not info.cwd and line:find('"cwd":"', 1, true) then
			local o = decode(line)
			if o and o.cwd then
				info.cwd, info.branch, info.version = o.cwd, o.gitBranch, o.version
				local c = o.message and o.message.content
				info.first = type(c) == "string" and c or (type(c) == "table" and c[1] and c[1].text or nil)
			end
		end
		-- model is on the assistant line (message.model). Taken from the head chunk already
		-- read -> no extra IO. NO token sum for claude: a correct number needs a scan of the
		-- whole file, the last line alone is wrong -> better to show nothing.
		if not info.model and line:find('"assistant"', 1, true) then
			local o = decode(line)
			local m = o and o.message
			if type(m) == "table" and type(m.model) == "string" then
				info.model = m.model
				info.version = info.version or o.version
			end
		end
		if info.cwd and info.model then
			break
		end
	end

	-- TAIL: scan BACKWARDS -> the last occurrence wins (ai-title is refined
	-- several times and the last one is best; measured up to 31.8 KB before EOF).
	local off = size > M.config.tail and size - M.config.tail or 0
	f:seek("set", off)
	local tail = f:read(M.config.tail) or ""
	f:close()
	local lines = {}
	for line in tail:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	if off > 0 then
		table.remove(lines, 1) -- the chunk's first line is almost surely cut
	end
	for i = #lines, 1, -1 do
		local line = lines[i]
		if not info.title and line:find('"aiTitle"', 1, true) then
			local o = decode(line)
			info.title = o and o.aiTitle or nil
		end
		if not info.prompt and line:find('"lastPrompt"', 1, true) then
			local o = decode(line)
			info.prompt = o and o.lastPrompt or nil
		end
		if info.title and info.prompt then
			break
		end
	end

	-- cwd fallback: assistant/user lines in the tail also carry cwd (saves files whose
	-- first prompt is huge, longer than the head chunk).
	if not info.cwd then
		for i = #lines, 1, -1 do
			if lines[i]:find('"cwd":"', 1, true) then
				local o = decode(lines[i])
				if o and o.cwd then
					info.cwd, info.branch = o.cwd, o.gitBranch or info.branch
					break
				end
			end
		end
	end
	return info
end

local function claude(cands, limit)
	local root = vim.fn.expand("~/.claude/projects")
	-- slug = cwd with every non-alphanumeric char -> "-". Each candidate cwd may
	-- give a different slug (container /app vs realpath) -> glob EACH slug and merge.
	-- The glob is depth-1, so subagents/*.jsonl and memory/ are excluded.
	local files, seen = {}, {}
	local function collect(pattern)
		for _, p in ipairs(vim.fn.glob(pattern, false, true)) do
			if not seen[p] then
				local st = vim.uv.fs_stat(p)
				if st and st.type == "file" and st.size > 0 then
					seen[p] = true
					files[#files + 1] = { path = p, mtime = st.mtime.sec, size = st.size }
				end
			end
		end
	end
	if cands then
		for _, c in ipairs(cands) do
			collect(root .. "/" .. c:gsub("[^%w]", "-") .. "/*.jsonl")
		end
	else
		collect(root .. "/*/*.jsonl")
	end
	table.sort(files, function(a, b)
		return a.mtime > b.mtime
	end)

	local out = {}
	for i = 1, math.min(#files, limit) do
		local e = files[i]
		-- claude appends to the jsonl every turn -> mtime is a perfect cache key.
		local c = claude_cache[e.path]
		if not (c and c.mtime == e.mtime) then
			local info = parse_jsonl(e.path, e.size)
			c = info and { mtime = e.mtime, info = info } or nil
			claude_cache[e.path] = c
		end
		if c then
			local i2 = c.info
			out[#out + 1] = {
				tool = "claude",
				id = vim.fn.fnamemodify(e.path, ":t:r"), -- session uuid = file name
				cwd = i2.cwd or (cands and cands[1]),
				branch = i2.branch,
				title = oneline(i2.title, M.config.title_width) or oneline(strip_tags(i2.first), M.config.title_width),
				prompt = oneline(i2.prompt, M.config.prompt_width),
				prompt_lines = head_lines(i2.prompt),
				time = e.mtime,
				model = i2.model,
				version = i2.version,
				jsonl = e.path, -- used by the delete action
			}
		end
	end
	return out
end

-- public -----------------------------------------------------------------

-- Used to LAUNCH a new session (cd into a real dir). Keeps realpath as before.
function M.project_cwd()
	local cwd = vim.fn.getcwd()
	return vim.uv.fs_realpath(cwd) or cwd
end

-- Used to SCOPE/filter history: returns nvim's RAW cwd. M.list adds the
-- realpath to the candidate set -> matches both the mount path (/app) and the realpath.
function M.scope_cwd()
	return vim.fn.getcwd()
end

--- Old on-disk sessions, newest first.
---@param cwd? string nil = every directory; otherwise matched against the candidate set (raw+realpath)
---@param limit? number overrides M.config.limit. It is a PER-TOOL limit, not a
---  total - a caller that wants exactly N rows cuts the returned list (the dashboard does).
function M.list(cwd, limit)
	limit = limit or M.config.limit
	local cands = cwd and cwd_candidates(cwd) or nil
	local out = {}
	local ok, err = pcall(function()
		vim.list_extend(out, claude(cands, limit))
		vim.list_extend(out, codex(cands, limit))
		vim.list_extend(out, opencode(cands, limit))
	end)
	if not ok then
		vim.notify("aiterm history: " .. tostring(err), vim.log.levels.WARN)
	end
	table.sort(out, function(a, b)
		return (a.time or 0) > (b.time or 0)
	end)
	return out
end

function M.invalidate()
	claude_cache = {}
	codex_jsonl_cache = {}
end

-- Diagnostics: why the picker does not see a session (usually cwd scoping or missing
-- sqlite3). Opens a scratch buffer reporting HOME/cwd/candidates/binaries + scoped vs
-- all-dirs counts per tool + a few recorded sample cwds. Bound to <leader>ad.
-- extra: caller-supplied lines appended at the end of the same buffer (see aiterm.M.doctor,
-- which attaches the ECC section here). Takes a LIST OF LINES rather than requiring another
-- module: this file is pure history data and knows nothing about ECC.
---@param extra? string[]
function M.doctor(extra)
	local raw = vim.fn.getcwd()
	local real = vim.uv.fs_realpath(raw)
	local cands = cwd_candidates(raw)

	local all = M.list(nil, 500)
	local scoped = M.list(raw, 500)
	local function counts(list)
		local c = { claude = 0, codex = 0, opencode = 0 }
		for _, e in ipairs(list) do
			c[e.tool] = (c[e.tool] or 0) + 1
		end
		return c
	end
	local ca, cs = counts(all), counts(scoped)

	-- a few sample cwds (all-dirs) to compare with candidates -> shows where the path differs.
	local samples, seen = {}, {}
	for _, e in ipairs(all) do
		if e.cwd and not seen[e.cwd] and #samples < 8 then
			seen[e.cwd] = true
			samples[#samples + 1] = ("  [%s] %s"):format(e.tool, e.cwd)
		end
	end

	local function yn(p)
		return (p and p ~= "" and vim.uv.fs_stat(p)) and ("ok  " .. p) or ("MISSING  " .. tostring(p))
	end

	local lines = {
		"# aiterm history doctor",
		"",
		"HOME        : " .. (vim.env.HOME or "?"),
		"getcwd      : " .. raw,
		"realpath    : " .. (real or "(nil)"),
		"candidates  : " .. table.concat(cands, "   |   "),
		"sqlite3     : " .. (sqlite_bin() or "(MISSING -> codex uses the jsonl fallback, opencode disabled)"),
		"",
		"## stores",
		"claude proj : " .. yn(vim.fn.expand("~/.claude/projects")),
		"codex sqlite: " .. yn(newest(vim.fn.expand("~/.codex/state_*.sqlite")) or ""),
		"codex jsonl : " .. yn(vim.fn.expand("~/.codex/sessions")),
		"opencode db : " .. yn(vim.fn.expand("~/.local/share/opencode/opencode.db")),
		"",
		"## counts (scoped cwd / all dirs)",
		("claude      : %d / %d"):format(cs.claude, ca.claude),
		("codex       : %d / %d"):format(cs.codex, ca.codex),
		("opencode    : %d / %d"):format(cs.opencode, ca.opencode),
		"",
		"## sample recorded cwd (all dirs)",
	}
	vim.list_extend(lines, #samples > 0 and samples or { "  (none)" })
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Hint: if 'all dirs' > 0 but 'scoped' = 0 -> the current cwd does not match the recorded cwds"
	lines[#lines + 1] =
		"above. Open nvim in the RIGHT project directory, or press <A-a> in the picker to see everything."
	if extra and #extra > 0 then
		lines[#lines + 1] = ""
		vim.list_extend(lines, extra)
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].modifiable = false
	vim.cmd("botright split")
	local w = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(w, buf)
	vim.api.nvim_win_set_height(w, math.min(#lines + 1, 22))
end

return M
