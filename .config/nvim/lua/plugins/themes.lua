local kitty = require("customize.kitty_palette")
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
		tag = "v2.0.0",
		lazy = true,
		priority = 1000,
		config = function()
			local flavour = kitty.active and kitty.active.flavour or "mocha"
			local palette = kitty.colors(require("catppuccin.palettes." .. flavour))
			local primary = kitty.active and kitty.active.primary or palette.lavender
			primary = kitty.ensure_contrast(primary or palette.lavender, palette.base, palette.text, 4.5)
			require("catppuccin").setup({
				flavour = kitty.active and kitty.active.flavour or "mocha",
				transparent_background = true,
				kitty = false,
				float = {
					transparent = true,
					solid = false,
				},
				styles = {
					comments = { "italic" },
					conditionals = { "bold" },
					loops = { "bold" },
					operators = {},
					functions = {},
					keywords = { "bold" },
					types = {},
					variables = {},
					miscs = {},
					properties = {},
				},
				dim_inactive = {
					enabled = false,
					shade = "light",
					percentage = 0.6,
				},
				lsp_styles = { -- Handles the style of specific lsp hl groups (see `:h lsp-highlight`).
					virtual_text = {
						hints = {},
						information = {},
						ok = {},
					},
					underlines = {
						errors = { "underline" },
						warnings = { "underline" },
					},
					inlay_hints = {
						background = false,
					},
				},
				highlight_overrides = {
					all = function(colors)
						return vim.tbl_deep_extend("force", {
							CursorLineNr = { fg = primary },
							Cursor = { fg = colors.base, bg = primary },
							FloatBorder = { fg = primary, bg = "NONE" },
							DashboardFooter = { fg = colors.overlay0 },
							TreesitterContextBottom = { style = {} },
							WinSeparator = { fg = primary },
							["@variable"] = { fg = colors.text, style = {} },
							["@keyword.operator"] = { fg = colors.mauve, style = {} },
							["@string.special.url"] = { fg = colors.blue, style = { "underline" } },
							["@constant"] = { fg = colors.peach, style = {} },
							["@constant.builtin"] = { fg = colors.peach, style = {} },
							["@lsp.type.enumMember"] = { fg = colors.peach, style = {} },
							["@lsp.typemod.variable.readonly"] = { fg = colors.peach, style = {} },
							["@variable.parameter"] = { fg = colors.maroon, style = {} },
							["@lsp.type.parameter"] = { fg = colors.maroon, style = {} },
							["@property"] = { fg = colors.teal, style = {} },
							["@variable.member"] = { fg = colors.teal, style = {} },
							["@lsp.type.property"] = { fg = colors.teal, style = {} },
							["@variable.builtin"] = { fg = colors.red, style = {} },
							["@function.builtin"] = { fg = colors.sapphire, style = {} },
							["@markup.italic"] = { fg = colors.blue, style = { "italic" } },
							["@markup.strong"] = { fg = colors.blue, style = { "bold" } },
							Headline = { style = { "bold" } },
							Headline1 = { fg = colors.blue, style = { "bold" } },
							Headline2 = { fg = colors.pink, style = { "bold" } },
							Headline3 = { fg = colors.lavender, style = { "bold" } },
							Headline4 = { fg = colors.green, style = { "bold" } },
							Headline5 = { fg = colors.peach, style = { "bold" } },
							Headline6 = { fg = colors.flamingo, style = { "bold" } },
							rainbow1 = { fg = colors.blue },
							rainbow2 = { fg = colors.pink },
							rainbow3 = { fg = colors.lavender },
							rainbow4 = { fg = colors.green },
							rainbow5 = { fg = colors.peach },
							rainbow6 = { fg = colors.flamingo },
						}, require("customize.transparent").highlights(colors, primary))
					end,
				},
				color_overrides = { [flavour] = palette },
				integrations = {
					cmp = false,
					nvimtree = false,
					indent_blankline = { enabled = false },
					colorful_winsep = { enabled = false },
					gitsigns = true,
					neotree = true,
					-- treesitter = true, -- remove from: v2.0.0
					blink_cmp = true,
					noice = true,
					harpoon = true,
					lsp_trouble = true,
					which_key = true,
					lsp_saga = true,
					diffview = true,
					grug_far = true,
					-- markdown = true, -- remove from: v2.0.0
					treesitter_context = true,
					rainbow_delimiters = true,
					window_picker = true,
					mason = true,
					snacks = {
						enabled = true,
						indent_scope_color = "", -- catppuccin color (eg. `lavender`) Default: text
					},
					telescope = {
						enabled = true,
					},
					-- remove from: v2.0.0
					-- native_lsp = {
					-- 	enabled = true,
					-- 	virtual_text = {
					-- 		errors = { "italic" },
					-- 		hints = { "italic" },
					-- 		warnings = { "italic" },
					-- 		information = { "italic" },
					-- 		ok = { "italic" },
					-- 	},
					-- 	underlines = {
					-- 		errors = { "underline" },
					-- 		hints = { "underline" },
					-- 		warnings = { "underline" },
					-- 		information = { "underline" },
					-- 		ok = { "underline" },
					-- 	},
					-- 	inlay_hints = {
					-- 		background = true,
					-- 	},
					-- },
				},
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
					local prompt = c.bg_highlight
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
