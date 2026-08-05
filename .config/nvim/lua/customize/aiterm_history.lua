-- Khám phá session cũ trên đĩa của claude / codex / opencode.
-- Module thuần data: KHÔNG mở window, KHÔNG gọi Snacks. customize/aiterm.lua consume nó.
--
-- Nguồn (đã verify trên máy này):
--   codex    -> sqlite ~/.codex/state_*.sqlite                 table threads
--   opencode -> sqlite ~/.local/share/opencode/opencode.db     table session
--   claude   -> JSONL  ~/.claude/projects/<slug>/<uuid>.jsonl  (không có index)
local M = {}

M.config = {
	limit = 40, -- số session mới nhất lấy mỗi tool (chặn cứng chi phí)
	head = 64 * 1024, -- bytes đọc từ ĐẦU file jsonl -> cwd / gitBranch / prompt đầu
	tail = 64 * 1024, -- bytes đọc từ CUỐI file jsonl -> ai-title / last-prompt cuối
	title_width = 60,
	prompt_width = 400,
}

-- cache claude: path -> { mtime, info }; invalidate bằng mtime
local claude_cache = {}

-- helpers ----------------------------------------------------------------

-- Gom về 1 dòng + truncate theo KÝ TỰ (strcharpart) để không cắt giữa UTF-8.
-- string.sub(1, 60) sẽ tạo ra "...dữ li<e1><bb>" - hỏng dấu tiếng Việt.
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

-- claude nhồi <ide_selection>/<system-reminder> vào prompt đầu -> bỏ đi khi làm title.
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
	-- macOS luôn có sẵn bản này (3.43.2)
	return vim.fn.executable("/usr/bin/sqlite3") == 1 and "/usr/bin/sqlite3" or nil
end

-- Escape literal cho SQL: '' là escape duy nhất SQLite hiểu trong single-quoted string.
local function q(s)
	return "'" .. s:gsub("'", "''") .. "'"
end

-- `-json` + vim.json.decode: an toàn tuyệt đối với title chứa | , newline, unicode.
-- 0 row -> sqlite3 in chuỗi RỖNG (không phải "[]") nên phải guard trước khi decode.
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
		r = run(false) -- WAL cần recovery -> mở read-write, vẫn chỉ SELECT
	end
	if not r or r.code ~= 0 or (r.stdout or "") == "" then
		return {}
	end
	local ok, rows = pcall(vim.json.decode, r.stdout, { luanil = { object = true, array = true } })
	return (ok and type(rows) == "table") and rows or {}
end

-- Chọn file mới nhất theo mtime. codex bump version suffix (state_5 -> state_10)
-- nên sort theo TÊN sẽ sai, sort theo mtime thì không.
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

-- codex ------------------------------------------------------------------
local function codex(cwd, limit)
	local db = newest(vim.fn.expand("~/.codex/state_*.sqlite"))
	local sql = ([[SELECT id, cwd, title, first_user_message, git_branch, updated_at_ms
		FROM threads WHERE archived = 0 %s ORDER BY updated_at_ms DESC LIMIT %d;]]):format(
		cwd and ("AND cwd = " .. q(cwd)) or "",
		limit
	)
	local out = {}
	for _, r in ipairs(sqlite_json(db, sql)) do
		out[#out + 1] = {
			tool = "codex",
			id = r.id,
			cwd = r.cwd,
			branch = r.git_branch,
			title = oneline(r.title, M.config.title_width) or oneline(r.first_user_message, M.config.title_width),
			prompt = oneline(r.first_user_message, M.config.prompt_width),
			time = math.floor((r.updated_at_ms or 0) / 1000),
		}
	end
	return out
end

-- opencode ---------------------------------------------------------------
local function opencode(cwd, limit)
	local db = vim.fn.expand("~/.local/share/opencode/opencode.db")
	-- parent_id NOT NULL = session của subagent -> lọc ra.
	local sql = ([[SELECT id, directory, title, time_updated FROM session
		WHERE parent_id IS NULL AND time_archived IS NULL %s
		ORDER BY time_updated DESC LIMIT %d;]]):format(cwd and ("AND directory = " .. q(cwd)) or "", limit)
	local out = {}
	for _, r in ipairs(sqlite_json(db, sql)) do
		out[#out + 1] = {
			tool = "opencode",
			id = r.id,
			cwd = r.directory,
			title = oneline(r.title, M.config.title_width),
			time = math.floor((r.time_updated or 0) / 1000),
		}
	end
	return out
end

-- claude -----------------------------------------------------------------

-- Decode 1 DÒNG json; nil nếu dòng bị cắt hoặc không phải object.
local function decode(line)
	local ok, o = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return (ok and type(o) == "table") and o or nil
end

-- Rẻ với file 5 MB: chỉ 2 lần read 64 KB, và chỉ json-decode những dòng NHỎ
-- đã lọc trước bằng string.find (ai-title ~129 B, last-prompt ~292 B).
-- Dùng vim.json.decode chứ KHÔNG string.match: '"aiTitle":"([^"]*)"' vỡ khi
-- title chứa \" và để nguyên \n / \u00xx (corpus có escape \u00xx thật).
local function parse_jsonl(path, size)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local info = {}

	-- HEAD: dòng đầu tiên có "cwd" (2 dòng queue-operation đầu file không có).
	-- cwd nằm SAU `message` trong dòng đó -> vị trí trôi theo độ dài prompt, cần 64 KB.
	local head = f:read(math.min(M.config.head, size)) or ""
	for line in head:gmatch("[^\n]+") do
		if line:find('"cwd":"', 1, true) then
			local o = decode(line)
			if o and o.cwd then
				info.cwd, info.branch = o.cwd, o.gitBranch
				local c = o.message and o.message.content
				info.first = type(c) == "string" and c or (type(c) == "table" and c[1] and c[1].text or nil)
				break
			end
		end
	end

	-- TAIL: quét NGƯỢC -> lần xuất hiện cuối cùng thắng (ai-title được refine
	-- nhiều lần, bản cuối là bản tốt nhất; đã đo cách EOF tới 31.8 KB).
	local off = size > M.config.tail and size - M.config.tail or 0
	f:seek("set", off)
	local tail = f:read(M.config.tail) or ""
	f:close()
	local lines = {}
	for line in tail:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	if off > 0 then
		table.remove(lines, 1) -- dòng đầu của chunk gần như chắc chắn bị cắt
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

	-- Fallback cwd: dòng assistant/user trong tail cũng mang cwd (cứu file có
	-- prompt đầu khổng lồ, dài hơn head chunk).
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

local function claude(cwd, limit)
	local root = vim.fn.expand("~/.claude/projects")
	-- slug = cwd với mọi ký tự không alphanumeric -> "-"
	-- glob depth-1 nên subagents/*.jsonl và memory/ tự bị loại.
	local pattern = cwd and (root .. "/" .. cwd:gsub("[^%w]", "-") .. "/*.jsonl") or (root .. "/*/*.jsonl")

	local files = {}
	for _, p in ipairs(vim.fn.glob(pattern, false, true)) do
		local st = vim.uv.fs_stat(p)
		if st and st.type == "file" and st.size > 0 then
			files[#files + 1] = { path = p, mtime = st.mtime.sec, size = st.size }
		end
	end
	table.sort(files, function(a, b)
		return a.mtime > b.mtime
	end)

	local out = {}
	for i = 1, math.min(#files, limit) do
		local e = files[i]
		-- claude append vào jsonl mỗi lượt -> mtime là cache key hoàn hảo.
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
				id = vim.fn.fnamemodify(e.path, ":t:r"), -- session uuid = tên file
				cwd = i2.cwd or cwd,
				branch = i2.branch,
				title = oneline(i2.title, M.config.title_width) or oneline(strip_tags(i2.first), M.config.title_width),
				prompt = oneline(i2.prompt, M.config.prompt_width),
				time = e.mtime,
				jsonl = e.path, -- dùng cho action delete
			}
		end
	end
	return out
end

-- public -----------------------------------------------------------------

-- codex/opencode lưu realpath -> resolve symlink để so sánh cwd không lệch.
function M.project_cwd()
	local cwd = vim.fn.getcwd()
	return vim.uv.fs_realpath(cwd) or cwd
end

--- Danh sách session cũ trên đĩa, mới nhất trước.
---@param cwd? string nil = mọi thư mục
---@param limit? number ghi đè M.config.limit. Là giới hạn MỖI TOOL, không phải
---  tổng - caller muốn đúng N dòng thì tự cắt list trả về (dashboard làm vậy).
function M.list(cwd, limit)
	limit = limit or M.config.limit
	local out = {}
	local ok, err = pcall(function()
		vim.list_extend(out, claude(cwd, limit))
		vim.list_extend(out, codex(cwd, limit))
		vim.list_extend(out, opencode(cwd, limit))
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
end

return M
