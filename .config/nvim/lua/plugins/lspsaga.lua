return {
	"glepnir/lspsaga.nvim",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		"nvim-treesitter/nvim-treesitter", -- optional
		"nvim-tree/nvim-web-devicons", -- optional
	},
	config = function()
		local map = vim.keymap.set
		local lspsaga = require("lspsaga")
		lspsaga.setup({
			lightbulb = {
				enable = false,
			},
			finder = { keys = { toggle_or_open = "o", vsplit = "s", split = "i", quit = "q" } },
			ui = {
				border = "rounded",
				use_nerd = vim.env.NVIM_ASCII ~= "1",
				kind = require("catppuccin.groups.integrations.lsp_saga").custom_kind(),
				code_action = require("lib.icons").diagnostics.Hint,
				lines = { "┗", "┣", "┃", "━", "┏" },
			},

			hover = {
				max_width = 0.5,
				max_height = 0.8,
			},
			diagnostic = {
				jump_num_shortcut = true,
				max_width = 0.7,
				keys = { exec_action = "o", quit = "q", go_action = "g" },
			},

			code_action = { keys = { quit = "q", exec = "<CR>" } },
			rename = { keys = { quit = "<C-c>", exec = "<CR>" } },
		})
		-- keymaps
		map("n", "<leader>lk", vim.lsp.buf.hover, { desc = "Hover Docs", noremap = true, silent = true })
		map("n", "<leader>lf", ":Lspsaga finder<cr>", { desc = "LSP Finder", noremap = true, silent = true })
		map(
			"n",
			"<leader>ld",
			":Lspsaga goto_definition<cr>",
			{ desc = "Go To Definition", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>lp",
			":Lspsaga peek_definition<cr>",
			{ desc = "Peek Definition", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>lt",
			":Lspsaga goto_type_definition<cr>",
			{ desc = "Type Definition", noremap = true, silent = true }
		)
		map("n", "<leader>lR", ":Lspsaga rename<cr>", { desc = "Rename", noremap = true, silent = true })
		map("n", "<leader>la", ":Lspsaga code_action<cr>", { desc = "Code Action", noremap = true, silent = true })
		map(
			"n",
			"<leader>lD",
			":Lspsaga show_buf_diagnostics<cr>",
			{ desc = "Buffer Diagnostic", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>lc",
			":Lspsaga show_cursor_diagnostics<cr>",
			{ desc = "Cursor Diagnostic", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>lw",
			":Lspsaga show_workspace_diagnostics<cr>",
			{ desc = "Workspace Diagnostic", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>le",
			":Lspsaga show_line_diagnostics<cr>",
			{ desc = "Line Diagnostics", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>ln",
			":Lspsaga diagnostic_jump_next<cr>",
			{ desc = "Go To Next Diagnostic", noremap = true, silent = true }
		)
		map(
			"n",
			"<leader>lN",
			":Lspsaga diagnostic_jump_prev<cr>",
			{ desc = "Go To Previous Diagnostic", noremap = true, silent = true }
		)
		map("n", "<leader>lo", ":Lspsaga outline<cr>", { desc = "LSP Outline", noremap = true, silent = true })

		vim.keymap.set(
			"n",
			"<C-q>",
			":Lspsaga term_toggle<cr>",
			{ desc = "Floating Terminal", noremap = true, silent = true }
		)
	end,
}
