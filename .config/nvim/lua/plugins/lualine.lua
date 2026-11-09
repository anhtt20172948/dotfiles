return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local palette = require("customize.kitty_palette").palette()
		local primary = require("customize.ui").primary()
		local icons = require("lib.icons")
		local theme = {}
		for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "terminal", "inactive" }) do
			theme[mode] = {
				a = { fg = mode == "inactive" and palette.subtext0 or primary, bg = "NONE", gui = "bold" },
				b = { fg = palette.text, bg = "NONE" },
				c = { fg = palette.text, bg = "NONE" },
			}
		end
		local function wide()
			return vim.api.nvim_win_get_width(0) >= 120
		end
		local function medium()
			return vim.api.nvim_win_get_width(0) >= 100
		end
		local function setup()
			require("lualine").setup({
				options = {
					theme = theme,
					globalstatus = false,
					icons_enabled = vim.env.NVIM_ASCII ~= "1",
					section_separators = "",
					component_separators = "",
				},
				sections = {
					lualine_a = {
						{
							"mode",
							fmt = function(mode)
								return vim.api.nvim_win_get_width(0) < 100 and mode:sub(1, 1) or mode
							end,
						},
					},
					lualine_b = { { "branch", icon = icons.git.Branch, cond = medium } },
					lualine_c = {
						{
							"diff",
							cond = wide,
							symbols = { added = icons.git.Add, modified = icons.git.Mod, removed = icons.git.Remove },
						},
						{ "filetype", cond = wide, colored = false },
						{ "filename", path = 0, color = { fg = palette.text, bg = "NONE", gui = "bold" } },
					},
					lualine_x = {
						{ require("customize.aiterm_ecc").account_status },
						{
							function()
								local clients = vim.lsp.get_clients({ bufnr = 0 })
								return clients[1] and clients[1].name or ""
							end,
							cond = wide,
							color = { fg = palette.text },
						},
						{
							require("lazy.status").updates,
							cond = function()
								return wide() and require("lazy.status").has_updates()
							end,
						},
						{ "encoding", cond = wide },
						{ "fileformat", cond = wide, icons_enabled = false },
						{ "searchcount", cond = medium },
						{
							"diagnostics",
							symbols = {
								error = icons.diagnostics.Error,
								warn = icons.diagnostics.Warn,
								info = icons.diagnostics.Info,
								hint = icons.diagnostics.Hint,
							},
						},
					},
					lualine_y = {},
					lualine_z = { "location" },
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
