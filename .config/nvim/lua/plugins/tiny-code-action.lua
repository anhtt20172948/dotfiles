return {
	"rachartier/tiny-code-action.nvim",
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
		{
			"folke/snacks.nvim",
			opts = {
				terminal = {},
			},
		},
	},
	event = "LspAttach",
	opts = {
		picker = {
			"snacks",
			opts = {
				layout_strategy = "vertical",
				layout_config = {
					width = 0.7,
					height = 0.9,
					preview_cutoff = 1,
					preview_height = function(_, _, max_lines)
						local h = math.floor(max_lines * 0.5)
						return math.max(h, 10)
					end,
				},
			},
		},
	},
}
