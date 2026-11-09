return {
	{
		"b0o/incline.nvim",
		config = function()
			require("incline").setup({
				highlight = {
					groups = {
						InclineNormal = { default = false, group = "Normal" },
						InclineNormalNC = { default = false, group = "NormalNC" },
					},
				},
				render = function(props)
					-- The filename already sits below this split in Lualine. Only a
					-- multi-window tab needs an extra window number for navigation.
					if #vim.api.nvim_tabpage_list_wins(0) < 2 or vim.api.nvim_win_get_width(props.win) < 100 then
						return ""
					end
					return { { " " .. vim.api.nvim_win_get_number(props.win) .. " ", group = "FloatBorder" } }
				end,
			})
		end,
	},
}
