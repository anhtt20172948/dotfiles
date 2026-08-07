-- AI terminal (tmux-style): chạy Codex / Claude / opencode trong một vsplit phải.
-- Nhiều session mỗi tool (codex-1, codex-2, claude-1...). Picker <leader>aa liệt kê:
--   ● live    session đang chạy trong nvim  -> attach
--    past    session CŨ trên đĩa của cwd   -> resume (đọc từ customize.aiterm_history)
--    new     tạo session mới
--    browse  fallback: gọi picker của chính tool (claude --resume, codex resume)
--
-- Keybindings ngoài picker:
--   <C-Space> (trong AI pane) -> quay lại code (pane vẫn mở, session vẫn chạy)
--   <C-w>p    (trong editor)  -> attach/focus AI pane (session gần nhất)
--
-- !! ICON: file này KHÔNG chứa glyph thô, tất cả dựng từ CODEPOINT !!
-- Glyph PUA thô bị huỷ mỗi lần file đi qua một vòng copy/encode. Đã xảy ra 2 lần:
-- U+F0D0 biến thành U+EE0D (codepoint không có trong font -> ô vuông), còn các
-- icon khác rụng sạch thành dấu cách trắng. Source chỉ có ASCII thì không hỏng
-- được nữa - xem M.icon_sets bên dưới.
local M = {}

-- Dựng chuỗi từ danh sách codepoint.
local function c(...)
	local out = {}
	for _, cp in ipairs({ ... }) do
		out[#out + 1] = vim.fn.nr2char(cp)
	end
	return table.concat(out)
end

-- Ba bộ icon, chọn bằng M.config.icon_style:
--   nerd    - glyph Nerd Font. CHỈ dùng codepoint <= U+FFFF (PUA U+E000-U+F8FF):
--             'SFMono Nerd Font' là patch Nerd Fonts v2, cmap chỉ tới U+FD46, nên
--             mọi glyph MDI-v3 kiểu U+F0xxx rơi xuống fallback font khác ->
--             khác typeface, khác advance width, nhìn lệch hẳn.
--   unicode - Geometric Shapes + Arrows, có trong gần như mọi font monospace.
--             Dùng khi terminal/SSH không có Nerd Font.
--   ascii   - thuần ASCII, chạy được ở mọi nơi kể cả Linux console.
-- Cả ba bộ đều đã kiểm nvim_strwidth == 1 cho từng glyph (ambiwidth=single) nên
-- đổi bộ không làm lệch cột.
M.icon_sets = {
	nerd = {
		claude = c(0xF0D0), -- magic
		codex = c(0xF121), -- code
		opencode = c(0xF489), -- terminal
		live = c(0x25CF), -- ●
		past = c(0xF1DA), -- history
		new = c(0xF067), -- plus
		browse = c(0xF002), -- search
		install = c(0xF019), -- download
		ecc = c(0xF1B2), -- cube (bộ skill/command của ECC)
		branch = c(0xF418), -- git-branch
		all_dirs = c(0xF07C), -- folder-open
		-- icon từng field của preview (f_ = field)
		f_model = c(0xF2DB), -- microchip
		f_tokens = c(0xF1C0), -- database
		f_cost = c(0xF155), -- dollar
		f_updated = c(0xF017), -- clock
		f_created = c(0xF073), -- calendar
		f_version = c(0xF02B), -- tag
		f_agent = c(0xF007), -- user
		f_id = c(0xF292), -- hashtag
		f_cwd = c(0xF07B), -- folder
		f_prompt = c(0xF075), -- comment
		f_cmd = c(0xF120), -- terminal
		-- action icon (dùng ở inlay hint + menu <leader>ai). Toàn Font-Awesome cổ
		-- điển U+F0xx (<= U+F0C3) nên chắc chắn nằm trong cmap SFMono NF v2.
		explain = c(0xF05A), -- info-circle
		ask = c(0xF059), -- question-circle
		fix = c(0xF0AD), -- wrench
		review = c(0xF06E), -- eye
		tests = c(0xF0C3), -- flask
		refactor = c(0xF021), -- refresh
		docs = c(0xF02D), -- book
		security = c(0xF132), -- shield
		plan = c(0xF0AE), -- tasks
		quality = c(0xF14A), -- check-square
		star = c(0xF005), -- fa-star (favorites/pin)
	},
	-- Bộ "chạy mọi nơi": MỌI codepoint dưới đây đã kiểm có trong CẢ SFMono NF lẫn
	-- JetBrainsMono NF. Cẩn thận khi đổi: nvim_strwidth trả 1 kể cả với glyph font
	-- KHÔNG có (nó chỉ tra bảng width của Unicode, không tra cmap) nên đo strwidth
	-- KHÔNG đủ để kết luận. Bản trước có 5 icon thiếu font đúng vì lý do này:
	-- ◆ U+25C6, ◼ U+25FC, ↺ U+21BA, ↳ U+21B3, ▤ U+25A4 đều KHÔNG có trong SFMono.
	unicode = {
		claude = c(0x25CE), -- ◎
		codex = c(0x25A1), -- □
		opencode = c(0x25B2), -- ▲
		live = c(0x25CF), -- ●
		past = c(0x2022), -- •
		new = "+",
		browse = c(0x00BB), -- »
		-- KHÔNG dùng U+26A0 warning: đã kiểm là THIẾU trong SFMono NF.
		install = c(0x2193), -- ↓
		ecc = c(0x2318), -- ⌘
		branch = "*", -- git hay đánh dấu nhánh hiện tại bằng *
		all_dirs = c(0x00A4), -- ¤
		-- Field trong preview đã có NHÃN CHỮ bên cạnh nên icon chỉ là dấu dẫn:
		-- dùng chung một ký tự trung tính, hơn là bịa 11 ký hiệu khó đoán.
		f_model = c(0x00B7), -- ·
		f_tokens = c(0x00B7),
		f_cost = c(0x00B7),
		f_updated = c(0x00B7),
		f_created = c(0x00B7),
		f_version = c(0x00B7),
		f_agent = c(0x00B7),
		f_id = c(0x00B7),
		f_cwd = c(0x00B7),
		f_prompt = c(0x00B7),
		f_cmd = c(0x203A), -- ›
		explain = c(0x00A7), -- §
		ask = "?",
		fix = c(0x00B1), -- ±
		review = c(0x25CB), -- ○
		tests = c(0x2713), -- ✓
		refactor = c(0x2192), -- →
		docs = c(0x2261), -- ≡
		security = c(0x2020), -- †
		plan = c(0x00B6), -- ¶
		quality = c(0x25A0), -- ■
		star = c(0x2605), -- ★ (width-1 dưới ambiwidth=single)
	},
	ascii = {
		claude = "C",
		codex = "X",
		opencode = "O",
		live = "*",
		past = "~",
		new = "+",
		browse = "?",
		install = "!",
		ecc = "E",
		branch = "*",
		all_dirs = "/",
		f_model = "-",
		f_tokens = "-",
		f_cost = "-",
		f_updated = "-",
		f_created = "-",
		f_version = "-",
		f_agent = "-",
		f_id = "-",
		f_cwd = "-",
		f_prompt = "-",
		f_cmd = ">",
		explain = "i",
		ask = "?",
		fix = "!",
		review = "o",
		tests = "v",
		refactor = "~",
		docs = "=",
		security = "S",
		plan = "P",
		quality = "Q",
		star = "*",
	},
}

-- Bộ icon đang dùng. "auto" -> theo vim.g.have_nerd_font (chưa set thì coi như có).
function M.icons()
	local style = M.config.icon_style
	if style == "auto" or style == nil then
		style = vim.g.have_nerd_font == false and "unicode" or "nerd"
	end
	return M.icon_sets[style] or M.icon_sets.nerd
end

-- Icon của tool, tra theo tên tool. Không lưu glyph trong M.config.tools nữa.
local function tool_icon(tool)
	return M.icons()[tool.name] or ""
end

M.config = {
	icon_style = "auto", -- "auto" | "nerd" | "unicode" | "ascii"
	tools = {
		{
			name = "claude",
			cmd = "claude",
			-- PATH của nvim cố định từ lúc khởi động -> cài xong mà thư mục đích
			-- không có trong PATH thì executable() vẫn báo không có tới khi restart.
			-- path là fallback để tool_cmd() nhận ra ngay sau khi cài.
			path = vim.fn.expand("~/.local/bin/claude"),
			install = "curl -fsSL https://claude.ai/install.sh | bash",
			-- icon tra tu M.icons()[name], KHONG luu glyph o day (xem dau file).
			resume = function(id)
				return { "--resume", id }
			end,
			fork = function(id)
				return { "--resume", id, "--fork-session" }
			end,
			-- prompt truyền NGAY lúc launch -> M.send không phải paste vào TUI đang
			-- boot (xem M.send). claude: positional, vẫn giữ chế độ tương tác.
			prompt_args = function(text)
				return { text }
			end,
			browse = { "--resume" }, -- picker tương tác của chính claude
			browse_label = "claude's own picker",
		},
		{
			name = "codex",
			cmd = "codex",
			path = vim.fn.expand("~/.local/bin/codex"),
			install = "curl -fsSL https://chatgpt.com/codex/install.sh | sh",
			-- icon tra tu M.icons()[name], KHONG luu glyph o day (xem dau file).
			resume = function(id)
				return { "resume", id }
			end,
			fork = function(id)
				return { "fork", id }
			end,
			prompt_args = function(text) -- codex: positional [PROMPT]
				return { text }
			end,
			browse = { "resume" },
			browse_label = "codex's own picker",
		},
		{
			name = "opencode",
			cmd = "opencode",
			-- ~/.zshrc thêm ~/.opencode/bin vào PATH, nhưng nvim mở từ GUI/launchd
			-- thì không có -> path làm fallback cho tool_cmd(). Đã đo: PATH của nvim
			-- KHÔNG có ~/.opencode/bin, nên riêng opencode phải dựa vào path này.
			path = vim.fn.expand("~/.opencode/bin/opencode"),
			install = "curl -fsSL https://opencode.ai/install | bash",
			-- icon tra tu M.icons()[name], KHONG luu glyph o day (xem dau file).
			resume = function(id)
				return { "--session", id }
			end,
			fork = function(id)
				return { "--session", id, "--fork" }
			end,
			prompt_args = function(text) -- opencode: qua flag, không phải positional
				return { "--prompt", text }
			end,
			-- opencode KHÔNG có CLI picker (chỉ `session list|delete`) -> fallback là --continue
			browse = { "--continue" },
			browse_label = "resume most recent",
		},
	},
	win = { width = 0.4 }, -- tỉ lệ rộng của vsplit
	start_insert = true,
	history = { scope = "cwd" }, -- scope mặc định của picker: "cwd" | "all"

	-- Gửi context (file/selection + instruction) vào session đang chạy. Xem M.actions().
	--   default_tools - CHUỖI ưu tiên khi CHƯA có session sống: chọn tool ĐÃ CÀI đầu
	--                   tiên. Ghi đè phiên/lâu dài qua M.set_default_tool (<leader>aD).
	--   ready         - phát hiện session vừa tạo "sẵn sàng" (terminal vẽ xong + im)
	--                   trước lần gửi đầu, thay cho delay cố định (hay miss request).
	--                   min_ms sàn boot, quiet_ms im bao lâu thì coi là xong, max_ms
	--                   trần fallback, interval_ms nhịp poll.
	--   submit_delay  - ms giữa lúc dán xong và lúc gửi <CR>; cho TUI (Ink/React của
	--                   claude) kịp xử lý bracketed-paste trước khi Enter submit.
	send = {
		default_tools = { "codex", "opencode", "claude" },
		-- Trên ngưỡng này thì message không nhét vào argv được nữa -> quay về đường
		-- tạo-session-rồi-paste. ARG_MAX của macOS là 1048576; chọn 344 dòng code
		-- mới ~15KB nên hiếm khi chạm.
		max_arg_bytes = 100000,
		-- CHỈ dùng cho đường DỰ PHÒNG (paste vào session đang boot). Đường chính là
		-- tool.prompt_args: nhúng prompt vào lệnh launch nên không có đua tranh.
		-- Đừng tưởng đây là cơ chế chính rồi đi tinh chỉnh số: heuristic quiescence
		-- về bản chất không phân biệt được "TUI xong rồi" với "đang lặng giữa lúc
		-- boot" - đó chính là lỗi làm mất request với opencode.
		ready = { min_ms = 800, quiet_ms = 1200, max_ms = 10000, interval_ms = 120 },
		submit_delay = 120,
		-- Tool nào CHẠY được /slash command của ECC natively. codex 0.146 KHÔNG bung
		-- ~/.codex/prompts/*.md thành /command (đã đo: "Unrecognized command"; chính
		-- CODEX-NAVIGATION-GUIDE của ECC cũng ghi "may not execute slash commands
		-- natively ... read the command file"). false -> M.workflows() DÁN NỘI DUNG
		-- file lệnh thay cho /token. Tool không có trong bảng coi như native.
		slash_native = { claude = true, opencode = true, codex = false },
	},

	-- Node treesitter coi là "khối code" để lấy làm context ở normal mode. Khớp
	-- theo SUBSTRING type nên phủ nhiều ngôn ngữ mà không cần query riêng từng ngôn
	-- ngữ (function_declaration, method_definition, class_specifier, struct_specifier...).
	ts_node_types = { "function", "method", "class", "struct", "constructor", "impl" },

	-- Inlay hint trên code buffer (kiểu code-lens của CodeCompanion): 1 dòng ảo phía
	-- trên function/class ĐANG chứa con trỏ. Badge = icon+tên tool mặc định (tô màu
	-- theo tool) + vài action có icon + phím tắt mờ. actions là danh sách action.key
	-- muốn quảng cáo; icon tra M.icons() nên tự xuống chữ ở style unicode/ascii.
	hints = {
		enabled = true,
		actions = { "explain", "fix", "tests" },
		key = "<leader>ai",
	},

	-- Preset cho picker M.actions(). `key` khớp icon trong M.icons() (hiện icon ở
	-- menu + hint). `prompt` là câu lệnh cố định; `input` (nếu có) hỏi câu hỏi tự do
	-- qua vim.fn.input rồi dùng thay cho prompt.
	--
	-- `skill` (tuỳ chọn) là SKILL của ECC khớp với việc đó. Lúc gửi sẽ dò trên đĩa
	-- (aiterm_ecc.skills): có thì chèn thêm dòng "Follow the `x` skill.", không có thì
	-- gửi đúng `prompt` như cũ. Message vẫn kèm @ref + khối code như thường.
	--
	-- Vì sao KHÔNG dùng command của ECC ở đây: command là quy trình CẤP REPO -
	-- /code-review chạy `git diff --name-only HEAD`, /build-fix chạy `npx tsc --noEmit`,
	-- /refactor-clean chạy `npx knip` - chúng bỏ qua hoàn toàn đoạn code đang chọn.
	-- Chúng nằm ở M.workflows() (<leader>aw), nơi gửi không kèm context.
	--
	-- Vì sao chỉ 3 action có `skill`: đã đọc mô tả cả 207 skill, không có cái nào cho
	-- "explain đoạn này" / "review đoạn này" / "viết docstring". code-tour là tạo file
	-- .tour, plankton-code-quality là chạy formatter lúc ghi file, plan-canvas là mở
	-- plan trong browser. Gán bừa chỉ làm prompt tệ đi.
	actions = {
		{ key = "explain", label = "Explain", prompt = "Explain what this code does, step by step." },
		{ key = "ask", label = "Ask a question", input = "Ask about this code: " },
		{ key = "fix", label = "Fix bugs", prompt = "Find and fix any bugs in this code. Explain the fix." },
		{
			key = "review",
			label = "Review",
			prompt = "Review this code for correctness, edge cases, and style issues.",
		},
		{
			key = "tests",
			label = "Write tests",
			prompt = "Write tests for this code.",
			skill = "tdd-workflow",
		},
		{
			key = "refactor",
			label = "Refactor",
			prompt = "Refactor this code to be clearer and more idiomatic, without changing its behavior.",
		},
		{ key = "docs", label = "Add docs", prompt = "Add documentation/docstrings to this code." },
		{
			key = "security",
			label = "Security scan",
			prompt = "Audit this code for security vulnerabilities. Report severity and a fix for each.",
			skill = "security-review",
		},
		{
			key = "plan",
			label = "Plan",
			prompt = "Write an implementation plan for a change to this code. Do not write code yet.",
		},
		{
			key = "quality",
			label = "Quality gate",
			prompt = "Run the quality checks for this code: lint, types, tests. Report what fails.",
			skill = "verification-loop",
		},
	},

	-- Ngoại lệ khi gửi command ECC ở M.workflows(). Mặc định gửi trơn "/tên".
	--   path - lệnh nhận đường dẫn (`/quality-gate [path|.]`) -> thêm "."
	--   ask  - lệnh nhận mô tả tự do qua $ARGUMENTS -> hỏi vim.fn.input
	workflow_args = {
		path = { "quality-gate", "security-scan" },
		ask = { plan = "Plan what? ", ["plan-prd"] = "PRD for: ", tdd = "TDD for: " },
	},
}

-- state ------------------------------------------------------------------
local win = nil -- handle vsplit dùng chung (một pane, swap buffer)
local sessions = {} -- array: { id, tool, buf, job, cwd, title, label }
local counters = {} -- tool.name -> số đếm để đặt id
local last_session = nil -- id session attach gần nhất

local function history()
	return require("customize.aiterm_history")
end

-- ECC module là TUỲ CHỌN: thiếu/ lỗi thì nhớ lỗi và trả nil (không dò lại mỗi lần).
-- Mọi caller đều suy biến thành "không có ECC" thay vì làm vỡ picker/doctor.
local ecc_mod, ecc_err
local function ecc()
	if ecc_mod or ecc_err then
		return ecc_mod
	end
	-- pcall trả (ok, kết quả) - gán thẳng vào (ecc_mod, ecc_err) là ecc_mod nhận đúng
	-- cờ boolean `true`, rồi mọi caller đi index một boolean. Phải tách hai biến ra.
	local ok, mod = pcall(require, "customize.aiterm_ecc")
	if ok then
		ecc_mod = mod
	else
		ecc_err = true
	end
	return ecc_mod
end

-- helpers ----------------------------------------------------------------
local function win_valid()
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

-- 0.11-safe: ưu tiên jobstart{term=true}, fallback termopen ở bản cũ.
-- cmd là LIST (không qua shell) -> session id / path chứa space, quote đều an toàn.
local function start_term(buf, cmd, cwd)
	return vim.api.nvim_buf_call(buf, function()
		local o = { term = true, cwd = cwd }
		if vim.fn.has("nvim-0.11") == 1 then
			return vim.fn.jobstart(cmd, o)
		end
		return vim.fn.termopen(cmd, o)
	end)
end

local function find_tool(name)
	for _, t in ipairs(M.config.tools) do
		if t.name == name then
			return t
		end
	end
end

-- Binary trong PATH; nếu không có thì thử tool.path (xem comment ở opencode).
local function tool_cmd(tool)
	if vim.fn.executable(tool.cmd) == 1 then
		return tool.cmd
	end
	if tool.path and vim.fn.executable(tool.path) == 1 then
		return tool.path
	end
	return nil
end

-- Terminal-mode: <C-Space> (và alias <C-@>/<Nul> mà kitty đôi khi gửi) để quay lại
-- code. rhs dùng noremap nên <C-w>p ở đây là builtin previous-window (về code),
-- KHÔNG vòng lại global map <C-w>p. <Esc>/<Space>/<C-w> vẫn truyền thẳng vào AI app.
local function set_term_keymaps(buf)
	local o = { buffer = buf, silent = true, nowait = true }
	vim.keymap.set("t", "<C-Space>", [[<C-\><C-n><C-w>p]], o)
	vim.keymap.set("t", "<C-@>", [[<C-\><C-n><C-w>p]], o)
end

local function is_alive(s)
	return s ~= nil and s.buf and vim.api.nvim_buf_is_valid(s.buf) and s.job and vim.fn.jobwait({ s.job }, 0)[1] == -1
end

local function find(id)
	for _, s in ipairs(sessions) do
		if s.id == id then
			return s
		end
	end
end

local function remove_session(id)
	for i, s in ipairs(sessions) do
		if s.id == id then
			table.remove(sessions, i)
			return
		end
	end
end

local function notify(msg, level)
	if _G.Snacks and Snacks.notifier then
		Snacks.notifier.notify(msg, level, { title = "AI terminal" })
	else
		vim.notify(msg, vim.log.levels[level:upper()] or vim.log.levels.INFO)
	end
end

-- window (vsplit phải) ---------------------------------------------------
local function open_split(buf)
	vim.cmd("botright vsplit") -- pane full-height sát mép phải
	win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * M.config.win.width))
	vim.wo[win].winfixwidth = true -- neo-tree mở không bóp méo pane AI
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
end

-- Reuse pane (swap buffer) nếu còn; nếu không thì mở split mới. Cập nhật winbar nhãn.
local function ensure_win(buf, label)
	if win_valid() then
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_set_current_win(win)
	else
		open_split(buf)
	end
	pcall(function()
		vim.wo[win].winbar = "%=" .. label .. "%="
	end)
end

-- session lifecycle ------------------------------------------------------

-- id session vẫn là "<tool>-<n>": uuid 36 ký tự làm buffer name / winbar không
-- dùng được. Phần người-đọc-được nằm ở session.label (winbar) và session.title.
---@param tool table
---@param opts? { args?: string[], cwd?: string, title?: string, cmd?: string[], on_exit?: fun(code:number) }
local function new_session(tool, opts)
	opts = opts or {}

	-- jobstart throw E475 nếu cwd không tồn tại (session cũ của repo đã xoá).
	local cwd = opts.cwd
	if cwd and not vim.uv.fs_stat(cwd) then
		notify(("cwd no longer exists: %s"):format(cwd), "warn")
		cwd = nil
	end

	-- opts.cmd: argv tuỳ ý, BỎ QUA tool_cmd và guard binary-not-found. Chỉ dùng
	-- cho install (lúc đó binary của tool chưa tồn tại là chuyện đương nhiên).
	local cmd
	if opts.cmd then
		cmd = opts.cmd
	else
		local exe = tool_cmd(tool)
		if not exe then
			notify(("binary '%s' not found in PATH"):format(tool.cmd), "warn")
			return nil
		end
		cmd = { exe }
		vim.list_extend(cmd, opts.args or {})
	end

	counters[tool.name] = (counters[tool.name] or 0) + 1
	local id = tool.name .. "-" .. counters[tool.name]

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide"
	local ok, job = pcall(start_term, buf, cmd, cwd)
	if not ok or type(job) ~= "number" or job <= 0 then
		notify(("failed to start: %s"):format(table.concat(cmd, " ")), "error")
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return nil
	end
	pcall(vim.api.nvim_buf_set_name, buf, "aiterm://" .. id)

	local session = {
		id = id,
		tool = tool,
		buf = buf,
		job = job,
		cwd = cwd,
		title = opts.title,
		label = tool_icon(tool) .. " " .. id .. (opts.title and (" · " .. opts.title) or ""),
	}
	sessions[#sessions + 1] = session
	-- set_term_keymaps ở đây -> mọi đường (new/resume/fork/browse) đều có <C-Space>.
	set_term_keymaps(buf)

	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		once = true,
		callback = function()
			remove_session(id)
			if opts.on_exit then
				-- vim.v.event.status = exit code của tiến trình vừa kết thúc.
				opts.on_exit(tonumber(vim.v.event.status) or 0)
			end
		end,
	})

	return session
end

local function attach(session)
	if not session then
		return
	end
	ensure_win(session.buf, session.label or (tool_icon(session.tool) .. " " .. session.id))
	last_session = session.id
	if M.config.start_insert then
		vim.cmd("startinsert")
	end
end

-- Cài tool chưa có. tool.install là lệnh SHELL (có pipe) nên phải chạy qua shell.
-- Đây là tải script từ mạng về chạy trực tiếp -> LUÔN hiện nguyên câu lệnh và hỏi
-- xác nhận, mặc định No: một lần bấm nhầm trong picker rất khó hoàn tác.
-- Chạy trong pane AI (không chạy ngầm) để đọc được output và lỗi.
local function install_tool(tool)
	if not tool or not tool.install then
		notify(("no install script configured for '%s'"):format(tool and tool.name or "?"), "warn")
		return
	end
	local prompt = ("Install %s?\n\n%s\n\nThis downloads and runs a remote script."):format(tool.name, tool.install)
	if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
		return
	end
	attach(new_session(tool, {
		-- argv tường minh { shell, -c, lệnh } thay vì truyền string thẳng, để giữ
		-- đúng hợp đồng "cmd là list" của start_term.
		cmd = { vim.o.shell, "-c", tool.install },
		cwd = history().project_cwd(),
		title = "install",
		on_exit = function(code)
			if code == 0 then
				notify(("%s installed - reopen the picker to use it"):format(tool.name), "info")
			else
				notify(("%s install failed (exit %d) - see the pane output"):format(tool.name, code), "warn")
			end
		end,
	}))
end

-- Cài/cập nhật ECC cho một tool. Rủi ro cao hơn install_tool: clone repo bên thứ ba,
-- `npm install` chạy lifecycle script tuỳ ý, rồi installer GHI vào ~/.claude / ~/.codex
-- (bản sync codex còn sửa AGENTS.md + config.toml, có backup dấu thời gian). Vì vậy
-- hiện NGUYÊN danh sách lệnh, confirm mặc định No, chạy trong pane để đọc được output.
local function install_ecc(tool)
	if not tool then
		return
	end
	local e = ecc()
	if not e then
		notify("ECC module unavailable - cannot install", "warn")
		return
	end
	local steps, why = e.steps(tool.name)
	if not steps then
		notify(why or "ECC install not supported here", "warn")
		return
	end
	local miss = e.missing_deps()
	if #miss > 0 then
		notify(("ECC needs %s on PATH - install %s first"):format(table.concat(miss, " + "), miss[1]), "warn")
		return
	end

	local lines = { ("Install ECC for %s?"):format(tool.name), "" }
	vim.list_extend(lines, steps)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "This clones a third-party repo and runs its installer."
	if tool.name == "opencode" then
		-- Không đổi ngầm: profile cấu hình là minimal nhưng README của ECC chỉ ghi
		-- --profile full cho target opencode.
		lines[#lines + 1] = ("Note: opencode uses --profile full (config profile is %s)."):format(e.config.profile)
	end
	if vim.fn.confirm(table.concat(lines, "\n"), "&Yes\n&No", 2) ~= 1 then
		return
	end

	attach(new_session(tool, {
		cmd = { vim.o.shell, "-c", table.concat(steps, " && ") },
		cwd = history().project_cwd(),
		title = "ecc",
		on_exit = function(code)
			e.refresh() -- dò lại đĩa: dòng picker biến mất, action bắt đầu dùng /command
			if code == 0 then
				notify(("ECC installed for %s (%d commands)"):format(tool.name, e.count(tool.name)), "info")
			else
				notify(("ECC install failed (exit %d) - see the pane output"):format(code), "warn")
			end
		end,
	}))
end

-- codex archive HOÀN TÁC được (codex unarchive); opencode session delete và xoá
-- file jsonl của claude thì KHÔNG -> caller phải confirm trước khi gọi.
local function delete_entry(tool, e)
	local exe = tool_cmd(tool)
	if tool.name == "codex" then
		return exe ~= nil and vim.system({ exe, "archive", e.id }, { text = true }):wait(5000).code == 0
	elseif tool.name == "opencode" then
		return exe ~= nil and vim.system({ exe, "session", "delete", e.id }, { text = true }):wait(5000).code == 0
	elseif e.jsonl then
		return vim.fn.delete(e.jsonl) == 0 -- claude không có CLI delete
	end
	return false
end

-- picker -----------------------------------------------------------------
-- hl group của từng kind; glyph lấy từ M.icons() lúc render (không hardcode).
local KIND_HL = {
	live = "SnacksPickerGitStatusStaged",
	past = "SnacksPickerTime",
	new = "SnacksPickerLabel",
	browse = "SnacksPickerSpecial",
	install = "DiagnosticWarn", -- amber, khác hẳn mọi màu khác trong dòng
	ecc = "SnacksPickerSpecial", -- không phải cảnh báo: tool vẫn chạy tốt khi thiếu ECC
}

-- Cột tool bên trái: "opencode" (8) + icon (1) + dấu cách (1) = 10, chừa 1 cột đệm.
local TOOL_W = 11
-- Phần đầu dòng trước title: icon kind (2 cột) + cột tool + 1 cột đệm.
local LEAD_W = 2 + TOOL_W + 1

-- Màu riêng cho từng tool. Dùng LINK tới nhóm ngữ nghĩa chứ không hardcode hex:
-- đổi colorscheme là tự đúng theo theme mới.
-- Đã đo dưới catppuccin mocha + color_overrides của repo: Constant/String/Keyword
-- ra 3 màu khác hẳn nhau (peach / mint / mauve). CẨN THẬN khi đổi - rất nhiều
-- nhóm trông có vẻ khác nhau nhưng lại trùng màu: GitBranch, Cmd, Directory,
-- Function, Title đều ra #7aa2f8; Time, Label, Special đều ra #ff79c7; còn
-- SnacksPickerBold thì không có fg nên không dùng làm màu được.
local TOOL_HL = { claude = "AitermClaude", codex = "AitermCodex", opencode = "AitermOpencode" }

-- Snacks.util.set_hl tự đăng ký augroup ColorScheme để set lại nên KHÔNG cần tự
-- viết autocmd. Không truyền default = true (group `default` bị colorscheme ghi đè).
-- Gọi lazy vì lúc require module này Snacks có thể chưa load.
local hl_done = false
local function ensure_hl()
	if hl_done or not (_G.Snacks and Snacks.util) then
		return
	end
	hl_done = true
	Snacks.util.set_hl({
		AitermClaude = "Constant", -- peach
		AitermCodex = "String", -- mint
		AitermOpencode = "Keyword", -- mauve
	})
end

local function cmdline(tool, args)
	local parts = { tool.cmd }
	vim.list_extend(parts, args or {})
	return table.concat(parts, " ")
end

-- 22017 -> "22,017"
local function commafy(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Bảng dựng preview: mỗi dòng là "<icon> <nhãn canh cột> <giá trị>", kèm extmark
-- tô màu icon + nhãn. snacks nhận item.preview.extmarks (picker/preview.lua) với
-- row 1-indexed, col 0-indexed tính theo BYTE.
local LABEL_W = 9

local function new_doc()
	return { lines = {}, marks = {} }
end

local function doc_raw(d, text)
	d.lines[#d.lines + 1] = text or ""
end

-- Bỏ qua hẳn dòng nếu value rỗng -> tool nào không có field thì không hiện, không
-- bịa "n/a". col tính bằng #s (byte) chứ không phải strwidth: icon là multibyte.
local function doc_row(d, icon, label, value, icon_hl)
	if value == nil or value == "" then
		return
	end
	local ic = M.icons()[icon] or " "
	local pad = string.rep(" ", math.max(1, LABEL_W - vim.api.nvim_strwidth(label)))
	local line = (" %s %s%s%s"):format(ic, label, pad, value)
	d.lines[#d.lines + 1] = line
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 1, end_col = 1 + #ic, hl_group = icon_hl or "SnacksPickerSpecial" }
	d.marks[#d.marks + 1] = { row = row, col = 2 + #ic, end_col = 2 + #ic + #label, hl_group = "SnacksPickerDimmed" }
end

local function doc_title(d, icon, text, icon_hl)
	local ic = M.icons()[icon] or " "
	d.lines[#d.lines + 1] = (" %s %s"):format(ic, text)
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 1, end_col = 1 + #ic, hl_group = icon_hl or "SnacksPickerSpecial" }
	d.marks[#d.marks + 1] = { row = row, col = 2 + #ic, end_col = #d.lines[row], hl_group = "SnacksPickerBold" }
end

local function doc_section(d, icon, text)
	doc_raw(d, "")
	local ic = M.icons()[icon] or " "
	d.lines[#d.lines + 1] = (" %s %s"):format(ic, text)
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 0, end_col = #d.lines[row], hl_group = "SnacksPickerLabel" }
end

-- Khối chữ thụt lề (prompt, mô tả). Nhận list dòng hoặc string.
local function doc_block(d, text, hl)
	local lines = type(text) == "table" and text or vim.split(tostring(text), "\n", { plain = true })
	for _, s in ipairs(lines) do
		d.lines[#d.lines + 1] = "    " .. s
		d.marks[#d.marks + 1] =
			{ row = #d.lines, col = 0, end_col = #d.lines[#d.lines], hl_group = hl or "SnacksPickerCode" }
	end
end

local function doc_done(d)
	return { text = table.concat(d.lines, "\n"), extmarks = d.marks }
end

-- Preview build ngay trong finder (dữ liệu đã có sẵn trong RAM từ discovery)
-- -> không đọc lại file jsonl 5 MB khi di chuyển con trỏ.
-- Nhãn + màu + động từ theo trạng thái ECC. "current" thì <CR> là CÀI LẠI chứ không
-- phải cập nhật; nói đúng để không mất vài phút chạy lại quy trình mà tưởng đang có
-- việc cần làm.
local ECC_STATE = {
	current = { "up to date", "SnacksPickerGitStatusStaged", "reinstall" },
	outdated = { "OUTDATED", "DiagnosticWarn", "update" },
	missing = { "not installed", "SnacksPickerDimmed", "install" },
	unknown = { "unknown", "SnacksPickerDimmed", "reinstall" },
}

-- Preview cho M.ecc. Nhận clone/remote qua tham số thay vì tự đọc: finder gọi nó nhiều
-- lần, mà clone_info() có spawn git - đọc lại mỗi dòng là phí.
local function ecc_preview(item, e, clone, remote)
	local d = new_doc()
	local s = ECC_STATE[item.state] or ECC_STATE.unknown
	local i = item.info
	doc_title(d, "ecc", ("ECC · %s"):format(item.tool.name), TOOL_HL[item.tool.name])
	doc_row(d, "f_updated", "status", s[1], s[2])
	doc_row(d, "f_version", "version", i and i.version)
	doc_row(d, "f_id", "commit", i and i.short)
	doc_row(d, "f_agent", "profile", i and i.profile)
	doc_row(d, "f_created", "since", i and i.at)
	doc_row(d, "f_cmd", "commands", tostring(item.cmds))
	doc_row(d, "f_prompt", "skills", tostring(item.skills))
	doc_row(d, "f_cwd", "reads", vim.fn.fnamemodify(e.source_dirs(item.tool.name)[1] or "?", ":~"))
	doc_section(d, "f_version", "Clone")
	doc_block(d, {
		clone and ("%s · %s (%s)"):format(clone.version or "?", clone.short or "?", clone.branch or "?")
			or "not cloned yet",
		vim.fn.fnamemodify(e.dir(), ":~"),
		remote and ("origin: " .. remote) or "origin: press <A-u> to ask GitHub",
	}, "SnacksPickerDimmed")
	doc_section(d, "f_cmd", ("Commands to run (%s)"):format(s[3]))
	doc_block(d, e.steps(item.tool.name) or { "(unsupported target)" })
	return doc_done(d)
end

local function preview_text(item)
	local d = new_doc()
	local tool = item.tool
	local thl = TOOL_HL[tool.name]

	-- BẮT BUỘC early-return cho install: nhánh past ở cuối hàm đọc item.entry
	-- (nil với install) -> lỗi ngay trong finder, picker không mở nổi.
	if item.kind == "install" then
		doc_title(d, "install", "Install " .. tool.name, "DiagnosticWarn")
		doc_row(d, "f_cmd", "command", tool.install, "DiagnosticWarn")
		doc_section(d, "install", "Heads up")
		doc_block(d, {
			"Downloads and runs a remote script.",
			"Read the URL before continuing.",
			"<CR> runs it in the AI pane - you will be asked to confirm first.",
		}, "SnacksPickerDimmed")
		return doc_done(d)
	end

	-- Cũng BẮT BUỘC early-return, cùng lý do với install: không có item.entry.
	if item.kind == "ecc" then
		local e = ecc()
		if not e then
			return doc_done(d)
		end
		doc_title(d, "ecc", "Install ECC for " .. tool.name, "SnacksPickerSpecial")
		doc_row(d, "f_prompt", "what", "281 skills + 94 commands for AI coding")
		doc_row(d, "f_cwd", "clone to", vim.fn.fnamemodify(e.dir(), ":~"))
		doc_row(d, "f_cmd", "reads", vim.fn.fnamemodify(e.source_dirs(tool.name)[1] or "?", ":~"))
		doc_section(d, "f_cmd", "Commands to run")
		doc_block(d, e.steps(tool.name) or { "(unsupported target)" })
		doc_section(d, "install", "Heads up")
		doc_block(d, {
			"Third-party repo: it is cloned, then npm install runs",
			"its lifecycle scripts and the installer writes into",
			"your ~/.claude / ~/.codex config.",
			"<CR> runs it in the AI pane - you will confirm first.",
		}, "SnacksPickerDimmed")
		doc_section(d, "f_prompt", "After installing")
		doc_block(d, {
			"<leader>ai actions switch from hand-written prompts",
			"to ECC commands (/code-review, /build-fix, ...).",
		}, "SnacksPickerDimmed")
		return doc_done(d)
	end

	if item.kind == "new" then
		doc_title(d, tool.name, "New " .. tool.name .. " session", thl)
		doc_row(d, "f_cwd", "cwd", vim.fn.fnamemodify(history().project_cwd(), ":~"))
		doc_section(d, "f_cmd", "Command")
		doc_block(d, cmdline(tool))
		return doc_done(d)
	end

	if item.kind == "browse" then
		doc_title(d, "browse", tool.name .. " · " .. (tool.browse_label or "own picker"), thl)
		doc_section(d, "f_prompt", "What this is")
		doc_block(d, {
			"Fallback when discovery finds nothing —",
			"schema changed, another machine's DB, etc.",
		}, "SnacksPickerDimmed")
		doc_section(d, "f_cmd", "Command")
		doc_block(d, cmdline(tool, tool.browse))
		return doc_done(d)
	end

	if item.kind == "live" then
		local s = item.session
		doc_title(d, "live", s.title or s.id, "SnacksPickerGitStatusStaged")
		doc_row(d, tool.name, "tool", tool.name, thl)
		doc_row(d, "f_id", "session", s.id)
		doc_row(d, "f_cwd", "cwd", item.cwd and vim.fn.fnamemodify(item.cwd, ":~"))
		doc_row(d, "f_agent", "job", tostring(s.job))
		doc_row(d, "f_updated", "state", "running")
		return doc_done(d)
	end

	local e = item.entry
	doc_title(d, tool.name, e.title or e.id, thl)

	local tool_line = e.tool .. (e.version and (" " .. e.version) or "")
	doc_row(d, tool.name, "tool", tool_line, thl)
	doc_row(d, "f_model", "model", e.model and (e.model .. (e.effort and (" (" .. e.effort .. ")") or "")))
	doc_row(d, "f_agent", "agent", e.agent)
	doc_row(d, "f_tokens", "tokens", e.tokens and commafy(e.tokens))
	doc_row(d, "f_cost", "cost", e.cost and ("$%.4f"):format(e.cost))
	doc_row(d, "branch", "branch", e.branch and (e.branch .. (e.sha and (" · " .. e.sha) or "")))
	doc_row(d, "f_cwd", "cwd", e.cwd and vim.fn.fnamemodify(e.cwd, ":~"))
	if e.time and e.time > 0 then
		doc_row(
			d,
			"f_updated",
			"updated",
			Snacks.picker.util.reltime(e.time) .. " · " .. os.date("%Y-%m-%d %H:%M", e.time)
		)
	end
	if e.created and e.created > 0 then
		doc_row(d, "f_created", "created", Snacks.picker.util.reltime(e.created))
	end
	doc_row(d, "f_id", "id", e.id)

	-- prompt_lines GIỮ NGUYÊN xuống dòng (aiterm_history). e.prompt là bản gộp 1
	-- dòng cho matcher -> chỉ dùng làm fallback khi thiếu prompt_lines.
	local prompt = e.prompt_lines or (e.prompt and { e.prompt })
	if prompt then
		doc_section(d, "f_prompt", "Last prompt")
		doc_block(d, prompt)
	end

	doc_section(d, "f_cmd", "Resume")
	doc_block(d, cmdline(tool, tool.resume(e.id)))
	return doc_done(d)
end

-- Bề rộng hiển thị của một list {text, hl}.
local function meta_width(meta)
	local w = 0
	for _, chunk in ipairs(meta) do
		w = w + vim.api.nvim_strwidth(chunk[1])
	end
	return w
end

local MIN_TITLE = 24 -- title không bao giờ bị bóp nhỏ hơn mức này

-- Ghép các segment metadata thành list {text, hl}, BỎ DẦN segment ưu tiên thấp
-- cho tới khi vừa chỗ. nvim KHÔNG tự đẩy right_align virt_text nên nếu không trim
-- thì meta sẽ đè lên title ở window hẹp (list chỉ ~38 cột khi terminal 80 cột).
--   segs = { { text, hl, drop = <số càng lớn càng bị bỏ trước> }, ... }
local function fit_meta(segs, budget)
	local keep = vim.deepcopy(segs)
	local function build()
		local out = {}
		for _, s in ipairs(keep) do
			if #out > 0 then
				out[#out + 1] = { " · ", "SnacksPickerDelim" }
			end
			out[#out + 1] = { s[1], s[2] }
		end
		out[#out + 1] = { " " } -- chừa 1 cột trước viền phải
		return out
	end
	local meta = build()
	while meta_width(meta) > budget and #keep > 1 do
		-- bỏ segment có `drop` lớn nhất (gặp đầu tiên nếu bằng nhau)
		local worst, worst_i = -1, nil
		for i, s in ipairs(keep) do
			if (s.drop or 0) > worst then
				worst, worst_i = s.drop or 0, i
			end
		end
		if not worst_i or worst <= 0 then
			break
		end
		table.remove(keep, worst_i)
		meta = build()
	end
	return meta
end

-- Title đứng ngay sau icon; metadata dán LỀ PHẢI bằng extmark right_align nên lề
-- phải luôn thẳng bất kể title dài ngắn (recipe của snacks format.file_git_status).
--
-- Hai điểm cố ý:
--   * icon dùng virtual = true -> render thành virt_text overlay, buffer thật chỉ
--     có dấu cách => icon KHÔNG lọt vào text mà matcher chấm điểm, cũng không lọt
--     vào yank. (gõ "magic"/"code"/"terminal" sẽ không match nhầm vì icon)
--   * title phải truncate theo (bề rộng list - bề rộng meta) vì nvim KHÔNG tự đẩy
--     right_align virt_text; không trừ là hai bên đè nhau.
local function format_item(item, picker)
	local ret = {}
	local ic = M.icons()
	local tool = item.tool

	-- icon dài 1 cột + 1 dấu cách -> luôn chiếm đúng 2 cột với cả 3 bộ icon.
	ret[#ret + 1] = { (ic[item.kind] or ic.past) .. " ", KIND_HL[item.kind] or KIND_HL.past, virtual = true }

	-- Cột tool CỐ ĐỊNH bên trái. Trước đây tool nằm trong meta dán lề phải nên rơi
	-- vào toạ độ khác nhau ở từng dòng -> mắt phải dò ngang từng dòng mới biết tool.
	-- Để là TEXT THẬT (không virtual): phần highlight match của snacks chạy trên
	-- text đã render của cả dòng, nên gõ "codex" sẽ highlight luôn ở cột này.
	ret[#ret + 1] = {
		Snacks.picker.util.align(tool_icon(tool) .. " " .. tool.name, TOOL_W),
		TOOL_HL[tool.name] or "SnacksPickerDimmed",
	}

	-- segs: metadata theo thứ tự hiển thị; `drop` càng lớn càng bị bỏ trước khi hẹp.
	-- KHÔNG còn tool ở đây nữa (đã có cột trái) -> nhường chỗ cho title.
	local segs = {}
	-- title dựng sẵn ở build_items (item.title là field thật để lọc `title:`).
	local title, title_hl = item.title or "", "SnacksPickerFile"

	if item.kind == "live" then
		segs[#segs + 1] = { item.session.id, "SnacksPickerBold", drop = 2 }
		segs[#segs + 1] = { "running", "SnacksPickerGitStatusStaged" }
	elseif item.kind == "past" then
		local e = item.entry
		if e.branch then
			segs[#segs + 1] = { ic.branch .. " " .. e.branch, "SnacksPickerGitBranch", drop = 2 }
		end
		if e.time and e.time > 0 then
			segs[#segs + 1] = { Snacks.picker.util.reltime(e.time), "SnacksPickerTime", drop = 1 }
		end
		-- Hiện cwd cả ở scope cwd: cho thấy edge case codex/opencode lưu cwd là
		-- thư mục cha, thay vì để nó gây bối rối ngầm. Bỏ đầu tiên khi hẹp.
		if e.cwd then
			segs[#segs + 1] = { vim.fn.fnamemodify(e.cwd, ":~"), "SnacksPickerDir", drop = 3 }
		end
	elseif item.kind == "new" then
		-- cột trái đã ghi tên tool -> title không lặp lại ("New session").
		title_hl = "SnacksPickerLabel"
	elseif item.kind == "install" then
		-- phải có nhánh riêng: rơi vào else sẽ đọc tool.browse_label -> meta sai.
		title_hl = "DiagnosticWarn"
		segs[#segs + 1] = { "install", "DiagnosticWarn", drop = 1 }
	elseif item.kind == "ecc" then
		-- cũng phải có nhánh riêng, cùng lý do với install.
		title_hl = "SnacksPickerSpecial"
		segs[#segs + 1] = { "not installed", "SnacksPickerDimmed", drop = 1 }
	else
		-- title chỉ là args; binary đã nằm ở cột tool -> đọc thành "claude  --resume".
		title_hl = "SnacksPickerCode"
		segs[#segs + 1] = { tool.browse_label or "own picker", "SnacksPickerSpecial", drop = 1 }
	end

	-- Đo bề rộng THẬT của list window (win:size() tính lại từ config chứ không
	-- phải kích thước hiện hành). Chưa mở window thì lấy 80 làm mức an toàn.
	local list_w = 80
	local lwin = picker and picker.list and picker.list.win and picker.list.win.win
	if lwin and vim.api.nvim_win_is_valid(lwin) then
		list_w = vim.api.nvim_win_get_width(lwin)
	end

	local meta = fit_meta(segs, math.max(0, list_w - LEAD_W - MIN_TITLE))
	local avail = list_w - LEAD_W - meta_width(meta)
	if avail > 0 then
		title = Snacks.picker.util.truncate(title, avail)
	end
	ret[#ret + 1] = { title, title_hl, field = "title" }

	ret[#ret + 1] = {
		col = 0,
		virt_text = meta,
		virt_text_pos = "right_align",
		hl_mode = "combine", -- không đè mất CursorLine ở dòng đang chọn
	}
	return ret
end

-- Key hints nằm luôn trong viền dưới. Ba điều kiện của snacks phải thoả:
--   * footer PHẢI gắn ở BOX có border: win="list" trong preset default có
--     border="none", mà snacks xoá title/footer của window không border
--     (win.lua M:win_opts).
--   * footer KHÔNG được template hoá (update_titles chỉ đụng title) -> tuple tĩnh.
--   * win:update() re-apply self.opts nên footer dính qua các lần layout update.
-- Ký hiệu phím dùng notation của vim (ASCII thuần): "⏎"/"⌥" không có ở mọi font
-- và "⌥" còn là ký hiệu riêng của macOS, sang Linux/Windows đọc thành sai phím.
local FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "resume  ", "SnacksPickerDimmed" },
	{ "C-x ", "SnacksPickerLabel" },
	{ "new  ", "SnacksPickerDimmed" },
	{ "C-o ", "SnacksPickerLabel" },
	{ "fork  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "scope  ", "SnacksPickerDimmed" },
	{ "dd ", "SnacksPickerLabel" },
	{ "delete  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- Footer riêng cho M.workflows: bộ phím khác hẳn (không resume/fork/delete), mà dùng
-- chung FOOTER thì quảng cáo phím không tồn tại. M-t là phím DUY NHẤT ở picker đó
-- không đoán được từ nội dung, nên bắt buộc phải có mặt.
local WF_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "run  ", "SnacksPickerDimmed" },
	{ "M-f ", "SnacksPickerLabel" },
	{ "pin  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "all  ", "SnacksPickerDimmed" },
	{ "M-t ", "SnacksPickerLabel" },
	{ "tool  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

local SKILL_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "use  ", "SnacksPickerDimmed" },
	{ "M-f ", "SnacksPickerLabel" },
	{ "pin  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "all  ", "SnacksPickerDimmed" },
	{ "M-t ", "SnacksPickerLabel" },
	{ "tool  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- Footer của M.ecc. M-u là phím DUY NHẤT đi mạng trong cả plugin nên phải hiện rõ.
local ECC_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "run  ", "SnacksPickerDimmed" },
	{ "M-u ", "SnacksPickerLabel" },
	{ "github  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- Tự khai layout.layout thì snacks BỎ QUA toàn bộ preset resolution
-- (config/init.lua: `if not (layout.layout and layout.layout[1])`), nghĩa là mất
-- luôn fallback sang "vertical" khi terminal hẹp. Nên phải tự branch, dùng đúng
-- ngưỡng 120 cột mà preset mặc định của snacks đang dùng.
---@param footer table[] key hints của chính picker gọi nó (xem FOOTER / WF_FOOTER)
local function build_layout(footer)
	if vim.o.columns < 120 then
		return {
			layout = {
				box = "vertical",
				width = 0.7,
				min_width = 70,
				height = 0.8,
				border = "rounded",
				title = "{title} {flags}",
				title_pos = "center",
				footer = footer,
				footer_pos = "center",
				{ win = "input", height = 1, border = "bottom" },
				{ win = "list", border = "none" },
				{ win = "preview", title = "{preview}", height = 0.4, border = "top" },
			},
		}
	end
	return {
		layout = {
			box = "horizontal",
			width = 0.85,
			min_width = 120,
			height = 0.8,
			{
				box = "vertical",
				border = "rounded",
				title = "{title} {flags}",
				title_pos = "center",
				footer = footer,
				footer_pos = "center",
				{ win = "input", height = 1, border = "bottom" },
				{ win = "list", border = "none" },
			},
			{ win = "preview", title = "{preview}", border = "rounded", width = 0.5 },
		},
	}
end

-- Thứ tự nhóm: live -> past (mới nhất trước) -> new -> browse. Giữ được khi prompt
-- rỗng vì snacks default matcher.sort_empty = false -> không cần sort riêng.
local function build_items(all_dirs)
	local items = {}

	for _, s in ipairs(sessions) do
		if is_alive(s) then
			items[#items + 1] = {
				kind = "live",
				session = s,
				tool = s.tool,
				cwd = s.cwd,
				-- item.text là BẮT BUỘC: matcher score theo nó.
				text = table.concat({ "live", s.tool.name, s.id, s.title or "" }, " "),
			}
		end
	end

	-- KHÔNG viết `all_dirs and nil or cwd`: nil là falsy nên nhánh and sập, biểu
	-- thức luôn trả cwd -> scope "all dirs" không bao giờ có tác dụng. Dùng if.
	local scope_cwd
	if not all_dirs then
		-- scope_cwd() trả cwd RAW; history tự thêm realpath vào tập ứng viên nên
		-- khớp cả path mount (vd /app trong container) lẫn realpath.
		scope_cwd = history().scope_cwd()
	end

	for _, e in ipairs(history().list(scope_cwd)) do
		local tool = find_tool(e.tool)
		if tool then
			items[#items + 1] = {
				kind = "past",
				tool = tool,
				entry = e,
				cwd = e.cwd,
				-- nhồi tool + title + cwd + branch + id -> query "codex redis" và
				-- "dotfiles main" đều trúng. KHÔNG dùng item.file cho e.jsonl:
				-- matcher.filename_bonus sẽ cho điểm cộng filename giả.
				text = table.concat({ e.tool, e.title or "", e.cwd or "", e.branch or "", e.id }, " "),
			}
		end
	end

	-- Tool chưa cài mà có script cài -> thay new + browse bằng ĐÚNG 1 dòng install.
	-- Bấm vào new/browse của tool chưa cài chỉ ra "binary not found" nên giữ lại
	-- chúng chỉ tạo dòng chết. Tính trạng thái một lần rồi dùng cho cả hai vòng.
	local needs_install = {}
	for _, t in ipairs(M.config.tools) do
		needs_install[t.name] = tool_cmd(t) == nil and t.install ~= nil
	end

	for _, t in ipairs(M.config.tools) do
		if needs_install[t.name] then
			items[#items + 1] = { kind = "install", tool = t, text = "install " .. t.name }
		else
			items[#items + 1] = { kind = "new", tool = t, text = "new " .. t.name }
		end
	end
	for _, t in ipairs(M.config.tools) do
		if t.browse and not needs_install[t.name] then
			items[#items + 1] = { kind = "browse", tool = t, text = "browse " .. t.name }
		end
	end

	-- Đã có binary nhưng chưa có command của ECC -> mời cài. Cài xong dò lại thấy có
	-- command nên dòng này tự biến mất; đường cập nhật về sau là M.ecc() (<leader>aE).
	for _, t in ipairs(M.config.tools) do
		if not needs_install[t.name] then
			local e = ecc()
			if e and not e.installed(t.name) then
				items[#items + 1] = { kind = "ecc", tool = t, text = "ecc " .. t.name }
			end
		end
	end

	-- item.title là field THẬT trên item, không phải chỉ để hiển thị: matcher lọc
	-- `title:redis` bằng item[field] (matcher.lua M:match -> item[mods.field]),
	-- chứ KHÔNG đọc text đã render. Không set ở đây thì `title:` luôn ra 0 kết quả.
	for _, it in ipairs(items) do
		if it.kind == "live" then
			it.title = it.session.title or it.session.id
		elseif it.kind == "past" then
			it.title = it.entry.title or it.entry.id
		elseif it.kind == "new" then
			it.title = "New session"
		elseif it.kind == "install" then
			-- nhánh riêng: else phía dưới trả browse args -> sai cho install.
			it.title = "not installed"
		elseif it.kind == "ecc" then
			it.title = "Add ECC skills & commands"
		else
			it.title = table.concat(it.tool.browse or {}, " ")
		end
		-- preview_text trả sẵn { text, extmarks }. KHÔNG đặt ft: bố cục là bảng canh
		-- cột, để markdown vào thì dòng thụt lề bị hiểu thành code block.
		it.preview = preview_text(it)
	end
	return items
end

-- public -----------------------------------------------------------------

-- Tạo session mới cho tool (theo tên) rồi attach. Dùng cho lệnh/keymap tạo nhanh.
---@param name string
---@param opts? { args?: string[], cwd?: string, title?: string }
function M.open(name, opts)
	local tool = find_tool(name)
	if not tool then
		vim.notify("aiterm: unknown tool '" .. tostring(name) .. "'", vim.log.levels.ERROR)
		return
	end
	opts = opts or {}
	opts.cwd = opts.cwd or history().project_cwd()
	attach(new_session(tool, opts))
end

--- Resume một session cũ trên đĩa vào pane AI.
---@param e table entry từ aiterm_history.list()
function M.resume(e)
	local tool = e and find_tool(e.tool)
	if not (tool and tool.resume) then
		notify("aiterm: tool does not support resume: " .. tostring(e and e.tool), "warn")
		return
	end
	attach(new_session(tool, { args = tool.resume(e.id), cwd = e.cwd, title = e.title }))
end

-- Resume session mới nhất của cwd, không qua picker. Chưa có gì -> mở picker.
function M.resume_last()
	local e = history().list(history().scope_cwd(), 1)[1]
	if not e then
		return M.pick()
	end
	M.resume(e)
end

-- Chẩn đoán vì sao picker không thấy session (cwd scoping / thiếu sqlite3...).
function M.doctor()
	-- Mục ECC nối vào cùng buffer với history doctor. Có nó vì trạng thái "installer
	-- chạy xong rồi mà tool vẫn không thấy command" (opencode dàn file ra ~/.opencode,
	-- không phải chỗ nó đọc) nhìn y hệt "chưa cài" - không có cách nào tự phát hiện.
	local e = ecc()
	local lines
	if e then
		lines = { "## ECC (skills/commands cho AI tool)", "clone       : " .. e.dir() }
		for _, t in ipairs(M.config.tools) do
			local n = e.count(t.name)
			-- commands = quy trình cấp repo (<leader>aw); skills = tài liệu áp lên đoạn
			-- code đang chọn (<leader>ai). Hai con số này lệch nhau là bình thường.
			local sk = vim.tbl_count(e.skills(t.name))
			local dir = e.source_dirs(t.name)[1] or "?"
			lines[#lines + 1] = ("%-12s: %3d commands  %3d skills  %s"):format(t.name, n, sk, dir)
			local pinned, pn = e.anthropic_pins(t.name)
			if pinned then
				lines[#lines + 1] = ("%-12s  ! %d chỗ pin model anthropic/* trong %s"):format("", pn, pinned)
				lines[#lines + 1] = ("%-12s    -> chạy lại <leader>aE để gỡ pin"):format("")
			end
		end
		lines[#lines + 1] = "Gợi ý: 0 commands -> <leader>ai gửi prompt viết tay thay cho /command."
		lines[#lines + 1] = "Cài/cập nhật bằng <leader>aE, hoặc dòng ECC trong picker <leader>aa."
	else
		lines = {
			"## ECC (skills/commands cho AI tool)",
			"module 'customize.aiterm_ecc' không tải được - bỏ qua mục này.",
		}
	end
	history().doctor(lines)
end

--- Picker chính: live session + session cũ trên đĩa + tạo mới + fallback.
---@param opts? { scope?: "cwd"|"all" }
function M.pick(opts)
	if not (_G.Snacks and Snacks.picker) then
		vim.notify("aiterm: snacks.nvim picker required", vim.log.levels.ERROR)
		return
	end
	ensure_hl()
	local scope = (opts and opts.scope) or M.config.history.scope

	-- Đóng picker TRƯỚC rồi mới mở terminal: tránh tranh chấp focus với pane AI.
	local function run(picker, fn)
		picker:close()
		vim.schedule(fn)
	end

	Snacks.picker({
		title = "AI Sessions",
		-- Scope là một opt BOOLEAN, không phải upvalue closure. snacks tự sinh
		-- action `toggle_all_dirs` + hl group cho mỗi entry trong toggles, và
		-- `{flags}` trong title tự chèn badge khi all_dirs = true.
		-- Quan trọng: finder đọc opts.all_dirs (tham số đầu CHÍNH LÀ picker.opts)
		-- nên chỉ có một đường đọc state -> hết cả lớp bug "title đổi mà list không".
		all_dirs = scope == "all",
		toggles = { all_dirs = { icon = M.icons().all_dirs, value = true } },
		finder = function(popts)
			return build_items(popts.all_dirs)
		end,
		format = format_item,
		preview = "preview",
		layout = build_layout(FOOTER),
		confirm = function(picker, item)
			if not item then
				return
			end
			run(picker, function()
				if item.kind == "live" then
					attach(item.session)
				elseif item.kind == "past" then
					M.resume(item.entry)
				elseif item.kind == "install" then
					install_tool(item.tool)
				elseif item.kind == "ecc" then
					install_ecc(item.tool)
				elseif item.kind == "browse" then
					attach(new_session(item.tool, {
						args = item.tool.browse,
						cwd = history().project_cwd(),
						title = "browse",
					}))
				else
					attach(new_session(item.tool, { cwd = history().project_cwd() }))
				end
			end)
		end,
		actions = {
			-- <C-x>: bỏ qua resume, mở session TRẮNG cùng tool + cùng cwd của item.
			aiterm_fresh = function(picker, item)
				if not item then
					return
				end
				-- trên dòng install thì new_session chỉ ra "binary not found"
				-- -> chuyển sang cài luôn, để <C-x> không thành đường chết.
				if item.kind == "install" then
					run(picker, function()
						install_tool(item.tool)
					end)
					return
				end
				if item.kind == "ecc" then
					run(picker, function()
						install_ecc(item.tool)
					end)
					return
				end
				local cwd = item.cwd or history().project_cwd()
				run(picker, function()
					attach(new_session(item.tool, { cwd = cwd }))
				end)
			end,
			-- <C-o>: fork session cũ -> không ghi tiếp vào history gốc.
			aiterm_fork = function(picker, item)
				if not (item and item.kind == "past" and item.tool.fork) then
					return
				end
				local e = item.entry
				run(picker, function()
					attach(new_session(item.tool, {
						args = item.tool.fork(e.id),
						cwd = e.cwd,
						title = e.title,
					}))
				end)
			end,
			-- dd: archive (codex, hoàn tác được) / delete (opencode, KHÔNG) /
			-- xoá file jsonl (claude, KHÔNG) -> default của confirm là &No.
			aiterm_delete = function(picker, item)
				if not (item and item.kind == "past") then
					return
				end
				local e = item.entry
				local prompt = ('Delete session "%s" (%s)?'):format(e.title or e.id, e.tool)
				if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
					return
				end
				if delete_entry(item.tool, e) then
					history().invalidate()
					picker:find({ refresh = true })
				else
					notify(("delete failed: %s"):format(e.id), "warn")
				end
			end,
		},
		-- `desc` không phải trang trí: overlay `?` (toggle_help_input) đọc keymap
		-- THẬT của buffer và render desc. Không đặt thì snacks tự suy từ tên action
		-- ("aiterm_fresh" -> "aiterm fresh"), đọc rất xấu.
		-- `?` mặc định chỉ chạy ở normal mode, mà picker mở ra là insert -> thêm
		-- <a-?> để xem key ngay khi đang gõ (không map `?` cho insert vì nó sẽ gõ
		-- luôn dấu ? vào query).
		-- desc <= ~18 ký tự: overlay help của snacks.win cắt ở col_width mặc định.
		win = {
			input = {
				keys = {
					["<c-x>"] = { "aiterm_fresh", mode = { "i", "n" }, desc = "new blank session" },
					["<c-o>"] = { "aiterm_fork", mode = { "i", "n" }, desc = "fork session" },
					["<a-a>"] = { "toggle_all_dirs", mode = { "i", "n" }, desc = "cwd / all dirs" },
					["dd"] = { "aiterm_delete", mode = "n", desc = "delete session" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<c-x>"] = { "aiterm_fresh", desc = "new blank session" },
					["<c-o>"] = { "aiterm_fork", desc = "fork session" },
					["<a-a>"] = { "toggle_all_dirs", desc = "cwd / all dirs" },
					["dd"] = { "aiterm_delete", mode = "n", desc = "delete session" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
	})
end

-- <C-w>p trong editor: focus pane nếu đang mở; nếu không -> attach session gần nhất
-- hoặc session còn sống đầu tiên; chưa có gì -> mở picker.
function M.focus()
	if win_valid() then
		vim.api.nvim_set_current_win(win)
		if M.config.start_insert then
			vim.cmd("startinsert")
		end
		return
	end
	local s = last_session and find(last_session)
	if not is_alive(s) then
		s = nil
		for _, cand in ipairs(sessions) do
			if is_alive(cand) then
				s = cand
				break
			end
		end
	end
	if s then
		attach(s)
	else
		M.pick()
	end
end

-- Ẩn pane AI: ĐÓNG window nhưng KHÔNG đụng tới job.
-- Buffer để bufhidden="hide" nên terminal chạy tiếp dưới nền; <C-w>p / <leader>aa
-- attach lại đúng session đó (nó vẫn nằm trong `sessions`, is_alive vẫn true).
-- Gọi được từ bất kỳ đâu, không cần đang focus trong pane.
function M.hide()
	if not win_valid() then
		return
	end
	-- nvim_win_close lỗi "cannot close last window" nếu đây là window duy nhất.
	if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
		notify("cannot hide: AI pane is the only window", "warn")
		return
	end
	-- rời terminal-mode trước, nếu không con trỏ kẹt lại ở insert sau khi đóng.
	if vim.api.nvim_get_current_win() == win and vim.fn.mode() == "t" then
		vim.cmd("stopinsert")
	end
	pcall(vim.api.nvim_win_close, win, false)
	win = nil
end

-- Đóng pane AI trước khi auto-session lưu: tránh mksession ghi buffer terminal ->
-- setlocal buftype=terminal (E474) làm hỏng restore. Job chết theo nvim khi thoát
-- nên không cần giữ. Đảm bảo không phải window cuối để nvim_win_close không lỗi.
function M.close_for_session()
	if not win_valid() then
		return
	end
	if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
		vim.cmd("new") -- chừa 1 window trống để đóng được pane
	end
	if vim.api.nvim_get_current_win() == win and vim.fn.mode() == "t" then
		vim.cmd("stopinsert")
	end
	pcall(vim.api.nvim_win_close, win, true)
	win = nil
end

-- Rời focus khỏi pane nhưng GIỮ pane mở. Đây là hành vi của <C-Space> trong
-- terminal-mode (map thẳng tới <C-w>p, không đi qua hàm này).
function M.blur()
	if win_valid() and vim.api.nvim_get_current_win() == win then
		vim.cmd("wincmd p")
	end
end

-- Toggle: pane đang mở -> ẩn; chưa mở -> focus/attach.
function M.toggle()
	if win_valid() then
		M.hide()
	else
		M.focus()
	end
end

-- code interaction (ask / explain ... kiểu CodeCompanion) ------------------
-- Không cần plugin LLM: aiterm chạy CLI trong PTY nên "tương tác source code" =
-- dựng message (file/selection + instruction) rồi CHANSEND vào job của session.

-- default tool (chuỗi fallback + override lưu qua các lần khởi động) ------
-- default_override: tên tool người dùng chốt (qua M.set_default_tool / <leader>aD),
-- đọc lại từ state file lúc require. Ưu tiên hơn M.config.send.default_tools.
local default_override
local refresh_hints -- forward-declare: định nghĩa ở mục inline hints bên dưới

local function state_file()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "aiterm-default-tool")
end

-- Tool để auto-tạo session: override (nếu hợp lệ) trước, rồi tool ĐÃ CÀI đầu tiên
-- trong default_tools; không cái nào cài -> tool hợp lệ đầu (new_session sẽ gợi ý cài).
local function resolve_default_tool()
	local order, first = {}, nil
	if default_override then
		order[#order + 1] = default_override
	end
	vim.list_extend(order, M.config.send.default_tools or {})
	for _, name in ipairs(order) do
		local t = find_tool(name)
		if t then
			first = first or t
			if tool_cmd(t) then
				return t
			end
		end
	end
	return first or M.config.tools[1]
end

-- Đọc lựa chọn đã lưu (pcall-safe: file thiếu/rác -> không override).
local function load_default()
	local ok, lines = pcall(vim.fn.readfile, state_file())
	local name = ok and lines[1] and vim.trim(lines[1]) or ""
	if name ~= "" and find_tool(name) then
		default_override = name
	end
end

-- favorites (pin) cho picker skill/command --------------------------------
-- Ghim theo TÊN, tách theo kind ("skills"/"commands"). Lưu qua các lần mở nvim, cùng
-- khuôn state file như default tool. Picker mặc định chỉ hiện mục đã ghim (xem M.skill_pick).
local fav = { skills = {}, commands = {} } -- kind -> { name -> true }
local function fav_file()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "aiterm-favorites.json")
end
local function load_favorites()
	local ok, lines = pcall(vim.fn.readfile, fav_file())
	if not ok or not lines or #lines == 0 then
		return
	end
	local ok2, d = pcall(vim.json.decode, table.concat(lines, "\n"))
	if ok2 and type(d) == "table" then
		fav.skills = type(d.skills) == "table" and d.skills or {}
		fav.commands = type(d.commands) == "table" and d.commands or {}
	end
end
local function is_fav(kind, name)
	return fav[kind][name] == true
end
local function toggle_fav(kind, name)
	fav[kind][name] = (not fav[kind][name]) or nil
	pcall(vim.fn.writefile, { vim.json.encode(fav) }, fav_file())
end
local function fav_count(kind)
	return vim.tbl_count(fav[kind])
end

--- Chốt tool mặc định (auto-tạo) và LƯU qua các lần khởi động.
---@param name string
function M.set_default_tool(name)
	if not find_tool(name) then
		notify("aiterm: unknown tool " .. tostring(name), "warn")
		return
	end
	default_override = name
	pcall(vim.fn.writefile, { name }, state_file())
	notify("AI default tool: " .. name, "info")
end

--- Menu chọn tool mặc định (<leader>aD), có icon + đánh dấu (current).
function M.pick_default()
	local ic, names = M.icons(), {}
	for _, t in ipairs(M.config.tools) do
		names[#names + 1] = t.name
	end
	vim.ui.select(names, {
		prompt = "Default AI tool:",
		format_item = function(n)
			return (ic[n] and ic[n] .. " " or "") .. n .. (default_override == n and "  (current)" or "")
		end,
	}, function(choice)
		if choice then
			M.set_default_tool(choice)
			refresh_hints() -- badge phản ánh ngay tool vừa chọn
		end
	end)
end

-- Session còn sống mà thao tác gửi sẽ nhắm tới. Ưu tiên:
--   1. session đang hiển thị trong pane AI (nếu pane đang focus)
--   2. last_session nếu còn sống
--   3. session còn sống đầu tiên
-- Trả nil nếu không có session nào sống. KHÔNG tự tạo: M.send cần biết "chưa có
-- session" để nhúng prompt vào lệnh launch thay vì paste vào TUI đang boot.
-- `tool` (tuỳ chọn) khoá kết quả về đúng tool đó. Cần cho M.workflows: lệnh ECC có
-- tiền tố riêng từng tool (/ecc-code-review của codex), dán nhầm vào session opencode
-- là gửi đi một dòng chữ vô nghĩa. Lọc phải áp cho CẢ BA nhánh - sót một nhánh là nó
-- lặng lẽ trả về session sai tool.
local function target_session(tool)
	local function usable(s)
		return is_alive(s) and (tool == nil or s.tool == tool)
	end
	if win_valid() then
		local buf = vim.api.nvim_win_get_buf(win)
		for _, s in ipairs(sessions) do
			if s.buf == buf and usable(s) then
				return s
			end
		end
	end
	local s = last_session and find(last_session)
	if usable(s) then
		return s
	end
	for _, cand in ipairs(sessions) do
		if usable(cand) then
			return cand
		end
	end
	return nil -- CHỈ tìm, không tạo: M.send tự quyết cách tạo (xem M.send).
end

-- Chữ ký nội dung terminal để phát hiện "đã vẽ xong rồi im" (quiescence): số dòng
-- + vài dòng cuối. Đủ nhạy để thấy CLI in gì đó, đủ rẻ để poll mỗi ~120ms.
local function term_signature(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	local n = vim.api.nvim_buf_line_count(buf)
	return n .. "\0" .. table.concat(vim.api.nvim_buf_get_lines(buf, math.max(0, n - 3), n, false), "\n")
end

-- Chờ session "sẵn sàng" rồi gọi cb. Sẵn sàng = ĐÃ thấy terminal đổi khác lúc mới
-- mở (CLI in gì đó -> đã boot) VÀ nội dung im quiet_ms, sau khi qua min_ms; hết
-- max_ms thì flush luôn. Thay cho delay cố định cũ (gửi sớm -> mất/lộn xộn request).
local function when_ready(session, cb)
	local r = M.config.send.ready
	local start = vim.uv.now()
	local initial = term_signature(session.buf)
	local last, stable_since, seen_change = initial, nil, false
	local timer = vim.uv.new_timer()
	local function stop()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end
	timer:start(
		r.interval_ms,
		r.interval_ms,
		vim.schedule_wrap(function()
			if not is_alive(session) then
				stop()
				return
			end
			local now = vim.uv.now()
			local sig = term_signature(session.buf)
			if sig ~= last then
				last, stable_since = sig, now
				if sig ~= initial then
					seen_change = true
				end
			end
			local quiet = seen_change and stable_since and (now - stable_since) >= r.quiet_ms
			if (now - start) >= r.max_ms or ((now - start) >= r.min_ms and quiet) then
				stop()
				cb()
			end
		end)
	)
end

-- Bracketed paste: TUI coi cả block (kể cả xuống dòng) là MỘT lần dán, không
-- submit từng dòng. \27[200~ ... \27[201~ là mã chuẩn của bracketed-paste.
local function chan_paste(job, text)
	vim.fn.chansend(job, "\27[200~" .. text .. "\27[201~")
end

--- Gửi text vào session AI đang chạy (tạo mới nếu chưa có), tuỳ chọn submit luôn.
---@param text string
---@param opts? { submit?: boolean, tool?: table }
function M.send(text, opts)
	opts = opts or {}
	-- opts.tool: khoá đích về đúng tool (M.workflows). Không truyền -> hành vi y hệt
	-- trước: bất kỳ session nào đang sống.
	local session = target_session(opts.tool) -- CHỈ tìm session đang sống

	if not session then
		-- ĐƯỜNG CHÍNH khi chưa có session: nhúng prompt thẳng vào lệnh launch.
		-- Không paste => không có đua tranh với lúc TUI đang boot. Đây là chỗ từng
		-- mất request: opencode boot chậm, paste rơi vào giữa lúc nó còn đang đàm
		-- phán capability với terminal nên request bay mất và tiến trình thoát.
		local tool = opts.tool or resolve_default_tool()
		if tool.prompt_args and #text <= M.config.send.max_arg_bytes then
			attach(new_session(tool, {
				args = tool.prompt_args(text),
				cwd = history().project_cwd(),
				title = "ask",
			}))
			return
		end
		-- Tool không hỗ trợ prompt lúc launch, hoặc message quá to cho argv
		-- -> quay về đường cũ: tạo, chờ boot, rồi paste.
		session = new_session(tool, { cwd = history().project_cwd() })
		if not session then
			return -- new_session đã notify lý do (binary not found ...)
		end
		session.ready = false
	end

	attach(session) -- mở + focus pane; job nhận input bất kể focus nên không đua.
	local function deliver()
		if not is_alive(session) then
			return
		end
		chan_paste(session.job, text)
		if opts.submit then
			-- Enter tách khỏi paste một nhịp: Ink của claude cần kịp xử lý paste.
			vim.defer_fn(function()
				if is_alive(session) then
					vim.fn.chansend(session.job, "\r")
				end
			end, M.config.send.submit_delay)
		end
	end
	-- session vừa tạo (ready=false): CLI chưa boot xong -> gửi sớm là mất/lộn xộn
	-- (bracketed-paste chưa bật). Chờ terminal vẽ xong + im rồi mới gửi; flip ready
	-- để lần gửi sau tới cùng session là tức thì. Session cũ (ready=nil) gửi ngay.
	if session.ready == false then
		notify(("waiting for %s to start…"):format(session.tool.name), "info")
		when_ready(session, function()
			session.ready = true
			deliver()
		end)
	else
		deliver()
	end
end

-- Node treesitter bao con trỏ ở window hiện tại, đi ngược lên tới type khớp
-- M.config.ts_node_types. nil nếu buffer không có parser hoặc con trỏ ở top-level.
local function enclosing_node()
	local ok, node = pcall(vim.treesitter.get_node) -- mặc định con trỏ + curbuf
	if not ok or not node then
		return nil
	end
	while node do
		local t = node:type()
		for _, pat in ipairs(M.config.ts_node_types) do
			if t:find(pat, 1, true) then
				return node
			end
		end
		node = node:parent()
	end
	return nil
end

-- Bắt context TẠI THỜI ĐIỂM gọi (phải còn trong visual mode để đọc selection).
-- Keymap bằng Lua function giữ nguyên visual mode nên getpos('v')/getpos('.') đọc
-- được vùng chọn. Buffer scratch/không tên -> bỏ @ref, chỉ giữ code (nếu có).
local function capture_context()
	local file = vim.fn.expand("%:.") -- tương đối với cwd; "" nếu chưa đặt tên
	if file == "" then
		file = nil
	end
	local lang = vim.bo.filetype
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then -- v / V / <C-v> (\22 = <C-v>)
		local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
		local region = vim.fn.getregion(a, b, { type = mode })
		return {
			file = file,
			lang = lang,
			code = table.concat(region, "\n"),
			l1 = math.min(a[2], b[2]),
			l2 = math.max(a[2], b[2]),
		}
	end
	-- normal mode: thử lấy function/class dưới con trỏ qua treesitter (act-on-scope
	-- kiểu CodeCompanion); ở top-level / không parser -> fallback @ref cả file.
	local node = enclosing_node()
	if node then
		local sr, _, er = node:range() -- row 0-indexed, er tính cả dòng cuối của node
		local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
		return { file = file, lang = lang, code = table.concat(lines, "\n"), l1 = sr + 1, l2 = er + 1 }
	end
	return { file = file, lang = lang }
end

-- Message hybrid: @ref (agent tự đọc cả file) + fenced block ghim đúng dòng đã chọn.
local function build_message(instruction, ctx)
	local l = { instruction, "" }
	if ctx.file then
		l[#l + 1] = ctx.l1 and ("@%s (lines %d-%d)"):format(ctx.file, ctx.l1, ctx.l2)
			or ("@%s"):format(ctx.file)
	end
	if ctx.code then
		l[#l + 1] = "```" .. (ctx.lang or "")
		vim.list_extend(l, vim.split(ctx.code, "\n", { plain = true }))
		l[#l + 1] = "```"
	end
	return table.concat(l, "\n")
end

-- Tool message SẼ tới, giải y hệt M.send: session đang sống trước, không có thì tool
-- mặc định. Phải khớp, vì tiền tố command của ECC khác nhau theo tool.
local function target_tool()
	local s = target_session()
	return (s and s.tool) or resolve_default_tool()
end

-- Skill của ECC cho action này trên tool này, hoặc nil. Tra bảng ĐÃ DÒ TRÊN ĐĨA nên
-- không bao giờ gọi tên một skill mà tool không có: nhắc tên không tồn tại chỉ khiến
-- agent đi tìm rồi bịa ra nội dung.
local function ecc_skill(action, tool)
	if not (action.skill and tool) then
		return nil
	end
	local e = ecc()
	if not e then
		return nil
	end
	return e.skills(tool.name)[action.skill] and action.skill or nil
end

-- Picker action (explain/ask/fix...). Gọi từ normal + visual (<leader>ai).
-- Mọi thứ ở đây là CẤP SELECTION: message luôn kèm @ref + khối code của đoạn đang chọn.
-- Lệnh cấp repo của ECC nằm ở M.workflows() - xem comment ở M.config.actions.
function M.actions()
	local ctx = capture_context() -- BẮT trước khi mở menu (menu thoát visual mode)
	if not (ctx.file or ctx.code) then
		notify("aiterm: no file or selection to send", "warn")
		return
	end
	-- Giải MỘT LẦN trước khi mở menu: format_item chạy cho từng dòng, để trong đó thì
	-- mỗi lần vẽ menu lại đi stat thư mục.
	local tool = target_tool()
	vim.ui.select(M.config.actions, {
		prompt = "AI action:",
		format_item = function(a)
			local icon = a.key and M.icons()[a.key]
			-- Hiện skill sẽ được nhắc kèm -> nhìn là biết mục nào có ECC đỡ lưng.
			local skill = ecc_skill(a, tool)
			return (icon and icon .. "  " or "") .. a.label .. (skill and ("   " .. skill) or "")
		end,
	}, function(choice)
		if not choice then
			return
		end
		local instr = choice.prompt
		if choice.input then
			instr = vim.fn.input(choice.input)
			if instr == "" then
				return
			end
		else
			-- Câu hỏi tự do (input) thì không gắn skill: người dùng tự quyết định hỏi gì.
			local skill = ecc_skill(choice, tool)
			if skill then
				instr = instr .. ("\nFollow the `%s` skill."):format(skill)
			end
		end
		M.send(build_message(instr, ctx), { submit = true })
	end)
end

-- Lệnh ECC CẤP REPO (<leader>aw). Tách hẳn khỏi M.actions vì chúng bỏ qua context:
-- template của /code-review mở đầu bằng `git diff --name-only HEAD`, /build-fix bằng
-- `npx tsc --noEmit`, /refactor-clean bằng `npx knip` - gửi kèm @ref hay khối code chỉ
-- là nhiễu. Dùng Snacks picker chứ không vim.ui.select: có cả trăm lệnh, cần fuzzy.
-- Tool có chạy được /slash command natively không (mặc định: có, trừ khi bảng ghi false).
local function slash_native(tool)
	return M.config.send.slash_native[tool.name] ~= false
end

-- Nội dung file lệnh ECC (đúng cái /command sẽ bung ra), dùng cho tool KHÔNG chạy
-- slash natively (codex). Thay $ARGUMENTS bằng arg; không có placeholder mà có arg
-- thì nối "Input: arg". nil nếu đọc file lỗi -> caller quay về gửi /token.
local function command_body(cm, arg)
	local ok, lines = pcall(vim.fn.readfile, cm.path)
	if not ok or not lines or #lines == 0 then
		return nil
	end
	local body = table.concat(lines, "\n")
	if body:find("$ARGUMENTS", 1, true) then
		-- %$ escape $ trong pattern; escape % trong chuỗi thay thế (gsub coi % là đặc biệt).
		-- Gán repl vào local TRƯỚC: (...):gsub trả (chuỗi, count); truyền thẳng vào gsub
		-- ngoài thì count=0 rơi vào tham số n -> gsub thay 0 lần. Local cắt còn 1 giá trị.
		local repl = (arg or ""):gsub("%%", "%%%%")
		body = body:gsub("%$ARGUMENTS", repl)
	elseif arg and arg ~= "" then
		body = body .. "\n\nInput: " .. arg
	end
	return body
end

function M.workflows()
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	local e = ecc()
	if not e then
		notify("aiterm: ECC module unavailable", "warn")
		return
	end
	-- cwd để kèm command CỤC BỘ repo (scope=project). Dùng project_cwd (realpath thật).
	local cwd = history().project_cwd()
	-- Chỉ xoay qua tool ĐÃ CÓ lệnh ECC: cho xoay vào một danh sách rỗng thì <A-t> nhìn
	-- như bị hỏng.
	local tools = {}
	for _, t in ipairs(M.config.tools) do
		if #e.command_list(t.name, cwd) > 0 then
			tools[#tools + 1] = t
		end
	end
	if #tools == 0 then
		notify("ECC not installed for any tool - use <leader>aE", "warn")
		return
	end
	-- Bắt đầu từ tool sẽ nhận message nếu nó có ECC (session đang sống > tool mặc định).
	local idx = 1
	local cur = target_tool()
	for i, t in ipairs(tools) do
		if cur and t.name == cur.name then
			idx = i
		end
	end
	ensure_hl()

	local path_args = {}
	for _, n in ipairs(M.config.workflow_args.path) do
		path_args[n] = true
	end
	local ask_args = M.config.workflow_args.ask
	local ic = M.icons()
	-- Lệnh hiện trong chế độ pinned: đã ghim HOẶC là lệnh của repo (project luôn hiện).
	local function shown_in_pinned(cm)
		return is_fav("commands", cm.name) or cm.scope == "project"
	end
	local function title_for(t, pinned)
		local n_show, n_all = 0, 0
		for _, cm in ipairs(e.command_list(t.name, cwd)) do
			n_all = n_all + 1
			if shown_in_pinned(cm) then
				n_show = n_show + 1
			end
		end
		local mode = pinned and (ic.star .. " %d pinned"):format(n_show) or ("all %d"):format(n_all)
		return ("ECC workflows (%s) · %s"):format(t.name, mode)
	end

	Snacks.picker({
		title = title_for(tools[idx], fav_count("commands") > 0),
		-- Tool nằm trong PICKER OPTS chứ không phải upvalue: finder đọc popts nên chỉ có
		-- một đường đọc state. Bug "title đổi mà list không đổi" của scope lần trước sinh
		-- ra đúng từ chỗ có hai đường.
		wf_tool = tools[idx].name,
		-- Mặc định chỉ hiện lệnh đã ghim; chưa ghim gì -> hiện tất cả (tránh list rỗng).
		pinned = fav_count("commands") > 0,
		finder = function(popts)
			local t = find_tool(popts.wf_tool) or tools[1]
			local list = e.command_list(t.name, cwd)
			-- pinned: lọc còn ghim + project. all: giữ hết, project/ghim lên đầu.
			local shown = {}
			for _, cm in ipairs(list) do
				if not popts.pinned or shown_in_pinned(cm) then
					shown[#shown + 1] = cm
				end
			end
			if not popts.pinned then
				table.sort(shown, function(a, b)
					local ra = a.scope == "project" and 0 or (is_fav("commands", a.name) and 1 or 2)
					local rb = b.scope == "project" and 0 or (is_fav("commands", b.name) and 1 or 2)
					if ra ~= rb then
						return ra < rb
					end
					return a.name < b.name
				end)
			end
			-- Canh cột theo lệnh dài nhất CỦA CHÍNH TOOL NÀY: tiền tố codex là /ecc-*
			-- nên dài hơn claude/opencode một quãng.
			local w = 0
			for _, cm in ipairs(shown) do
				w = math.max(w, #cm.invoke)
			end
			local items = {}
			for _, cm in ipairs(shown) do
				items[#items + 1] = {
					cmd = cm,
					-- tool + pad gắn thẳng lên item: format/confirm khỏi đọc upvalue đã cũ
					-- sau khi đổi tool.
					tool = t,
					pad = string.rep(" ", w - #cm.invoke + 2),
					-- desc + "fav" vào text để gõ "dead code"/"fav" cũng lọc được.
					text = (is_fav("commands", cm.name) and "fav " or "") .. cm.name .. " " .. cm.desc,
					-- file = đường dẫn thật -> dùng luôn preview file của snacks, khỏi tự
					-- dựng doc và khỏi đọc cả trăm file markdown lúc mở picker.
					file = cm.path,
				}
			end
			return items
		end,
		format = function(item)
			local cm = item.cmd
			local star = is_fav("commands", cm.name) and ic.star or " "
			local row = {
				{ star .. " ", "SnacksPickerSpecial" },
				{ ic.f_cmd .. " ", TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ cm.invoke, "SnacksPickerLabel" },
				{ item.pad },
				{ cm.desc, "SnacksPickerDimmed" },
			}
			if cm.scope == "project" then
				row[#row + 1] = { "  project", "SnacksPickerGitBranch" }
			end
			-- Tool không chạy slash natively: /ecc-* sẽ gửi dưới dạng NỘI DUNG file, không
			-- phải slash command -> báo rõ để cái /ecc-… hiện ra không gây hiểu lầm.
			if not slash_native(item.tool) then
				row[#row + 1] = { "  " .. ic.f_prompt .. " prompt", "SnacksPickerDimmed" }
			end
			return row
		end,
		preview = "file",
		-- Cùng layout với picker session (kèm fallback dọc khi terminal hẹp), nhưng
		-- footer riêng: M-t là phím duy nhất ở đây không đoán được từ nội dung.
		layout = build_layout(WF_FOOTER),
		actions = {
			-- <A-t>: xoay tool. Đổi opts + title rồi find() - find() tự gọi update_titles
			-- và update_titles đọc picker.title, nên hai thứ luôn đổi cùng một nhịp.
			aiterm_wf_tool = function(picker)
				if #tools < 2 then
					notify(("only %s has ECC commands"):format(tools[1].name), "info")
					return
				end
				idx = idx % #tools + 1
				picker.opts.wf_tool = tools[idx].name
				picker.title = title_for(tools[idx], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-f>: ghim/bỏ ghim lệnh dưới con trỏ, lưu ngay.
			aiterm_fav_toggle = function(picker, item)
				if not item then
					return
				end
				toggle_fav("commands", item.cmd.name)
				picker.title = title_for(find_tool(picker.opts.wf_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-a>: đổi giữa chỉ-ghim và tất-cả.
			aiterm_fav_all = function(picker)
				picker.opts.pinned = not picker.opts.pinned
				picker.title = title_for(find_tool(picker.opts.wf_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
		},
		win = {
			input = {
				keys = {
					["<a-t>"] = { "aiterm_wf_tool", mode = { "i", "n" }, desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", mode = { "i", "n" }, desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", mode = { "i", "n" }, desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-t>"] = { "aiterm_wf_tool", desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			local cm = item.cmd
			-- Tính ARG một lần: lệnh path -> "."; lệnh ask -> hỏi (huỷ thì không gửi).
			local arg
			if path_args[cm.name] then
				arg = "." -- lệnh nhận [path]; "." = cả project
			elseif ask_args[cm.name] then
				arg = vim.fn.input(ask_args[cm.name])
				if arg == "" then
					return -- huỷ input thì KHÔNG gửi lệnh cụt
				end
			end
			-- Tool chạy slash natively -> gửi /token (+arg). Không (codex) -> DÁN NỘI DUNG
			-- file lệnh (đúng cái /command bung ra); đọc lỗi thì quay về /token best-effort.
			local msg
			if slash_native(item.tool) then
				msg = cm.invoke .. (arg and (" " .. arg) or "")
			else
				msg = command_body(cm, arg)
				if not msg then
					notify(("could not read %s; sending slash token"):format(cm.name), "warn")
					msg = cm.invoke .. (arg and (" " .. arg) or "")
				end
			end
			picker:close()
			vim.schedule(function()
				-- tool LẤY TỪ ITEM, không phải target_tool(): sau <A-t> thì tool đang hiện
				-- khác tool mặc định, mà /ecc-* của codex dán vào session opencode là vô nghĩa.
				M.send(msg, { submit = true, tool = item.tool })
			end)
		end,
	})
end

-- Picker skill (<leader>as). KHÁC M.workflows: command là quy trình cấp repo (chạy
-- git diff / npx), còn skill là TÀI LIỆU HƯỚNG DẪN nên áp được lên đoạn code đang chọn
-- -> message dựng theo ngữ cảnh y như <leader>ai.
-- Hiện ĐỦ mọi skill, phân nhóm theo nguồn: ecc (ECC cài) / builtin (skill gốc của tool,
-- ví dụ 6 cái .system của codex) / user (bạn tự viết).
local SKILL_ORIGIN = {
	project = { "project", "SnacksPickerGitBranch" }, -- skill CỤC BỘ repo, hiện đầu
	ecc = { "ECC", nil }, -- nil -> lấy màu theo tool
	builtin = { "built-in", "SnacksPickerSpecial" },
	user = { "user", "SnacksPickerLabel" },
}

function M.skill_pick()
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	local e = ecc()
	if not e then
		notify("aiterm: ECC module unavailable", "warn")
		return
	end
	-- cwd để kèm skill CỤC BỘ repo (origin=project). Dùng project_cwd (realpath thật).
	local cwd = history().project_cwd()
	-- Chỉ xoay qua tool CÓ skill: xoay vào danh sách rỗng thì <A-t> nhìn như bị hỏng.
	local tools = {}
	for _, t in ipairs(M.config.tools) do
		if #e.skill_list(t.name, cwd) > 0 then
			tools[#tools + 1] = t
		end
	end
	if #tools == 0 then
		notify("no skills found for any tool - use <leader>aE", "warn")
		return
	end
	local idx = 1
	local cur = target_tool()
	for i, t in ipairs(tools) do
		if cur and t.name == cur.name then
			idx = i
		end
	end
	-- BẮT context TRƯỚC khi mở picker: mở picker là đổi buffer/window, capture_context
	-- lúc confirm sẽ đọc nhầm chính cửa sổ picker.
	local ctx = capture_context()
	ensure_hl()

	-- Mục hiện trong chế độ pinned: đã ghim HOẶC là skill của repo (project luôn hiện).
	local function shown_in_pinned(s)
		return is_fav("skills", s.name) or s.origin == "project"
	end
	local function title_for(t, pinned)
		local n_show, n_all = 0, 0
		for _, s in ipairs(e.skill_list(t.name, cwd)) do
			n_all = n_all + 1
			if shown_in_pinned(s) then
				n_show = n_show + 1
			end
		end
		local mode = pinned and (M.icons().star .. " %d pinned"):format(n_show) or ("all %d"):format(n_all)
		return ("Skills (%s) · %s"):format(t.name, mode)
	end

	Snacks.picker({
		title = title_for(tools[idx], fav_count("skills") > 0),
		sk_tool = tools[idx].name,
		-- Mặc định chỉ hiện mục đã ghim; chưa ghim gì -> hiện tất cả (tránh list rỗng).
		pinned = fav_count("skills") > 0,
		finder = function(popts)
			local t = find_tool(popts.sk_tool) or tools[1]
			local list = e.skill_list(t.name, cwd)
			-- pinned: lọc còn ghim + project. all: giữ hết, project/ghim lên đầu.
			local shown = {}
			for _, s in ipairs(list) do
				if not popts.pinned or shown_in_pinned(s) then
					shown[#shown + 1] = s
				end
			end
			if not popts.pinned then
				table.sort(shown, function(a, b)
					local ra = a.origin == "project" and 0 or (is_fav("skills", a.name) and 1 or 2)
					local rb = b.origin == "project" and 0 or (is_fav("skills", b.name) and 1 or 2)
					if ra ~= rb then
						return ra < rb
					end
					return a.name < b.name
				end)
			end
			local w = 0
			for _, s in ipairs(shown) do
				w = math.max(w, #s.name)
			end
			local items = {}
			for _, s in ipairs(shown) do
				items[#items + 1] = {
					skill = s,
					tool = t,
					pad = string.rep(" ", w - #s.name + 2),
					-- origin + "fav" nằm trong text -> gõ "ecc"/"project"/"fav" lọc theo nhóm.
					text = s.origin .. " " .. (is_fav("skills", s.name) and "fav " or "") .. s.name .. " " .. s.desc,
					file = s.path, -- preview thẳng SKILL.md, khỏi tự dựng doc
				}
			end
			return items
		end,
		format = function(item)
			local o = SKILL_ORIGIN[item.skill.origin] or SKILL_ORIGIN.user
			local star = is_fav("skills", item.skill.name) and M.icons().star or " "
			return {
				{ star .. " ", "SnacksPickerSpecial" },
				{ ("%-9s "):format(o[1]), o[2] or TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ item.skill.name, "SnacksPickerLabel" },
				{ item.pad },
				{ item.skill.desc, "SnacksPickerDimmed" },
			}
		end,
		preview = "file",
		layout = build_layout(SKILL_FOOTER),
		actions = {
			aiterm_skill_tool = function(picker)
				if #tools < 2 then
					notify(("only %s has skills"):format(tools[1].name), "info")
					return
				end
				idx = idx % #tools + 1
				picker.opts.sk_tool = tools[idx].name
				picker.title = title_for(tools[idx], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-f>: ghim/bỏ ghim skill dưới con trỏ, lưu ngay.
			aiterm_fav_toggle = function(picker, item)
				if not item then
					return
				end
				toggle_fav("skills", item.skill.name)
				picker.title = title_for(find_tool(picker.opts.sk_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-a>: đổi giữa chỉ-ghim và tất-cả.
			aiterm_fav_all = function(picker)
				picker.opts.pinned = not picker.opts.pinned
				picker.title = title_for(find_tool(picker.opts.sk_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
		},
		win = {
			input = {
				keys = {
					["<a-t>"] = { "aiterm_skill_tool", mode = { "i", "n" }, desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", mode = { "i", "n" }, desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", mode = { "i", "n" }, desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-t>"] = { "aiterm_skill_tool", desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			local s = item.skill
			local instr = ("Use the `%s` skill."):format(s.name)
			if s.hint then
				-- Skill khai argument-hint nghĩa là nó CẦN tham số (tdd-workflow cần
				-- đường dẫn plan). Huỷ input thì không gửi, đừng gửi lệnh cụt.
				local answer = vim.fn.input(("%s %s: "):format(s.name, s.hint))
				if answer == "" then
					return
				end
				instr = instr .. " " .. answer
			end
			picker:close()
			vim.schedule(function()
				-- Không có context thì gửi thẳng instr: build_message luôn chèn một dòng
				-- trống sau instruction (để tách với @ref), không có @ref thì dòng trống
				-- đó thành rác đuôi. M.actions không gặp ca này vì nó chặn từ đầu khi
				-- thiếu cả file lẫn code.
				local msg = (ctx.file or ctx.code) and build_message(instr, ctx) or instr
				-- tool LẤY TỪ ITEM: <A-t> cho phép chọn tool khác session đang mở.
				M.send(msg, { submit = true, tool = item.tool })
			end)
		end,
	})
end

-- Trạng thái ECC từng tool + cài/cập nhật. Dòng "ecc" trong picker biến mất sau khi
-- cài xong, nên đây là đường để cập nhật (git pull) về sau. <leader>aE.
function M.ecc()
	local e = ecc()
	if not e then
		notify("ECC module unavailable", "warn")
		return
	end
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	ensure_hl()

	local clone = e.clone_info()
	-- Kết quả <A-u> giữ ở đây để find() vẽ lại vẫn còn. nil = chưa hỏi GitHub lần nào;
	-- KHÔNG hỏi lúc mở picker: ls-remote đo được ~1s, chặn chừng đó là thấy rõ.
	local remote, remote_err
	local function title()
		if not clone then
			return "ECC  (chưa clone)"
		end
		local t = ("ECC  %s"):format(clone.version or "?")
		if clone.short then
			t = t .. " · " .. clone.short
		end
		if remote_err then
			return t .. "  (github: " .. remote_err .. ")"
		elseif remote then
			-- ASCII trong literal: file này đã ba lần bị ký tự lạ lọt vào, nên gate glyph
			-- giữ ở 0 cho dòng mới. Mũi tên/dấu ba chấm không đáng để phá lệ.
			return t .. (remote == clone.short and "  = origin" or ("  <- origin " .. remote))
		end
		return t
	end
	Snacks.picker({
		title = title(),
		finder = function()
			local items = {}
			for _, t in ipairs(M.config.tools) do
				local st = e.status(t.name)
				local it = {
					tool = t,
					state = st,
					info = e.installed_info(t.name),
					cmds = e.count(t.name),
					skills = vim.tbl_count(e.skills(t.name)),
					text = t.name .. " " .. st,
				}
				it.preview = ecc_preview(it, e, clone, remote)
				items[#items + 1] = it
			end
			return items
		end,
		format = function(item)
			local s = ECC_STATE[item.state] or ECC_STATE.unknown
			local ver = item.info and item.info.version or "-"
			if item.info and item.info.short then
				ver = ver .. " · " .. item.info.short
			end
			return {
				{ (M.icons()[item.tool.name] or " ") .. " ", TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ ("%-9s "):format(item.tool.name), "SnacksPickerLabel" },
				{ ("%-14s"):format(s[1]), s[2] },
				{ ("%-18s"):format(ver), "SnacksPickerDimmed" },
				{ ("%4d cmd  %4d skills"):format(item.cmds, item.skills), "SnacksPickerDimmed" },
			}
		end,
		-- item.preview = { text, extmarks } dựng sẵn trong finder, đúng khuôn đã dùng ở
		-- M.pick: khỏi phải đụng API preview-function của snacks.
		preview = "preview",
		layout = build_layout(ECC_FOOTER),
		actions = {
			-- <A-u>: lần DUY NHẤT plugin đi mạng, và chỉ khi bạn bấm. ls-remote chỉ hỏi
			-- HEAD của origin, không tải gì về.
			aiterm_ecc_remote = function(picker)
				notify("asking GitHub...", "info")
				e.remote_head(function(sha, err)
					remote, remote_err = sha, err
					if not picker.closed then
						picker.title = title()
						picker:find({ refresh = true })
					end
				end)
			end,
		},
		win = {
			input = {
				keys = {
					["<a-u>"] = { "aiterm_ecc_remote", mode = { "i", "n" }, desc = "check github" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-u>"] = { "aiterm_ecc_remote", desc = "check github" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()
			vim.schedule(function()
				install_ecc(item.tool)
			end)
		end,
	})
end

-- inline hints (inlay kiểu code-lens) ------------------------------------
-- 1 dòng ảo phía trên function/class ĐANG chứa con trỏ, quảng cáo <leader>ai.
-- Terminal virt_text KHÔNG click được -> hint chỉ là gợi ý trực quan, kích hoạt
-- vẫn qua <leader>ai (tác động lên đúng node dưới con trỏ, xem capture_context).
local hint_ns = vim.api.nvim_create_namespace("aiterm_hints")
local hints_on -- nil tới lần đọc đầu -> lấy từ M.config.hints.enabled
local hint_state = {} -- buf -> start-row của node đã vẽ (bỏ vẽ lại khi chưa đổi node)

local function hints_enabled()
	if hints_on == nil then
		hints_on = M.config.hints.enabled
	end
	return hints_on
end

-- Buffer file thường (buftype rỗng) và có parser treesitter.
local function hintable_buf(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
		return false
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	return ok and parser ~= nil
end

local function clear_hints(buf)
	pcall(vim.api.nvim_buf_clear_namespace, buf, hint_ns, 0, -1)
	hint_state[buf] = nil
end

-- Vẽ lại hint cho buf. Chỉ vẽ khi buf là window hiện tại (hint theo con trỏ).
refresh_hints = function(buf) -- gán vào local đã forward-declare ở mục default tool
	buf = buf or vim.api.nvim_get_current_buf()
	if not (hints_enabled() and hintable_buf(buf) and buf == vim.api.nvim_get_current_buf()) then
		clear_hints(buf)
		return
	end
	local node = enclosing_node()
	local sr = node and select(1, node:range()) or nil
	if sr == hint_state[buf] then -- cùng node -> không nhấp nháy
		return
	end
	pcall(vim.api.nvim_buf_clear_namespace, buf, hint_ns, 0, -1)
	hint_state[buf] = sr
	if not sr then
		return
	end
	-- căn theo indent dòng đầu node cho dòng ảo thẳng với code.
	local first = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
	local indent = first:match("^%s*") or ""

	-- Badge: icon+tên tool mặc định (tô màu theo tool) + action có icon + phím mờ.
	local tool = resolve_default_tool()
	local ic = M.icons()
	local thl = TOOL_HL[tool.name] or "Special"
	local vt = {
		{ indent, "Normal" },
		{ tool_icon(tool) .. " ", thl },
		{ tool.name .. "   ", thl },
	}
	for i, akey in ipairs(M.config.hints.actions or {}) do
		if i > 1 then
			vt[#vt + 1] = { " · ", "NonText" }
		end
		if ic[akey] then
			vt[#vt + 1] = { ic[akey] .. " ", thl }
		end
		vt[#vt + 1] = { akey, "Comment" }
	end
	if M.config.hints.key then
		vt[#vt + 1] = { "   " .. M.config.hints.key, "NonText" }
	end

	pcall(vim.api.nvim_buf_set_extmark, buf, hint_ns, sr, 0, {
		virt_lines = { vt },
		virt_lines_above = true,
		hl_mode = "combine",
	})
end

-- Đăng ký autocmd refresh (idempotent). Gọi từ bootstrap VeryLazy và toggle.
local hints_group
function M.setup_hints()
	ensure_hl() -- đăng ký AitermClaude/Codex/Opencode để badge có màu tool (Snacks đã load ở VeryLazy)
	if not hints_enabled() or hints_group then
		return
	end
	hints_group = vim.api.nvim_create_augroup("AitermHints", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold", "BufEnter", "TextChanged", "InsertLeave" }, {
		group = hints_group,
		callback = function(args)
			refresh_hints(args.buf)
		end,
	})
	refresh_hints()
end

-- Bật/tắt hint. Tắt -> xoá hết extmark ở mọi buffer.
function M.toggle_hints()
	hints_on = not hints_enabled()
	if hints_on then
		M.setup_hints()
		refresh_hints()
	else
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			clear_hints(b)
		end
	end
	notify("AI code hints " .. (hints_on and "on" or "off"), "info")
end

-- Đọc default tool + favorites đã lưu ngay khi require (độc lập với hint bật/tắt).
load_default()
load_favorites()

return M
