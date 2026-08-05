-- AI terminal (tmux-style): chạy Codex / Claude / opencode trong một vsplit phải.
-- Nhiều session mỗi tool (codex-1, codex-2, claude-1...). Picker <leader>aa liệt kê
-- các session đang chạy để attach + mục "+ New <tool>" để tạo mới.
--
-- 2 keybindings:
--   <C-Space> (trong AI pane) -> quay lại code (pane vẫn mở, session vẫn chạy)
--   <C-w>p    (trong editor)   -> attach/focus AI pane (session gần nhất)
local M = {}

M.config = {
	tools = {
		{ name = "claude", cmd = "claude", icon = "󰚩 " },
		{ name = "codex", cmd = "codex", icon = " " },
		{ name = "opencode", cmd = "opencode", icon = " " },
	},
	win = { width = 0.4 }, -- tỉ lệ rộng của vsplit
	start_insert = true,
}

-- state ------------------------------------------------------------------
local win = nil -- handle vsplit dùng chung (một pane, swap buffer)
local sessions = {} -- array: { id, tool, buf, job }
local counters = {} -- tool.name -> số đếm để đặt id
local last_session = nil -- id session attach gần nhất

-- helpers ----------------------------------------------------------------
local function win_valid()
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

-- 0.11-safe: ưu tiên jobstart{term=true}, fallback termopen ở bản cũ.
local function start_term(buf, cmd)
	return vim.api.nvim_buf_call(buf, function()
		if vim.fn.has("nvim-0.11") == 1 then
			return vim.fn.jobstart(cmd, { term = true })
		end
		return vim.fn.termopen(cmd)
	end)
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
	return s ~= nil
		and s.buf
		and vim.api.nvim_buf_is_valid(s.buf)
		and s.job
		and vim.fn.jobwait({ s.job }, 0)[1] == -1
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
local function new_session(tool)
	if vim.fn.executable(tool.cmd) ~= 1 then
		notify(("không tìm thấy binary '%s' trong PATH"):format(tool.cmd), "warn")
		return nil
	end

	counters[tool.name] = (counters[tool.name] or 0) + 1
	local id = tool.name .. "-" .. counters[tool.name]

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide"
	local job = start_term(buf, tool.cmd)
	pcall(vim.api.nvim_buf_set_name, buf, "aiterm://" .. id)

	local session = { id = id, tool = tool, buf = buf, job = job }
	sessions[#sessions + 1] = session
	set_term_keymaps(buf)

	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		once = true,
		callback = function()
			remove_session(id)
		end,
	})

	return session
end

local function attach(session)
	if not session then
		return
	end
	ensure_win(session.buf, (session.tool.icon or "") .. session.id)
	last_session = session.id
	if M.config.start_insert then
		vim.cmd("startinsert")
	end
end

-- public -----------------------------------------------------------------

-- Tạo session mới cho tool (theo tên) rồi attach. Dùng cho lệnh/keymap tạo nhanh.
function M.open(name)
	local tool
	for _, t in ipairs(M.config.tools) do
		if t.name == name then
			tool = t
		end
	end
	if not tool then
		vim.notify("aiterm: unknown tool '" .. tostring(name) .. "'", vim.log.levels.ERROR)
		return
	end
	attach(new_session(tool))
end

-- Chọn qua snacks picker: session đang chạy (attach) ở đầu + "+ New <tool>".
function M.pick()
	if not (_G.Snacks and Snacks.picker) then
		vim.notify("aiterm: cần snacks.nvim picker", vim.log.levels.ERROR)
		return
	end

	local items = {}
	for _, s in ipairs(sessions) do
		if is_alive(s) then
			items[#items + 1] = {
				kind = "attach",
				session = s,
				label = "● " .. (s.tool.icon or "") .. s.id,
			}
		end
	end
	for _, t in ipairs(M.config.tools) do
		items[#items + 1] = {
			kind = "new",
			tool = t,
			label = "  " .. (t.icon or "") .. "+ New " .. t.name,
		}
	end

	Snacks.picker.select(items, {
		prompt = "AI sessions:",
		format_item = function(it)
			return it.label
		end,
	}, function(choice)
		if not choice then
			return
		end
		if choice.kind == "attach" then
			attach(choice.session)
		else
			attach(new_session(choice.tool))
		end
	end)
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

-- Rời focus khỏi pane (pane vẫn mở). Thường dùng bằng <C-Space> trong terminal.
function M.hide()
	if win_valid() and vim.api.nvim_get_current_win() == win then
		vim.cmd("wincmd p")
	end
end

-- Toggle: đang focus pane -> rời; nếu không -> focus/attach.
function M.toggle()
	if win_valid() and vim.api.nvim_get_current_win() == win then
		M.hide()
	else
		M.focus()
	end
end

return M
