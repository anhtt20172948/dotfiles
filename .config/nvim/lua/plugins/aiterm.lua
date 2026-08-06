-- AI terminal (vsplit phải): Codex / Claude / opencode.
-- Merge vào spec snacks (cùng name -> lazy tự gộp; snacks lazy=false nên keymap
-- đăng ký ngay). Logic ở lua/customize/aiterm.lua, discovery session cũ trên đĩa
-- ở lua/customize/aiterm_history.lua.
return {
	"folke/snacks.nvim",
	keys = {
		{
			"<leader>aa",
			function()
				require("customize.aiterm").pick()
			end,
			desc = "AI terminal: sessions (cwd)",
			mode = "n",
		},
		{
			-- Cùng picker, scope mọi thư mục. Trong picker bấm <A-a> để đổi qua lại.
			"<leader>aA",
			function()
				require("customize.aiterm").pick({ scope = "all" })
			end,
			desc = "AI terminal: sessions (all dirs)",
			mode = "n",
		},
		{
			"<leader>al",
			function()
				require("customize.aiterm").resume_last()
			end,
			desc = "AI terminal: resume last session",
			mode = "n",
		},
		{
			-- Ẩn pane AI (đóng window), session vẫn chạy nền -> <C-w>p mở lại.
			"<leader>ah",
			function()
				require("customize.aiterm").hide()
			end,
			desc = "AI terminal: hide pane (keeps running)",
			mode = "n",
		},
		{
			-- Chẩn đoán history (cwd scoping / thiếu sqlite3, hữu ích trong container).
			"<leader>ad",
			function()
				require("customize.aiterm").doctor()
			end,
			desc = "AI terminal: history doctor",
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
