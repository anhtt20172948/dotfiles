local icons = require("lib.icons")
return {
	{
		"folke/snacks.nvim",
		-- commit = "2b52d89",
		tag = "v2.22.0",
		priority = 1000,
		lazy = false,
		---@type snacks.Config
		opts = {
			bigfile = {
				enabled = true,
			},
			explorer = {
				enabled = false,
				---@class snacks.explorer.Config
				{
					replace_netrw = true, -- Replace netrw with the snacks explorer
				},
			},
			git = {
				enabled = true,
			},
			indent = {
				enabled = true,
				priority = 1,
				char = icons.ui.SeparatorLight,
				only_scope = true,
				only_current = true,
				hl = {
					"SnacksIndent1",
					"SnacksIndent2",
					"SnacksIndent3",
					"SnacksIndent4",
					"SnacksIndent5",
					"SnacksIndent6",
					"SnacksIndent7",
					"SnacksIndent8",
				},
				scope = {
					enabled = true, -- enable highlighting the current scope
					priority = 200,
					char = "│",
					underline = false, -- underline the start of the scope
					only_current = false, -- only show scope in the current window
					hl = "SnacksPickerDelim", ---@type string|string[] hl group for scopes
				},
				chunk = {
					-- when enabled, scopes will be rendered as chunks, except for the
					-- top-level scope which will be rendered as a scope.
					enabled = false,
					-- only show chunk scopes in the current window
					only_current = true,
					priority = 200,
					hl = "SnacksPickerDelim", ---@type string|string[] hl group for chunk scopes
					char = {
						corner_top = "┌ ",
						corner_bottom = "└",
						horizontal = "",
						vertical = "│",
						arrow = icons.ui.ArrowRight,
					},
				},
				animate = { enabled = false }, -- do not animate -- feels slow for me
			},
			input = {
				enabled = true,
			},
			notifier = {
				enabled = true,
				timeout = 2000,
				width = { min = 40, max = 0.4 },
				height = { min = 1, max = 0.6 },
				margin = { top = 0, right = 1, bottom = 0 },
				padding = true,
				sort = { "level", "added" },
				level = vim.log.levels.TRACE,
				icons = {
					debug = icons.ui.Bug,
					error = icons.diagnostics.Error,
					info = icons.diagnostics.Information,
					trace = icons.ui.Bookmark,
					warn = icons.diagnostics.Warning,
				},
				style = "compact",
				top_down = true,
				date_format = "%R",
				more_format = " ↓ %d lines ",
				refresh = 50,
			},
			picker = {
				enabled = true,
				sources = {
					explorer = {
						enabled = true,
						hidden = true,
						exclude = {
							".svn",
							".hg",
							".DS_Store",
							".idea",
							".vscode",
							".cache",
							".sass-cache",
							".history",
							".gitignore",
							".gitmodules",
							".DS_Store",
							"node_modules",
							"vendor",
							".clangd",
						},
						auto_close = false,
						win = {
							list = {
								keys = {
									["o"] = { { "pick_win", "jump" }, mode = { "n", "i" } },
								},
							},
						},
					},
					icons = {
						icon_sources = { "nerd_fonts", "emoji" },
					},
				},
			},
			quickfile = {
				enabled = true,
			},
			scope = {
				enabled = true,
			},
			scroll = {
				enabled = true,

				animate = {
					duration = { step = 15, total = 200 },
					easing = "linear",
					-- fps = 60,
				},
			},
			statuscolumn = {
				enabled = false,
			},
			words = {
				enabled = true,
			},
			styles = {
				notification = {
					wo = {
						wrap = true,
					}, -- Wrap notifications
				},
			},
			image = {
				enabled = true,
				formats = {
					"png",
					"jpg",
					"jpeg",
					"gif",
					"bmp",
					"webp",
					"tiff",
					"heic",
					"avif",
					"mp4",
					"mov",
					"avi",
					"mkv",
					"webm",
					"pdf",
				},
				force = true, -- try displaying the image, even if the terminal does not support it
				doc = {
					-- enable image viewer for documents
					-- a treesitter parser must be available for the enabled languages.
					enabled = true,
					-- render the image inline in the buffer
					-- if your env doesn't support unicode placeholders, this will be disabled
					-- takes precedence over `opts.float` on supported terminals
					inline = true,
					-- render the image in a floating window
					-- only used if `opts.inline` is disabled
					float = true,
					max_width = 80,
					max_height = 40,
					-- Set to `true`, to conceal the image text when rendering inline.
					-- (experimental)
					---@param lang string tree-sitter language
					---@param type snacks.image.Type image type
					conceal = function(lang, type)
						-- only conceal math expressions
						return type == "math"
					end,
				},
				img_dirs = { "img", "images", "assets", "static", "public", "media", "attachments" },
				-- window options applied to windows displaying image buffers
				-- an image buffer is a buffer with `filetype=image`
				wo = {
					wrap = false,
					number = false,
					relativenumber = false,
					cursorcolumn = false,
					signcolumn = "no",
					foldcolumn = "0",
					list = false,
					spell = false,
					statuscolumn = "",
				},
				cache = vim.fn.stdpath("cache") .. "/snacks/image",
				debug = {
					request = false,
					convert = false,
					placement = false,
				},
				env = {},
				-- icons used to show where an inline image is located that is
				-- rendered below the text.
				icons = {
					math = "󰪚 ",
					chart = "󰄧 ",
					image = " ",
				},
				---@class snacks.image.convert.Config
				convert = {
					notify = true, -- show a notification on error
					---@type snacks.image.args
					mermaid = function()
						local theme = vim.o.background == "light" and "neutral" or "dark"
						return { "-i", "{src}", "-o", "{file}", "-b", "transparent", "-t", theme, "-s", "{scale}" }
					end,
					---@type table<string,snacks.image.args>
					magick = {
						default = { "{src}[0]", "-scale", "1920x1080>" }, -- default for raster images
						vector = { "-density", 192, "{src}[0]" }, -- used by vector images like svg
						math = { "-density", 192, "{src}[0]", "-trim" },
						pdf = { "-density", 192, "{src}[0]", "-background", "white", "-alpha", "remove", "-trim" },
					},
				},
				math = {
					enabled = true, -- enable math expression rendering
					-- in the templates below, `${header}` comes from any section in your document,
					-- between a start/end header comment. Comment syntax is language-specific.
					-- * start comment: `// snacks: header start`
					-- * end comment:   `// snacks: header end`
					typst = {
						tpl = [[
                          #set page(width: auto, height: auto, margin: (x: 2pt, y: 2pt))
                          #show math.equation.where(block: false): set text(top-edge: "bounds", bottom-edge: "bounds")
                          #set text(size: 12pt, fill: rgb("${color}"))
                          ${header}
                          ${content}]],
					},
					latex = {
						font_size = "Large", -- see https://www.sascha-frank.com/latex-font-size.html
						-- for latex documents, the doc packages are included automatically,
						-- but you can add more packages here. Useful for markdown documents.
						packages = { "amsmath", "amssymb", "amsfonts", "amscd", "mathtools" },
						tpl = [[
                          \documentclass[preview,border=0pt,varwidth,12pt]{standalone}
                          \usepackage{${packages}}
                          \begin{document}
                          ${header}
                          { \${font_size} \selectfont
                            \color[HTML]{${color}}
                          ${content}}
                          \end{document}]],
					},
				},
			},
			dashboard = {
				preset = {
					pick = function(cmd, opts)
						return LazyVim.pick(cmd, opts)()
					end,
					header = [[
███╗   ███╗ █████╗ ██╗     █████╗ ███╗   ██╗██╗  ██╗
████╗ ████║██╔══██╗██║    ██╔══██╗████╗  ██║██║  ██║
██╔████╔██║███████║██║    ███████║██╔██╗ ██║███████║
██║╚██╔╝██║██╔══██║██║    ██╔══██║██║╚██╗██║██╔══██║
██║ ╚═╝ ██║██║  ██║██║    ██║  ██║██║ ╚████║██║  ██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝    ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝
]],
                    -- stylua: ignore
                    ---@type snacks.dashboard.Item[]
                    keys = {
                        { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
                        { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
                        { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
                        { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
                        { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
                        { icon = " ", key = "s", desc = "Restore Session", section = "session" },
                        { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
                        { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
                        { icon = " ", key = "q", desc = "Quit", action = ":qa" },
                    },
				},
			},
		},
		keys = { -- Top Pickers & Explorer
			{
				"<leader><space>",
				function()
					Snacks.picker.smart()
				end,
				desc = "Smart Find Files",
			},
			{
				"<leader>,",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Buffers",
			},
			-- {
			--     "<leader>/",
			--     function()
			--         Snacks.picker.grep()
			--     end,
			--     desc = "Grep"
			-- },
			-- {
			--     "<leader>e",
			--     function()
			--         Snacks.explorer({
			--             -- cwd = vim.fn.stdpath("config"),
			--             show_empty = true,
			--             hidden = true,
			--             ignored = true,
			--             follow = false,
			--             supports_live = true
			--         })
			--     end,
			--     desc = "File Explorer"
			-- },
			{
				"<leader>:",
				function()
					Snacks.picker.command_history()
				end,
				desc = "Command History",
			},
			{
				"<leader>n",
				function()
					Snacks.picker.notifications()
				end,
				desc = "Notification History",
			}, -- find
			{
				"<leader>fb",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Buffers",
			},
			{
				"<leader>fc",
				function()
					Snacks.picker.files({
						cwd = vim.fn.stdpath("config"),
					})
				end,
				desc = "Find Config File",
			},
			{
				"<leader>ff",
				function()
					Snacks.picker.files({
						finder = "files",
						format = "file",
						show_empty = true,
						hidden = true,
						ignored = true,
						follow = false,
						supports_live = true,
					})
				end,
				desc = "Find Files",
			},
			{
				"<leader>fg",
				function()
					Snacks.picker.git_files()
				end,
				desc = "Find Git Files",
			},
			{
				"<leader>fp",
				function()
					Snacks.picker.projects()
				end,
				desc = "Projects",
			},
			{
				"<leader>fr",
				function()
					Snacks.picker.recent()
				end,
				desc = "Recent",
			}, -- git
			{
				"<leader>gb",
				function()
					Snacks.picker.git_branches()
				end,
				desc = "Git Branches",
			},
			{
				"<leader>gl",
				function()
					Snacks.picker.git_log()
				end,
				desc = "Git Log",
			},
			{
				"<leader>gL",
				function()
					Snacks.picker.git_log_line()
				end,
				desc = "Git Log Line",
			},
			{
				"<leader>gs",
				function()
					Snacks.picker.git_status()
				end,
				desc = "Git Status",
			},
			{
				"<leader>gS",
				function()
					Snacks.picker.git_stash()
				end,
				desc = "Git Stash",
			},
			{
				"<leader>gd",
				function()
					Snacks.picker.git_diff()
				end,
				desc = "Git Diff (Hunks)",
			},
			{
				"<leader>gf",
				function()
					Snacks.picker.git_log_file()
				end,
				desc = "Git Log File",
			}, -- Grep
			{
				"<leader>sb",
				function()
					Snacks.picker.lines()
				end,
				desc = "Buffer Lines",
			},
			{
				"<leader>sB",
				function()
					Snacks.picker.grep_buffers()
				end,
				desc = "Grep Open Buffers",
			},
			{
				"<leader>sg",
				function()
					Snacks.picker.grep({
						hidden = true,
						ignored = true,
					})
				end,
				desc = "Grep",
			},
			{
				"<leader>sw",
				function()
					Snacks.picker.grep_word({
						hidden = true,
						ignored = true,
					})
				end,
				desc = "Visual selection or word",
				mode = { "n", "x" },
			}, -- search
			{
				'<leader>s"',
				function()
					Snacks.picker.registers()
				end,
				desc = "Registers",
			},
			{
				"<leader>s/",
				function()
					Snacks.picker.search_history()
				end,
				desc = "Search History",
			},
			{
				"<leader>sa",
				function()
					-- Snacks.picker.autocmds()
				end,
				desc = "Autocmds",
			},
			{
				"<leader>sb",
				function()
					Snacks.picker.lines()
				end,
				desc = "Buffer Lines",
			},
			{
				"<leader>sc",
				function()
					Snacks.picker.command_history()
				end,
				desc = "Command History",
			},
			{
				"<leader>sC",
				function()
					Snacks.picker.commands()
				end,
				desc = "Commands",
			},
			{
				"<leader>sd",
				function()
					Snacks.picker.diagnostics()
				end,
				desc = "Diagnostics",
			},
			{
				"<leader>sD",
				function()
					Snacks.picker.diagnostics_buffer()
				end,
				desc = "Buffer Diagnostics",
			},
			{
				"<leader>sh",
				function()
					Snacks.picker.help()
				end,
				desc = "Help Pages",
			},
			{
				"<leader>sH",
				function()
					Snacks.picker.highlights()
				end,
				desc = "Highlights",
			},
			{
				"<leader>si",
				function()
					Snacks.picker.icons()
				end,
				desc = "Icons",
			},
			{
				"<leader>sj",
				function()
					Snacks.picker.jumps()
				end,
				desc = "Jumps",
			},
			{
				"<leader>sk",
				function()
					Snacks.picker.keymaps()
				end,
				desc = "Keymaps",
			},
			{
				"<leader>sl",
				function()
					Snacks.picker.loclist()
				end,
				desc = "Location List",
			},
			{
				"<leader>sm",
				function()
					Snacks.picker.marks()
				end,
				desc = "Marks",
			},
			{
				"<leader>sM",
				function()
					Snacks.picker.man()
				end,
				desc = "Man Pages",
			},
			{
				"<leader>sp",
				function()
					Snacks.picker.lazy()
				end,
				desc = "Search for Plugin Spec",
			},
			{
				"<leader>sq",
				function()
					Snacks.picker.qflist()
				end,
				desc = "Quickfix List",
			},
			{
				"<leader>sR",
				function()
					Snacks.picker.resume()
				end,
				desc = "Resume",
			},
			{
				"<leader>su",
				function()
					Snacks.picker.undo()
				end,
				desc = "Undo History",
			},
			{
				"<leader>uC",
				function()
					Snacks.picker.colorschemes()
				end,
				desc = "Colorschemes",
			}, -- LSP
			{
				"gd",
				function()
					Snacks.picker.lsp_definitions()
				end,
				desc = "Goto Definition",
			},
			{
				"gD",
				function()
					Snacks.picker.lsp_declarations()
				end,
				desc = "Goto Declaration",
			},
			{
				"gr",
				function()
					Snacks.picker.lsp_references()
				end,
				nowait = true,
				desc = "References",
			},
			{
				"gI",
				function()
					Snacks.picker.lsp_implementations()
				end,
				desc = "Goto Implementation",
			},
			{
				"gy",
				function()
					Snacks.picker.lsp_type_definitions()
				end,
				desc = "Goto T[y]pe Definition",
			},
			{
				"<leader>ss",
				function()
					Snacks.picker.lsp_symbols()
				end,
				desc = "LSP Symbols",
			},
			{
				"<leader>sS",
				function()
					Snacks.picker.lsp_workspace_symbols()
				end,
				desc = "LSP Workspace Symbols",
			}, -- Other
			{
				"<leader>z",
				function()
					Snacks.zen()
				end,
				desc = "Toggle Zen Mode",
			},
			{
				"<leader>Z",
				function()
					Snacks.zen.zoom()
				end,
				desc = "Toggle Zoom",
			},
			{
				"<leader>.",
				function()
					Snacks.scratch()
				end,
				desc = "Toggle Scratch Buffer",
			},
			{
				"<leader>S",
				function()
					Snacks.scratch.select()
				end,
				desc = "Select Scratch Buffer",
			},
			{
				"<leader>n",
				function()
					Snacks.notifier.show_history()
				end,
				desc = "Notification History",
			},
			{
				"<leader>bd",
				function()
					Snacks.bufdelete()
				end,
				desc = "Delete Buffer",
			},
			{
				"<leader>cR",
				function()
					Snacks.rename.rename_file()
				end,
				desc = "Rename File",
			},
			{
				"<leader>gB",
				function()
					Snacks.gitbrowse()
				end,
				desc = "Git Browse",
				mode = { "n", "v" },
			},
			{
				"<leader>gg",
				function()
					Snacks.lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>un",
				function()
					Snacks.notifier.hide()
				end,
				desc = "Dismiss All Notifications",
			},
			{
				"<c-/>",
				function()
					Snacks.terminal()
				end,
				desc = "Toggle Terminal",
			},
			{
				"<c-_>",
				function()
					Snacks.terminal()
				end,
				desc = "which_key_ignore",
			},
			{
				"]]",
				function()
					Snacks.words.jump(vim.v.count1)
				end,
				desc = "Next Reference",
				mode = { "n", "t" },
			},
			{
				"[[",
				function()
					Snacks.words.jump(-vim.v.count1)
				end,
				desc = "Prev Reference",
				mode = { "n", "t" },
			},
			{
				"<leader>N",
				desc = "Neovim News",
				function()
					Snacks.win({
						file = vim.api.nvim_get_runtime_file("doc/news.txt", false)[1],
						width = 0.6,
						height = 0.6,
						wo = {
							spell = false,
							wrap = false,
							signcolumn = "yes",
							statuscolumn = " ",
							conceallevel = 3,
						},
					})
				end,
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("User", {
				pattern = "VeryLazy",
				callback = function()
					-- Setup some globals for debugging (lazy-loaded)
					_G.dd = function(...)
						Snacks.debug.inspect(...)
					end
					_G.bt = function()
						Snacks.debug.backtrace()
					end
					vim.print = _G.dd -- Override print to use snacks for `:=` command

					-- Create some toggle mappings
					Snacks.toggle
						.option("spell", {
							name = "Spelling",
						})
						:map("<leader>us")
					Snacks.toggle
						.option("wrap", {
							name = "Wrap",
						})
						:map("<leader>uw")
					Snacks.toggle
						.option("relativenumber", {
							name = "Relative Number",
						})
						:map("<leader>uL")
					Snacks.toggle.diagnostics():map("<leader>ud")
					Snacks.toggle.line_number():map("<leader>ul")
					Snacks.toggle
						.option("conceallevel", {
							off = 0,
							on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2,
						})
						:map("<leader>uc")
					Snacks.toggle.treesitter():map("<leader>uT")
					Snacks.toggle
						.option("background", {
							off = "light",
							on = "dark",
							name = "Dark Background",
						})
						:map("<leader>ub")
					Snacks.toggle.inlay_hints():map("<leader>uh")
					Snacks.toggle.indent():map("<leader>ug")
					Snacks.toggle.dim():map("<leader>uD")
				end,
			})
		end,
	},
}
