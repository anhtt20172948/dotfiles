-- Claude accounts via ai-acct: statusline label, :AiAccount and the <leader>au menu.
-- Refresh on user events, never spawn a process during statusline redraws.
-- Tokens are read with inputsecret and handed to ai-acct on stdin, never argv.
local M = {}
local label = "AI:-"
local initialized = false
local SUBCOMMANDS = { "add", "edit", "list", "menu", "remove", "rename", "status", "use" }
local NAMED = { edit = true, remove = true, rename = true, use = true }

-- Same name rule as ai-acct.
local function valid_name(name)
	return #name <= 32 and name:match("^[a-z0-9][a-z0-9_-]*$") ~= nil
end

function M.refresh()
	local path = vim.env.HOME .. "/.config/claude-accounts/active"
	local value = ""
	if vim.uv.fs_stat(path) then
		local ok, lines = pcall(vim.fn.readfile, path, "", 1)
		value = ok and lines[1] or ""
	end
	if value == "" then
		label = "AI:-"
	elseif valid_name(value) then
		label = "AI:" .. value
	else
		label = "AI:?"
	end
end

function M.status()
	return label
end

-- { name, active } from ai-acct, the single owner of account names.
local function accounts(with_quota)
	local ok, result = pcall(function()
		return vim.system(with_quota and { "ai-acct", "list", "--quota" } or { "ai-acct", "list" }, { text = true }):wait()
	end)
	if not ok or result.code ~= 0 then
		return with_quota and accounts() or {}
	end
	local list = {}
	for line in vim.gsplit(result.stdout or "", "\n", { trimempty = true }) do
		local name, state, quota = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
		if not name then
			name, state = line:match("^([^\t]+)\t?(.*)$")
		end
		if name then
			list[#list + 1] = { name = name, active = state == "active", quota = quota }
		end
	end
	return list
end

local function names()
	return vim.tbl_map(function(account)
		return account.name
	end, accounts())
end

local function run(args, stdin)
	local cmd = vim.list_extend({ "ai-acct" }, args)
	local ok, err = pcall(vim.system, cmd, { text = true, stdin = stdin }, function(result)
		vim.schedule(function()
			M.refresh()
			vim.cmd.redrawstatus()
			local output = vim.trim((result.stdout or "") .. "\n" .. (result.stderr or ""))
			vim.notify(
				output,
				result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR,
				{ title = "AI account" }
			)
		end)
	end)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR, { title = "AI account" })
	end
end

-- Calls fn(name) with the given name, or one picked from the account list.
local function with_account(name, prompt, fn)
	if name then
		return fn(name)
	end
	local list = names()
	if #list == 0 then
		vim.notify("No Claude accounts yet; add one first", vim.log.levels.WARN, { title = "AI account" })
		return
	end
	vim.ui.select(list, { prompt = prompt }, function(choice)
		if choice then
			fn(choice)
		end
	end)
end

local function with_token(name, fn)
	local token = vim.fn.inputsecret("Token for " .. name .. ": ")
	if token ~= "" then
		fn(token .. "\n")
	end
end

local actions = {}

function actions.status()
	run({ "status" })
end

function actions.list()
	run({ "list" })
end

function actions.use(name)
	with_account(name, "Use Claude account", function(account)
		run({ "use", account })
	end)
end

function actions.add(name)
	local function add(account)
		if account and account ~= "" then
			with_token(account, function(stdin)
				run({ "add", account }, stdin)
			end)
		end
	end
	if name then
		return add(name)
	end
	vim.ui.input({ prompt = "New account name (lowercase, digits, - _): " }, add)
end

function actions.edit(name)
	with_account(name, "Replace token of", function(account)
		with_token(account, function(stdin)
			run({ "edit", account }, stdin)
		end)
	end)
end

function actions.rename(name, new)
	with_account(name, "Rename account", function(account)
		local function rename(target)
			if target and target ~= "" then
				run({ "rename", account, target })
			end
		end
		if new then
			return rename(new)
		end
		vim.ui.input({ prompt = "New name for " .. account .. ": " }, rename)
	end)
end

function actions.remove(name)
	with_account(name, "Remove account", function(account)
		if vim.fn.confirm("Remove Claude account " .. account .. " and its token?", "&Yes\n&No", 2) == 1 then
			run({ "remove", account })
		end
	end)
end

-- Mirrors tmux prefix E.
function M.menu()
	local items = {}
	local list = accounts(true)
	for _, account in ipairs(list) do
		items[#items + 1] = {
			action = "use",
			name = account.name,
			text = "Use " .. account.name .. (account.active and " (active)" or "")
				.. (account.quota and "  " .. account.quota or ""),
		}
	end
	items[#items + 1] = { action = "add", text = "+ Add account" }
	if #list > 0 then
		items[#items + 1] = { action = "edit", text = "Replace token" }
		items[#items + 1] = { action = "rename", text = "Rename account" }
		items[#items + 1] = { action = "remove", text = "Remove account" }
	end
	vim.ui.select(items, {
		prompt = "Claude accounts",
		format_item = function(item)
			return item.text
		end,
	}, function(item)
		if item then
			actions[item.action](item.name)
		end
	end)
end
actions.menu = M.menu

local function command(opts)
	local args = opts.fargs
	if #args == 0 then
		return actions.status()
	end
	local action = actions[args[1]]
	if action then
		return action(args[2], args[3])
	end
	-- `:AiAccount NAME` keeps working as a shortcut for `use NAME`.
	if #args == 1 and valid_name(args[1]) then
		return actions.use(args[1])
	end
	vim.notify("Use :AiAccount [" .. table.concat(SUBCOMMANDS, "|") .. "] [NAME]", vim.log.levels.ERROR)
end

local function complete(_, line)
	local words = vim.split(line, "%s+")
	if #words <= 2 then
		return vim.list_extend(vim.deepcopy(SUBCOMMANDS), names())
	end
	if #words == 3 and NAMED[words[2]] then
		return names()
	end
	return {}
end

function M.setup()
	if initialized then
		return
	end
	initialized = true
	M.refresh()
	local group = vim.api.nvim_create_augroup("AiAccount", { clear = true })
	vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
		group = group,
		callback = M.refresh,
	})
	vim.api.nvim_create_user_command("AiAccount", command, {
		nargs = "*",
		complete = complete,
		desc = "Show quota or manage Claude accounts (use/add/edit/rename/remove/menu)",
	})
end

return M
