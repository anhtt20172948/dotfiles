-- kunchenguid's agent workflow in nvim: treehouse / no-mistakes / gnhf / firstmate.
-- Installed by ~/.local/bin/install_agent_workflow. Keys live in lua/plugins/aiterm.lua.
--
-- Push gate, gnhf and firstmate are NOT reimplemented here: they call the shared tmux script
-- ~/.config/tmux/scripts/ai-workflow.sh <action> (also the prefix F menu), so the rules for
-- remote init / detached HEAD / iteration limits live in one place.
-- Worktrees are the exception: the result must open as an aiterm session in nvim.
local M = {}

M.config = {
	script = vim.fn.expand("~/.config/tmux/scripts/ai-workflow.sh"),
	firstmate_dir = vim.env.FIRSTMATE_DIR or vim.fn.expand("~/.local/share/firstmate"),
	-- Skill DIRECTORY name (the lavish-axi repo installs as skill "lavish").
	axi_skills = { "gh-axi", "chrome-devtools-axi", "lavish" },
}

-- Test seam: tests replace these three functions with stubs so no real process runs.
-- exec: runs synchronously, returns { code, stdout, stderr }.
function M.exec(cmd, cwd)
	return vim.system(cmd, { cwd = cwd, text = true }):wait()
end

-- spawn: runs in the background; reports stderr on a non-zero exit.
function M.spawn(cmd, cwd)
	vim.system(cmd, { cwd = cwd, text = true }, function(res)
		if res.code ~= 0 then
			vim.schedule(function()
				M.notify(vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("exit " .. res.code), "error")
			end)
		end
	end)
end

-- float: floating terminal, KEPT open after the command ends so the output can be read.
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

--- Root of the git repo holding cwd, or nil.
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
		M.notify("not a git repo: " .. vim.fn.getcwd(), "warn")
	end
	return root
end

local function script_ok()
	if vim.fn.executable(M.config.script) == 1 then
		return true
	end
	M.notify("missing " .. M.config.script .. " (did you run ~/dotfiles/install.sh?)", "error")
	return false
end

local function in_tmux()
	return (vim.env.TMUX or "") ~= ""
end

-- actions ----------------------------------------------------------------

--- git push no-mistakes <branch> in a floating terminal. The script offers
--- `no-mistakes init` when the repo has no remote yet and refuses a detached HEAD.
function M.push_gate()
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	M.float({ M.config.script, "push" }, root)
end

--- no-mistakes pipeline monitor TUI.
function M.pipelines()
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	M.float({ M.config.script, "pipelines" }, root)
end

--- gnhf --worktree on a goal, in its own tmux window (does not block nvim).
---@param goal? string empty -> ask via vim.ui.input
function M.gnhf(goal)
	local root = require_root()
	if not (root and script_ok()) then
		return
	end
	if not in_tmux() then
		M.notify("gnhf needs tmux: the loop runs in its own window", "warn")
		return
	end
	local function run(g)
		if not g or vim.trim(g) == "" then
			return
		end
		M.spawn({ M.config.script, "gnhf", vim.trim(g) }, root)
		M.notify("gnhf started in tmux window 'gnhf'")
	end
	if goal then
		return run(goal)
	end
	vim.ui.input({ prompt = "gnhf goal: " }, run)
end

--- Focus the firstmate window, creating it when missing.
function M.firstmate()
	if not script_ok() then
		return
	end
	if not in_tmux() then
		M.notify("firstmate needs tmux: crewmates are tmux windows", "warn")
		return
	end
	-- The fzf pickers (agent/account/model/effort) need a terminal: run them in a tmux
	-- popup like prefix F; vim.system has no tty.
	local cwd = vim.fn.getcwd()
	M.spawn({
		"tmux",
		"display-popup",
		"-d",
		cwd,
		"-w",
		"70%",
		"-h",
		"60%",
		"-b",
		"rounded",
		"-T",
		" 󰚩 firstmate ",
		"-E",
		M.config.script,
		"firstmate",
	}, cwd)
end

--- Lease a worktree from the treehouse pool and open a new AI session in it.
--- --lease: no subshell, prints just the path on stdout; the worktree is held until
--- `treehouse return <path>`, so tell the user the return command.
function M.worktree()
	local root = require_root()
	if not root then
		return
	end
	if vim.fn.executable("treehouse") == 0 then
		M.notify("treehouse is missing: run install_agent_workflow", "error")
		return
	end
	local res = M.exec({ "treehouse", "get", "--lease" }, root)
	local path = vim.trim(res.stdout or "")
	if res.code ~= 0 or path == "" then
		M.notify("treehouse get --lease failed: " .. vim.trim(res.stderr or ""), "error")
		return
	end
	local aiterm = require("customize.aiterm")
	aiterm.open(aiterm.default_tool_name(), { cwd = path })
	M.notify(("worktree: %s\nwhen done: treehouse return %s"):format(path, path))
end

-- crew review ------------------------------------------------------------

-- ex: runs an ex command (test seam, so no real tab / diffview opens).
function M.ex(cmd)
	vim.cmd(cmd)
end

--- Copies (worktrees) of the firstmate crew, read from state/*.meta. READ-ONLY: never
--- touches the worker's state or worktree. Records whose worktree dir is gone are skipped.
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

--- merge-base between the task's base and the worktree HEAD. Base = origin/<base_branch>,
--- else the repo's origin/HEAD. Read-only commands (no fetch).
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
			return nil, "cannot determine the base (origin/HEAD) of " .. wt
		end
	end
	local res = M.exec({ "git", "-C", wt, "merge-base", base, "HEAD" })
	local sha = vim.trim(res.stdout or "")
	if res.code ~= 0 or sha == "" then
		return nil, ("no merge-base with %s in %s"):format(base, wt)
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

--- Open diffview of the worker's copy against its base, in diffview's own tab.
--- -C instead of tabnew + tcd leaves no extra tab: q closes the diffview tab and
--- lands straight on the old tab. Read-only: the worker is writing there.
function M.crew_open(rec)
	local sha, err = M.crew_merge_base(rec.worktree, rec.base_branch)
	if not sha then
		return M.notify(err, "error")
	end
	M.ex(("DiffviewOpen -C%s %s"):format(vim.fn.fnameescape(rec.worktree), sha))
	M.notify(("%s\nthe worker's copy, read-only: do not edit/save files here"):format(rec.worktree), "warn")
end

local function crew_stat(rec)
	local sha = M.crew_merge_base(rec.worktree, rec.base_branch)
	if not sha then
		return { "(base unknown)" }
	end
	local res = M.exec({ "git", "-C", rec.worktree, "diff", "--stat", sha })
	return vim.split(vim.trim(res.stdout or ""), "\n")
end

--- Crew worktree picker: <CR> opens a tab + diffview, <A-g> opens lazygit.
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

--- Status lines for <leader>ad (appended to the aiterm doctor).
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
