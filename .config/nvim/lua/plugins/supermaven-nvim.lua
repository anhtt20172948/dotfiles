return {
	{
		"supermaven-inc/supermaven-nvim",
		event = "InsertEnter",

		cmd = {
			"SupermavenStart",
			"SupermavenStop",
			"SupermavenRestart",
			"SupermavenToggle",
			"SupermavenStatus",
			"SupermavenUseFree",
			"SupermavenUsePro",
			"SupermavenLogout",
			"SupermavenShowLog",
			"SupermavenClearLog",
		},

		opts = {
			keymaps = {
				accept_suggestion = "<Tab>",
				accept_word = "<C-j>",
				clear_suggestion = "<C-]>",
			},

			ignore_filetypes = {
				"bigfile",
				"snacks_input",
				"snacks_notif",
				"TelescopePrompt",
				"neo-tree",
				"lazy",
				"mason",
				"help",
				"dashboard",
				"alpha",
				"starter",
				"gitcommit",
				"gitrebase",
				"DressingInput",
				"DressingSelect",
			},

			disable_inline_completion = false,
			disable_keymaps = false,

			log_level = "warn",

			condition = function()
				local buftype = vim.bo.buftype

				if buftype ~= "" then
					return true
				end

				if not vim.bo.modifiable or vim.bo.readonly then
					return true
				end

				return false
			end,
		},

		keys = {
			{
				"<leader>at",
				"<cmd>SupermavenToggle<cr>",
				desc = "Toggle Supermaven",
			},
			{
				"<leader>as",
				"<cmd>SupermavenStatus<cr>",
				desc = "Supermaven status",
			},
			{
				"<leader>ar",
				"<cmd>SupermavenRestart<cr>",
				desc = "Restart Supermaven",
			},
		},
	},

	{
		"zbirenbaum/copilot.lua",
		enabled = false,
	},

	{
		"zbirenbaum/copilot-cmp",
		enabled = false,
	},

	{
		"github/copilot.vim",
		enabled = false,
	},
}
