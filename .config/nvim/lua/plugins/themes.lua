local lspsaga = require("lspsaga")
return {
	{
		"uloco/bluloco.nvim",
		lazy = true,
		priority = 1000,
		dependencies = { "rktjmp/lush.nvim" },
		config = function()
			require("bluloco").setup({
				style = "dark", -- "auto" | "dark" | "light"
				transparent = true,
				italics = true,
				terminal = vim.fn.has("gui_running") == 1, -- bluoco colors are enabled in gui terminals per default.
				guicursor = true,
				rainbow_headings = true,
			})
			-- vim.opt.termguicolors = true
			-- vim.cmd('colorscheme bluloco')
		end,
	},
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = true,
		priority = 1000,
		config = function()
			require("catppuccin").setup({
				flavour = "mocha",
				transparent_background = true, -- disables setting the background color.
				styles = {
					comments = { "italic" },
					conditionals = { "italic" },
					loops = { "italic" },
					operators = { "italic" },
					functions = { "bold" },
					keywords = { "bold" },
					types = { "bold" },
				},
				dim_inactive = {
					enabled = false,
					shade = "light",
					percentage = 0.6,
				},
				highlight_overrides = {
					all = function(colors)
						return {
							CurSearch = { bg = colors.sky },
							IncSearch = { bg = colors.sky },
							CursorLineNr = { fg = colors.blue, style = { "bold" } },
							DashboardFooter = { fg = colors.overlay0 },
							TreesitterContextBottom = { style = {} },
							WinSeparator = { fg = colors.overlay0, style = { "bold" } },
							["@markup.italic"] = { fg = colors.blue, style = { "italic" } },
							["@markup.strong"] = { fg = colors.blue, style = { "bold" } },
							Headline = { style = { "bold" } },
							Headline1 = { fg = colors.blue, style = { "bold" } },
							Headline2 = { fg = colors.pink, style = { "bold" } },
							Headline3 = { fg = colors.lavender, style = { "bold" } },
							Headline4 = { fg = colors.green, style = { "bold" } },
							Headline5 = { fg = colors.peach, style = { "bold" } },
							Headline6 = { fg = colors.flamingo, style = { "bold" } },
							rainbow1 = { fg = colors.blue, style = { "bold" } },
							rainbow2 = { fg = colors.pink, style = { "bold" } },
							rainbow3 = { fg = colors.lavender, style = { "bold" } },
							rainbow4 = { fg = colors.green, style = { "bold" } },
							rainbow5 = { fg = colors.peach, style = { "bold" } },
							rainbow6 = { fg = colors.flamingo, style = { "bold" } },
						}
					end,
				},
				color_overrides = {
					mocha = {
						rosewater = "#F5B8AB",
						flamingo = "#F29D9D",
						pink = "#AD6FF7",
						mauve = "#FF8F40",
						red = "#E66767",
						maroon = "#EB788B",
						peach = "#FAB770",
						yellow = "#FACA64",
						green = "#70CF67",
						teal = "#4CD4BD",
						sky = "#61BDFF",
						sapphire = "#4BA8FA",
						blue = "#00BFFF",
						lavender = "#00BBCC",
						text = "#C1C9E6",
						subtext1 = "#A3AAC2",
						subtext0 = "#8E94AB",
						overlay2 = "#7D8296",
						overlay1 = "#676B80",
						overlay0 = "#464957",
						surface2 = "#3A3D4A",
						surface1 = "#2F313D",
						surface0 = "#1D1E29",
						base = "#0b0b12",
						mantle = "#11111a",
						crust = "#191926",
					},
				},
				-- color_overrides = {
				--     mocha = {
				--         -- this 16 colors are changed to onedark
				--         base = "#282c34",
				--         mantle = "#353b45",
				--         surface0 = "#3e4451",
				--         surface1 = "#545862",
				--         surface2 = "#565c64",
				--         text = "#abb2bf",
				--         rosewater = "#b6bdca",
				--         lavender = "#c8ccd4",
				--         red = "#e06c75",
				--         peach = "#d19a66",
				--         yellow = "#e5c07b",
				--         green = "#98c379",
				--         teal = "#56b6c2",
				--         blue = "#61afef",
				--         mauve = "#c678dd",
				--         flamingo = "#be5046",
				--
				--         -- now patching extra palettes
				--         maroon = "#e06c75",
				--         sky = "#d19a66",
				--
				--         -- extra colors not decided what to do
				--         pink = "#F5C2E7",
				--         sapphire = "#74C7EC",
				--
				--         subtext1 = "#BAC2DE",
				--         subtext0 = "#A6ADC8",
				--         overlay2 = "#9399B2",
				--         overlay1 = "#7F849C",
				--         overlay0 = "#6C7086",
				--         crust = "#11111B",
				--     }
				-- },
				integrations = {
					cmp = true,
					gitsigns = true,
					nvimtree = true,
					neotree = true,
					treesitter = true,
					blink_cmp = true,
					noice = true,
					harpoon = true,
					copilot_vim = true,
					notify = true,
					lsp_trouble = true,
					which_key = true,
					lsp_saga = true,
					diffview = true,
					grug_far = true,
					markdown = true,
					treesitter_context = true,
					rainbow_delimiters = true,
					window_picker = true,
					mason = true,
					snacks = {
						enabled = false,
						indent_scope_color = "", -- catppuccin color (eg. `lavender`) Default: text
					},
					telescope = {
						enabled = true,
					},
					indent_blankline = {
						enabled = true,
						scope_color = "lavender", -- catppuccin color (eg. `lavender`) Default: text
						colored_indent_levels = false,
					},
					colorful_winsep = {
						enabled = true,
						color = "lavender",
					},
					native_lsp = {
						enabled = true,
						virtual_text = {
							errors = { "italic" },
							hints = { "italic" },
							warnings = { "italic" },
							information = { "italic" },
							ok = { "italic" },
						},
						underlines = {
							errors = { "underline" },
							hints = { "underline" },
							warnings = { "underline" },
							information = { "underline" },
							ok = { "underline" },
						},
						inlay_hints = {
							background = true,
						},
					},
				},
			})
		end,
	},
	{
		"akinsho/bufferline.nvim",
		config = function(_, opts)
			local mocha = require("catppuccin.palettes").get_palette("mocha")
			require("bufferline").setup({
				highlights = require("catppuccin.groups.integrations.bufferline").get({
					styles = { "italic", "bold" },
					custom = {
						all = {
							fill = { bg = "#000000" },
						},
						mocha = {
							background = { fg = mocha.text },
						},
						latte = {
							background = { fg = "#000000" },
						},
					},
				}),
			})
		end,
	},
	{
		"folke/tokyonight.nvim",
		lazy = true,
		priority = 1000,
		opts = function()
			require("tokyonight").setup({
				style = "night",
				transparent = true, -- Enable this to disable setting the background color
				styles = {
					-- Style to be applied to different syntax groups
					-- Value is any valid attr-list value `:help attr-list`
					comments = "NONE",
					keywords = "italic",
					functions = "NONE",
					variables = "NONE",
					-- Background styles. Can be "dark", "transparent" or "normal"
					sidebars = vim.g.neovide and "dark" or "dark", -- style for sidebars, see below
					floats = vim.g.neovide and "dark" or "dark", -- style for floating windows
				},
				sidebars = { "qf", "help", "snacks_layout_box", "snacks_picker_list" }, -- Set a darker background on sidebar-like windows. For example: `["qf", "vista_kind", "terminal", "packer"]`
				day_brightness = 0.3, -- Adjusts the brightness of the colors of the **Day** style. Number between 0 and 1, from dull to vibrant colors
				hide_inactive_statusline = false, -- Enabling this option, will hide inactive statuslines and replace them with a thin border instead. Should work with the standard **StatusLine** and **LuaLine**.
				dim_inactive = false, -- dims inactive windows
				lualine_bold = false, -- When `true`, section headers in the lualine theme will be bold

				cache = true, -- When set to true, the theme will be cached for better performance
				---@type table<string, boolean|{enabled:boolean}>
				plugins = {
					-- enable all plugins when not using lazy.nvim
					-- set to false to manually enable/disable plugins
					all = package.loaded.lazy == nil,
					-- uses your plugin manager to automatically enable needed plugins
					-- currently only lazy.nvim is supported
					auto = true,
					-- add any plugins here that you want to enable
					-- for all possible plugins, see:
					--   * https://github.com/folke/tokyonight.nvim/tree/main/lua/tokyonight/groups
				},
				on_highlights = function(hl, c)
					local prompt = "#2d3149"
					hl.TelescopeNormal = {
						bg = c.bg_dark,
						fg = c.fg_dark,
					}
					hl.TelescopeBorder = {
						bg = c.bg_dark,
						fg = c.bg_dark,
					}
					hl.TelescopePromptNormal = {
						bg = prompt,
					}
					hl.TelescopePromptBorder = {
						bg = prompt,
						fg = prompt,
					}
					hl.TelescopePromptTitle = {
						bg = prompt,
						fg = prompt,
					}
					hl.TelescopePreviewTitle = {
						bg = c.bg_dark,
						fg = c.bg_dark,
					}
					hl.TelescopeResultsTitle = {
						bg = c.bg_dark,
						fg = c.bg_dark,
					}
				end,
			})
		end,
	},
}
