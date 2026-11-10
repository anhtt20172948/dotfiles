return {
	{
		"nvzone/showkeys",
		cmd = "ShowkeysToggle",
		opts = {
			-- position = "bottom-right",
			maxkeys = 3,
			show_count = true,
			winopts = {
				focusable = false,
				relative = "editor",
				style = "minimal",
				border = "rounded",
				height = 1,
				row = 1,
				col = 0,
			},
		},
		keys = {
			{ "<leader>usk", "<cmd>ShowkeysToggle<cr>", desc = "Showkeys" },
		},
	},
}
