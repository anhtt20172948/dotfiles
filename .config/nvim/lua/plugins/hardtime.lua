return {
	"m4xshen/hardtime.nvim",
	lazy = false,
	dependencies = { "MunifTanjim/nui.nvim" },
	opts = {},
	config = function(_, opts)
		require("hardtime").setup(opts)
		vim.keymap.set("n", "<leader>ht", "<cmd>Hardtime toggle<cr>", { desc = "Toggle Hardtime" })
	end,
}
