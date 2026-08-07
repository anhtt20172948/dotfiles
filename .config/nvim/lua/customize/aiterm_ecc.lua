-- ECC (https://github.com/affaan-m/ECC) cho claude / codex / opencode.
-- Module thuần data: KHÔNG mở window, KHÔNG gọi Snacks — cùng khuôn aiterm_history.
--
-- Hai việc:
--   1. DÒ trên đĩa xem tool nào đã có command của ECC, và gõ nó ra sao.
--   2. Dựng danh sách lệnh SHELL để cài (customize/aiterm.lua chạy + hỏi xác nhận).
--
-- Vì sao phải dò chứ không hardcode: tiền tố lệnh KHÁC nhau theo tool.
--   claude (cài tay) ~/.claude/commands/code-review.md      -> /code-review
--   claude (plugin)  cache plugin của Claude Code           -> /ecc:code-review
--   codex            ~/.codex/prompts/ecc-code-review.md    -> /ecc-code-review
--   opencode         ~/.config/opencode/command/*.md        -> /code-review
-- Nguồn tiền tố codex: scripts/sync-ecc-to-codex.sh sinh file "ecc-$name.md".
-- Thư mục command của opencode CHƯA verify được từ repo -> dò nhiều ứng viên, không
-- có thì trả bảng rỗng. Không bao giờ sinh ra một lệnh không tồn tại trên đĩa.
local M = {}

M.config = {
	repo = "https://github.com/affaan-m/ECC",
	dir = nil, -- nil -> stdpath("data")/ecc
	-- developer = profile "kỹ sư mặc định" của ECC: minimal + framework-language +
	-- database + orchestration. Nhiều skill/command hơn minimal; favorites/pin
	-- (<leader>aS/<leader>aw) giữ picker gọn. codex (sync) và opencode (pin full)
	-- bỏ qua giá trị này; chỉ claude dùng --profile.
	profile = "developer",
}

-- Command của ECC dùng làm MỐC nhận diện. ~/.claude/commands/ có thể toàn command tự
-- viết của người dùng, nên "thư mục không rỗng" KHÔNG đủ để kết luận đã cài ECC.
local MARKERS = { "code-review", "build-fix", "refactor-clean", "update-docs" }
local MARKER_MIN = 2

-- Số dòng đầu đọc từ mỗi file command để lấy frontmatter `description:`.
local HEAD_LINES = 10

-- cache: tool -> { sig, cmds, paths }; sig ghép mtime các thư mục nguồn nên cài xong
-- là tự mới. skill_cache/desc_cache dùng cùng cơ chế sig đó.
local cache = {}
local skill_cache = {}
local desc_cache = {}
local owned_cache = {}

local function read_json(path)
	local ok, data = pcall(vim.fn.readfile, path)
	if not ok or not data or #data == 0 then
		return nil
	end
	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	return ok and type(decoded) == "table" and decoded or nil
end

-- helpers ----------------------------------------------------------------

local function home(p)
	return vim.fn.expand("~/" .. p)
end

local function config_home()
	local x = vim.env.XDG_CONFIG_HOME
	if x and x ~= "" then
		return x
	end
	return vim.fn.expand("~/.config")
end

-- Thư mục command CỤC BỘ của repo (rooted ở cwd), theo tool. Đứng TRƯỚC nguồn HOME
-- nên bản của repo thắng. scope="project" để command_list gắn nhãn + sort đầu.
local function project_command_srcs(tool, cwd)
	if not cwd then
		return {}
	end
	local by_tool = {
		claude = { { dir = cwd .. "/.claude/commands", prefix = "", invoke = "/%s" } },
		codex = { { dir = cwd .. "/.codex/prompts", prefix = "ecc-", invoke = "/ecc-%s" } },
		opencode = {
			{ dir = cwd .. "/.opencode/commands", prefix = "", invoke = "/%s" },
			{ dir = cwd .. "/.opencode/command", prefix = "", invoke = "/%s" },
		},
	}
	local out = by_tool[tool] or {}
	for _, s in ipairs(out) do
		s.scope = "project"
	end
	return out
end

-- Danh sách thư mục có thể chứa command, theo thứ tự ưu tiên. Trả cả thư mục KHÔNG
-- tồn tại: sig phải phân biệt được "chưa có" với "vừa tạo" thì cache mới tự hết hạn.
-- cwd (tuỳ chọn): thêm nguồn CỤC BỘ repo lên đầu (scope="project"). Không truyền -> chỉ HOME.
---@return { dir: string, prefix: string, invoke: string, scope?: string }[]
local function sources(tool, cwd)
	local home_srcs = {}
	if tool == "claude" then
		home_srcs = { { dir = home(".claude/commands"), prefix = "", invoke = "/%s" } }
		-- Đường plugin (/plugin install ecc@ecc) không phải đường mình cài, nhưng nếu
		-- người dùng đã cài kiểu đó thì vẫn nhận ra. Glob ĐỘ SÂU CỐ ĐỊNH, không đệ quy:
		-- ~/.claude/plugins có thể chứa node_modules, quét đệ quy ở đây là bẫy hiệu năng.
		for _, pat in ipairs({ ".claude/plugins/*/ecc", ".claude/plugins/*/*/ecc" }) do
			for _, d in ipairs(vim.fn.glob(home(pat) .. "/commands", false, true)) do
				home_srcs[#home_srcs + 1] = { dir = d, prefix = "", invoke = "/ecc:%s" }
			end
		end
	elseif tool == "codex" then
		home_srcs = { { dir = home(".codex/prompts"), prefix = "ecc-", invoke = "/ecc-%s" } }
	elseif tool == "opencode" then
		-- ĐÃ ĐO trên máy này: opencode coi ~/.opencode LÀ một config root - gõ /code-rev
		-- trong TUI ra đủ autocomplete dù ~/.config/opencode không có thư mục command
		-- nào. Đó cũng là lý do `install.sh --target opencode` của ECC ghi vào đây.
		-- Vẫn giữ ~/.config/opencode (đường tài liệu ghi) cho ai tự chép sang.
		local c = config_home() .. "/opencode"
		home_srcs = {
			{ dir = home(".opencode/commands"), prefix = "", invoke = "/%s" },
			{ dir = home(".opencode/command"), prefix = "", invoke = "/%s" },
			{ dir = c .. "/command", prefix = "", invoke = "/%s" },
			{ dir = c .. "/commands", prefix = "", invoke = "/%s" },
		}
	else
		return {}
	end
	-- Nguồn CỤC BỘ repo đứng TRƯỚC nguồn HOME: "nguồn trước thắng" trong M.commands()
	-- nên bản của repo ưu tiên hơn bản global cùng tên.
	local out = project_command_srcs(tool, cwd)
	vim.list_extend(out, home_srcs)
	return out
end

local function signature(srcs)
	local parts = {}
	for _, s in ipairs(srcs) do
		local st = vim.uv.fs_stat(s.dir)
		parts[#parts + 1] = s.dir .. ":" .. (st and st.mtime.sec or 0)
	end
	return table.concat(parts, "|")
end

-- public -----------------------------------------------------------------

-- Thư mục clone dùng chung cho cả ba tool.
function M.dir()
	return M.config.dir or (vim.fn.stdpath("data") .. "/ecc")
end

-- Bảng "tên command của ECC" -> "chuỗi gõ vào session". Rỗng nếu chưa cài.
-- cwd (tuỳ chọn): thêm command CỤC BỘ repo (scope="project"). Không truyền -> chỉ HOME
-- (installed/count/status/doctor gọi kiểu này -> phát hiện cài đặt không đổi).
---@param tool string
---@param cwd? string
---@return table<string, string>
function M.commands(tool, cwd)
	local srcs = sources(tool, cwd)
	local sig = signature(srcs)
	local c = cache[tool]
	if c and c.sig == sig then
		return c.cmds
	end

	local cmds, paths, scopes = {}, {}, {}
	for _, s in ipairs(srcs) do
		if vim.uv.fs_stat(s.dir) then
			-- Độ sâu 1: command của cả ba harness đều là file phẳng trong thư mục.
			for name, kind in vim.fs.dir(s.dir) do
				local base = kind == "file" and name:match("^(.*)%.md$")
				if base and (s.prefix == "" or base:sub(1, #s.prefix) == s.prefix) then
					local key = base:sub(#s.prefix + 1)
					-- Nguồn trước thắng: bản CỤC BỘ repo / bản cài tay ưu tiên hơn.
					if key ~= "" and not cmds[key] then
						cmds[key] = s.invoke:format(key)
						paths[key] = s.dir .. "/" .. name
						scopes[key] = s.scope == "project" and "project" or "global"
					end
				end
			end
		end
	end

	cache[tool] = { sig = sig, cmds = cmds, paths = paths, scopes = scopes }
	return cmds
end

-- Thư mục skill mà TOOL THẬT SỰ ĐỌC. KHÁC command: skill là tài liệu hướng dẫn nên áp
-- được lên một đoạn code, còn command là quy trình cấp repo (xem M.command_list).
--   codex: $CODEX_HOME/skills, mặc định ~/.codex/skills - nguồn là chính skill
--   `skill-creator` của codex ("default to $CODEX_HOME/skills ... so the skill is
--   auto-discovered"). KHÔNG dò ~/.agents/skills như README của ECC nói: thư mục đó
--   codex không đọc, liệt kê thứ tool không thấy chính là kiểu "quảng cáo lệnh không
--   tồn tại" mà cả plugin này đang tránh. Skill gốc của codex nằm sâu một tầng trong
--   .system/ nên phải quét riêng.
-- Trả list { dir, scope }. cwd (tuỳ chọn) -> thêm thư mục skill CỤC BỘ repo lên đầu
-- (scope="project"); không truyền -> chỉ HOME (scope="global"). Không truy đệ quy.
local function skill_dirs(tool, cwd)
	local home_dirs
	if tool == "claude" then
		home_dirs = { home(".claude/skills") }
	elseif tool == "opencode" then
		-- ~/.opencode/skills: ECC ghi vào đây. ~/.config/opencode/skills: vercel skills
		-- CLI (`npx skills add -a opencode -g`) ghi vào đây -> phải quét cả hai.
		home_dirs = { home(".opencode/skills"), config_home() .. "/opencode/skills" }
	elseif tool == "codex" then
		home_dirs = { home(".codex/skills"), home(".codex/skills/.system") }
	else
		return {}
	end
	-- Project: đường của tool + `.agents/skills` (vercel skills CLI ghi skill CỤC BỘ
	-- của codex/opencode vào <cwd>/.agents/skills).
	local proj = ({
		claude = cwd and { cwd .. "/.claude/skills" } or {},
		opencode = cwd and { cwd .. "/.opencode/skills", cwd .. "/.agents/skills" } or {},
		codex = cwd and { cwd .. "/.codex/skills", cwd .. "/.agents/skills" } or {},
	})[tool] or {}
	local out = {}
	for _, d in ipairs(proj) do
		out[#out + 1] = { dir = d, scope = "project" }
	end
	for _, d in ipairs(home_dirs) do
		out[#out + 1] = { dir = d, scope = "global" }
	end
	-- ~/.agents/skills: dir "universal" mà vercel skills CLI hay ghi vào, nhưng
	-- claude/codex/opencode KHÔNG đọc. Xếp CUỐI -> dedup theo tên giữ bản ở dir thật
	-- của tool trước, nên skill chỉ hiện scope="shared" khi CHƯA activate vào tool.
	out[#out + 1] = { dir = vim.fn.expand("~/.agents/skills"), scope = "shared" }
	return out
end

-- File ECC đã ghi ra cho tool này, lấy từ install-state. Đây là dấu vết CHUẨN để biết
-- skill nào của ECC: frontmatter `metadata.origin: ECC` KHÔNG đủ - riêng claude có
-- 13/44 skill thiếu tag đó mà vẫn là của ECC (ecc-guide, santa-method, repo-scan...).
---@return table<string, true>
function M.ecc_owned(tool)
	local path = tool == "claude" and home(".claude/ecc/install-state.json")
		or tool == "opencode" and home(".opencode/ecc-install-state.json")
	local st = path and vim.uv.fs_stat(path)
	local sig = tostring(path) .. ":" .. (st and st.mtime.sec or 0)
	local c = owned_cache[tool]
	if c and c.sig == sig then
		return c.set
	end
	local set = {}
	local d = st and read_json(path)
	for _, op in ipairs(d and type(d.operations) == "table" and d.operations or {}) do
		if type(op) == "table" and type(op.destinationPath) == "string" then
			set[op.destinationPath] = true
		end
	end
	owned_cache[tool] = { sig = sig, set = set }
	return set
end

local ORIGIN_ORDER = { project = 0, ecc = 1, builtin = 2, user = 3, shared = 4 }

-- Skill của tool, kèm mô tả + nguồn. Sắp theo NHÓM rồi tên.
-- cwd (tuỳ chọn): kèm skill CỤC BỘ repo, origin="project" (sort đầu). Không truyền -> chỉ HOME.
---@param tool string
---@param cwd? string
---@return { name: string, desc: string, hint: string|nil, path: string, origin: string }[]
function M.skill_list(tool, cwd)
	local dirs = skill_dirs(tool, cwd)
	local sig = signature(dirs) -- dirs đã có .dir -> dùng thẳng
	local c = skill_cache[tool]
	if c and c.sig == sig then
		return c.list
	end

	local owned = M.ecc_owned(tool)
	local list, seen = {}, {}
	for _, entry in ipairs(dirs) do
		local dir = entry.dir
		if vim.uv.fs_stat(dir) then
			for name, kind in vim.fs.dir(dir) do
				local path = dir .. "/" .. name .. "/SKILL.md"
				-- "link": skill đã activate là symlink -> vim.fs.dir báo type "link", không
				-- phải "directory". fs_stat theo symlink nên vẫn xác nhận SKILL.md thật.
				if (kind == "directory" or kind == "link") and not seen[name] and vim.uv.fs_stat(path) then
					seen[name] = true
					local desc, hint, tagged = "", nil, false
					local ok, lines = pcall(vim.fn.readfile, path, "", HEAD_LINES)
					for _, l in ipairs(ok and lines or {}) do
						desc = desc ~= "" and desc or (l:match("^description:%s*(.+)$") or "")
						hint = hint or l:match("^argument%-hint:%s*(.+)$")
						tagged = tagged or l:find("origin: ECC", 1, true) ~= nil
					end
					desc = desc:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
					-- Thứ tự xác định nguồn: CỤC BỘ repo -> .system (skill gốc của tool) ->
					-- install-state (chuẩn nhất) -> frontmatter (dự phòng cho codex, vốn
					-- không có install-state) -> còn lại là bạn tự viết.
					local origin = "user"
					if entry.scope == "project" then
						origin = "project"
					elseif entry.scope == "shared" then
						origin = "shared" -- ~/.agents/skills, chưa activate vào dir tool
					elseif dir:find("/.system", 1, true) then
						origin = "builtin"
					elseif owned[path] or tagged then
						origin = "ecc"
					end
					list[#list + 1] = { name = name, desc = desc, hint = hint, path = path, origin = origin }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.origin ~= b.origin then
			return (ORIGIN_ORDER[a.origin] or 9) < (ORIGIN_ORDER[b.origin] or 9)
		end
		return a.name < b.name
	end)

	local set = {}
	for _, s in ipairs(list) do
		set[s.name] = true
	end
	skill_cache[tool] = { sig = sig, list = list, set = set }
	return list
end

-- Set tên skill. Giữ chữ ký cũ cho <leader>ai + doctor; dựng từ skill_list để chỉ có
-- MỘT đường dò.
---@return table<string, true>
function M.skills(tool)
	M.skill_list(tool)
	return skill_cache[tool].set
end

-- Danh sách command kèm mô tả, cho picker M.workflows(). Mô tả lấy từ frontmatter
-- `description:` - chỉ đọc HEAD_LINES dòng đầu mỗi file, đủ để qua frontmatter mà
-- không nuốt cả trăm file markdown vào RAM.
-- cwd (tuỳ chọn): kèm command CỤC BỘ repo, gắn scope="project" (picker sort đầu + nhãn).
---@param tool string
---@param cwd? string
---@return { name: string, invoke: string, desc: string, path: string, scope: string }[]
function M.command_list(tool, cwd)
	local cmds = M.commands(tool, cwd) -- nạp cache trước, cache[tool].paths/scopes có ngay sau đó
	local sig = cache[tool].sig
	local c = desc_cache[tool]
	if c and c.sig == sig then
		return c.list
	end
	local paths = cache[tool].paths or {}
	local scopes = cache[tool].scopes or {}
	local list = {}
	for name, invoke in pairs(cmds) do
		local path = paths[name]
		local desc = ""
		if path then
			local ok, lines = pcall(vim.fn.readfile, path, "", HEAD_LINES)
			if ok then
				for _, l in ipairs(lines) do
					local d = l:match("^description:%s*(.+)$")
					if d then
						-- frontmatter của ECC lúc có lúc không có nháy kép.
						desc = d:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
						break
					end
				end
			end
		end
		list[#list + 1] = { name = name, invoke = invoke, desc = desc, path = path, scope = scopes[name] or "global" }
	end
	-- project trước, rồi theo tên: picker hiện convention của repo lên đầu.
	table.sort(list, function(a, b)
		if (a.scope == "project") ~= (b.scope == "project") then
			return a.scope == "project"
		end
		return a.name < b.name
	end)
	desc_cache[tool] = { sig = sig, list = list }
	return list
end

-- Đã cài ECC chưa. Đếm MARKERS thay vì "thư mục không rỗng" (xem comment ở MARKERS).
function M.installed(tool)
	local cmds = M.commands(tool)
	local hit = 0
	for _, m in ipairs(MARKERS) do
		if cmds[m] then
			hit = hit + 1
		end
	end
	return hit >= MARKER_MIN
end

function M.refresh()
	cache = {}
	skill_cache = {}
	owned_cache = {}
	desc_cache = {}
end

-- version / commit ------------------------------------------------------
-- Để trả lời "tool đã cài có khớp clone không" mà KHÔNG cần mạng. Mọi dữ liệu đều nằm
-- sẵn trên đĩa; chỉ M.remote_head mới đi mạng và nó phải do người dùng chủ động gọi.

local function short(sha)
	return type(sha) == "string" and #sha >= 7 and sha:sub(1, 7) or nil
end

-- Clone dùng chung đang ở đâu. nil = chưa clone bao giờ.
---@return { version: string|nil, commit: string|nil, short: string|nil, branch: string|nil }|nil
function M.clone_info()
	local dir = M.dir()
	if not vim.uv.fs_stat(dir) then
		return nil
	end
	local info = {}
	local ok, lines = pcall(vim.fn.readfile, dir .. "/VERSION", "", 1)
	if ok and lines and lines[1] then
		info.version = vim.trim(lines[1])
	end
	-- Thiếu git thì chỉ mất phần commit, vẫn so được bằng version.
	if vim.fn.executable("git") == 1 then
		local function git(...)
			local r = vim.system({ "git", "-C", dir, ... }, { text = true }):wait(2000)
			return r.code == 0 and vim.trim(r.stdout or "") or nil
		end
		info.commit = git("rev-parse", "HEAD")
		info.short = short(info.commit)
		info.branch = git("rev-parse", "--abbrev-ref", "HEAD")
	end
	return info
end

-- ECC đã cài cho tool này ở phiên bản nào.
-- claude/opencode: installer ghi install-state.json có cả version lẫn commit.
-- codex: bản sync KHÔNG ghi state -> chỉ moi được version từ khối <!-- BEGIN ECC -->
-- trong ~/.codex/AGENTS.md, không có commit.
---@return { version: string|nil, commit: string|nil, short: string|nil, profile: string|nil, at: string|nil }|nil
function M.installed_info(tool)
	if tool == "codex" then
		local agents = home(".codex/AGENTS.md")
		local ok, lines = pcall(vim.fn.readfile, agents, "", 40)
		if not ok or not lines then
			return nil
		end
		local inside = false
		for _, l in ipairs(lines) do
			if l:find("BEGIN ECC", 1, true) then
				inside = true
			elseif l:find("END ECC", 1, true) then
				break
			elseif inside then
				local v = l:match("^%*%*Version:%*%*%s*(%S+)")
				if v then
					local st = vim.uv.fs_stat(home(".codex/prompts/ecc-prompts-manifest.txt"))
					return { version = v, at = st and os.date("%Y-%m-%d", st.mtime.sec) or nil }
				end
			end
		end
		return nil
	end

	local path = tool == "claude" and home(".claude/ecc/install-state.json")
		or tool == "opencode" and home(".opencode/ecc-install-state.json")
	local d = path and read_json(path)
	if not d then
		return nil
	end
	local src = type(d.source) == "table" and d.source or {}
	return {
		version = src.repoVersion,
		commit = src.repoCommit,
		short = short(src.repoCommit),
		profile = type(d.request) == "table" and d.request.profile or nil,
		at = type(d.installedAt) == "string" and d.installedAt:sub(1, 10) or nil,
	}
end

-- "missing" chưa cài | "current" khớp clone | "outdated" lệch | "unknown" không đủ dữ liệu.
-- So COMMIT trước vì đó là thứ chắc chắn; version chỉ đổi mỗi lần release nên hai commit
-- khác nhau vẫn có thể cùng version. Thiếu dữ kiện thì trả "unknown" chứ TUYỆT ĐỐI không
-- đoán thành "current": báo "up to date" sai còn tệ hơn nói không biết.
---@return "missing"|"current"|"outdated"|"unknown"
function M.status(tool)
	if not M.installed(tool) then
		return "missing"
	end
	local inst, clone = M.installed_info(tool), M.clone_info()
	if not (inst and clone) then
		return "unknown"
	end
	if inst.commit and clone.commit then
		return inst.commit == clone.commit and "current" or "outdated"
	end
	if inst.version and clone.version then
		return inst.version == clone.version and "current" or "outdated"
	end
	return "unknown"
end

-- HEAD của origin, KHÔNG fetch (ls-remote chỉ hỏi, không tải). Bất đồng bộ vì đã đo mất
-- ~1s - chặn UI chừng đó là thấy rõ. cb nhận short sha hoặc nil.
---@param cb fun(short: string|nil, err: string|nil)
function M.remote_head(cb)
	local dir = M.dir()
	if vim.fn.executable("git") ~= 1 or not vim.uv.fs_stat(dir) then
		cb(nil, "no git clone")
		return
	end
	vim.system({ "git", "-C", dir, "ls-remote", "origin", "HEAD" }, { text = true }, function(r)
		local sha = r.code == 0 and (r.stdout or ""):match("^(%x+)") or nil
		-- KHÔNG viết `sha and nil or err`: `sha and nil` ra nil (falsy) nên nhánh or
		-- luôn sập về err -> lấy được sha rồi mà vẫn báo lỗi. Đúng cái bẫy and/or đã
		-- ghi ở build_items ("all_dirs and nil or cwd"). Dùng if tường minh.
		local err
		if not sha then
			-- Luôn có nội dung: git hỏng mà stderr rỗng thì ít nhất còn exit code, chứ
			-- hiện "(github: )" trống trơn thì không lần ra được gì.
			err = vim.trim(r.stderr or "")
			if err == "" then
				err = ("exit %d"):format(r.code or -1)
			end
		end
		vim.schedule(function()
			cb(short(sha), err)
		end)
	end)
end

-- Binary cần có trước khi cài. Trả danh sách THIẾU (rỗng = đủ).
function M.missing_deps()
	local miss = {}
	for _, b in ipairs({ "git", "npm" }) do
		if vim.fn.executable(b) ~= 1 then
			miss[#miss + 1] = b
		end
	end
	return miss
end

-- Config của ECC cho opencode có bị pin model Anthropic không.
-- ECC ghi ~/.opencode/opencode.json với "model": "anthropic/claude-sonnet-4-5" ở cả
-- top-level lẫn CẢ 26 agent. opencode đọc file này thật (đã đo), nên không có tài
-- khoản Anthropic là hiện banner đỏ "Agent build's configured model ... is not valid"
-- và mọi command chạy qua agent của ECC đều hỏng. Trả về số chỗ bị pin.
---@return string|nil path, integer pinned
function M.anthropic_pins(tool)
	if tool ~= "opencode" then
		return nil, 0
	end
	local path = home(".opencode/opencode.json")
	local ok, data = pcall(vim.fn.readfile, path)
	if not ok or not data or #data == 0 then
		return nil, 0
	end
	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	if not ok or type(decoded) ~= "table" then
		return nil, 0
	end
	local n = 0
	for _, k in ipairs({ "model", "small_model" }) do
		if type(decoded[k]) == "string" and decoded[k]:match("^anthropic/") then
			n = n + 1
		end
	end
	for _, a in pairs(type(decoded.agent) == "table" and decoded.agent or {}) do
		if type(a) == "table" and type(a.model) == "string" and a.model:match("^anthropic/") then
			n = n + 1
		end
	end
	if n == 0 then
		return nil, 0
	end
	return path, n
end

-- Các lệnh shell để cài/cập nhật ECC cho tool. Chạy lại nhiều lần được (clone -> pull).
-- Trả về ĐÚNG chuỗi sẽ chạy, không rút gọn: hộp confirm hiện nguyên văn danh sách này.
---@param tool string
---@return string[]|nil, string|nil  -- steps, lý do khi không hỗ trợ
function M.steps(tool)
	local d = vim.fn.shellescape(M.dir())
	local repo = vim.fn.shellescape(M.config.repo)
	local prof = vim.fn.shellescape(M.config.profile)
	local steps = {
		-- Đặt đường dẫn vào biến $D thay vì lặp lại 4 lần: preview trong picker không
		-- wrap, một dòng 200 ký tự là đọc không nổi. Chạy vẫn y hệt cái hiện ra.
		("D=%s"):format(d),
		('if [ -d "$D/.git" ]; then git -C "$D" pull --ff-only; else git clone --depth 1 %s "$D"; fi'):format(repo),
		'cd "$D" && npm install --no-audit --no-fund',
	}
	local function add(s)
		steps[#steps + 1] = s
	end

	if tool == "claude" then
		add(('cd "$D" && ./install.sh --profile %s --target claude'):format(prof))
		-- ECC đang chuyển sang "skills-first" nên installer CÓ THỂ không đổ commands/
		-- ra nữa; README liệt kê dòng cp này như bước tương thích tuỳ chọn. Thiếu nó
		-- thì cài xong vẫn 0 command -> <leader>ai lặng lẽ quay về prompt viết tay.
		-- Chỉ chạy khi thư mục đang RỖNG: có sẵn command của bạn thì không đụng vào.
		add(
			'[ -n "$(ls -A ~/.claude/commands 2>/dev/null)" ] || '
				.. '{ mkdir -p ~/.claude/commands && cp "$D"/commands/*.md ~/.claude/commands/; }'
		)
	elseif tool == "codex" then
		-- Sync là đường ECC khuyến nghị cho codex; script tự backup có dấu thời gian
		-- rồi merge vào ~/.codex/AGENTS.md + config.toml. Không có tham số profile.
		-- Nó ghi thẳng ~/.codex/prompts nên không cần bước nối.
		add('cd "$D" && bash scripts/sync-ecc-to-codex.sh')
	elseif tool == "opencode" then
		-- install-apply.js nhận `--profile <name> --target opencode` cho MỌI profile
		-- (usage dòng 29), nên dùng chung M.config.profile như claude (giờ = developer).
		-- README chỉ nêu ví dụ full; developer là tập con hợp lệ, ít module hơn.
		add(('cd "$D" && npm run build:opencode && ./install.sh --profile %s --target opencode'):format(prof))
		-- VÁ CONFIG CỦA ECC. Hai lỗi trong ~/.opencode/opencode.json, mà opencode ĐỌC
		-- file đó thật (đã đo):
		--   1. model Anthropic pin cứng ở top-level + cả 26 agent -> không có tài khoản
		--      Anthropic là banner "configured model ... is not valid", và command nào
		--      chạy qua agent của ECC cũng hỏng. Xoá `model` thì thừa kế model đang dùng.
		--   2. skills.paths = ["../skills"] -> trỏ ~/skills, KHÔNG tồn tại; skill thật
		--      nằm ở ~/.opencode/skills. Ghi đường TUYỆT ĐỐI cho khỏi phụ thuộc cách
		--      opencode resolve tương đối.
		-- Dùng node (đã có sẵn vì bước npm ở trên cần), giữ backup .bak.
		add(table.concat({
			"node -e '",
			'const fs=require("fs"),os=require("os"),f=os.homedir()+"/.opencode/opencode.json";',
			'if(fs.existsSync(f)){fs.copyFileSync(f,f+".bak");',
			'const d=JSON.parse(fs.readFileSync(f,"utf8"));delete d.model;delete d.small_model;',
			"for(const a of Object.values(d.agent||{}))delete a.model;",
			'if(d.skills&&Array.isArray(d.skills.paths))d.skills.paths=[os.homedir()+"/.opencode/skills"];',
			"fs.writeFileSync(f,JSON.stringify(d,null,2))}",
			"'",
		}, ""))
	else
		return nil, ("ECC has no install target for '%s'"):format(tostring(tool))
	end
	return steps
end

-- Nơi tool đó ĐỌC command, để hiện trong preview/doctor.
function M.source_dirs(tool)
	local out = {}
	for _, s in ipairs(sources(tool)) do
		out[#out + 1] = s.dir
	end
	return out
end

-- Số command dò được (hiện ở menu trạng thái <leader>aE).
function M.count(tool)
	return vim.tbl_count(M.commands(tool))
end

return M
