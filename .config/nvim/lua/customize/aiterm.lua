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
-- !! ICON: CHỈ dùng codepoint <= U+FFFF (vùng PUA U+E000-U+F8FF) !!
-- Font chính là 'SFMono Nerd Font' (kitty.conf) - bản patch Nerd Fonts v2, cmap
-- chỉ tới U+FD46, KHÔNG có mặt phẳng 15. Mọi glyph MDI-v3 kiểu U+F0xxx (bản cũ
-- của file này dùng U+F06A9, U+F0109, U+F0349 - cố ý viết bằng codepoint để file
-- này luôn sạch glyph non-BMP) rơi xuống fallback JetBrainsMono NF -> khác
-- typeface, khác advance width, nhìn lệch hẳn so với chữ xung quanh.
-- Check trước khi thêm icon mới:
--   python3 -c "print(hex(ord('<glyph>')))"   -- phải <= 0xFFFF
local M = {}

M.config = {
	tools = {
		{
			name = "claude",
			cmd = "claude",
			icon = "  ", -- U+F0D0 magic
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
			icon = " ", -- U+F121 code
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
			-- thì không có -> path làm fallback cho tool_cmd().
			path = vim.fn.expand("~/.opencode/bin/opencode"),
			icon = " ", -- U+F489 terminal
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
---@param opts? { args?: string[], cwd?: string, title?: string }
local function new_session(tool, opts)
	opts = opts or {}
	local exe = tool_cmd(tool)
	if not exe then
		notify(("binary '%s' not found in PATH"):format(tool.cmd), "warn")
		return nil
	end

	-- jobstart throw E475 nếu cwd không tồn tại (session cũ của repo đã xoá).
	local cwd = opts.cwd
	if cwd and not vim.uv.fs_stat(cwd) then
		notify(("cwd no longer exists: %s"):format(cwd), "warn")
		cwd = nil
	end

	counters[tool.name] = (counters[tool.name] or 0) + 1
	local id = tool.name .. "-" .. counters[tool.name]

	local cmd = { exe }
	vim.list_extend(cmd, opts.args or {})

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
		label = (tool.icon or "") .. id .. (opts.title and (" · " .. opts.title) or ""),
	}
	sessions[#sessions + 1] = session
	-- set_term_keymaps ở đây -> mọi đường (new/resume/fork/browse) đều có <C-Space>.
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
	ensure_win(session.buf, session.label or ((session.tool.icon or "") .. session.id))
	last_session = session.id
	if M.config.start_insert then
		vim.cmd("startinsert")
	end
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
-- Xem cảnh báo ICON ở đầu file trước khi đổi mấy glyph này.
local KIND = {
	live = { "● ", "SnacksPickerGitStatusStaged" }, -- U+25CF
	past = { " ", "SnacksPickerTime" }, -- U+F1DA history
	new = { " ", "SnacksPickerLabel" }, -- U+F067 plus
	browse = { " ", "SnacksPickerSpecial" }, -- U+F002 search
}
local ICON_BRANCH = " " -- U+F418 git-branch
local ICON_ALL_DIRS = " " -- U+F07C folder-open (badge {flags} của scope)

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
		add("updated", os.date("%Y-%m-%d %H:%M", e.time) .. " (" .. Snacks.picker.util.reltime(e.time) .. ")")
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
	local kind = KIND[item.kind] or KIND.past
	local tool = item.tool

	ret[#ret + 1] = { kind[1], kind[2], virtual = true }

	-- segs: metadata theo thứ tự hiển thị; `drop` càng lớn càng bị bỏ trước khi hẹp.
	local segs = { { (tool.icon or "") .. tool.name, "SnacksPickerDimmed" } }
	local title, title_hl = nil, "SnacksPickerFile"

	if item.kind == "live" then
		title = item.session.title or item.session.id
		segs[#segs + 1] = { item.session.id, "SnacksPickerBold", drop = 2 }
		segs[#segs + 1] = { "running", "SnacksPickerGitStatusStaged" }
	elseif item.kind == "past" then
		local e = item.entry
		title = e.title or e.id
		if e.branch then
			segs[#segs + 1] = { ICON_BRANCH .. e.branch, "SnacksPickerGitBranch", drop = 2 }
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
		title = "New " .. tool.name .. " session"
		title_hl = "SnacksPickerLabel"
	else
		title = table.concat(vim.list_extend({ tool.cmd }, tool.browse or {}), " ")
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

	-- 3 = icon (2 cột) + 1 cột đệm giữa title và meta
	local meta = fit_meta(segs, math.max(0, list_w - 3 - MIN_TITLE))
	local avail = list_w - 3 - meta_width(meta)
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
local FOOTER = {
	{ " ⏎ ", "SnacksPickerLabel" },
	{ "resume  ", "SnacksPickerDimmed" },
	{ "^x ", "SnacksPickerLabel" },
	{ "new  ", "SnacksPickerDimmed" },
	{ "^o ", "SnacksPickerLabel" },
	{ "fork  ", "SnacksPickerDimmed" },
	{ "⌥a ", "SnacksPickerLabel" },
	{ "scope  ", "SnacksPickerDimmed" },
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
		scope_cwd = history().project_cwd()
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

	for _, t in ipairs(M.config.tools) do
		items[#items + 1] = { kind = "new", tool = t, text = "new " .. t.name }
	end
	for _, t in ipairs(M.config.tools) do
		if t.browse then
			items[#items + 1] = { kind = "browse", tool = t, text = "browse " .. t.name }
		end
	end

	for _, it in ipairs(items) do
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
	local e = history().list(history().project_cwd(), 1)[1]
	if not e then
		return M.pick()
	end
	M.resume(e)
end

--- Picker chính: live session + session cũ trên đĩa + tạo mới + fallback.
---@param opts? { scope?: "cwd"|"all" }
function M.pick(opts)
	if not (_G.Snacks and Snacks.picker) then
		vim.notify("aiterm: snacks.nvim picker required", vim.log.levels.ERROR)
		return
	end
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
		toggles = { all_dirs = { icon = ICON_ALL_DIRS, value = true } },
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
