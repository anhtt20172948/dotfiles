return {
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"saghen/blink.cmp",
			{
				"SmiteshP/nvim-navbuddy",
				dependencies = {
					"SmiteshP/nvim-navic",
					"MunifTanjim/nui.nvim",
				},
				opts = {
					lsp = { auto_attach = true },
					window = { sections = { right = { preview = "always" } }, border = "rounded" },
					size = "80%",
				},
				keys = {
					{
						"<leader>j",
						function()
							require("nvim-navbuddy").open()
						end,
						desc = "Jump to symbol",
					},
				},
			},
		},
		config = function()
			require("configs.lspconfig")
		end,
	},
}
