-- Boot probe for the real-plugin smoke test (tests/smoke/nvim_plugins.sh).
-- Loaded with `--cmd "luafile ..."`, i.e. before init.lua, so it sees every
-- error the full config raises while starting.
--
-- Headless Neovim never attaches a UI, so lazy.nvim would never fire VeryLazy
-- (it waits for UIEnter). The probe fires UIEnter itself after VimEnter, waits
-- SMOKE_SETTLE_MS for VeryLazy plugins to settle, then writes a JSON report to
-- SMOKE_REPORT and exits: 0 when no error was seen, 1 otherwise.
local report_path = assert(os.getenv("SMOKE_REPORT"), "SMOKE_REPORT is not set")
local settle_ms = tonumber(os.getenv("SMOKE_SETTLE_MS") or "") or 500
local timeout_ms = tonumber(os.getenv("SMOKE_TIMEOUT_MS") or "") or 60000

local errors = {}

local function record(source, msg)
	table.insert(errors, { source = source, message = tostring(msg) })
end

-- Errors notified before snacks.nvim takes over vim.notify. Later ones are
-- read back from the snacks notifier history.
local builtin_notify = vim.notify
vim.notify = function(msg, level, opts)
	if level and level >= vim.log.levels.ERROR then
		record("notify", msg)
	end
	return builtin_notify(msg, level, opts)
end

local function snacks_errors()
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.notifier or not snacks.notifier.get_history then
		return
	end
	for _, n in ipairs(snacks.notifier.get_history()) do
		if n.level == "error" or n.level == vim.log.levels.ERROR then
			record("snacks.notifier", n.msg)
		end
	end
end

-- Error lines in :messages (Lua errors, :echoerr, E-numbered errors).
local function message_errors()
	local output = vim.api.nvim_exec2("messages", { output = true }).output
	for line in vim.gsplit(output, "\n", { plain = true }) do
		if line:match("^E%d+:") or line:match("[Ee]rror") then
			record("messages", line)
		end
	end
end

local function lazy_stats()
	local ok, lazy = pcall(require, "lazy")
	if not ok then
		return nil
	end
	local stats = lazy.stats()
	-- Failed install/build/checkout tasks of any plugin in the spec.
	local Plugin = require("lazy.core.plugin")
	local failed = {}
	for name, plugin in pairs(require("lazy.core.config").plugins) do
		if Plugin.has_errors(plugin) then
			table.insert(failed, name)
		end
	end
	table.sort(failed)
	for _, name in ipairs(failed) do
		record("lazy", name .. " has failed lazy.nvim tasks")
	end
	return {
		startuptime_ms = stats.startuptime,
		loaded = stats.loaded,
		count = stats.count,
		real_cputime = stats.real_cputime,
	}
end

local finished = false
local function finish(reason)
	if finished then
		return
	end
	finished = true
	snacks_errors()
	message_errors()
	if vim.v.errmsg ~= "" then
		record("v:errmsg", vim.v.errmsg)
	end
	local report = {
		reason = reason,
		nvim = tostring(vim.version()),
		lazy = lazy_stats(),
		errors = errors,
	}
	local file = assert(io.open(report_path, "w"))
	file:write(vim.json.encode(report), "\n")
	file:close()
	vim.cmd((#errors == 0 and reason == "settled") and "qall!" or "cquit! 1")
end

vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		vim.defer_fn(function()
			finish("settled")
		end, settle_ms)
	end,
})

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		vim.schedule(function()
			vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
		end)
	end,
})

vim.defer_fn(function()
	record("probe", ("VeryLazy did not fire within %d ms"):format(timeout_ms))
	finish("timeout")
end, timeout_ms)
