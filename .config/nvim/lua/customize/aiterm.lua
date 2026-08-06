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
		branch = c(0xF418), -- git-branch
		all_dirs = c(0xF07C), -- folder-open
		-- action icon (dùng ở inlay hint + menu <leader>ai). Toàn Font-Awesome cổ
		-- điển U+F0xx (<= U+F0C3) nên chắc chắn nằm trong cmap SFMono NF v2.
		explain = c(0xF05A), -- info-circle
		ask = c(0xF059), -- question-circle
		fix = c(0xF0AD), -- wrench
		review = c(0xF06E), -- eye
		tests = c(0xF0C3), -- flask
		refactor = c(0xF021), -- refresh
		docs = c(0xF02D), -- book
	},
	unicode = {
		claude = c(0x25C6), -- ◆
		codex = c(0x25FC), -- ◼
		opencode = c(0x25B2), -- ▲
		live = c(0x25CF), -- ●
		past = c(0x21BA), -- ↺
		new = "+",
		browse = c(0x00BB), -- »
		-- KHÔNG dùng U+26A0 warning: đã kiểm là THIẾU trong SFMono NF.
		install = c(0x2193), -- ↓
		branch = c(0x21B3), -- ↳
		all_dirs = c(0x25A4), -- ▤
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
		branch = "@",
		all_dirs = "/",
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
		ready = { min_ms = 250, quiet_ms = 400, max_ms = 10000, interval_ms = 120 },
		submit_delay = 120,
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
	actions = {
		{ key = "explain", label = "Explain", prompt = "Explain what this code does, step by step." },
		{ key = "ask", label = "Ask a question", input = "Ask about this code: " },
		{ key = "fix", label = "Fix bugs", prompt = "Find and fix any bugs in this code. Explain the fix." },
		{ key = "review", label = "Review", prompt = "Review this code for correctness, edge cases, and style issues." },
		{ key = "tests", label = "Write tests", prompt = "Write tests for this code." },
		{ key = "refactor", label = "Refactor", prompt = "Refactor this code to be clearer and more idiomatic, without changing its behavior." },
		{ key = "docs", label = "Add docs", prompt = "Add documentation/docstrings to this code." },
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
	return "`" .. table.concat(parts, " ") .. "`"
end

-- Preview build ngay trong finder (dữ liệu đã có sẵn trong RAM từ discovery)
-- -> không đọc lại file jsonl 5 MB khi di chuyển con trỏ.
local function preview_text(item)
	local l = {}
	local function add(k, v)
		if v and v ~= "" then
			l[#l + 1] = ("**%s:** %s"):format(k, v)
		end
	end

	-- BẮT BUỘC early-return: nhánh fallthrough cuối hàm đọc item.entry (nil với
	-- install) -> lỗi ngay trong finder, picker không mở nổi.
	if item.kind == "install" then
		l[#l + 1] = "# Install " .. item.tool.name
		l[#l + 1] = ""
		add("command", "`" .. tostring(item.tool.install) .. "`")
		l[#l + 1] = ""
		l[#l + 1] = "Downloads and runs a remote script. Read the URL before continuing."
		l[#l + 1] = "Press <CR> to run it in the AI pane - you will be asked to confirm first."
		return table.concat(l, "\n")
	end

	if item.kind == "new" then
		l[#l + 1] = "# New " .. item.tool.name
		add("cwd", vim.fn.fnamemodify(history().project_cwd(), ":~"))
		l[#l + 1] = ""
		l[#l + 1] = cmdline(item.tool)
		return table.concat(l, "\n")
	end

	if item.kind == "browse" then
		l[#l + 1] = "# " .. item.tool.name .. ": " .. (item.tool.browse_label or "own picker")
		l[#l + 1] = ""
		l[#l + 1] = "Fallback when discovery finds nothing — schema changed, another machine's DB, etc."
		l[#l + 1] = ""
		l[#l + 1] = cmdline(item.tool, item.tool.browse)
		return table.concat(l, "\n")
	end

	if item.kind == "live" then
		l[#l + 1] = "# " .. item.session.id .. " (running)"
		add("title", item.session.title)
		add("cwd", item.cwd and vim.fn.fnamemodify(item.cwd, ":~"))
		add("job", tostring(item.session.job))
		return table.concat(l, "\n")
	end

	local e = item.entry
	l[#l + 1] = "# " .. (e.title or e.id)
	add("tool", e.tool)
	add("id", e.id)
	add("cwd", e.cwd and vim.fn.fnamemodify(e.cwd, ":~"))
	add("branch", e.branch)
	if e.time and e.time > 0 then
		add("updated", os.date("%Y-:::::::::::::::::::::::::kjkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk%m-%d %H:%M", e.time) .. " (" .. Snacks.picker.util.reltime(e.time) .. ")")
	end
	if e.prompt then
		l[#l + 1] = ""
		l[#l + 1] = "## Last prompt"
		l[#l + 1] = ""
		l[#l + 1] = "```"
		vim.list_extend(l, vim.split(e.prompt, "\n", { plain = true }))
		l[#l + 1] = "```"
	end
	l[#l + 1] = ""
	l[#l + 1] = cmdline(item.tool, item.tool.resume(e.id))
	return table.concat(l, "\n")
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

-- Tự khai layout.layout thì snacks BỎ QUA toàn bộ preset resolution
-- (config/init.lua: `if not (layout.layout and layout.layout[1])`), nghĩa là mất
-- luôn fallback sang "vertical" khi terminal hẹp. Nên phải tự branch, dùng đúng
-- ngưỡng 120 cột mà preset mặc định của snacks đang dùng.
local function build_layout()
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
				footer = FOOTER,
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
				footer = FOOTER,
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
		else
			it.title = table.concat(it.tool.browse or {}, " ")
		end
		it.preview = { text = preview_text(it), ft = "markdown" }
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
	history().doctor()
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
		layout = build_layout(),
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
--   4. tạo mới bằng resolve_default_tool() -> trả kèm fresh=true để hoãn lần gửi đầu.
-- Trả về: session, fresh(boolean). session=nil nếu tạo mới thất bại.
local function target_session()
	if win_valid() then
		local buf = vim.api.nvim_win_get_buf(win)
		for _, s in ipairs(sessions) do
			if s.buf == buf and is_alive(s) then
				return s, false
			end
		end
	end
	local s = last_session and find(last_session)
	if is_alive(s) then
		return s, false
	end
	for _, cand in ipairs(sessions) do
		if is_alive(cand) then
			return cand, false
		end
	end
	local created = new_session(resolve_default_tool(), { cwd = history().project_cwd() })
	if created then
		created.ready = false -- session vừa tạo: M.send phải chờ CLI boot xong (when_ready)
	end
	return created, true
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
---@param opts? { submit?: boolean }
function M.send(text, opts)
	opts = opts or {}
	local session = target_session() -- (fresh flag không cần: dựa vào session.ready)
	if not session then
		return -- new_session đã notify lý do (binary not found ...)
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

-- Picker action (explain/ask/fix...). Gọi từ normal + visual (<leader>ai).
function M.actions()
	local ctx = capture_context() -- BẮT trước khi mở menu (menu thoát visual mode)
	if not (ctx.file or ctx.code) then
		notify("aiterm: no file or selection to send", "warn")
		return
	end
	vim.ui.select(M.config.actions, {
		prompt = "AI action:",
		format_item = function(a)
			local icon = a.key and M.icons()[a.key]
			return (icon and icon .. "  " or "") .. a.label
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
		end
		M.send(build_message(instr, ctx), { submit = true })
	end)
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

-- Đọc default tool đã lưu ngay khi require (độc lập với việc hint bật hay tắt).
load_default()

return M
