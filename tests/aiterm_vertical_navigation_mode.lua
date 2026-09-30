-- Run with: TMUX= nvim --headless -u NONE -i NONE -c 'luafile tests/aiterm_vertical_navigation_mode.lua'
-- This asynchronous test needs Neovim's event loop; -l exits before its timers run.
local root = vim.fn.getcwd()
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

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

local function press(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
end

step(function()
	-- Use a fake tmux socket: load the plugin's real global terminal maps without
	-- allowing a failed mapping to navigate the user's actual tmux session.
	vim.env.TMUX = "/tmp/aiterm-navigation-test-tmux,1,0"
	vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/vim-tmux-navigator")
	vim.cmd("runtime plugin/tmux_navigator.vim")
	check(vim.g.loaded_tmux_navigator == 1, "vim-tmux-navigator must load for terminal-map regression test")
	check(vim.fn.maparg("<C-j>", "t") ~= "" and vim.fn.maparg("<C-k>", "t") ~= "", "navigator terminal mappings must be active")
	local aiterm = require("customize.aiterm")
	aiterm.config.tools = { { name = "test", cmd = "cat" } }
	aiterm.open("test", { cwd = "/tmp" })
	local ai_win = vim.api.nvim_get_current_win()
	vim.cmd("stopinsert")

	vim.cmd("aboveleft split")
	local top_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(top_win, vim.api.nvim_create_buf(false, true))
	vim.api.nvim_set_current_win(ai_win)
	vim.cmd("belowright split")
	local bottom_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(bottom_win, vim.api.nvim_create_buf(false, true))
	vim.api.nvim_set_current_win(ai_win)
	vim.cmd("startinsert")

	local actions = {
		{ key = "<C-j>", win = bottom_win, mode = "n", message = "Ctrl+j should move down from AI terminal" },
		{ command = "wincmd k", win = ai_win, mode = "t", message = "returning to AI should enter terminal mode" },
		{ key = "<C-k>", win = top_win, mode = "n", message = "Ctrl+k should move up from AI terminal" },
		{ command = "wincmd j", win = ai_win, mode = "t", message = "returning from above should enter terminal mode" },
		{ key = "<C-w>j", win = bottom_win, mode = "n", message = "Ctrl+w j should move down from AI terminal" },
		{ command = "wincmd k", win = ai_win, mode = "t", message = "returning from below should enter terminal mode" },
		{ key = "<C-w>k", win = top_win, mode = "n", message = "Ctrl+w k should move up from AI terminal" },
		{ command = "wincmd j", win = ai_win, mode = "t", message = "returning from above should enter terminal mode" },
		{ key = "<C-j>", win = ai_win, mode = "t", message = "Ctrl+j without lower pane should stay in terminal mode", close_neighbors = true },
		{ key = "<C-k>", win = ai_win, mode = "t", message = "Ctrl+k without upper pane should stay in terminal mode" },
		{ key = "<C-w>j", win = ai_win, mode = "t", message = "Ctrl+w j without lower pane should stay in terminal mode" },
		{ key = "<C-w>k", win = ai_win, mode = "t", message = "Ctrl+w k without upper pane should stay in terminal mode" },
	}

	local function run_action(index)
		local action = actions[index]
		if not action then
			print("aiterm vertical navigation: OK")
			vim.cmd("qa!")
			return
		end
		if action.close_neighbors then
			vim.api.nvim_win_close(top_win, true)
			vim.api.nvim_win_close(bottom_win, true)
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
		check(vim.api.nvim_get_current_win() == ai_win and vim.api.nvim_get_mode().mode == "t", "AI should be ready before vertical navigation")
		run_action(1)
	end)
end)
