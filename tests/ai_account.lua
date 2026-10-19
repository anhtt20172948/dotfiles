-- Run with: nvim --headless -u NONE -i NONE -l tests/ai_account.lua <repo-root>
local root = assert(arg[1])
package.path = root .. "/.config/nvim/lua/?.lua;" .. package.path
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/config", "p")
vim.env.FM_HOME = tmp
local ecc = require("customize.aiterm_ecc")
local acct = require("customize.ai_account")
acct.setup()
assert(vim.fn.exists(":AiAccount") == 2)
assert(ecc.account_status() == "AI:A")
vim.fn.writefile({ vim.env.HOME .. "/.claude-b" }, tmp .. "/config/claude-account")
acct.refresh()
assert(ecc.account_status() == "AI:B")
vim.fn.writefile({ "ordinary" }, tmp .. "/config/claude-account")
assert(ecc.account_status() == "AI:B", "statusline should use cached value")
vim.api.nvim_exec_autocmds("FocusGained", {})
assert(ecc.account_status() == "AI:A")
vim.fn.writefile({ "invalid" }, tmp .. "/config/claude-account")
acct.refresh()
assert(ecc.account_status() == "AI:?")
local calls = {}
vim.system = function(cmd, _, cb)
	calls[#calls + 1] = cmd
	cb({ code = 0, stdout = "Selected account", stderr = "" })
end
vim.notify = function() end
vim.cmd("AiAccount b")
assert(vim.wait(1000, function()
	return #calls == 1
end))
assert(vim.deep_equal(calls[1], { "ai-acct", "use", "b" }))
vim.cmd("AiAccount")
assert(vim.wait(1000, function()
	return #calls == 2
end))
assert(vim.deep_equal(calls[2], { "ai-acct", "status" }))
vim.fn.delete(tmp, "rf")
print("ai account: OK")
