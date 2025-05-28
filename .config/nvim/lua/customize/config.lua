local options = {

	ui = {
		cmp = {
			icons_left = true, -- only for non-atom styles!
			style = "default", -- default/flat_light/flat_dark/atom/atom_colored
			abbr_maxwidth = 60,
			-- for tailwind, css lsp etc
			format_colors = { lsp = true, icon = "󱓻" },
		},
	},
}
return options
