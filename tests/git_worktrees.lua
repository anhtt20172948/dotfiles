local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. package.path
local original = vim.fn.getcwd()
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local repo = tmp .. "/main"
local linked = tmp .. "/linked space"
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
	_G.Snacks = {
		picker = function(value)
			opts = value
		end,
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
	assert(target, "path with spaces must remain intact")
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
	assert(vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified, "switch must preserve dirty buffers")
	assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "keep unsaved edits")
	mapping[2]()
	assert(#opts.items == 3, "picker must also work from linked worktree with old buffer open")
	git("-C", repo, "worktree", "remove", "--force", detached)
	local previous = vim.fn.getcwd()
	opts.confirm(picker, { file = detached })
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
	vim.cmd.cd(tmp)
	opts, notices = nil, nil
	mapping[2]()
	assert(not opts and notices, "outside Git must notify instead of opening an empty picker")
end
local ok, err = xpcall(run, debug.traceback)
vim.cmd.cd(original)
vim.fn.delete(tmp, "rf")
assert(ok, err)
print("git_worktrees: OK")
