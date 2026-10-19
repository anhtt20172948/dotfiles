-- Drive the real nvim account picker and ai-acct with a failed/missing/hung helper.
local root = assert(arg[1])
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/bin", "p")
vim.fn.mkdir(tmp .. "/.config/claude-accounts", "p")
vim.env.HOME = tmp
vim.env.XDG_CACHE_HOME = tmp .. "/cache"
vim.env.XDG_CONFIG_HOME = tmp .. "/.config"
vim.env.XDG_DATA_HOME = tmp .. "/data"
vim.env.XDG_STATE_HOME = tmp .. "/state"
vim.env.CODEX_HOME = tmp .. "/.codex"
vim.env.TMUX = ""
vim.env.PATH = tmp .. "/bin:" .. vim.env.PATH
vim.fn.writefile(vim.fn.readfile(root .. "/.local/bin/ai-acct"), tmp .. "/bin/ai-acct")
assert(vim.uv.fs_chmod(tmp .. "/bin/ai-acct", 493))
for _, name in ipairs({ "a", "work" }) do
	local path = tmp .. "/.config/claude-accounts/" .. name .. ".token"
	vim.fn.writefile({ "synthetic-" .. name }, path)
	assert(vim.uv.fs_chmod(path, 384))
end
vim.opt.rtp:prepend(root .. "/.config/nvim")
local acct = require("customize.ai_account")
local offered, notified = {}, ""
vim.notify = function(output)
	notified = output
end
vim.ui.select = function(items, opts, choose)
	offered = vim.tbl_map(opts.format_item, items)
	for _, item in ipairs(items) do
		if item.name == "work" then
			choose(item)
			return
		end
	end
	error("helper failure hid work account")
end
for _, mode in ipairs({ "failure", "missing", "hang" }) do
	vim.fn.writefile({ "a" }, tmp .. "/.config/claude-accounts/active")
	local helper = tmp .. "/bin/ai-acct-quota"
	if mode == "missing" then
		vim.fn.delete(helper)
	else
		vim.fn.writefile(mode == "hang" and { "import time", "time.sleep(60)" } or { "raise SystemExit(1)" }, helper)
	end
	notified = ""
	acct.menu()
	assert(offered[1] == "Use a (active)  ◌ unknown", mode .. ": missing active/unknown label")
	assert(offered[2] == "Use work  ◌ unknown", mode .. ": missing inactive/unknown label")
	assert(vim.wait(5000, function()
		return notified ~= "" and vim.fn.readfile(tmp .. "/.config/claude-accounts/active")[1] == "work"
	end), mode .. ": switching did not complete: " .. notified)
end
vim.fn.delete(tmp, "rf")
print("ai account fallback: OK")
