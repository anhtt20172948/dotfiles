return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local kitty = require("customize.kitty_palette")
		local palette = kitty.palette()
		local ui = require("customize.ui")
		local primary = ui.primary()
		local icons = require("lib.icons")
		local ascii = vim.env.NVIM_ASCII == "1"
		local function text(color)
			return kitty.ensure_contrast(color, palette.base, palette.text, 4.5)
		end
		local colors = {
			text = text(palette.text),
			dim = text(palette.subtext0),
			green = text(palette.green),
			mauve = text(palette.mauve),
			red = text(palette.red),
			peach = text(palette.peach),
			yellow = text(palette.yellow),
			blue = text(palette.blue),
			teal = text(palette.teal),
		}
		local function transparent(color)
			return { fg = color, bg = "NONE" }
		end
		local theme = {}
		for mode, color in pairs({
			normal = primary,
			insert = colors.green,
			visual = colors.mauve,
			replace = colors.red,
			command = colors.peach,
			terminal = colors.green,
		}) do
			-- A light palette can produce dark accents. Lift the pill separately
			-- so its dark label stays readable without changing section colours.
			local ink = string.format("#%06x", 0)
			local background = kitty.ensure_contrast(color, ink, string.format("#%06x", 16777215), 4.5)
			theme[mode] = {
				a = { fg = ink, bg = background, gui = "bold" },
				b = transparent(colors.text),
				c = transparent(colors.text),
				x = transparent(colors.text),
				y = transparent(colors.text),
				z = { fg = ink, bg = background, gui = "bold" },
			}
		end
		theme.inactive = {}
		for _, section in ipairs({ "a", "b", "c", "x", "y", "z" }) do
			theme.inactive[section] = transparent(colors.dim)
		end
		local function at_least(width)
			return function()
				return vim.api.nvim_win_get_width(0) >= width
			end
		end
		local compact, medium, wide, full = at_least(40), at_least(60), at_least(80), at_least(100)
		local pill = { left = ascii and "" or "", right = ascii and "" or "" }
		local separator = ascii and "|" or "│"
		local function setup()
			require("lualine").setup({
				options = {
					theme = theme,
					globalstatus = false,
					icons_enabled = not ascii,
					section_separators = "",
					component_separators = { left = separator, right = separator },
					padding = { left = 1, right = 0 },
				},
				sections = {
					lualine_a = {
						{
							"mode",
							separator = pill,
							padding = 1,
							fmt = function(mode)
								return vim.api.nvim_win_get_width(0) >= 120 and mode or mode:sub(1, 1)
							end,
						},
					},
					lualine_b = {
						{
							"branch",
							icon = vim.trim(icons.git.Branch),
							cond = medium,
							color = transparent(primary),
							fmt = function(branch)
								return ui.truncate(branch, math.floor(vim.api.nvim_win_get_width(0) / 8))
							end,
						},
					},
					lualine_c = {
						{
							"diff",
							cond = medium,
							symbols = { added = "+", modified = "~", removed = "-" },
							diff_color = {
								added = transparent(colors.green),
								modified = transparent(colors.yellow),
								removed = transparent(colors.red),
							},
						},
						{ "filetype", cond = wide, colored = true, color = transparent(colors.dim) },
						{
							"filename",
							path = 0,
							file_status = true,
							symbols = { modified = "[+]", readonly = "[RO]" },
							color = { fg = colors.text, bg = "NONE", gui = "bold" },
						},
					},
					lualine_x = {
						{ require("customize.aiterm_ecc").account_status },
						{
							function()
								local clients = vim.lsp.get_clients({ bufnr = 0 })
								return clients[1] and clients[1].name or ""
							end,
							cond = wide,
							icon = ascii and "" or vim.trim(icons.ui.Code),
							color = transparent(colors.teal),
							fmt = function(name)
								return (ascii and name ~= "" and "LSP " or "") .. ui.truncate(name, 16)
							end,
						},
						{
							require("lazy.status").updates,
							cond = function()
								return full() and require("lazy.status").has_updates()
							end,
							color = transparent(primary),
							fmt = function(updates)
								return ascii and ("U" .. (updates:match("%d+$") or "0")) or updates
							end,
						},
						{ "encoding", cond = full, color = transparent(colors.dim) },
						{ "fileformat", cond = full, icons_enabled = false, color = transparent(colors.dim) },
						{ "searchcount", cond = wide, color = transparent(colors.text) },
						{
							"diagnostics",
							cond = compact,
							diagnostics_color = {
								error = transparent(colors.red),
								warn = transparent(colors.yellow),
								info = transparent(colors.blue),
								hint = transparent(colors.teal),
							},
							symbols = {
								error = vim.trim(icons.diagnostics.Error),
								warn = vim.trim(icons.diagnostics.Warn),
								info = vim.trim(icons.diagnostics.Info),
								hint = vim.trim(icons.diagnostics.Hint),
							},
						},
					},
					lualine_y = {},
					lualine_z = { { "location", separator = pill, padding = 1, fmt = vim.trim } },
				},
				extensions = { "lazy", "man", "mason", "nvim-dap-ui", "overseer", "quickfix", "trouble", "neo-tree" },
			})
		end
		setup()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("DotfilesLualine", { clear = true }),
			callback = function()
				-- Rebuild resolved colors when the theme is reconfigured.
				vim.schedule(function()
					require("plugins.lualine").config()
				end)
			end,
		})
	end,
}
