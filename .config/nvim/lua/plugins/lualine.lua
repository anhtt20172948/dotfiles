return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local lualine = require("lualine")
		local lazy_status = require("lazy.status") -- to configure lazy pending updates count

		local colors = {
			color0 = "#092236",
			color1 = "#ff5874",
			color2 = "#c3ccdc",
			-- color3 = "#1c1e26",
			color3 = "none",
			color6 = "#a1aab8",
			color7 = "#828697",
			color8 = "#ae81ff",
		}
		local my_lualine_theme = {
			replace = {
				a = { fg = colors.color0, bg = colors.color1, gui = "bold" },
				b = { fg = colors.color2, bg = colors.color3 },
			},
			inactive = {
				a = { fg = colors.color6, bg = colors.color3, gui = "bold" },
				b = { fg = colors.color6, bg = colors.color3 },
				c = { fg = colors.color6, bg = colors.color3 },
			},
			normal = {
				a = { fg = colors.color0, bg = colors.color7, gui = "bold" },
				b = { fg = colors.color2, bg = colors.color3 },
				c = { fg = colors.color2, bg = colors.color3 },
			},
			visual = {
				a = { fg = colors.color0, bg = colors.color8, gui = "bold" },
				b = { fg = colors.color2, bg = colors.color3 },
			},
			insert = {
				a = { fg = colors.color0, bg = colors.color2, gui = "bold" },
				b = { fg = colors.color2, bg = colors.color3 },
			},
		}

		local mode = {
			"mode",
			fmt = function(str)
				-- return ' '
				-- displays only the first character of the mode
				return " " .. str
			end,
		}

		local diff = {
			"diff",
			colored = true,
			symbols = { added = " ", modified = " ", removed = " " }, -- changes diff symbols
			-- cond = hide_in_width,
		}

		local filename = {
			"filename",
			file_status = true,
			path = 0,
			symbols = {
				modified = "✥", -- Text that shows when the file is modified.
				readonly = "", -- Text that shows when the file is non-modifiable or readonly.
			},
			color = { fg = "white", gui = "bold", bg = "#3d3d3d" }, -- Sets highlighting of component
		}
		local filetype = {
			"filetype",
			colored = true,
			icon_only = false, -- Display only an icon for filetype
		}

		local branch = {
			"branch",
			icon = { "", color = { fg = "#A6D4DE" } },
			"|",
			gui = "bold",
		}

		lualine.setup({
			icons_enabled = true,
			options = {
				-- theme = my_lualine_theme,
				theme = "catppuccin",
				-- component_separators = { left = "", right = "" },
				-- section_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
				component_separators = { left = "", right = "" },
			},
			sections = {
				lualine_a = { mode },
				lualine_b = { branch },
				lualine_c = { diff, filetype, filename },

				lualine_x = {
					{
						function()
							-- local clients = vim.lsp.get_active_clients({ bufnr = 0 })
							-- TODO: fix deprecated API
							local clients = vim.lsp.get_clients({ bufnr = 0 })
							if #clients == 0 then
								return "No LSP"
							end
							return "LSP: " .. clients[1].name
						end,
						icon = " ", -- optional: nice gear icon
						color = { fg = "cyan" },
					},
					{
						-- require("noice").api.statusline.mode.get,
						-- cond = require("noice").api.statusline.mode.has,
						lazy_status.updates,
						cond = lazy_status.has_updates,
						color = { fg = "#ff9e64" },
					},
					{
						"encoding",
						fmt = function(str)
							return str:upper()
						end,
					},
					{
						"fileformat",
						icons_enabled = true,
						symbols = {
							unix = " LF",
						},
					},
					{ "searchcount" },
					{ "diagnostics" },
				},
				lualine_y = { "progress" },
				lualine_z = {
					{ "location", separator = "" },
					{
						function()
							return ""
						end,
						padding = { left = 0, right = 1 },
					},
				},
			},
			extensions = {
				"lazy",
				"man",
				"mason",
				"nvim-dap-ui",
				"overseer",
				"quickfix",
				"toggleterm",
				"trouble",
				"neo-tree",
				"symbols-outline",
			},
		})
	end,
}
