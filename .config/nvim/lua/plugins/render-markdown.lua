return {
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	opts = {
		heading = {
			sign = false,
			icons = { "# ", "## ", "### ", "#### ", "##### ", "###### " },
			backgrounds = { "Headline1Bg", "Headline2Bg", "Headline3Bg", "Headline4Bg", "Headline5Bg", "Headline6Bg" },
			foregrounds = { "Headline1Fg", "Headline2Fg", "Headline3Fg", "Headline4Fg", "Headline5Fg", "Headline6Fg" },
		},
		code = { sign = false, width = "block", right_pad = 1 },
		bullet = { enabled = true },
	},
}
