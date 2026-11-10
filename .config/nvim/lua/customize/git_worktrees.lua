-- <leader>gw picker: worktrees of the current repo (git worktree list) plus worktrees
-- in the treehouse pool (~/.treehouse/<repo>-<hash>/<n>/<repo>-<n>), where firstmate
-- crews work. READ-ONLY: never runs treehouse, never writes to a worktree or
-- firstmate state; `status` uses --no-optional-locks so the index is not refreshed.
local M = {}

local function home()
	return vim.env.HOME or vim.fn.expand("~")
end

local function realpath(path)
	return vim.uv.fs_realpath(path) or path
end

--- Repo name of a git dir: parent of the git-common-dir (or the bare repo name).
---@return string?
local function repo_name(cwd)
	local res = vim.system(
		{ "git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir" },
		{ text = true }
	)
		:wait()
	if res.code ~= 0 then
		return nil
	end
	local dir = vim.trim(res.stdout)
	if vim.fs.basename(dir) == ".git" then
		dir = vim.fs.dirname(dir)
	end
	return (vim.fs.basename(dir):gsub("%.git$", ""))
end

---@return table[]? entries
---@return string? err
local function git_entries(cwd)
	local result = vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain", "-z" }, { text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or "Git failed")
	end
	local entries = {}
	for _, record in ipairs(vim.split(result.stdout, "\0\0", { plain = true, trimempty = true })) do
		local fields = vim.split(record, "\0", { plain = true, trimempty = true })
		local path = fields[1]:match("^worktree (.*)$")
		local entry = { path = path, branch = "detached", labels = {} }
		local bare = false
		for _, field in ipairs(fields) do
			entry.branch = field:match("^branch refs/heads/(.*)$") or entry.branch
			entry.sha = field:match("^HEAD (%x+)$") or entry.sha
			bare = bare or field == "bare"
			if field:match("^locked") then
				entry.labels[#entry.labels + 1] = "locked"
			elseif field:match("^prunable") then
				entry.labels[#entry.labels + 1] = "prunable"
			end
		end
		if path and not bare then
			entries[#entries + 1] = entry
		end
	end
	return entries
end

--- Worktrees in every repo's treehouse pool, found by path (treehouse is not called).
local function treehouse_entries()
	local root = vim.env.TREEHOUSE_ROOT or (home() .. "/.treehouse")
	local entries = {}
	local paths = vim.fn.glob(root .. "/*/*/*", false, true)
	table.sort(paths)
	for _, path in ipairs(paths) do
		local pool = vim.fs.basename(vim.fs.dirname(vim.fs.dirname(path)))
		if vim.uv.fs_stat(path .. "/.git") then
			entries[#entries + 1] = {
				path = path,
				branch = "detached",
				labels = {},
				repo = pool:gsub("%-%x%x%x%x%x%x$", ""),
			}
		end
	end
	return entries
end

--- worktree (realpath) -> firstmate task id, read from state/*.meta.
local function task_ids()
	local dir = vim.env.FIRSTMATE_DIR or (home() .. "/.local/share/firstmate")
	local ids = {}
	local files = vim.fn.glob(dir .. "/state/*.meta", false, true)
	table.sort(files)
	for _, file in ipairs(files) do
		local ok, lines = pcall(vim.fn.readfile, file)
		for _, line in ipairs(ok and lines or {}) do
			local worktree = line:match("^worktree=(.+)$")
			if worktree then
				ids[realpath(worktree)] = vim.fn.fnamemodify(file, ":t:r")
			end
		end
	end
	return ids
end

--- Branch (or short sha when detached) and dirty state (tracked files only; untracked
--- are skipped to avoid scanning the whole tree), via one read-only status per
--- worktree; all run in parallel before waiting.
local function fill_status(entries)
	local jobs = {}
	for i, entry in ipairs(entries) do
		jobs[i] = vim.system({
			"git",
			"--no-optional-locks",
			"-C",
			entry.path,
			"status",
			"--porcelain=v2",
			"--branch",
			"--untracked-files=no",
		}, { text = true })
	end
	for i, entry in ipairs(entries) do
		local res = jobs[i]:wait()
		if res.code == 0 then
			local head = res.stdout:match("# branch%.head ([^\n]*)")
			local oid = res.stdout:match("# branch%.oid (%x+)")
			if head == "(detached)" then
				entry.branch = "detached " .. (oid and oid:sub(1, 7) or "?")
			elseif head then
				entry.branch = head
			end
			entry.dirty = res.stdout:find("\n[12u] ") ~= nil
		elseif entry.branch == "detached" and entry.sha then
			entry.branch = "detached " .. entry.sha:sub(1, 7)
		end
	end
end

local function build_entries(cwd)
	local entries, err = git_entries(cwd)
	local repo = repo_name(cwd)
	for _, entry in ipairs(entries or {}) do
		entry.repo = repo
	end
	local by_path = {}
	for _, entry in ipairs(entries or {}) do
		entry.actual = realpath(entry.path)
		by_path[entry.actual] = entry
	end
	for _, entry in ipairs(treehouse_entries()) do
		entry.actual = realpath(entry.path)
		if not by_path[entry.actual] then
			entries = entries or {}
			entries[#entries + 1] = entry
			by_path[entry.actual] = entry
		end
	end
	if not entries or #entries == 0 then
		return nil, err
	end

	-- Compare real paths so a cwd in a subdirectory matches too; the deepest worktree wins.
	local current, current_entry = realpath(cwd), nil
	for _, entry in ipairs(entries) do
		if
			(current == entry.actual or vim.startswith(current, entry.actual .. "/"))
			and (not current_entry or #entry.actual > #current_entry.actual)
		then
			current_entry = entry
		end
	end
	if current_entry then
		current_entry.labels[#current_entry.labels + 1] = "current"
	end

	local ids = task_ids()
	fill_status(entries)
	for index, entry in ipairs(entries) do
		entry.index = index
		entry.task = ids[entry.actual]
	end
	-- Current repo first; within a group keep the source order (git list, then treehouse).
	table.sort(entries, function(a, b)
		local a_cur, b_cur = a.repo == repo, b.repo == repo
		if a_cur ~= b_cur then
			return a_cur
		end
		if a.repo ~= b.repo then
			return (a.repo or "") < (b.repo or "")
		end
		return a.index < b.index
	end)
	return entries
end

local function label(entry)
	local tags = vim.list_extend({}, entry.labels)
	if entry.dirty then
		tags[#tags + 1] = "dirty"
	end
	if entry.task then
		tags[#tags + 1] = "task " .. entry.task
	end
	local suffix = #tags > 0 and (" [" .. table.concat(tags, ", ") .. "]") or ""
	return ("%s  %s  %s%s"):format(entry.repo or "?", entry.branch, entry.path, suffix)
end

function M.open(entry)
	-- Do not delete buffers: unsaved changes stay intact.
	local ok, err = pcall(vim.api.nvim_set_current_dir, entry.path)
	if not ok then
		return vim.notify("Cannot switch Git worktree: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.pick()
	local entries, err = build_entries(vim.fn.getcwd())
	if not entries then
		vim.notify("Cannot list Git worktrees: " .. (err or "none found"), vim.log.levels.WARN)
		return
	end

	local items = {}
	for _, entry in ipairs(entries) do
		items[#items + 1] = { file = entry.path, text = label(entry), entry = entry }
	end

	return Snacks.picker({
		title = "Git Worktrees",
		items = items,
		format = "text",
		layout = { preview = false },
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()
			M.open(item.entry)
		end,
	})
end

return M
