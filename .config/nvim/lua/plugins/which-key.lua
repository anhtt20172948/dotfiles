return {
	"folke/which-key.nvim",
	keys = { "<leader>", "<c-w>", '"', "'", "`", "c", "v", "g" },
	cmd = "WhichKey",
	opts = {
		spec = {
			{ "<leader>d", group = "Debug" },
			{ "<leader>t", group = "Test" },
			{ "<leader>o", group = "Overseer/Run" },
			{ "<leader>m", group = "CMake" },
			{ "<leader>r", group = "Run" },
			{ "<leader>g", group = "Git" },
			{ "<leader>s", group = "Search" },
			{ "<leader>f", group = "Find" },
			{ "<leader>x", group = "Trouble/Diagnostics" },
			{ "<leader>a", group = "AI" },
			{ "<leader>c", group = "Code/LSP" },
			{ "<leader>u", group = "UI Toggles" },
		},
	},
}
