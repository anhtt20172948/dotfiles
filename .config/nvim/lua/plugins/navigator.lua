local function navigate_right()
	local aiterm = package.loaded["customize.aiterm"]
	if not (aiterm and aiterm.focus_if_right()) then
		vim.cmd("TmuxNavigateRight")
	end
end

return {
	"christoomey/vim-tmux-navigator",
	event = "VeryLazy",
	-- plugin/tmux_navigator.vim tự đặt nnoremap <C-l> khi load, ghi đè keys của lazy.
	-- Config chạy sau packadd nên đặt lại riêng map này, giữ các terminal map của plugin.
	config = function()
		vim.keymap.set("n", "<c-l>", navigate_right, { silent = true })
	end,
	cmd = {
		"TmuxNavigateLeft",
		"TmuxNavigateDown",
		"TmuxNavigateUp",
		"TmuxNavigateRight",
		"TmuxNavigatePrevious",
		"TmuxNavigatorProcessList",
	},
	keys = {
		{ "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
		{ "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
		{ "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
		{ "<c-l>", navigate_right },
		{ "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
	},
}
