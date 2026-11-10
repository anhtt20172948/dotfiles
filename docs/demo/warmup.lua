-- The first start of the real config on a new machine. render.sh runs it in a
-- detached tmux pane, since lazy.nvim's VeryLazy needs a UI:
--   nvim -c "luafile docs/demo/warmup.lua" FILE
-- Mason installs the debug adapters and Tree-sitter builds its parsers in the
-- background on the first start, with notifications. Waiting for both here
-- makes every recording look like the second start a user sees.
-- It writes "ok" or the reason it gave up to $DEMO_WARMUP_STATUS, then quits.
local timeout_ms = (tonumber(vim.env.DEMO_WARMUP_TIMEOUT) or 600) * 1000
-- Mason starts installing a moment after VeryLazy; idle before that means nothing.
local settle_ms = 5000

local function parsers_ready()
	local ok, configs = pcall(require, "nvim-treesitter.configs")
	if not ok then
		return true
	end
	local parsers = require("nvim-treesitter.parsers")
	for _, lang in ipairs(configs.get_ensure_installed_parsers()) do
		if not parsers.has_parser(lang) then
			return false
		end
	end
	return true
end

local function mason_idle()
	local ok, registry = pcall(require, "mason-registry")
	if not ok then
		return true
	end
	for _, pkg in ipairs(registry.get_all_packages()) do
		if pkg:is_installing() then
			return false
		end
	end
	return true
end

local function report(status)
	local path = vim.env.DEMO_WARMUP_STATUS
	if path and path ~= "" then
		local file = assert(io.open(path, "w"))
		file:write(status, "\n")
		file:close()
	end
end

local function wait_and_quit()
	vim.wait(settle_ms)
	local finished = vim.wait(timeout_ms, function()
		return mason_idle() and parsers_ready()
	end, 500)
	if finished then
		report("ok")
	else
		report(
			string.format(
				"timed out after %ds (mason idle %s, parsers %s)",
				timeout_ms / 1000,
				tostring(mason_idle()),
				tostring(parsers_ready())
			)
		)
	end
	vim.cmd("qall!")
end

vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		vim.schedule(wait_and_quit)
	end,
})
