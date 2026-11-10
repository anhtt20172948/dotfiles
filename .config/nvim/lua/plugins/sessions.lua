return {
	{
		"nvim-telescope/telescope.nvim",
		branch = "0.1.x",
		lazy = true,
		cmd = "Telescope",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			defaults = {
				borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
				winblend = 0,
			},
		},
	},
	{
		"rmagatti/auto-session",
		---enables autocomplete for opts
		---@module "auto-session"
		---@type AutoSession.Config
		tag = "v2.5.1",
		lazy = false,
		opts = {
			-- false: restore only the session of this exact cwd; a directory without a session
			-- stays empty (true falls back to the last session, so any dir would open
			-- another dir's session).
			auto_restore_last_session = false,
			-- v2.5.1 also uses this for "Could not restore session", which would cover
			-- the dashboard in every directory without a session.
			show_auto_restore_notif = false,
			lsp_stop_on_restore = true, -- Should language servers be stopped when restoring a session. Can also be a function that will be called if set. Not called on autorestore from startup
			session_lens = {
				-- If load_on_setup is false, make sure you use `:SessionSearch` to open the picker as it will initialize everything first
				-- v2.5.1 only supports Telescope here. Preserve its delete/copy/
				-- alternate actions, but load it only when selecting a session.
				load_on_setup = false,
				previewer = false,
				mappings = {
					-- Mode can be a string or a table, e.g. {"i", "n"} for both insert and normal mode
					delete_session = { "i", "<C-D>" },
					alternate_session = { "i", "<C-S>" },
					copy_session = { "i", "<C-Y>" },
				},
				-- Can also set some Telescope picker options
				-- For all options, see: https://github.com/nvim-telescope/telescope.nvim/blob/master/doc/telescope.txt#L112
				theme_conf = {
					border = true,
					borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
					winblend = 0,
					layout_config = { width = 0.85, height = 0.6 },
				},
			},
		},
		config = function(_, opts)
			-- DROP "terminal": mksession writes the AI pane's terminal buffer, so restore
			-- runs `setlocal buftype=terminal` (E474), breaking the session and auto-save.
			vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions"
			vim.keymap.set("n", "<leader>P", function()
				require("auto-session.session-lens").search_session()
			end, { desc = "Select Session" })
			-- Reuse the spec's `opts` block (previously lost because setup was called without it),
			-- then add pre/post cmds. Close the AI pane before saving, like the Neotree pattern.
			opts.pre_save_cmds = {
				"Neotree close",
				function()
					require("customize.aiterm").close_for_session()
				end,
			}
			opts.post_restore_cmds = { "Neotree filesystem show" }
			require("auto-session").setup(opts)
		end,
	},
}
