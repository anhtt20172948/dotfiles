local function navigate_right()
	local aiterm = package.loaded["customize.aiterm"]
	if not (aiterm and aiterm.focus_if_right()) then
		vim.cmd("TmuxNavigateRight")
	end
end

return {
	"christoomey/vim-tmux-navigator",
	event = "VeryLazy",
	-- plugin/tmux_navigator.vim sets nnoremap <C-l> on load, overriding lazy's keys.
	-- Config runs after packadd, so re-set just this map and keep the plugin's terminal maps.
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
