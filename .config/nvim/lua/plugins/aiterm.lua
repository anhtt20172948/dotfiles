-- AI terminal (floating sidebar): Codex / Claude / opencode.
-- Merge vào spec snacks (cùng name -> lazy tự gộp; snacks lazy=false nên keymap
-- đăng ký ngay). Logic ở lua/customize/aiterm.lua.
return {
	"folke/snacks.nvim",
	keys = {
		{
			"<leader>aa",
			function()
				require("customize.aiterm").pick()
			end,
			desc = "AI terminal: pick tool",
			mode = "n",
		},
		{
			-- Override <C-w>p mặc định: focus AI sidebar thay vì "previous window".
			"<C-w>p",
			function()
				require("customize.aiterm").focus()
			end,
			desc = "AI terminal: focus",
			mode = "n",
		},
	},
}
