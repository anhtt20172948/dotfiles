-- Run with: nvim --headless -u NONE -i NONE -l tests/aiterm_flow.lua <repo-root>
local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

local flow = require("customize.aiterm_flow")

-- Stub mọi tiến trình: ghi lại lệnh thay vì chạy.
local calls, notes, opened
local git_root, lease
local function reset(opts)
	opts = opts or {}
	calls = { float = {}, spawn = {} }
	notes = {}
	opened = nil
	git_root = opts.git_root
	lease = opts.lease or { code = 0, stdout = "/pool/1/repo\n", stderr = "" }
	vim.env.TMUX = opts.tmux and "/tmp/tmux-1000/default,1,0" or nil
end

flow.config.script = "/bin/true" -- executable() phải đúng
flow.exec = function(cmd)
	if cmd[1] == "git" and cmd[2] == "rev-parse" then
		return git_root and { code = 0, stdout = git_root .. "\n" } or { code = 128, stdout = "", stderr = "fatal" }
	end
	if cmd[1] == "git" and cmd[2] == "remote" then
		return { code = 1, stdout = "", stderr = "" }
	end
	if cmd[1] == "treehouse" then
		return lease
	end
	error("unexpected exec: " .. table.concat(cmd, " "))
end
flow.spawn = function(cmd, cwd)
	calls.spawn[#calls.spawn + 1] = { cmd = cmd, cwd = cwd }
end
flow.float = function(cmd, cwd)
	calls.float[#calls.float + 1] = { cmd = cmd, cwd = cwd }
end
flow.notify = function(msg, level)
	notes[#notes + 1] = { msg = msg, level = level or "info" }
end
package.loaded["customize.aiterm"] = {
	default_tool_name = function()
		return "claude"
	end,
	open = function(name, opts)
		opened = { name = name, cwd = opts.cwd }
	end,
}

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
		os.exit(1)
	end
end

test("push_gate warns outside a git repo and runs nothing", function()
	reset()
	flow.push_gate()
	assert(#calls.float == 0, "must not open terminal")
	assert(notes[1] and notes[1].level == "warn", "must warn")
end)

test("push_gate runs the shared script's push action at the repo root", function()
	reset({ git_root = "/work/repo" })
	flow.push_gate()
	assert(#calls.float == 1, "terminal expected")
	assert(vim.deep_equal(calls.float[1].cmd, { "/bin/true", "push" }), vim.inspect(calls.float[1].cmd))
	assert(calls.float[1].cwd == "/work/repo")
end)

test("pipelines opens the no-mistakes TUI through the script", function()
	reset({ git_root = "/work/repo" })
	flow.pipelines()
	assert(vim.deep_equal(calls.float[1].cmd, { "/bin/true", "pipelines" }))
end)

test("gnhf refuses to run outside tmux", function()
	reset({ git_root = "/work/repo" })
	flow.gnhf("add tests")
	assert(#calls.spawn == 0, "must not spawn")
	assert(notes[1].level == "warn")
end)

test("gnhf spawns the trimmed goal at the repo root", function()
	reset({ git_root = "/work/repo", tmux = true })
	flow.gnhf("  add tests  ")
	assert(vim.deep_equal(calls.spawn[1].cmd, { "/bin/true", "gnhf", "add tests" }), vim.inspect(calls.spawn[1]))
	assert(calls.spawn[1].cwd == "/work/repo")
end)

test("gnhf with a blank goal is a no-op", function()
	reset({ git_root = "/work/repo", tmux = true })
	flow.gnhf("   ")
	assert(#calls.spawn == 0)
end)

test("firstmate refuses outside tmux and spawns inside", function()
	reset()
	flow.firstmate()
	assert(#calls.spawn == 0 and notes[1].level == "warn")
	reset({ tmux = true })
	flow.firstmate()
	assert(vim.deep_equal(calls.spawn[1].cmd, { "/bin/true", "firstmate" }))
end)

-- treehouse không có trên máy test -> giả executable() cho riêng nó.
local real_executable = vim.fn.executable
vim.fn.executable = function(bin)
	if bin == "treehouse" then
		return 1
	end
	return real_executable(bin)
end

test("worktree opens the default tool in the leased path", function()
	reset({ git_root = "/work/repo" })
	flow.worktree()
	assert(opened and opened.name == "claude" and opened.cwd == "/pool/1/repo", vim.inspect(opened))
	assert(notes[1].msg:find("treehouse return /pool/1/repo", 1, true), "must tell how to return it")
end)

test("worktree reports a failed lease and opens nothing", function()
	reset({ git_root = "/work/repo", lease = { code = 1, stdout = "", stderr = "pool full" } })
	flow.worktree()
	assert(opened == nil)
	assert(notes[1].level == "error" and notes[1].msg:find("pool full", 1, true))
end)

vim.fn.executable = real_executable

test("doctor lists every tool, skill and the gate remote", function()
	reset({ git_root = "/work/repo" })
	local text = table.concat(flow.doctor_lines(), "\n")
	for _, want in ipairs({ "treehouse", "no-mistakes", "gnhf", "gh", "firstmate", "ai-workflow.sh", "skill gh-axi", "skill chrome-devtools-axi", "skill lavish", "remote no-mistakes" }) do
		assert(text:find(want, 1, true), "doctor missing " .. want)
	end
	assert(text:find("-> no-mistakes init", 1, true), "doctor must hint init when remote missing")
end)

test("plugin spec binds the flow keys", function()
	local spec = dofile(root .. "/.config/nvim/lua/plugins/aiterm.lua")
	local keys = {}
	for _, k in ipairs(spec.keys) do
		keys[k[1]] = true
	end
	for _, want in ipairs({ "<leader>ap", "<leader>aP", "<leader>ag", "<leader>aW", "<leader>aF", "<leader>aR" }) do
		assert(keys[want], "missing key " .. want)
	end
	assert(not keys["<leader>at"], "<leader>at belongs to supermaven")
end)

print("aiterm flow: OK")
