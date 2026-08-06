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

-- cwd matching -----------------------------------------------------------
-- Trong container project bind-mount tại /app (có thể là symlink) nên
-- fs_realpath(getcwd()) lệch với cwd mà tool đã GHI (thường là /app raw) ->
-- filter theo mỗi realpath loại sạch. Match theo TẬP ứng viên: raw + bỏ trailing
-- slash + realpath. Trên host realpath == path nên chỉ 1 phần tử -> y như cũ.
local function cwd_candidates(cwd)
	local out, seen = {}, {}
	local function add(p)
		if type(p) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			out[#out + 1] = p
		end
	end
	add(cwd)
	add((cwd or ""):gsub("/+$", "")) -- gsub trả 2 giá trị; ngoặc cắt còn 1 khi truyền
	add(vim.uv.fs_realpath(cwd))
	return out
end

-- "AND <col> IN ('c1','c2',...)" đã escape. cands rỗng -> chuỗi rỗng (không lọc).
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

-- Cảnh báo 1 lần / phiên (vd thiếu sqlite3 cho opencode).
local warned = {}
local function notify_once(key, msg, level)
	if warned[key] then
		return
	end
	warned[key] = true
	vim.notify(msg, vim.log.levels[(level or "warn"):upper()] or vim.log.levels.WARN, { title = "AI history" })
end

-- Decode 1 DÒNG json; nil nếu dòng bị cắt hoặc không phải object. (Dùng chung cho
-- codex jsonl fallback lẫn claude parser bên dưới -> khai báo sớm.)
local function decode(line)
	local ok, o = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return (ok and type(o) == "table") and o or nil
end

-- codex JSONL fallback (khi thiếu sqlite3) --------------------------------
-- codex ghi transcript ở ~/.codex/sessions/YYYY/MM/DD/rollout-<iso>-<uuid>.jsonl.
-- Dòng đầu là session_meta {payload:{id,cwd,timestamp}}; user_message đầu tiên
-- {payload:{type:"user_message",message}} làm title. Chỉ đọc HEAD nên rẻ.
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
				time = e.mtime, -- mtime thay ISO->epoch: tránh lệch TZ, đủ để sort
			}
		end
	end
	return out
end

-- codex ------------------------------------------------------------------
local function codex(cands, limit)
	-- Thiếu sqlite3 (hay gặp trong container tối giản) -> đọc jsonl thuần Lua.
	if not sqlite_bin() then
		return codex_jsonl(cands, limit)
	end
	local db = newest(vim.fn.expand("~/.codex/state_*.sqlite"))
	local sql = ([[SELECT id, cwd, title, first_user_message, git_branch, updated_at_ms
		FROM threads WHERE archived = 0 %s ORDER BY updated_at_ms DESC LIMIT %d;]]):format(
		in_list("cwd", cands),
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
local function opencode(cands, limit)
	-- opencode CHỈ có store sqlite (không có bản jsonl) -> không có fallback.
	if not sqlite_bin() then
		notify_once("opencode_sqlite", "opencode history cần sqlite3 — cài `sqlite3` trong container để bật")
		return {}
	end
	local db = vim.fn.expand("~/.local/share/opencode/opencode.db")
	-- parent_id NOT NULL = session của subagent -> lọc ra.
	local sql = ([[SELECT id, directory, title, time_updated FROM session
		WHERE parent_id IS NULL AND time_archived IS NULL %s
		ORDER BY time_updated DESC LIMIT %d;]]):format(in_list("directory", cands), limit)
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

-- (decode() được khai báo sớm ở phần cwd matching để codex jsonl fallback dùng chung.)

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

local function claude(cands, limit)
	local root = vim.fn.expand("~/.claude/projects")
	-- slug = cwd với mọi ký tự không alphanumeric -> "-". Mỗi candidate cwd có thể
	-- ra một slug khác (container /app vs realpath) -> glob TỪNG slug rồi gộp.
	-- glob depth-1 nên subagents/*.jsonl và memory/ tự bị loại.
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
				cwd = i2.cwd or (cands and cands[1]),
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

-- Dùng cho việc LAUNCH session mới (cd vào một dir thật). Giữ realpath như cũ.
function M.project_cwd()
	local cwd = vim.fn.getcwd()
	return vim.uv.fs_realpath(cwd) or cwd
end

-- Dùng cho việc SCOPE/lọc history: trả cwd RAW của nvim. M.list tự dựng thêm
-- realpath vào tập ứng viên -> khớp cả path mount (/app) lẫn realpath.
function M.scope_cwd()
	return vim.fn.getcwd()
end

--- Danh sách session cũ trên đĩa, mới nhất trước.
---@param cwd? string nil = mọi thư mục; nếu có -> match theo tập ứng viên (raw+realpath)
---@param limit? number ghi đè M.config.limit. Là giới hạn MỖI TOOL, không phải
---  tổng - caller muốn đúng N dòng thì tự cắt list trả về (dashboard làm vậy).
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

-- Chẩn đoán: vì sao picker không thấy session (thường do cwd scoping hoặc thiếu
-- sqlite3). Mở scratch buffer báo cáo HOME/cwd/candidates/binary + đếm scoped vs
-- all-dirs cho từng tool + vài cwd mẫu đã ghi. Gắn với <leader>ad.
function M.doctor()
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

	-- vài cwd mẫu (all-dirs) để so với candidates -> thấy ngay path lệch chỗ nào.
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
		"sqlite3     : " .. (sqlite_bin() or "(MISSING -> codex dùng jsonl fallback, opencode tắt)"),
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
	lines[#lines + 1] = "Gợi ý: nếu 'all dirs' > 0 mà 'scoped' = 0 -> cwd hiện tại không khớp cwd đã ghi"
	lines[#lines + 1] = "ở trên. Mở nvim ĐÚNG thư mục dự án, hoặc dùng <A-a> trong picker để xem tất cả."

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
