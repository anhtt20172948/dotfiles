return {
	"smjonas/inc-rename.nvim",
	lazy = false,
	cmd = "Increname",
	opts = {},
	config = function()
		require("inc_rename").setup({})

		-- Keymap for renaming
		-- vim.keymap.set("n", "<leader>rn", function()
		--     return ":IncRename " .. vim.fn.expand("<cword>")
		-- end, { expr = true })
		vim.keymap.set("n", "<leader>rn", ":IncRename ")
	end,
}
