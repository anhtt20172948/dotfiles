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
	profile = "minimal", -- profile cho install.sh (minimal = không có hooks-runtime)
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

-- Danh sách thư mục có thể chứa command, theo thứ tự ưu tiên. Trả cả thư mục KHÔNG
-- tồn tại: sig phải phân biệt được "chưa có" với "vừa tạo" thì cache mới tự hết hạn.
---@return { dir: string, prefix: string, invoke: string }[]
local function sources(tool)
	if tool == "claude" then
		local out = { { dir = home(".claude/commands"), prefix = "", invoke = "/%s" } }
		-- Đường plugin (/plugin install ecc@ecc) không phải đường mình cài, nhưng nếu
		-- người dùng đã cài kiểu đó thì vẫn nhận ra. Glob ĐỘ SÂU CỐ ĐỊNH, không đệ quy:
		-- ~/.claude/plugins có thể chứa node_modules, quét đệ quy ở đây là bẫy hiệu năng.
		for _, pat in ipairs({ ".claude/plugins/*/ecc", ".claude/plugins/*/*/ecc" }) do
			for _, d in ipairs(vim.fn.glob(home(pat) .. "/commands", false, true)) do
				out[#out + 1] = { dir = d, prefix = "", invoke = "/ecc:%s" }
			end
		end
		return out
	elseif tool == "codex" then
		return { { dir = home(".codex/prompts"), prefix = "ecc-", invoke = "/ecc-%s" } }
	elseif tool == "opencode" then
		-- ĐÃ ĐO trên máy này: opencode coi ~/.opencode LÀ một config root - gõ /code-rev
		-- trong TUI ra đủ autocomplete dù ~/.config/opencode không có thư mục command
		-- nào. Đó cũng là lý do `install.sh --target opencode` của ECC ghi vào đây.
		-- Vẫn giữ ~/.config/opencode (đường tài liệu ghi) cho ai tự chép sang.
		local c = config_home() .. "/opencode"
		return {
			{ dir = home(".opencode/commands"), prefix = "", invoke = "/%s" },
			{ dir = home(".opencode/command"), prefix = "", invoke = "/%s" },
			{ dir = c .. "/command", prefix = "", invoke = "/%s" },
			{ dir = c .. "/commands", prefix = "", invoke = "/%s" },
		}
	end
	return {}
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
---@param tool string
---@return table<string, string>
function M.commands(tool)
	local srcs = sources(tool)
	local sig = signature(srcs)
	local c = cache[tool]
	if c and c.sig == sig then
		return c.cmds
	end

	local cmds, paths = {}, {}
	for _, s in ipairs(srcs) do
		if vim.uv.fs_stat(s.dir) then
			-- Độ sâu 1: command của cả ba harness đều là file phẳng trong thư mục.
			for name, kind in vim.fs.dir(s.dir) do
				local base = kind == "file" and name:match("^(.*)%.md$")
				if base and (s.prefix == "" or base:sub(1, #s.prefix) == s.prefix) then
					local key = base:sub(#s.prefix + 1)
					-- Nguồn trước thắng: bản cài tay ưu tiên hơn bản plugin dò được.
					if key ~= "" and not cmds[key] then
						cmds[key] = s.invoke:format(key)
						paths[key] = s.dir .. "/" .. name
					end
				end
			end
		end
	end

	cache[tool] = { sig = sig, cmds = cmds, paths = paths }
	return cmds
end

-- Skill của ECC (thư mục con có SKILL.md). KHÁC command: skill là tài liệu hướng dẫn
-- nên áp được lên một đoạn code, còn command là quy trình cấp repo (xem M.command_list).
-- codex đọc skill từ ~/.agents/skills - bản sync KHÔNG đổ skill ra đó, nên codex thường
-- rỗng và caller tự rơi về prompt trơn.
---@return table<string, true>
function M.skills(tool)
	local dir = ({
		claude = home(".claude/skills"),
		opencode = home(".opencode/skills"),
		codex = home(".agents/skills"),
	})[tool]
	local st = dir and vim.uv.fs_stat(dir)
	local sig = dir .. ":" .. (st and st.mtime.sec or 0)
	local c = skill_cache[tool]
	if c and c.sig == sig then
		return c.set
	end
	local set = {}
	if st then
		for name, kind in vim.fs.dir(dir) do
			if kind == "directory" and vim.uv.fs_stat(dir .. "/" .. name .. "/SKILL.md") then
				set[name] = true
			end
		end
	end
	skill_cache[tool] = { sig = sig, set = set }
	return set
end

-- Danh sách command kèm mô tả, cho picker M.workflows(). Mô tả lấy từ frontmatter
-- `description:` - chỉ đọc HEAD_LINES dòng đầu mỗi file, đủ để qua frontmatter mà
-- không nuốt cả trăm file markdown vào RAM.
---@return { name: string, invoke: string, desc: string, path: string }[]
function M.command_list(tool)
	local cmds = M.commands(tool) -- nạp cache trước, cache[tool].paths có ngay sau đó
	local sig = cache[tool].sig
	local c = desc_cache[tool]
	if c and c.sig == sig then
		return c.list
	end
	local paths = cache[tool].paths or {}
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
		list[#list + 1] = { name = name, invoke = invoke, desc = desc, path = path }
	end
	table.sort(list, function(a, b)
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
	desc_cache = {}
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
		-- README chỉ ghi ĐÚNG một dòng cho target này và nó là --profile full; không
		-- có tài liệu cho minimal --target opencode nên giữ nguyên full, và hộp
		-- confirm phải nói rõ chỗ lệch này thay vì đổi ngầm.
		add('cd "$D" && npm run build:opencode && ./install.sh --profile full --target opencode')
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
