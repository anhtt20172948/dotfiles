-- Picker <leader>gw: worktree của repo hiện tại (git worktree list) + worktree
-- trong pool treehouse (~/.treehouse/<repo>-<hash>/<n>/<repo>-<n>), nơi crew của
-- firstmate làm việc. CHỈ ĐỌC: không chạy treehouse, không ghi vào worktree hay
-- state của firstmate; `status` dùng --no-optional-locks để khỏi làm mới index.
local M = {}

-- Seam cho test (giống aiterm_flow): mở file picker.
function M.open_files(path)
	Snacks.picker.files({ cwd = path })
end

local function home()
	return vim.env.HOME or vim.fn.expand("~")
end

local function realpath(path)
	return vim.uv.fs_realpath(path) or path
end

--- Tên repo của một thư mục git: thư mục cha của git-common-dir (hoặc tên bare repo).
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

--- Worktree trong pool treehouse của mọi repo, tìm bằng đường dẫn (không gọi treehouse).
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

--- worktree (realpath) -> id task firstmate, đọc từ state/*.meta.
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

--- Nhánh (hoặc sha ngắn khi detached) và trạng thái dirty (chỉ file đã track, bỏ
--- qua untracked để khỏi quét cả cây), qua một lệnh status chỉ đọc cho mỗi
--- worktree; chạy song song rồi mới chờ.
local function fill_status(entries)
	local jobs = {}
	for i, entry in ipairs(entries) do
		jobs[i] = vim.system(
			{ "git", "--no-optional-locks", "-C", entry.path, "status", "--porcelain=v2", "--branch", "--untracked-files=no" },
			{ text = true }
		)
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

	-- So sánh đường dẫn thật để nhận cả cwd nằm trong thư mục con; worktree lồng sâu nhất thắng.
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
	-- Repo hiện tại trước; trong nhóm giữ thứ tự gốc (git list rồi treehouse).
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
	-- Không xóa buffer: giữ nguyên cả các thay đổi chưa lưu.
	local ok, err = pcall(vim.cmd.cd, entry.path)
	if not ok then
		return vim.notify("Cannot switch Git worktree: " .. tostring(err), vim.log.levels.ERROR)
	end
	M.open_files(entry.path)
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
