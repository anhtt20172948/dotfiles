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
			-- Tools Mason keeps installed for language servers, formatters, and linters.
			-- Some packages are intentionally excluded because they are managed elsewhere
			-- in this config or installed manually.
			ensure_installed = {
				-- Shell and web stack LSPs.
				"bash-language-server",
				"css-lsp",
				"dockerfile-language-server",
				"eslint-lsp",
				"html-lsp",
				"json-lsp",
				"lua-language-server",
				"pyright",
				-- C/C++ and Python tools are managed separately.
				-- "clangd", -- installed manually
				-- "clang-format", -- installed manually
				-- "ruff", -- installed by mason-tool-installer elsewhere
				-- "isort", -- installed by mason-tool-installer elsewhere
				-- Documentation and formatting tools.
				"harper-ls",
				"prettier",
				"stylua",
				-- Linters and language tooling.
				"markdownlint-cli2",
				"shellcheck",
				"typescript-language-server", -- ts_ls is enabled in lspconfig.lua
				-- Debuggers are installed by mason-nvim-dap.
				-- Keep them out of this list to avoid concurrent install races.
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
