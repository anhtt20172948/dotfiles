-- Run with: nvim --headless -u NONE -i NONE -l tests/aiterm_crew_review.lua <repo-root>
-- Dùng git thật trên repo tạm; chỉ stub ex/notify để khỏi mở tab / diffview.
local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

local flow = require("customize.aiterm_flow")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/state", "p")
flow.config.firstmate_dir = tmp

local function git(dir, ...)
	local res = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
	assert(res.code == 0, "git failed: " .. (res.stderr or ""))
	return vim.trim(res.stdout)
end

-- Repo gốc có origin; worktree là clone, có commit riêng + thay đổi chưa commit.
local origin = tmp .. "/origin.git"
local wt = tmp .. "/wt"
vim.system({ "git", "init", "-q", "--bare", "-b", "main", origin }):wait()
vim.system({ "git", "clone", "-q", origin, wt }):wait()
git(wt, "config", "user.email", "t@t")
git(wt, "config", "user.name", "t")
vim.fn.writefile({ "one" }, wt .. "/a.txt")
git(wt, "add", ".")
git(wt, "commit", "-qm", "base")
git(wt, "push", "-q", "origin", "HEAD:main")
git(wt, "fetch", "-q")
git(wt, "remote", "set-head", "origin", "main")
local base_sha = git(wt, "rev-parse", "HEAD")
vim.fn.writefile({ "two" }, wt .. "/b.txt")
git(wt, "add", ".")
git(wt, "commit", "-qm", "work")

local function meta(id, lines)
	vim.fn.writefile(lines, tmp .. "/state/" .. id .. ".meta")
end
meta("alpha", {
	"worktree=" .. wt,
	"branch=fm/alpha",
	"project=/p/dotfiles",
	"base_branch=main",
	"pr=12",
	"kind=ship",
	"harness=claude",
})
meta("beta", { "worktree=" .. wt, "branch=fm/beta", "project=/p/dotfiles" })
meta("gone", { "worktree=" .. tmp .. "/missing", "branch=fm/gone" })
meta("nowt", { "branch=fm/nowt" })

local notes, cmds
flow.notify = function(msg, level)
	notes[#notes + 1] = { msg = msg, level = level or "info" }
end
flow.ex = function(c)
	cmds[#cmds + 1] = c
end

local function test(name, fn)
	notes, cmds = {}, {}
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
		os.exit(1)
	end
end

test("crew_worktrees parses meta and skips missing worktrees", function()
	local recs = flow.crew_worktrees()
	assert(#recs == 2, vim.inspect(recs))
	assert(recs[1].id == "alpha" and recs[1].worktree == wt and recs[1].branch == "fm/alpha")
	assert(recs[1].base_branch == "main" and recs[1].pr == "12" and recs[1].kind == "ship")
	assert(recs[2].id == "beta" and recs[2].base_branch == "" and recs[2].pr == "")
end)

test("merge base uses origin/<base_branch> and falls back to origin/HEAD", function()
	assert(flow.crew_merge_base(wt, "main") == base_sha)
	assert(flow.crew_merge_base(wt, "") == base_sha)
end)

test("merge base reports an unknown base instead of erroring", function()
	local sha, err = flow.crew_merge_base(wt, "nope")
	assert(sha == nil and err:find("origin/nope", 1, true), tostring(err))
end)

test("crew_open runs diffview at the merge base in the worker copy without a helper tab", function()
	flow.crew_open(flow.crew_worktrees()[1])
	assert(#cmds == 1, vim.inspect(cmds))
	assert(cmds[1] == "DiffviewOpen -C" .. vim.fn.fnameescape(wt) .. " " .. base_sha, vim.inspect(cmds))
	assert(notes[1].msg:find("chỉ xem", 1, true), "must remind it is the worker's copy")
end)

test("crew_open with an unresolvable base opens nothing", function()
	flow.crew_open({ worktree = wt, base_branch = "nope" })
	assert(#cmds == 0 and notes[1].level == "error")
end)

test("crew_review says no crew running when there are no records", function()
	flow.config.firstmate_dir = tmp .. "/empty"
	flow.crew_review()
	assert(#cmds == 0 and notes[1].msg == "no crew running", vim.inspect(notes))
	flow.config.firstmate_dir = tmp
end)

test("crew_review falls back to vim.ui.select and opens the choice", function()
	local real = vim.ui.select
	vim.ui.select = function(items, opts, cb)
		assert(
			opts.format_item(items[1]):find("alpha · dotfiles · fm/alpha · PR 12", 1, true),
			opts.format_item(items[1])
		)
		cb(items[1])
	end
	_G.Snacks = nil
	flow.crew_review()
	vim.ui.select = real
	assert(cmds[1] == "DiffviewOpen -C" .. vim.fn.fnameescape(wt) .. " " .. base_sha, vim.inspect(cmds))
end)

-- Chạy diffview thật (bản ghim trong tests/fixtures): đóng review phải về đúng tab/cwd cũ.
local diffview = root .. "/tests/fixtures/diffview.nvim"
test("closing a real crew review returns to the starting tab and cwd", function()
	vim.opt.runtimepath:append(diffview)
	vim.cmd("runtime! plugin/diffview.lua")
	require("diffview").setup({ use_icons = false })
	flow.ex = vim.cmd
	local start_tab, start_cwd, start_count =
		vim.api.nvim_get_current_tabpage(), vim.fn.getcwd(), #vim.api.nvim_list_tabpages()
	flow.crew_open(flow.crew_worktrees()[1])
	assert(#vim.api.nvim_list_tabpages() == start_count + 1, "diffview should add exactly one tab")
	assert(vim.api.nvim_get_current_tabpage() ~= start_tab)
	local lib = require("diffview.lib")
	vim.wait(5000, function()
		local view = lib.get_current_view()
		return view ~= nil and view.ready
	end)
	vim.cmd("DiffviewClose")
	vim.wait(2000, function()
		return #vim.api.nvim_list_tabpages() == start_count
	end)
	assert(#vim.api.nvim_list_tabpages() == start_count, "tab count must match the start")
	assert(vim.api.nvim_get_current_tabpage() == start_tab and vim.fn.getcwd() == start_cwd)
end)

test("the worker copy is untouched", function()
	assert(git(wt, "status", "--porcelain") == "")
end)

vim.fn.delete(tmp, "rf")
print("aiterm crew review: OK")
