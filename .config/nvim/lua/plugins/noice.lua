return {
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		cond = function()
			return vim.fn.has("nvim-0.11") == 1 and #vim.api.nvim_list_uis() > 0
		end,
		dependencies = { "MunifTanjim/nui.nvim" },
		opts = {
			popupmenu = { enabled = false }, -- Blink owns completion, including cmdline.
			notify = { enabled = false }, -- Snacks owns vim.notify and its history.
			lsp = {
				hover = { enabled = false },
				signature = { enabled = false },
				progress = { enabled = false },
			},
			presets = {
				bottom_search = true,
				command_palette = true,
				long_message_to_split = true,
				inc_rename = true,
			},
			views = {
				mini = { win_options = { winblend = 0 } },
				popup = { border = { style = "rounded" }, win_options = { winblend = 0 } },
				cmdline_popup = { win_options = { winblend = 0 } },
				confirm = { win_options = { winblend = 0 } },
			},
		},
	},
}
