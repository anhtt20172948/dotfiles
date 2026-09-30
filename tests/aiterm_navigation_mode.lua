-- Run with: TMUX= nvim --headless -u NONE -i NONE -c 'luafile tests/aiterm_navigation_mode.lua'
-- This asynchronous test needs Neovim's event loop; -l exits before its timers run.
local root = vim.fn.getcwd()
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

local function press(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
end

local function check(condition, message)
	assert(condition, message .. " (mode=" .. vim.api.nvim_get_mode().mode .. ")")
end

local function step(callback)
	vim.defer_fn(function()
		local ok, err = xpcall(callback, debug.traceback)
		if not ok then
			vim.api.nvim_err_writeln(err)
			vim.cmd("cquit 1")
		end
	end, 80)
end

step(function()
	local aiterm = require("customize.aiterm")
	aiterm.config.tools = { { name = "test", cmd = "cat" } }
	aiterm.config.start_insert = true
	local ai_spec = dofile(root .. "/.config/nvim/lua/plugins/aiterm.lua")
	local nav_spec = dofile(root .. "/.config/nvim/lua/plugins/navigator.lua")
	for _, spec in ipairs(ai_spec.keys) do
		if spec[1] == "<C-w>l" then
			vim.keymap.set("n", spec[1], spec[2])
		end
	end
	for _, spec in ipairs(nav_spec.keys) do
		if spec[1] == "<c-l>" then
			vim.keymap.set("n", spec[1], spec[2])
		end
	end
	vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/vim-tmux-navigator")
	vim.cmd("runtime plugin/tmux_navigator.vim")
	check(vim.g.loaded_tmux_navigator == 1, "vim-tmux-navigator must load for mapping regression test")
	if nav_spec.config then
		nav_spec.config()
	end
	check(type(vim.fn.maparg("<C-l>", "n", false, true).callback) == "function", "Ctrl+l should retain its AI-aware mapping after navigator loads")
	local code_win = vim.api.nvim_get_current_win()
	aiterm.open("test", { cwd = "/tmp" })
	local ai_win = vim.api.nvim_get_current_win()
	local actions = {
		{ key = "<C-h>", win = code_win, mode = "n", message = "Ctrl+h should enter left code window in normal mode" },
		{ command = "wincmd l", win = ai_win, mode = "t", message = "ordinary window focus should enter AI terminal mode" },
		{ key = "<C-h>", win = code_win, mode = "n", message = "Ctrl+h should leave AI terminal mode" },
		{ key = "<C-l>", win = ai_win, mode = "t", message = "Ctrl+l should enter AI terminal mode" },
		{ key = "<C-w>h", win = code_win, mode = "n", message = "Ctrl+w h should enter left code window in normal mode" },
		{ key = "<C-w>l", win = ai_win, mode = "t", message = "Ctrl+w l should enter AI terminal mode" },
		{ key = "<C-h>", win = code_win, mode = "n", message = "Ctrl+h should leave AI terminal mode when auto-insert is disabled", start_insert = false },
		{ command = "wincmd l", win = ai_win, mode = "nt", message = "disabled auto-insert should keep AI pane in terminal-normal mode" },
		{ command = "wincmd h", win = code_win, mode = "n", message = "ordinary window focus should leave AI pane" },
		{ key = "<C-l>", win = ai_win, mode = "t", message = "re-enabled auto-insert should enter AI terminal mode", start_insert = true },
		{ key = "<C-h>", win = ai_win, mode = "t", message = "Ctrl+h without left pane should stay in terminal mode", close_code = true },
		{ key = "<C-w>h", win = ai_win, mode = "t", message = "Ctrl+w h without left pane should stay in terminal mode" },
	}

	local function run_action(index)
		local action = actions[index]
		if not action then
			print("aiterm navigation mode: OK")
			vim.cmd("qa!")
			return
		end
		if action.close_code then
			vim.api.nvim_win_close(code_win, true)
		end
		if action.start_insert ~= nil then
			aiterm.config.start_insert = action.start_insert
		end
		if action.command then
			vim.cmd(action.command)
		else
			press(action.key)
		end
		step(function()
			check(vim.api.nvim_get_current_win() == action.win and vim.api.nvim_get_mode().mode == action.mode, action.message)
			run_action(index + 1)
		end)
	end

	step(function()
		check(vim.api.nvim_get_mode().mode == "t", "AI pane should start in terminal mode")
		run_action(1)
	end)
end)
