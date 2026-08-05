return {
	{
		"mason-org/mason.nvim",
		lazy = false,
		build = ":MasonUpdate",

		opts = {
			PATH = "prepend",

			ui = {
				border = "rounded",

				icons = {
					package_pending = " ",
					package_installed = " ",
					package_uninstalled = " ",
				},
			},

			max_concurrent_installers = 10,
		},
	},

	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = {
			"mason-org/mason.nvim",
		},
		opts = {
			ensure_installed = {
				"bash-language-server",
				"css-lsp",
				"dockerfile-language-server",
				"eslint-lsp",
				"html-lsp",
				"json-lsp",
				"lua-language-server",
				"pyright",
				"clangd",
				"clang-format",
				"ruff",
				"isort",
				"harper-ls",
				"prettier",
				"stylua",
				"markdownlint-cli2",
				"shellcheck",
				"typescript-language-server", -- ts_ls is enabled in lspconfig.lua
				-- NOTE: debuggers (debugpy, codelldb) are installed by mason-nvim-dap.
				-- Do NOT list them here too — both installing at once races and errors
				-- with "Package is already installing".
			},

			run_on_start = true,
			start_delay = 1000,
			auto_update = false,
		},
	},

	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			"mason-org/mason.nvim",
		},

		opts = {
			automatic_enable = true,
		},
	},
}
