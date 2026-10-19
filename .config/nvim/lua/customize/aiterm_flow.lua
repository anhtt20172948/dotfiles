-- Agent workflow của kunchenguid trong nvim: treehouse / no-mistakes / gnhf / firstmate.
-- Cài bằng ~/.local/bin/install_agent_workflow. Phím ở lua/plugins/aiterm.lua.
--
-- Push gate, gnhf, firstmate KHÔNG tự cài lại ở đây: gọi chung script tmux
-- ~/.config/tmux/scripts/ai-workflow.sh <action> (cũng là menu prefix F), để luật
-- init remote / detached HEAD / giới hạn iteration chỉ nằm một chỗ.
-- Riêng worktree thì làm ở đây: kết quả phải mở thành session aiterm trong nvim.
local M = {}

M.config = {
	script = vim.fn.expand("~/.config/tmux/scripts/ai-workflow.sh"),
	firstmate_dir = vim.env.FIRSTMATE_DIR or vim.fn.expand("~/.local/share/firstmate"),
	-- Tên THƯ MỤC skill (repo lavish-axi cài thành skill "lavish").
	axi_skills = { "gh-axi", "chrome-devtools-axi", "lavish" },
}

-- Seam cho test: thay ba hàm này bằng stub, khỏi chạy tiến trình thật.
-- exec: chạy đồng bộ, trả { code, stdout, stderr }.
function M.exec(cmd, cwd)
	return vim.system(cmd, { cwd = cwd, text = true }):wait()
end

-- spawn: chạy nền; báo lỗi (stderr) khi thoát khác 0.
function M.spawn(cmd, cwd)
	vim.system(cmd, { cwd = cwd, text = true }, function(res)
		if res.code ~= 0 then
			vim.schedule(function()
				M.notify(vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("exit " .. res.code), "error")
			end)
		end
	end)
end

-- float: terminal nổi, GIỮ lại sau khi lệnh xong để đọc output.
function M.float(cmd, cwd)
	if _G.Snacks and Snacks.terminal then
		Snacks.terminal.open(cmd, { cwd = cwd, auto_close = false, win = { position = "float" } })
		return
	end
	vim.cmd("botright split")
	vim.fn.jobstart(cmd, { cwd = cwd, term = true })
	vim.cmd("startinsert")
end

function M.notify(msg, level)
	vim.notify(msg, vim.log.levels[(level or "info"):upper()], { title = "aiterm flow" })
end

-- helpers ----------------------------------------------------------------

--- Root của repo git chứa cwd, hoặc nil.
---@return string?
function M.git_root()
	local res = M.exec({ "git", "rev-parse", "--show-toplevel" }, vim.fn.getcwd())
	if res.code ~= 0 then
		return nil
	end
	local root = vim.trim(res.stdout or "")
	return root ~= "" and root or nil
end

local function require_root()
	local root = M.git_root()
	if not root then
		M.notify("không phải git repo: " .. vim.fn.getcwd(), "warn")
	end
	return root
end

local function script_ok()
	if vim.fn.executable(M.config.script) == 1 then
		return true
	end
	M.notify("thiếu " .. M.config.script .. " (chạy ~/dotfiles/install.sh chưa?)", "error")
	return false
end

local function in_tmux()
	return (vim.env.TMUX or "") ~= ""
end

-- actions ----------------------------------------------------------------

--- git push no-mistakes <branch> trong terminal nổi. Script lo việc hỏi
--- `no-mistakes init` khi repo chưa có remote và chặn detached HEAD.
function M.push_gate()
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	M.float({ M.config.script, "push" }, root)
end

--- TUI theo dõi pipeline no-mistakes.
function M.pipelines()
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	M.float({ M.config.script, "pipelines" }, root)
end

--- gnhf --worktree trên một goal, chạy ở window tmux riêng (không chặn nvim).
---@param goal? string bỏ trống -> hỏi qua vim.ui.input
function M.gnhf(goal)
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	if not in_tmux() then
		M.notify("gnhf cần tmux: vòng lặp chạy trong window riêng", "warn")
		return
	end
	local function run(g)
		if not g or vim.trim(g) == "" then
			return
		end
		M.spawn({ M.config.script, "gnhf", vim.trim(g) }, root)
		M.notify("gnhf đã chạy ở window tmux 'gnhf'")
	end
	if goal then
		return run(goal)
	end
	vim.ui.input({ prompt = "gnhf goal: " }, run)
end

--- Focus window firstmate, chưa có thì tạo.
function M.firstmate()
	if not script_ok() then
		return
	end
	if not in_tmux() then
		M.notify("firstmate cần tmux: crewmate là các window tmux", "warn")
		return
	end
	-- Các picker fzf (agent/account/model/effort) cần terminal: chạy trong popup
	-- tmux như prefix F, vim.system không có tty.
	local cwd = vim.fn.getcwd()
	M.spawn({
		"tmux", "display-popup", "-d", cwd, "-w", "70%", "-h", "60%", "-b", "rounded",
		"-T", " 󰚩 firstmate ", "-E", M.config.script, "firstmate",
	}, cwd)
end

--- Thuê một worktree từ pool treehouse rồi mở session AI mới trong đó.
--- --lease: không mở subshell, in đúng đường dẫn ra stdout; worktree được giữ tới
--- khi `treehouse return <path>`, nên báo lệnh trả lại cho người dùng.
function M.worktree()
	local root = require_root()
	if not root then
		return
	end
	if vim.fn.executable("treehouse") == 0 then
		M.notify("thiếu treehouse: chạy install_agent_workflow", "error")
		return
	end
	local res = M.exec({ "treehouse", "get", "--lease" }, root)
	local path = vim.trim(res.stdout or "")
	if res.code ~= 0 or path == "" then
		M.notify("treehouse get --lease lỗi: " .. vim.trim(res.stderr or ""), "error")
		return
	end
	local aiterm = require("customize.aiterm")
	aiterm.open(aiterm.default_tool_name(), { cwd = path })
	M.notify(("worktree: %s\nxong thì: treehouse return %s"):format(path, path))
end

-- crew review ------------------------------------------------------------

-- ex: chạy lệnh ex (seam cho test, khỏi mở tab / diffview thật).
function M.ex(cmd)
	vim.cmd(cmd)
end

--- Các bản sao (worktree) của crew firstmate, đọc từ state/*.meta. CHỈ ĐỌC: không
--- đụng state hay worktree của worker. Bỏ record mà thư mục worktree đã mất.
---@return { id: string, worktree: string, branch: string, project: string, base_branch: string, pr: string, kind: string }[]
function M.crew_worktrees()
	local keys = { worktree = true, branch = true, project = true, base_branch = true, pr = true, kind = true }
	local out = {}
	local files = vim.fn.glob(M.config.firstmate_dir .. "/state/*.meta", false, true)
	table.sort(files)
	for _, file in ipairs(files) do
		local ok, lines = pcall(vim.fn.readfile, file)
		if ok then
			local rec = { id = vim.fn.fnamemodify(file, ":t:r") }
			for _, line in ipairs(lines) do
				local k, v = line:match("^([%w_]+)=(.*)$")
				if k and keys[k] then
					rec[k] = v
				end
			end
			if rec.worktree and rec.worktree ~= "" and vim.fn.isdirectory(rec.worktree) == 1 then
				for k in pairs(keys) do
					rec[k] = rec[k] or ""
				end
				out[#out + 1] = rec
			end
		end
	end
	return out
end

--- merge-base giữa base của task và HEAD của worktree. Base = origin/<base_branch>,
--- không có thì origin/HEAD của repo. Chỉ lệnh đọc (không fetch).
---@return string? sha
---@return string? err
function M.crew_merge_base(wt, base_branch)
	local base
	if base_branch and base_branch ~= "" then
		base = "origin/" .. base_branch
	else
		local res = M.exec({ "git", "-C", wt, "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
		base = res.code == 0 and vim.trim(res.stdout or "") or ""
		if base == "" then
			return nil, "không xác định được base (origin/HEAD) của " .. wt
		end
	end
	local res = M.exec({ "git", "-C", wt, "merge-base", base, "HEAD" })
	local sha = vim.trim(res.stdout or "")
	if res.code ~= 0 or sha == "" then
		return nil, ("không có merge-base với %s trong %s"):format(base, wt)
	end
	return sha
end

local function crew_label(rec)
	local project = vim.fn.fnamemodify(rec.project ~= "" and rec.project or rec.worktree, ":t")
	return ("%s · %s · %s%s"):format(
		rec.id,
		project,
		rec.branch ~= "" and rec.branch or "-",
		rec.pr ~= "" and (" · PR " .. rec.pr) or ""
	)
end

--- Mở diffview của bản sao worker so với base, trong tab riêng của diffview.
--- Dùng -C thay cho tabnew + tcd để không còn tab phụ: q đóng tab diffview là
--- về thẳng tab cũ. Chỉ xem: worker đang ghi vào đó.
function M.crew_open(rec)
	local sha, err = M.crew_merge_base(rec.worktree, rec.base_branch)
	if not sha then
		return M.notify(err, "error")
	end
	M.ex(("DiffviewOpen -C%s %s"):format(vim.fn.fnameescape(rec.worktree), sha))
	M.notify(("%s\nbản sao của worker, chỉ xem, đừng sửa/lưu file ở đây"):format(rec.worktree), "warn")
end

local function crew_stat(rec)
	local sha = M.crew_merge_base(rec.worktree, rec.base_branch)
	if not sha then
		return { "(không tính được base)" }
	end
	local res = M.exec({ "git", "-C", rec.worktree, "diff", "--stat", sha })
	return vim.split(vim.trim(res.stdout or ""), "\n")
end

--- Picker các worktree của crew: <CR> mở tab + diffview, <A-g> mở lazygit.
function M.crew_review()
	local recs = M.crew_worktrees()
	if #recs == 0 then
		return M.notify("no crew running")
	end
	if not (_G.Snacks and Snacks.picker) then
		return vim.ui.select(recs, { prompt = "Crew review", format_item = crew_label }, function(rec)
			if rec then
				M.crew_open(rec)
			end
		end)
	end
	local items = {}
	for _, rec in ipairs(recs) do
		items[#items + 1] = { text = crew_label(rec), rec = rec, file = rec.worktree }
	end
	Snacks.picker({
		title = "Crew review",
		items = items,
		format = "text",
		preview = function(ctx)
			ctx.preview:reset()
			ctx.preview:set_lines(crew_stat(ctx.item.rec))
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				M.crew_open(item.rec)
			end
		end,
		actions = {
			crew_lazygit = function(picker, item)
				picker:close()
				if item then
					Snacks.lazygit({ cwd = item.rec.worktree })
				end
			end,
		},
		win = { input = { keys = { ["<a-g>"] = { "crew_lazygit", mode = { "n", "i" } } } } },
	})
end

-- doctor -----------------------------------------------------------------

--- Các dòng trạng thái cho <leader>ad (nối vào doctor của aiterm).
---@return string[]
function M.doctor_lines()
	local lines = { "", "## Agent workflow (install_agent_workflow)" }
	local function row(name, ok, detail)
		lines[#lines + 1] = ("%-20s: %s%s"):format(name, ok and "ok" or "MISSING", detail and ("  " .. detail) or "")
	end
	for _, bin in ipairs({ "treehouse", "no-mistakes", "gnhf", "gh" }) do
		local path = vim.fn.exepath(bin)
		row(bin, path ~= "", path ~= "" and path or nil)
	end
	row("firstmate", vim.fn.isdirectory(M.config.firstmate_dir .. "/.git") == 1, M.config.firstmate_dir)
	row("ai-workflow.sh", vim.fn.executable(M.config.script) == 1, M.config.script)
	for _, skill in ipairs(M.config.axi_skills) do
		local found = vim.fn.isdirectory(vim.fn.expand("~/.agents/skills/" .. skill)) == 1
			or vim.fn.isdirectory(vim.fn.expand("~/.claude/skills/" .. skill)) == 1
		row("skill " .. skill, found)
	end
	local root = M.git_root()
	if root then
		local has_remote = M.exec({ "git", "remote", "get-url", "no-mistakes" }, root).code == 0
		row("remote no-mistakes", has_remote, has_remote and root or "-> no-mistakes init")
	end
	return lines
end

return M
