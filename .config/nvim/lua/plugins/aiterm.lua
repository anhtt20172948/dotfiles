-- AI terminal (vsplit phải): Codex / Claude / opencode.
-- Merge vào spec snacks (cùng name -> lazy tự gộp; snacks lazy=false nên keymap
-- đăng ký ngay). Logic ở lua/customize/aiterm.lua, discovery session cũ trên đĩa
-- ở lua/customize/aiterm_history.lua.

-- Bootstrap inlay hints "bật sẵn" mà KHÔNG require module sớm: đăng ký 1 autocmd
-- lúc lazy import file này (startup), rồi tới VeryLazy mới require + setup_hints.
vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		require("customize.aiterm").setup_hints()
	end,
})

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
		{
			-- Gửi file/selection tới session AI đang chạy: menu explain/ask/fix/...
			-- (kiểu CodeCompanion). Visual = @ref + fenced selection; normal = @ref +
			-- function/class dưới con trỏ (treesitter), top-level = @ref cả file.
			"<leader>ai",
			function()
				require("customize.aiterm").actions()
			end,
			desc = "AI: code actions (explain/ask/fix)",
			mode = { "n", "x" },
		},
		{
			-- Bật/tắt inlay hint (dòng ảo phía trên function/class dưới con trỏ).
			"<leader>at",
			function()
				require("customize.aiterm").toggle_hints()
			end,
			desc = "AI: toggle code hints",
			mode = "n",
		},
		{
			-- Lệnh ECC CẤP REPO (/code-review, /build-fix, /quality-gate...). Tách khỏi
			-- <leader>ai vì chúng chạy git diff / npx trên cả project, bỏ qua đoạn code
			-- đang chọn -> gửi không kèm context file.
			"<leader>aw",
			function()
				require("customize.aiterm").workflows()
			end,
			desc = "AI: ECC workflow (repo-wide)",
			mode = "n",
		},
		{
			-- Trạng thái ECC (skills/commands cho AI tool) + cài/cập nhật từng tool.
			-- Tool chưa có ECC cũng hiện sẵn 1 dòng trong picker <leader>aa.
			"<leader>aE",
			function()
				require("customize.aiterm").ecc()
			end,
			desc = "AI: ECC skills (install/update)",
			mode = "n",
		},
		{
			-- Chốt tool mặc định (auto-tạo khi chưa có session), lưu qua các lần mở nvim.
			"<leader>aD",
			function()
				require("customize.aiterm").pick_default()
			end,
			desc = "AI: set default tool",
			mode = "n",
		},
	},
}
