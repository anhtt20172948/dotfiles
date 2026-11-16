return {
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	opts = {
		heading = {
			sign = false,
			icons = { "󰉫 ", "󰉬 ", "󰉭 ", "󰉮 ", "󰉯 ", "󰉰 " },
			position = "inline",
			width = "block",
			right_pad = 1,
		},
		code = {
			sign = false,
			width = "block",
			left_pad = 1,
			right_pad = 1,
			language_pad = 1,
			border = "thin",
			highlight_language = "RenderMarkdownCodeInfo",
			inline_pad = 1,
		},
		bullet = { icons = { "•", "◦", "▪" } },
		checkbox = {
			unchecked = { icon = "󰄱 " },
			checked = { icon = "󰄵 " },
		},
		pipe_table = { preset = "round", cell = "trimmed", alignment_indicator = "─" },
		quote = { icon = "│", highlight = "RenderMarkdownQuote" },
		dash = { width = 60 },
	},
}
