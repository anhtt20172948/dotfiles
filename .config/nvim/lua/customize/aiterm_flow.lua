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
	M.spawn({ M.config.script, "firstmate" }, vim.fn.getcwd())
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
