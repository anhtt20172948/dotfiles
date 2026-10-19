-- Run with: nvim --headless -u NONE -i NONE -l tests/ai_account.lua <repo-root>
local root = assert(arg[1])
package.path = root .. "/.config/nvim/lua/?.lua;" .. package.path
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.config/claude-accounts", "p")
vim.env.HOME = tmp
local ecc = require("customize.aiterm_ecc")
local acct = require("customize.ai_account")
acct.setup()
assert(vim.fn.exists(":AiAccount") == 2)
assert(ecc.account_status() == "AI:-")
vim.fn.writefile({ "b" }, tmp .. "/.config/claude-accounts/active")
acct.refresh()
assert(ecc.account_status() == "AI:b")
vim.fn.writefile({ "a" }, tmp .. "/.config/claude-accounts/active")
assert(ecc.account_status() == "AI:b", "statusline should use cached value")
vim.api.nvim_exec_autocmds("FocusGained", {})
assert(ecc.account_status() == "AI:a")
vim.fn.writefile({ "work-2" }, tmp .. "/.config/claude-accounts/active")
acct.refresh()
assert(ecc.account_status() == "AI:work-2")
vim.fn.writefile({ "Invalid" }, tmp .. "/.config/claude-accounts/active")
acct.refresh()
assert(ecc.account_status() == "AI:?")

-- ai-acct is mocked: async calls are recorded, `list` answers synchronously.
local calls = {}
vim.system = function(cmd, opts, cb)
	if cmd[2] == "list" then
		return {
			wait = function()
				local output = cmd[3] == "--quota"
					and "a\t\t███████░░░ 75% left\nwork\tactive\t◌ rate-limited\n"
					or "a\t\nwork\tactive\n"
				return { code = 0, stdout = output, stderr = "" }
			end,
		}
	end
	calls[#calls + 1] = { cmd = cmd, stdin = opts and opts.stdin }
	cb({ code = 0, stdout = "ok", stderr = "" })
end
vim.notify = function() end
local function last(n)
	assert(
		vim.wait(1000, function()
			return #calls == n
		end),
		("expected %d ai-acct calls, got %d"):format(n, #calls)
	)
	return calls[n]
end

vim.cmd("AiAccount b")
assert(vim.deep_equal(last(1).cmd, { "ai-acct", "use", "b" }), "bare name selects it")
vim.cmd("AiAccount")
assert(vim.deep_equal(last(2).cmd, { "ai-acct", "status" }))
vim.cmd("AiAccount use work")
assert(vim.deep_equal(last(3).cmd, { "ai-acct", "use", "work" }))

-- Tokens are typed into inputsecret and passed on stdin only.
local typed = "synthetic-token"
vim.fn.inputsecret = function()
	return typed
end
vim.cmd("AiAccount add home")
local add = last(4)
assert(vim.deep_equal(add.cmd, { "ai-acct", "add", "home" }))
assert(add.stdin == typed .. "\n", "token must go to stdin")
vim.ui.input = function(_, on_confirm)
	on_confirm("lab")
end
vim.cmd("AiAccount add")
assert(vim.deep_equal(last(5).cmd, { "ai-acct", "add", "lab" }), "add prompts for a name")
vim.cmd("AiAccount edit work")
local edit = last(6)
assert(vim.deep_equal(edit.cmd, { "ai-acct", "edit", "work" }) and edit.stdin == typed .. "\n")
typed = ""
vim.cmd("AiAccount edit work")
vim.wait(50)
assert(#calls == 6, "empty token cancels")
typed = "synthetic-token"

vim.cmd("AiAccount rename work job")
assert(vim.deep_equal(last(7).cmd, { "ai-acct", "rename", "work", "job" }))
local answer = 2
vim.fn.confirm = function()
	return answer
end
vim.cmd("AiAccount remove a")
vim.wait(50)
assert(#calls == 7, "declined remove must not run")
answer = 1
vim.cmd("AiAccount remove a")
assert(vim.deep_equal(last(8).cmd, { "ai-acct", "remove", "a" }))

-- The menu lists accounts from ai-acct and offers the management actions.
local offered
vim.ui.select = function(items, opts, on_choice)
	offered = vim.tbl_map(opts.format_item, items)
	for _, item in ipairs(items) do
		if item.action == "use" and item.name == "a" then
			return on_choice(item)
		end
	end
end
acct.menu()
assert(vim.deep_equal(last(9).cmd, { "ai-acct", "use", "a" }))
assert(vim.deep_equal(offered, {
	"Use a  ███████░░░ 75% left",
	"Use work (active)  ◌ rate-limited",
	"+ Add account",
	"Replace token",
	"Rename account",
	"Remove account",
}))

local completions = vim.fn.getcompletion("AiAccount ", "cmdline")
assert(vim.tbl_contains(completions, "add") and vim.tbl_contains(completions, "work"))
assert(vim.deep_equal(vim.fn.getcompletion("AiAccount edit ", "cmdline"), { "a", "work" }))

for _, call in ipairs(calls) do
	for _, part in ipairs(call.cmd) do
		assert(not part:find("synthetic", 1, true), "token leaked into argv")
	end
end
vim.fn.delete(tmp, "rf")
print("ai account: OK")
