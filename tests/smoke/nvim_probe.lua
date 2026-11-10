-- Boot probe for the real-plugin smoke test (tests/smoke/nvim_plugins.sh).
-- Loaded with `--cmd "luafile ..."`, i.e. before init.lua, so it sees every
-- error the full config raises while starting.
--
-- Headless Neovim never attaches a UI, so lazy.nvim would never fire VeryLazy
-- (it waits for UIEnter). The probe fires UIEnter itself after VimEnter, waits
-- SMOKE_SETTLE_MS for VeryLazy plugins to settle, then writes a JSON report to
-- SMOKE_REPORT and exits: 0 when no error was seen, 1 otherwise.
--
-- Before exiting it forces a full treesitter parse of every loaded buffer.
-- With SMOKE_FILES=1 it also opens an LSP-hover-style markdown float and
-- checks each buffer for a highlighter and its expected injections.
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

-- Headless Neovim never redraws, so treesitter highlight and injection queries
-- (and their custom predicates/directives) only run when a parse is forced.
-- Parse every loaded buffer fully, injections included, and record what each
-- one ended up with.
local function treesitter_buffers()
	local buffers = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
			local path = vim.api.nvim_buf_get_name(buf)
			local name = vim.b[buf].smoke_name or vim.fs.basename(path)
			local info = {
				name = name ~= "" and name or ("[buf " .. buf .. "]"),
				fixture = path:find("/tests/smoke/fixtures/", 1, true) ~= nil,
				filetype = vim.bo[buf].filetype,
				highlight = vim.treesitter.highlighter.active[buf] ~= nil,
				injections = {},
			}
			local parser = vim.treesitter.get_parser(buf, nil, { error = false })
			if parser then
				info.lang = parser:lang()
				local ok, err = pcall(parser.parse, parser, true)
				if ok then
					info.injections = vim.tbl_keys(parser:children())
					table.sort(info.injections)
				else
					record("treesitter", ("%s: %s"):format(info.name, err))
				end
			end
			table.insert(buffers, info)
		end
	end
	return buffers
end

-- SMOKE_FILES=1 (the boot with tests/smoke/fixtures/* open): every fixture is in
-- a language the treesitter spec installs, so each must be highlighted, and the
-- injections below must be found. Other buffers (notifications, the hover
-- float) only have to parse.
local expected_injections = {
	["sample.md"] = "lua",
	["heredoc.sh"] = "python",
	["[hover]"] = "lua", -- an LSP hover float with a code fence
}

local function check_files(buffers)
	local seen = {}
	for _, info in ipairs(buffers) do
		local name = info.name
		seen[name] = true
		if info.fixture and not info.highlight then
			record("treesitter", ("%s (%s): no treesitter highlighter attached"):format(name, info.filetype))
		end
		local want = expected_injections[name]
		if want and not vim.list_contains(info.injections, want) then
			record(
				"treesitter",
				("%s: expected a %s injection, got {%s}"):format(name, want, table.concat(info.injections, ","))
			)
		end
	end
	for name in pairs(expected_injections) do
		if not seen[name] then
			record("treesitter", name .. ": buffer not loaded")
		end
	end
end

-- What `K` shows: a markdown float whose fenced code block is injected.
local function open_hover()
	local buf = vim.lsp.util.open_floating_preview({ "```lua", "local x = 1", "```" }, "markdown")
	vim.b[buf].smoke_name = "[hover]"
end

-- Neovim's own runtime/ftplugin/markdown.lua runs `sil! nunmap <buffer> gO`
-- whenever the markdown filetype is applied again, which leaves this in
-- v:errmsg (with --clean too). It is not an error of this config.
local benign_errmsg = {
	["E31: No such mapping"] = true,
}

local files_mode = os.getenv("SMOKE_FILES") == "1"

local finished = false
local function finish(reason)
	if finished then
		return
	end
	finished = true
	local buffers = treesitter_buffers()
	if files_mode then
		check_files(buffers)
	end
	snacks_errors()
	message_errors()
	if vim.v.errmsg ~= "" and not benign_errmsg[vim.v.errmsg] then
		record("v:errmsg", vim.v.errmsg)
	end
	local report = {
		reason = reason,
		nvim = tostring(vim.version()),
		lazy = lazy_stats(),
		buffers = buffers,
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
		if files_mode then
			local ok, err = pcall(open_hover)
			if not ok then
				record("hover", err)
			end
		end
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
