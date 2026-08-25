return { -- If you want neo-tree's file operations to work with LSP (updating imports, etc.), you can use a plugin like
	-- https://github.com/antosha417/nvim-lsp-file-operations:
	{
		"antosha417/nvim-lsp-file-operations",
		dependencies = { "nvim-lua/plenary.nvim", "nvim-neo-tree/neo-tree.nvim" },
		config = function()
			require("lsp-file-operations").setup()
		end,
	},
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
				{ -- named directory icons (distinct Material Design folder-* variants; verified render in kitty)
					"echasnovski/mini.icons",
					opts = {
						directory = {
							src = { glyph = "󰝰", hl = "MiniIconsPurple" },
							components = { glyph = "󰉓", hl = "MiniIconsAzure" },
							component = { glyph = "󰉓", hl = "MiniIconsAzure" },
							context = { glyph = "󱂷", hl = "MiniIconsCyan" },
							types = { glyph = "󱂷", hl = "MiniIconsBlue" },
							models = { glyph = "󱋣", hl = "MiniIconsOrange" },
							views = { glyph = "󱞊", hl = "MiniIconsAzure" },
							controllers = { glyph = "󰉒", hl = "MiniIconsAzure" },
							services = { glyph = "󰉒", hl = "MiniIconsAzure" },
							service = { glyph = "󰉒", hl = "MiniIconsAzure" },
							middleware = { glyph = "󰾶", hl = "MiniIconsYellow" },
							providers = { glyph = "󰉒", hl = "MiniIconsAzure" },
							js = { glyph = "󰣞", hl = "MiniIconsYellow" },
							javascript = { glyph = "󰣞", hl = "MiniIconsYellow" },
							ts = { glyph = "󰣞", hl = "MiniIconsBlue" },
							typescript = { glyph = "󰣞", hl = "MiniIconsBlue" },
							react = { glyph = "󰣞", hl = "MiniIconsBlue" },
							vue = { glyph = "󰣞", hl = "MiniIconsGreen" },
							angular = { glyph = "󰣞", hl = "MiniIconsRed" },
							svelte = { glyph = "󰣞", hl = "MiniIconsOrange" },
							node = { glyph = "󰣞", hl = "MiniIconsGreen" },
							nodejs = { glyph = "󰣞", hl = "MiniIconsGreen" },
							python = { glyph = "󰣞", hl = "MiniIconsPurple" },
							rust = { glyph = "󰣞", hl = "MiniIconsOrange" },
							go = { glyph = "󰣞", hl = "MiniIconsCyan" },
							golang = { glyph = "󰣞", hl = "MiniIconsCyan" },
							java = { glyph = "󰣞", hl = "MiniIconsOrange" },
							kotlin = { glyph = "󰣞", hl = "MiniIconsPurple" },
							php = { glyph = "󰣞", hl = "MiniIconsBlue" },
							ruby = { glyph = "󰣞", hl = "MiniIconsRed" },
							swift = { glyph = "󰣞", hl = "MiniIconsOrange" },
							dart = { glyph = "󰣞", hl = "MiniIconsCyan" },
							flutter = { glyph = "󰣞", hl = "MiniIconsAzure" },
							elixir = { glyph = "󰣞", hl = "MiniIconsPurple" },
							scala = { glyph = "󰣞", hl = "MiniIconsRed" },
							lua = { glyph = "󰣞", hl = "MiniIconsBlue" },
							graphql = { glyph = "󰣞", hl = "MiniIconsRed" },
							api = { glyph = "󰡰", hl = "MiniIconsGreen" },
							lib = { glyph = "󰲂", hl = "MiniIconsGrey" },
							core = { glyph = "󰲂", hl = "MiniIconsGrey" },
							common = { glyph = "󰲂", hl = "MiniIconsGrey" },
							utils = { glyph = "󱧼", hl = "MiniIconsYellow" },
							util = { glyph = "󱧼", hl = "MiniIconsYellow" },
							helpers = { glyph = "󱧼", hl = "MiniIconsYellow" },
							vendor = { glyph = "󰉓", hl = "MiniIconsGrey" },
							app = { glyph = "󱂵", hl = "MiniIconsAzure" },
							apps = { glyph = "󱂵", hl = "MiniIconsAzure" },
							layouts = { glyph = "󰉋", hl = "MiniIconsAzure" },
							pages = { glyph = "󱧶", hl = "MiniIconsAzure" },
							public = { glyph = "󱧰", hl = "MiniIconsGrey" },
							static = { glyph = "󱧰", hl = "MiniIconsGrey" },
							fonts = { glyph = "󰉋", hl = "MiniIconsPurple" },
							font = { glyph = "󰉋", hl = "MiniIconsPurple" },
							styles = { glyph = "󰉋", hl = "MiniIconsRed" },
							css = { glyph = "󰉋", hl = "MiniIconsRed" },
							scss = { glyph = "󰉋", hl = "MiniIconsRed" },
							sass = { glyph = "󰉋", hl = "MiniIconsRed" },
							themes = { glyph = "󰚝", hl = "MiniIconsPurple" },
							theme = { glyph = "󰚝", hl = "MiniIconsPurple" },
							nvim = { glyph = "󰉋", hl = "MiniIconsGreen" },
							assets = { glyph = "󰉏", hl = "MiniIconsAzure" },
							images = { glyph = "󰉏", hl = "MiniIconsAzure" },
							img = { glyph = "󰉏", hl = "MiniIconsAzure" },
							icons = { glyph = "󰉏", hl = "MiniIconsYellow" },
							config = { glyph = "󱁿", hl = "MiniIconsGrey" },
							configs = { glyph = "󱁿", hl = "MiniIconsGrey" },
							settings = { glyph = "󱁿", hl = "MiniIconsGrey" },
							constants = { glyph = "󱁽", hl = "MiniIconsGrey" },
							docker = { glyph = "󰡰", hl = "MiniIconsAzure" },
							kubernetes = { glyph = "󰡰", hl = "MiniIconsAzure" },
							k8s = { glyph = "󰡰", hl = "MiniIconsAzure" },
							terraform = { glyph = "󰡰", hl = "MiniIconsPurple" },
							ansible = { glyph = "󰡰", hl = "MiniIconsRed" },
							aws = { glyph = "󰡰", hl = "MiniIconsOrange" },
							azure = { glyph = "󰡰", hl = "MiniIconsAzure" },
							gcp = { glyph = "󰡰", hl = "MiniIconsAzure" },
							nginx = { glyph = "󰡰", hl = "MiniIconsGreen" },
							ci = { glyph = "󰴋", hl = "MiniIconsGrey" },
							workflows = { glyph = "󰴋", hl = "MiniIconsAzure" },
							keys = { glyph = "󰢬", hl = "MiniIconsYellow" },
							certs = { glyph = "󰢬", hl = "MiniIconsYellow" },
							secrets = { glyph = "󰉐", hl = "MiniIconsYellow" },
							[".github"] = { glyph = "󰴋", hl = "MiniIconsAzure" },
							[".gitlab"] = { glyph = "󰴋", hl = "MiniIconsOrange" },
							[".git"] = { glyph = "󰴋", hl = "MiniIconsOrange" },
							[".vscode"] = { glyph = "󱁿", hl = "MiniIconsAzure" },
							[".idea"] = { glyph = "󱁿", hl = "MiniIconsOrange" },
							[".docker"] = { glyph = "󰡰", hl = "MiniIconsAzure" },
							[".vercel"] = { glyph = "󱧰", hl = "MiniIconsGrey" },
							[".config"] = { glyph = "󱁿", hl = "MiniIconsGrey" },
							docs = { glyph = "󱂷", hl = "MiniIconsPurple" },
							examples = { glyph = "󱂷", hl = "MiniIconsPurple" },
							i18n = { glyph = "󱉭", hl = "MiniIconsCyan" },
							locales = { glyph = "󱉭", hl = "MiniIconsCyan" },
							lang = { glyph = "󱉭", hl = "MiniIconsCyan" },
							translations = { glyph = "󱉭", hl = "MiniIconsCyan" },
							hooks = { glyph = "󰴋", hl = "MiniIconsRed" },
							plugins = { glyph = "󰉗", hl = "MiniIconsGreen" },
							modules = { glyph = "󰉓", hl = "MiniIconsGreen" },
							scripts = { glyph = "󱧶", hl = "MiniIconsYellow" },
							[".husky"] = { glyph = "󰴋", hl = "MiniIconsYellow" },
							[".storybook"] = { glyph = "󱞊", hl = "MiniIconsRed" },
							[".next"] = { glyph = "󰉋", hl = "MiniIconsGrey" },
							[".nuxt"] = { glyph = "󱂵", hl = "MiniIconsGreen" },
							[".expo"] = { glyph = "󰉋", hl = "MiniIconsGrey" },
							coverage = { glyph = "󱥾", hl = "MiniIconsGrey" },
							logs = { glyph = "󰥨", hl = "MiniIconsGrey" },
							tmp = { glyph = "󰪺", hl = "MiniIconsGrey" },
							temp = { glyph = "󰪺", hl = "MiniIconsGrey" },
							cache = { glyph = "󰪺", hl = "MiniIconsYellow" },
							backup = { glyph = "󰛫", hl = "MiniIconsGrey" },
							[".cache"] = { glyph = "󰪺", hl = "MiniIconsGrey" },
							build = { glyph = "󱧼", hl = "MiniIconsGrey" },
							dist = { glyph = "󱧼", hl = "MiniIconsGrey" },
							out = { glyph = "󱧼", hl = "MiniIconsGrey" },
							target = { glyph = "󱧼", hl = "MiniIconsGrey" },
							server = { glyph = "󰡰", hl = "MiniIconsCyan" },
							cloud = { glyph = "󰡰", hl = "MiniIconsCyan" },
							packages = { glyph = "󰉓", hl = "MiniIconsYellow" },
							deps = { glyph = "󰉍", hl = "MiniIconsGreen" },
							bin = { glyph = "󱁽", hl = "MiniIconsYellow" },
							node_modules = { glyph = "󰉍", hl = "MiniIconsGreen" },
							[".local"] = { glyph = "󰉌", hl = "MiniIconsCyan" },
							test = { glyph = "󱥾", hl = "MiniIconsBlue" },
							tests = { glyph = "󱥾", hl = "MiniIconsBlue" },
							spec = { glyph = "󱥾", hl = "MiniIconsBlue" },
							mocks = { glyph = "󱧊", hl = "MiniIconsGrey" },
							media = { glyph = "󱧺", hl = "MiniIconsYellow" },
							videos = { glyph = "󱧺", hl = "MiniIconsYellow" },
							audio = { glyph = "󱍙", hl = "MiniIconsYellow" },
							schema = { glyph = "󱋣", hl = "MiniIconsCyan" },
							schemas = { glyph = "󱋣", hl = "MiniIconsCyan" },
							store = { glyph = "󱋣", hl = "MiniIconsRed" },
							stores = { glyph = "󱋣", hl = "MiniIconsRed" },
							database = { glyph = "󱋣", hl = "MiniIconsYellow" },
							db = { glyph = "󱋣", hl = "MiniIconsYellow" },
							data = { glyph = "󱋣", hl = "MiniIconsYellow" },
							redis = { glyph = "󱋣", hl = "MiniIconsRed" },
							migrations = { glyph = "󰴋", hl = "MiniIconsPurple" },
							seeders = { glyph = "󰉙", hl = "MiniIconsGreen" },
						},
					},
				},
			"MunifTanjim/nui.nvim",
			-- {"3rd/image.nvim", opts = {}}, -- Optional image support in preview window: See `# Preview Mode` for more information
			{
				"s1n7ax/nvim-window-picker", -- for open_with_window_picker keymaps
				version = "2.*",
				config = function()
					require("window-picker").setup({
						hint = "floating-big-letter",
					})
				end,
			},
		},
		lazy = false,
		keys = {
			{
				"<leader>fE",
				function()
					require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd() })
				end,
				desc = "Explorer NeoTree (cwd)",
			},
			-- { "<leader>e", "<Cmd>Neotree reveal<CR>", desc = "NeoTree reveal", remap = true },
			{
				"<leader>ge",
				function()
					require("neo-tree.command").execute({ source = "git_status", toggle = true })
				end,
				desc = "Git Explorer",
			},
			{
				"<leader>be",
				function()
					require("neo-tree.command").execute({ source = "buffers", toggle = true })
				end,
				desc = "Buffer Explorer",
			},
		},
		-----Instead of using `config`, you can use `opts` instead, if you'd like:
		-----@module "neo-tree"
		-----@type neotree.Config
		-- opts = {},
		config = function(_, opts)
			local function on_move(data)
				Snacks.rename.on_rename_file(data.source, data.destination)
			end
			local events = require("neo-tree.events")

			local local_opts = {
				close_if_last_window = false, -- Close Neo-tree if it is the last window left in the tab
				popup_border_style = "NC", -- or "" to use 'winborder' on Neovim v0.11+
				enable_git_status = true,
				enable_diagnostics = true,
				open_files_do_not_replace_types = { "terminal", "trouble", "qf" }, -- when opening files, do not use windows containing these filetypes or buftypes
				open_files_using_relative_paths = false,
				sort_case_insensitive = true, -- used when sorting files and directories in the tree
				sort_function = nil, -- use a custom function for sorting files and directories in the tree

				-- sort_function = function (a,b)
				--       if a.type == b.type then
				--           return a.path > b.path
				--       else
				--           return a.type > b.type
				--       end
				--   end , -- this sorts files and directories descendantly
				source_selector = {
					winbar = true, -- toggle to show,
					show_scrolled_off_parent_node = true,
					padding = { left = 1, right = 0 },
					sources = {
						{ source = "filesystem", display_name = "  Files" }, --      
						{ source = "buffers", display_name = "  Buffers" }, --      
						{ source = "git_status", display_name = " 󰊢 Git" }, -- 󰊢      
					},
				},

				default_component_configs = {
					container = {
						enable_character_fade = true,
					},
					indent = {
						indent_size = 2,
						padding = 1, -- extra padding on left hand side
						-- indent guides
						with_markers = true,
						indent_marker = "│",
						last_indent_marker = "└",
						highlight = "NeoTreeIndentMarker",
						-- expander config, needed for nesting files
						with_expanders = true, -- if nil and file nesting is enabled, will enable expanders
						expander_collapsed = "",
						expander_expanded = "",
						expander_highlight = "NeoTreeExpander",
					},
					modified = {
						symbol = "•",
						highlight = "NeoTreeModified",
					},
					diagnostics = {
						symbols = {
							error = "",
							warn = "",
							info = "",
							hint = "󰌵",
						},
					},
					icon = {
						folder_closed = "󰉋",
						folder_open = "󰝰",
						folder_empty = "󰉖",
						folder_empty_open = "󰷏",
						-- Custom folder icons based on name
						provider = function(icon, node, state) -- default icon provider utilizes nvim-web-devicons if available
							if node.type == "directory" then
								-- Named folder icons (Material-style) via mini.icons.
								-- neo-tree has already set icon.text to folder_open/closed/empty
								-- based on node state; only override for folders that mini.icons
								-- has a dedicated (non-default) icon for, so plain folders keep
								-- their open/closed distinction and expander arrows.
								local ok, mini_icons = pcall(require, "mini.icons")
								if ok then
									local devicon, hl, is_default = mini_icons.get("directory", node.name)
									if not is_default then
										icon.text = devicon or icon.text
										icon.highlight = hl or icon.highlight
									end
								end
							elseif node.type == "file" or node.type == "terminal" then
								local success, web_devicons = pcall(require, "nvim-web-devicons")
								local name = node.type == "terminal" and "terminal" or node.name
								if success then
									-- default = true: unknown extensions get web-devicons' generic
									-- file glyph instead of falling back to the "*" placeholder.
									local devicon, hl = web_devicons.get_icon(name, nil, { default = true })
									icon.text = devicon or icon.text
									icon.highlight = hl or icon.highlight
								end
							end
						end,
						-- The next two settings are only a fallback, if you use nvim-web-devicons and configure default icons there
						-- then these will never be used.
						default = "*",
						highlight = "NeoTreeFileIcon",
					},
					name = {
						trailing_slash = false,
						use_git_status_colors = true,
						highlight = "NeoTreeFileName",
					},
					git_status = {
						symbols = {
							-- Change type
							added = "A", -- or "✚", but this is redundant info if you use git_status_colors on the name
							modified = "M", -- or "", but this is redundant info if you use git_status_colors on the name
							deleted = "✖", -- this can only be used in the git_status source
							renamed = "󰁕", -- this can only be used in the git_status source
							-- Status type
							untracked = "",
							ignored = "",
							unstaged = "󰄱",
							staged = "",
							conflict = "",
						},
					},
					-- If you don't want to use these columns, you can set `enabled = false` for each of them individually
					file_size = {
						enabled = true,
						width = 12, -- width of the column
						required_width = 64, -- min width of window required to show this column
					},
					type = {
						enabled = true,
						width = 10, -- width of the column
						required_width = 122, -- min width of window required to show this column
					},
					last_modified = {
						enabled = true,
						width = 20, -- width of the column
						required_width = 88, -- min width of window required to show this column
					},
					created = {
						enabled = true,
						width = 20, -- width of the column
						required_width = 110, -- min width of window required to show this column
					},
					symlink_target = {
						enabled = false,
					},
				},
				-- A list of functions, each representing a global custom command
				-- that will be available in all sources (if not overridden in `opts[source_name].commands`)
				-- see `:h neo-tree-custom-commands-global`
				commands = {},
				window = {
					position = "left",
					width = 45,
					mapping_options = {
						noremap = true,
						nowait = true,
					},
					mappings = {
						["<space>"] = {
							"toggle_node",
							nowait = false, -- disable `nowait` if you have existing combos starting with this char that you want to use
						},
						["<2-LeftMouse>"] = "open",
						["<cr>"] = "open",
						["<esc>"] = "cancel", -- close preview or floating neo-tree window
						["P"] = {
							"toggle_preview",
							config = {
								use_float = true,
								use_image_nvim = true,
							},
						},
						-- Read `# Preview Mode` for more information
						["l"] = "focus_preview",
						-- ["S"] = "open_split",
						-- ["<C-v>"] = "open_vsplit",
						["<C-v>"] = "vsplit_with_window_picker",
						["S"] = "split_with_window_picker",
						-- ["s"] = "vsplit_with_window_picker",
						["t"] = "open_tabnew",
						-- ["<cr>"] = "open_drop",
						-- ["t"] = "open_tab_drop",
						["o"] = "open_with_window_picker",
						["P"] = "toggle_preview", -- enter preview mode, which shows the current node without focusing
						["C"] = "close_node",
						-- ['C'] = 'close_all_subnodes',
						["z"] = "close_all_nodes",
						-- ["Z"] = "expand_all_nodes",
						-- ["Z"] = "expand_all_subnodes",
						["a"] = {
							"add",
							-- this command supports BASH style brace expansion ("x{a,b,c}" -> xa,xb,xc). see `:h neo-tree-file-actions` for details
							-- some commands may take optional config options, see `:h neo-tree-mappings` for details
							config = {
								show_path = "none", -- "none", "relative", "absolute"
							},
						},
						["A"] = "add_directory", -- also accepts the optional config.show_path option like "add". this also supports BASH style brace expansion.
						["d"] = "delete",
						["r"] = "rename",
						["b"] = "rename_basename",
						["y"] = "copy_to_clipboard",
						["x"] = "cut_to_clipboard",
						["p"] = "paste_from_clipboard",
						["c"] = "copy", -- takes text input for destination, also accepts the optional config.show_path option like "add":
						-- ["c"] = {
						--  "copy",
						--  config = {
						--    show_path = "none" -- "none", "relative", "absolute"
						--  }
						-- }
						["m"] = "move", -- takes text input for destination, also accepts the optional config.show_path option like "add".
						["q"] = "close_window",
						["R"] = "refresh",
						["?"] = "show_help",
						["<"] = "prev_source",
						[">"] = "next_source",
						["Y"] = "copy_selector",
						-- ["i"] = "show_file_details",
						["i"] = {
							"show_file_details",
							-- format strings of the timestamps shown for date created and last modified (see `:h os.date()`)
							-- both options accept a string or a function that takes in the date in seconds and returns a string to display
							config = {
								created_format = "%Y-%m-%d %I:%M %p",
								modified_format = "relative", -- equivalent to the line below
								modified_format = function(seconds)
									return require("neo-tree.utils").relative_date(seconds)
								end,
							},
						},
					},
				},
				nesting_rules = {},
				filesystem = {
					filtered_items = {
						visible = true, -- when true, they will just be displayed differently than normal items
						hide_dotfiles = false,
						hide_gitignored = false,
						hide_hidden = true, -- only works on Windows for hidden files/directories
						hide_by_name = {
							"node_modules",
							".hg",
							".cache",
							"__pycache__",
							".DS_Store",
							"thumbs.db",
							".vscode",
							".cache",
						},
						hide_by_pattern = { -- uses glob style patterns
							-- "*.meta",
							-- "*/src/*/tsconfig.json",
						},
						always_show = { -- remains visible even if other settings would normally hide it
							".gitignored",
						},
						always_show_by_pattern = { -- uses glob style patterns
							-- ".env*",
						},
						never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
							-- ".DS_Store",
							-- "thumbs.db"
							".cache",
							".vscode",
							"__pycache__",
							"node_modules",
							".venv",
						},
						never_show_by_pattern = { -- uses glob style patterns
							-- ".null-ls_*",
						},
					},
					follow_current_file = {
						enabled = true, -- This will find and focus the file in the active buffer every time
						--               -- the current file is changed while the tree is open.
						leave_dirs_open = true, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
					},
					group_empty_dirs = true, -- when true, empty folders will be grouped together
					hijack_netrw_behavior = "disabled", -- netrw disabled, opening a directory opens neo-tree
					-- in whatever position is specified in window.position
					-- "open_current",  -- netrw disabled, opening a directory opens within the
					-- window like netrw would, regardless of window.position
					-- "disabled",    -- netrw left alone, neo-tree does not handle opening dirs
					use_libuv_file_watcher = true, -- This will use the OS level file watchers to detect changes
					-- instead of relying on nvim autocmd events.
					window = {
						mappings = {
							["<bs>"] = "navigate_up",
							["."] = "set_root",
							["H"] = "toggle_hidden",
							["/"] = "fuzzy_finder",
							["D"] = "fuzzy_finder_directory",
							["#"] = "fuzzy_sorter", -- fuzzy sorting using the fzy algorithm
							-- ["D"] = "fuzzy_sorter_directory",
							["f"] = "filter_on_submit",
							["<c-x>"] = "clear_filter",
							["[g"] = "prev_git_modified",
							["]g"] = "next_git_modified",
							-- ["w"] = {
							--   "show_help",
							--   nowait = false,
							--   config = { title = "Order by", prefix_key = "o" },
							-- },
							["oc"] = {
								"order_by_created",
								nowait = false,
							},
							["od"] = {
								"order_by_diagnostics",
								nowait = false,
							},
							["og"] = {
								"order_by_git_status",
								nowait = false,
							},
							["om"] = {
								"order_by_modified",
								nowait = false,
							},
							["on"] = {
								"order_by_name",
								nowait = false,
							},
							["os"] = {
								"order_by_size",
								nowait = false,
							},
							["ot"] = {
								"order_by_type",
								nowait = false,
							},
							-- ['<key>'] = function(state) ... end,
						},
						fuzzy_finder_mappings = { -- define keymaps for filter popup window in fuzzy_finder_mode
							["<down>"] = "move_cursor_down",
							["<C-n>"] = "move_cursor_down",
							["<up>"] = "move_cursor_up",
							["<C-p>"] = "move_cursor_up",
							["<esc>"] = "close",
							-- ['<key>'] = function(state, scroll_padding) ... end,
						},
					},

					commands = {
						copy_selector = function(state)
							local node = state.tree:get_node()
							local filepath = node:get_id()
							local filename = node.name
							local modify = vim.fn.fnamemodify

							local vals = {
								["BASENAME"] = modify(filename, ":r"),
								["EXTENSION"] = modify(filename, ":e"),
								["FILENAME"] = filename,
								["PATH (CWD)"] = modify(filepath, ":."),
								["PATH (HOME)"] = modify(filepath, ":~"),
								["PATH"] = filepath,
								["URI"] = vim.uri_from_fname(filepath),
							}

							local options = vim.tbl_filter(function(val)
								return vals[val] ~= ""
							end, vim.tbl_keys(vals))
							if vim.tbl_isempty(options) then
								vim.notify("No values to copy", vim.log.levels.WARN)
								return
							end
							table.sort(options)
							vim.ui.select(options, {
								prompt = "Choose to copy to clipboard:",
								format_item = function(item)
									return ("%s: %s"):format(item, vals[item])
								end,
							}, function(choice)
								local result = vals[choice]
								if result then
									vim.notify(("Copied: `%s`"):format(result))
									vim.fn.setreg("+", result)
								end
							end)
						end,
					}, -- Add a custom command or override a global one using the same function name
				},

				renderers = {
					directory = {
						{ "indent" },
						{ "icon" },
						{ "current_filter" },
						{
							"container",
							content = {
								{ "name", zindex = 10 },
								{
									"symlink_target",
									zindex = 10,
									highlight = "NeoTreeSymbolicLinkTarget",
								},
								{ "clipboard", zindex = 10 },
								{ "diagnostics", zindex = 20, align = "right" },
								{ "git_status", zindex = 10, align = "right", hide_when_expanded = true },
								{ "file_size", zindex = 10, align = "right" },
								{ "type", zindex = 10, align = "right" },
								{ "last_modified", zindex = 10, align = "right" },
								{ "created", zindex = 10, align = "right" },
							},
						},
					},
					file = {
						{ "indent" },
						{ "icon" },
						{
							"container",
							content = {
								{
									"name",
									zindex = 10,
								},
								{
									"symlink_target",
									zindex = 10,
									highlight = "NeoTreeSymbolicLinkTarget",
								},
								{ "clipboard", zindex = 10 },
								{ "bufnr", zindex = 10 },
								{ "modified", zindex = 20, align = "right" },
								{ "diagnostics", zindex = 20, align = "left" },
								{ "git_status", zindex = 10, align = "right" },
								{ "file_size", zindex = 10, align = "right" },
								{ "type", zindex = 10, align = "right" },
								{ "last_modified", zindex = 10, align = "right" },
								{ "created", zindex = 10, align = "right" },
							},
						},
					},
				},
				buffers = {
					follow_current_file = {
						enabled = true, -- This will find and focus the file in the active buffer every time
						--              -- the current file is changed while the tree is open.
						leave_dirs_open = true, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
					},
					group_empty_dirs = true, -- when true, empty folders will be grouped together
					show_unloaded = true,
					window = {
						mappings = {
							["d"] = "buffer_delete",
							["bd"] = "buffer_delete",
							["<bs>"] = "navigate_up",
							["."] = "set_root",
							-- ["o"] = {
							--     "show_help",
							--     nowait = false,
							--     config = {
							--         title = "Order by",
							--         prefix_key = "o"
							--     }
							-- },
							["oc"] = {
								"order_by_created",
								nowait = false,
							},
							["od"] = {
								"order_by_diagnostics",
								nowait = false,
							},
							["om"] = {
								"order_by_modified",
								nowait = false,
							},
							["on"] = {
								"order_by_name",
								nowait = false,
							},
							["os"] = {
								"order_by_size",
								nowait = false,
							},
							["ot"] = {
								"order_by_type",
								nowait = false,
							},
						},
					},
				},
				git_status = {
					window = {
						position = "float",
						mappings = {
							["A"] = "git_add_all",
							["gu"] = "git_unstage_file",
							["ga"] = "git_add_file",
							["gr"] = "git_revert_file",
							["gc"] = "git_commit",
							["gp"] = "git_push",
							["gg"] = "git_commit_and_push",
							["o"] = {
								"show_help",
								nowait = false,
								config = {
									title = "Order by",
									prefix_key = "o",
								},
							},
							["oc"] = {
								"order_by_created",
								nowait = false,
							},
							["od"] = {
								"order_by_diagnostics",
								nowait = false,
							},
							["om"] = {
								"order_by_modified",
								nowait = false,
							},
							["on"] = {
								"order_by_name",
								nowait = false,
							},
							["os"] = {
								"order_by_size",
								nowait = false,
							},
							["ot"] = {
								"order_by_type",
								nowait = false,
							},
						},
					},
				},
			}
			local move_handlers = {
				{ event = events.FILE_MOVED, handler = on_move },
				{ event = events.FILE_RENAMED, handler = on_move },
			}
			local incoming_opts = opts or {}
			local merged_handlers = vim.list_extend(
				vim.deepcopy(incoming_opts.event_handlers or {}),
				move_handlers
			)
			local final_opts = vim.tbl_deep_extend("force", {}, vim.deepcopy(incoming_opts), local_opts)
			final_opts.event_handlers = merged_handlers

			-- Folder icon/name turn yellow (warning) / red (error) based on the most
			-- severe LSP diagnostic found in the files they contain. neo-tree already
			-- aggregates child diagnostics onto ancestor dirs in
			-- utils.get_diagnostic_counts(); these wrappers only recolor the built-in
			-- icon/name output, keeping mini.icons folder variants and git colors.
			local common_components = require("neo-tree.sources.common.components")
			-- The renderer resolves components through `state.components`, which is a
			-- tbl_deep_extend() snapshot of the common module taken when
			-- filesystem/components.lua first loads. Custom components must therefore
			-- be attached to that snapshot table, not to common.components itself.
			local components = require("neo-tree.sources.filesystem.components")
			local DIAG_HL = { [1] = "DiagnosticError", [2] = "DiagnosticWarn" }
			local function folder_diag_hl(node, state)
				local d = state.diagnostics_lookup and state.diagnostics_lookup[node:get_id()]
				if d and d.severity_number and d.severity_number <= 2 then
					return DIAG_HL[d.severity_number]
				end
			end
			-- Renderer entries keep their standard names ("icon"/"name") so they still
			-- receive the default_component_configs merge (folder glyphs, provider,
			-- git colors...). The diagnostic recoloring is applied by overriding those
			-- keys on the snapshot table, wrapping the originals, guarded to
			-- directories only so file rendering stays untouched.
			local orig_icon, orig_name = common_components.icon, common_components.name
			components.icon = function(config, node, state)
				local item = orig_icon(config, node, state)
				if node.type == "directory" then
					local hl = folder_diag_hl(node, state)
					if item.text and hl then
						item.highlight = hl
					end
				end
				return item
			end
			components.name = function(config, node, state)
				local item = orig_name(config, node, state)
				local hl = node.type == "directory" and folder_diag_hl(node, state)
				if hl then
					item.highlight = hl
				end
				return item
			end

			require("neo-tree").setup(final_opts)

			vim.api.nvim_create_autocmd("TermClose", {
				pattern = "*lazygit",
				callback = function()
					if package.loaded["neo-tree.sources.git_status"] then
						require("neo-tree.sources.git_status").refresh()
					end
				end,
			})

			vim.keymap.set("n", "<leader>e", "<Cmd>Neotree reveal<CR>")
		end,
	},
}
