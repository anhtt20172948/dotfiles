local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

local function check(condition, message)
	assert(condition, message)
end

local aiterm = require("customize.aiterm")
aiterm.config.tools = { { name = "test", cmd = "cat" } }
aiterm.config.start_insert = true

-- Install the same lazy key specs that Neovim installs at startup.
local ai_spec = dofile(root .. "/.config/nvim/lua/plugins/aiterm.lua")
local nav_spec = dofile(root .. "/.config/nvim/lua/plugins/navigator.lua")
local right_ctrl_l
local right_ctrl_w_l
local tmux_right_calls = 0
vim.api.nvim_create_user_command("TmuxNavigateRight", function()
	tmux_right_calls = tmux_right_calls + 1
	vim.cmd("wincmd l")
end, {})
for _, spec in ipairs(nav_spec.keys) do
	if spec[1] == "<c-l>" then
		right_ctrl_l = spec[2]
	end
end
for _, spec in ipairs(ai_spec.keys) do
	if spec[1] == "<C-w>l" then
		right_ctrl_w_l = spec[2]
	end
end

local code_win = vim.api.nvim_get_current_win()
aiterm.open("test", { cwd = "/tmp" })
local ai_win = vim.api.nvim_get_current_win()
local ai_buf = vim.api.nvim_get_current_buf()
check(ai_win ~= code_win, "AI terminal should open in a separate pane")
local ai_maps = vim.api.nvim_buf_get_keymap(ai_buf, "t")
local mapped = {}
for _, map in ipairs(ai_maps) do
	mapped[map.lhs] = map
end
check(mapped["<C-H>"] and mapped["<C-H>"].callback, "AI terminal needs a Ctrl+h callback")
check(mapped["<C-W>h"] and mapped["<C-W>h"].callback, "AI terminal needs a Ctrl+w h callback")
for _, lhs in ipairs({ "<C-J>", "<C-K>", "<C-W>j", "<C-W>k" }) do
	check(mapped[lhs] and mapped[lhs].callback, "AI terminal needs a buffer-local " .. lhs .. " callback")
end

mapped["<C-H>"].callback()
check(vim.api.nvim_get_current_win() == code_win, "Ctrl+h should move left from AI terminal")
check(type(right_ctrl_l) == "function", "Ctrl+l needs AI-aware navigation")
right_ctrl_l()
check(vim.api.nvim_get_current_win() == ai_win, "Ctrl+l should focus right-hand AI terminal")

mapped["<C-W>h"].callback()
check(vim.api.nvim_get_current_win() == code_win, "Ctrl+w h should move left from AI terminal")
check(type(right_ctrl_w_l) == "function", "Ctrl+w l needs AI-aware navigation")
right_ctrl_w_l()
check(vim.api.nvim_get_current_win() == ai_win, "Ctrl+w l should focus right-hand AI terminal")

vim.api.nvim_set_current_win(code_win)
vim.cmd("rightbelow vsplit")
local middle_win = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(code_win)
right_ctrl_l()
check(vim.api.nvim_get_current_win() == middle_win and tmux_right_calls == 1, "Ctrl+l should keep tmux navigation when AI is not adjacent")
vim.api.nvim_set_current_win(code_win)
right_ctrl_w_l()
check(vim.api.nvim_get_current_win() == middle_win, "Ctrl+w l should keep normal navigation when AI is not adjacent")
vim.api.nvim_win_close(middle_win, false)
vim.api.nvim_set_current_win(ai_win)

vim.cmd("only")
check(vim.api.nvim_get_current_win() == ai_win, "AI pane should be the only pane")
mapped["<C-H>"].callback()
check(vim.api.nvim_get_current_win() == ai_win, "Ctrl+h without left pane should stay in AI pane")
mapped["<C-W>h"].callback()
check(vim.api.nvim_get_current_win() == ai_win, "Ctrl+w h without left pane should stay in AI pane")
check(mapped["<C-Space>"] or mapped["<C-@>"], "Ctrl+Space behavior should remain mapped")
check(not mapped["<C-W>"], "Ctrl+w alone should still pass through to AI app")

local other_buf = vim.api.nvim_create_buf(false, true)
local other_maps = vim.api.nvim_buf_get_keymap(other_buf, "t")
for _, map in ipairs(other_maps) do
	check(not vim.tbl_contains({ "<C-H>", "<C-W>h", "<C-J>", "<C-K>", "<C-W>j", "<C-W>k" }, map.lhs), "other terminal buffers should not get AI navigation maps")
end

print("aiterm navigation: OK")
