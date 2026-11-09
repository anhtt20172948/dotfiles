return {
	"rachartier/tiny-inline-diagnostic.nvim",
	event = "LspAttach",
	priority = 1000,
	config = function()
		require("tiny-inline-diagnostic").setup({
			preset = "simple",
			transparent_bg = true,
			hi = { arrow = "DiagnosticInfo" },
			options = {
				show_source = { enabled = true },
				use_icons_from_diagnostic = true,
				multilines = {
					enabled = true,
					always_show = false,
				},
				-- Auto-hide inline diagnostics when vim.diagnostic.open_float() is used (gl keymap)
				override_open_float = true,
			},
		})
		require("customize.ui").decorations()

		-- Disable native virtual text to avoid duplicates
		vim.diagnostic.config({ virtual_text = false })
	end,
}
