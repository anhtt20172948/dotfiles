local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. package.path
vim.opt.rtp:prepend(root .. "/.config/nvim")
local original = vim.fn.getcwd()
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
-- git in ra đường dẫn thật; trên macOS tempname() nằm sau symlink /var -> /private/var.
tmp = assert(vim.uv.fs_realpath(tmp))
local repo = tmp .. "/main"
local linked = tmp .. "/linked space%#"
local detached = tmp .. "/detached"
local function git(...)
	local result = vim.system({ "git", ... }, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
local function run()
	git("init", "-q", repo)
	git(
		"-C",
		repo,
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.com",
		"commit",
		"--allow-empty",
		"-qm",
		"initial"
	)
	git("-C", repo, "worktree", "add", "-qb", "feature", linked)
	git("-C", repo, "worktree", "add", "--detach", detached)
	git("-C", repo, "worktree", "lock", "--reason", "test", linked)
	vim.cmd.cd(repo)
	vim.cmd.edit(repo .. "/unsaved.txt")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "keep unsaved edits" })
	local opts, notices
	local opened = {}
	local home = tmp .. "/home"
	vim.fn.mkdir(home, "p")
	vim.env.HOME, vim.env.TREEHOUSE_ROOT, vim.env.FIRSTMATE_DIR = home, nil, nil
	_G.Snacks = {
		picker = setmetatable({
			files = function(value)
				opened[#opened + 1] = value.cwd
			end,
		}, {
			__call = function(_, value)
				opts = value
			end,
		}),
	}
	vim.notify = function(message)
		notices = message
	end
	local spec = dofile(root .. "/.config/nvim/lua/plugins/snacks.lua")[1]
	local mapping
	for _, key in ipairs(spec.keys) do
		if key[1] == "<leader>gw" then
			mapping = key
		end
	end
	assert(mapping and mapping.desc == "Git Worktrees", "worktree keymap must be discoverable")
	mapping[2]()
	assert(opts and #opts.items == 3, "picker must show all three worktrees")
	local target
	for _, item in ipairs(opts.items) do
		if item.file == linked then
			target = item
			assert(item.text:find("feature", 1, true) and item.text:find("locked", 1, true))
		elseif item.file == detached then
			assert(item.text:find("detached", 1, true))
		elseif item.file == repo then
			assert(item.text:find("current", 1, true))
		end
	end
	assert(target, "path with spaces and literal %/# must remain intact")
	local closed = false
	local picker = {
		close = function()
			closed = true
		end,
	}
	opts.confirm(picker, nil)
	assert(vim.fn.getcwd() == repo, "empty selection must not change cwd")
	opts.confirm(picker, target)
	assert(closed and vim.fn.getcwd() == linked, "confirmation must close picker and switch cwd")
	assert(#opened == 0, "confirmation must not open a file picker")
	assert(vim.api.nvim_get_current_buf() == buf, "switch must keep the current buffer")
	assert(vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified, "switch must preserve dirty buffers")
	assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "keep unsaved edits")
	mapping[2]()
	assert(#opts.items == 3, "picker must also work from linked worktree with old buffer open")
	git("-C", repo, "worktree", "remove", "--force", detached)
	local previous = vim.fn.getcwd()
	opts.confirm(picker, { file = detached, entry = { path = detached } })
	assert(vim.fn.getcwd() == previous and notices, "missing worktree must report an error without switching")
	local nested = repo .. "/.worktrees/nested"
	git("-C", repo, "worktree", "add", "--detach", nested)
	vim.fn.mkdir(nested .. "/sub", "p")
	vim.cmd.cd(nested .. "/sub")
	mapping[2]()
	local current_items = {}
	for _, item in ipairs(opts.items) do
		if item.text:find("current", 1, true) then
			current_items[#current_items + 1] = item.file
		end
	end
	assert(
		#current_items == 1 and current_items[1] == nested,
		"only the innermost worktree must be current, got: " .. table.concat(current_items, ", ")
	)
	local current_name = vim.fs.basename(repo)
	local other = tmp .. "/other"
	git("init", "-q", "-b", "main", other)
	git(
		"-C",
		other,
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.com",
		"commit",
		"--allow-empty",
		"-qm",
		"init"
	)
	-- Pool treehouse giả: <repo>-<hash>/<n>/<repo>-<n>, tạo từ repo thật.
	local pool = home .. "/.treehouse"
	local pool_main1 = pool .. "/" .. current_name .. "-abc123/1/" .. current_name .. "-1"
	local pool_main2 = pool .. "/" .. current_name .. "-abc123/2/" .. current_name .. "-2"
	local pool_other = pool .. "/other-def456/1/other-1"
	vim.fn.mkdir(pool .. "/" .. current_name .. "-abc123/3/not-a-worktree", "p")
	vim.fn.writefile({ "{}" }, pool .. "/" .. current_name .. "-abc123/treehouse-state.json")
	git("-C", repo, "worktree", "add", "--detach", pool_main1)
	git("-C", repo, "worktree", "add", "-b", "fm/task-two", pool_main2)
	git("-C", other, "worktree", "add", "-b", "fm/other-task", pool_other)
	vim.fn.writefile({ "tracked" }, pool_main2 .. "/tracked.txt")
	git("-C", pool_main2, "add", "tracked.txt")
	git("-C", pool_main2, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "tracked")
	vim.fn.writefile({ "untracked" }, pool_main1 .. "/untracked.txt")
	vim.fn.writefile({ "modified" }, pool_main2 .. "/tracked.txt")
	local state = home .. "/.local/share/firstmate/state"
	vim.fn.mkdir(state, "p")
	vim.fn.writefile({ "window=x", "worktree=" .. pool_main2, "branch=fm/task-two" }, state .. "/task-two.meta")
	vim.fn.writefile({ "worktree=" .. pool_other }, state .. "/other-task.meta")
	local before = git("-C", pool_main2, "status", "--porcelain")

	local function index_of(path)
		for i, item in ipairs(opts.items) do
			if item.file == path then
				return i
			end
		end
	end

	vim.cmd.cd(repo)
	mapping[2]()
	local by_path = {}
	for _, item in ipairs(opts.items) do
		assert(not by_path[item.file], "worktree must be listed once: " .. item.file)
		by_path[item.file] = item.text
	end
	assert(by_path[pool_other] and by_path[pool_main1] and by_path[pool_main2], "treehouse worktrees must be listed")
	assert(not by_path[pool .. "/" .. current_name .. "-abc123/3/not-a-worktree"], "non-git dirs must be skipped")
	assert(by_path[pool_main2]:find(current_name .. "  fm/task-two", 1, true), "label must show repo and branch")
	assert(by_path[pool_main2]:find("dirty", 1, true), "modified tracked file must mark dirty")
	assert(by_path[pool_main2]:find("task task-two", 1, true), "owning firstmate task must be shown")
	assert(not by_path[pool_main1]:find("dirty", 1, true), "untracked-only worktree must not be marked dirty")
	assert(by_path[pool_main1]:find("detached " .. git("-C", pool_main1, "rev-parse", "--short=7", "HEAD"), 1, true))
	assert(not by_path[pool_main1]:find("task ", 1, true), "unowned worktree has no task id")
	assert(by_path[pool_other]:find("other  fm/other-task", 1, true), "other repo name comes from the pool dir")
	assert(by_path[pool_other]:find("task other-task", 1, true))
	assert(
		index_of(pool_main1) < index_of(pool_other) and index_of(pool_main2) < index_of(pool_other),
		"current repo entries must sort first"
	)
	assert(index_of(repo) == 1, "current repo keeps git order")

	-- Từ repo khác: pool treehouse vẫn hiện, repo đó lên đầu.
	vim.cmd.cd(other)
	mapping[2]()
	assert(index_of(other) == 1 and index_of(pool_other) == 2, "cwd repo must sort first from another repo")

	-- Mở worktree treehouse: chỉ đổi cwd, git tools chạy trong đó.
	vim.cmd.cd(repo)
	mapping[2]()
	local pool_item = opts.items[index_of(pool_main2)]
	opts.confirm(picker, pool_item)
	assert(vim.fn.getcwd() == vim.uv.fs_realpath(pool_main2), "opening a treehouse worktree must change cwd")
	assert(#opened == 0, "treehouse switch must not open a file picker")
	assert(git("-C", vim.fn.getcwd(), "rev-parse", "--show-toplevel") == vim.uv.fs_realpath(pool_main2))

	assert(git("-C", pool_main2, "status", "--porcelain") == before, "picker must leave worktrees untouched")

	vim.cmd.cd(tmp)
	opts, notices = nil, nil
	mapping[2]()
	assert(
		opts and #opts.items == 3 and not notices,
		"outside Git the treehouse pool must still be listed: " .. vim.inspect({ opts and #opts.items, notices })
	)
	for _, item in ipairs(opts.items) do
		assert(not item.text:find("current", 1, true), "nothing is current outside Git")
	end
	opts = nil
	vim.env.HOME = tmp .. "/empty-home"
	mapping[2]()
	assert(not opts and notices, "outside Git without a pool must notify instead of opening an empty picker")
end
local ok, err = xpcall(run, debug.traceback)
vim.cmd.cd(original)
vim.fn.delete(tmp, "rf")
assert(ok, err)
print("git_worktrees: OK")
