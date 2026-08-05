-- Central overrides that don't belong to a single spec file.
-- Every other enable/disable now lives inside the plugin's own spec file.
return {
	-- nvzone/menu is only declared here (it has no separate spec file).
	{ "nvzone/menu", enabled = true },

	-- Retired completion / copilot stack: kept installed but OFF.
	-- The active completion stack is blink.cmp + supermaven.
	{ "github/copilot.vim", enabled = true },
	{ "hrsh7th/nvim-cmp", enabled = false },
	{ "hrsh7th/cmp-nvim-lsp", enabled = false },
	{ "hrsh7th/cmp-buffer", enabled = false },
	{ "hrsh7th/cmp-path", enabled = false },
	{ "hrsh7th/cmp-cmdline", enabled = false },
	{ "hrsh7th/cmp-nvim-lua", enabled = false },
	{ "dmitmel/cmp-cmdline-history", enabled = false },
	{ "zbirenbaum/copilot-cmp", enabled = false },
}
