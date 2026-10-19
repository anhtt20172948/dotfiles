-- Refresh on user events, never spawn a process during statusline redraws.
local M = {}
local label = "AI:A"
local initialized = false

function M.refresh()
	local home = vim.env.HOME
	local fm_home = vim.env.FM_HOME
	if not fm_home or fm_home == "" then
		fm_home = home .. "/.local/share/firstmate"
	end
	local path = fm_home .. "/config/claude-account"
	local value = "ordinary"
	if vim.uv.fs_stat(path) then
		local ok, lines = pcall(vim.fn.readfile, path, "", 1)
		value = ok and lines[1] or ""
	end
	if value == "ordinary" then
		label = "AI:A"
	elseif value == home .. "/.claude-b" then
		label = "AI:B"
	else
		label = "AI:?"
	end
end

function M.status()
	return label
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
	vim.api.nvim_create_user_command("AiAccount", function(opts)
		if opts.args ~= "" and opts.args ~= "a" and opts.args ~= "b" then
			vim.notify("Use :AiAccount [a|b]", vim.log.levels.ERROR)
			return
		end
		local cmd = opts.args == "" and { "ai-acct", "status" } or { "ai-acct", "use", opts.args }
		local ok, err = pcall(vim.system, cmd, { text = true }, function(result)
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
	end, {
		nargs = "?",
		complete = function()
			return { "a", "b" }
		end,
		desc = "Show quota or select Claude account for Firstmate workers",
	})
end

return M
