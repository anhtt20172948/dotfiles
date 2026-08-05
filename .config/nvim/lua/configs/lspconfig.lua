-- local lspconfig = require("lspconfig")

-- enable inlay hints by default
vim.lsp.inlay_hint.enable()
-- vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, {})
vim.keymap.set("n", "<leader>ca", function()
	require("tiny-code-action").code_action()
end, { noremap = true, silent = true })

local x = vim.diagnostic.severity

vim.diagnostic.config({
	virtual_text = { prefix = "" },
	signs = { text = { [x.ERROR] = "󰅙", [x.WARN] = "", [x.INFO] = "󰋼", [x.HINT] = "󰌵" } },
	underline = true,
	float = { border = "single" },
})

local capabilities = require("blink.cmp").get_lsp_capabilities()

vim.lsp.enable("ruff")
vim.lsp.config("ruff", {
	init_options = {
		settings = {
			-- Ruff language server settings go here
			lint = {
				preview = true,
			},
			single_file_support = true,
		},
	},
	capabilities = capabilities,
})

vim.lsp.enable("pyright")
vim.lsp.config("pyright", {
	settings = {
		pyright = {
			-- Using Ruff's import organizer
			disableOrganizeImports = true,
		},
		python = {
			analysis = {
				-- Ignore all files for analysis to exclusively use Ruff for linting
				ignore = { "*" },
			},
		},
	},
	capabilities = capabilities,
})

vim.lsp.enable("clangd")
vim.lsp.config("clangd", {
	cmd = {
		"clangd",
		"--background-index",
		"--clang-tidy",
		"--completion-style=detailed",
		"--header-insertion=iwyu",
		"--function-arg-placeholders",
		"--all-scopes-completion",
		"--pch-storage=memory",
		"-j=6",
		"--offset-encoding=utf-16",
	},
	settings = {
		clangd = {
			InlayHints = {
				Designators = true,
				Enabled = true,
				ParameterNames = true,
				DeducedTypes = true,
			},
			fallbackFlags = { "-std=c++20" },
		},
	},
	capabilities = capabilities,
})

-- clangd-specific keymap: jump between the source file and its header.
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client.name == "clangd" then
			vim.keymap.set("n", "<leader>ch", "<cmd>LspClangdSwitchSourceHeader<cr>", {
				buffer = args.buf,
				desc = "Switch Source/Header (clangd)",
			})
		end
	end,
})

vim.lsp.enable("ts_ls")
vim.lsp.config("ts_ls", {
	capabilities = capabilities,
	-- Disable ts_ls's built-in formatting
	on_attach = function(client)
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end,
})

vim.lsp.enable("lua_ls")
vim.lsp.config("lua_ls", {
	on_init = function(client)
		if client.workspace_folders then
			local path = client.workspace_folders[1].name
			if
				path ~= vim.fn.stdpath("config")
				and (vim.loop.fs_stat(path .. "/.luarc.json") or vim.loop.fs_stat(path .. "/.luarc.jsonc"))
			then
				return
			end
		end

		client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
			runtime = {
				-- Tell the language server which version of Lua you're using
				-- (most likely LuaJIT in the case of Neovim)
				version = "LuaJIT",
			},
			-- Make the server aware of Neovim runtime files
			workspace = {
				checkThirdParty = false,
				library = {
					vim.env.VIMRUNTIME, -- Depending on the usage, you might want to add additional paths here.
					-- "${3rd}/luv/library"
					-- "${3rd}/busted/library",
				},
				-- or pull in all of 'runtimepath'. NOTE: this is a lot slower and will cause issues when working on your own configuration (see https://github.com/neovim/nvim-lspconfig/issues/3189)
				-- library = vim.api.nvim_get_runtime_file("", true)
			},
		})
	end,
	settings = {
		Lua = {},
	},
})

-- General LSP setup
vim.lsp.config["*"] = {
	capabilities = { textDocument = { semanticTokens = { multilineTokenSupport = true } } },
	root_markers = { ".git" },
}
-- NOTE: virtual_lines is intentionally OFF. tiny-inline-diagnostic renders
-- diagnostics; enabling virtual_lines here double-rendered every diagnostic as a
-- multi-line tree (heavy + laggy on files with many clang-tidy warnings).

-- Harper (grammar/spell) — restrict to prose filetypes ONLY.
-- mason-lspconfig auto-enables it under the real name `harper_ls`, whose default
-- filetypes include C/C++/Python/etc. That made Harper spell-check code comments
-- (the "Did you mean to spell 's'" noise). Pin its filetypes to prose.
vim.lsp.config("harper_ls", {
	filetypes = { "markdown", "text", "tex", "typst", "gitcommit" },
})
vim.lsp.enable("harper_ls")
