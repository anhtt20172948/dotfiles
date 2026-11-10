-- AI terminal (right vsplit): Codex / Claude / opencode.
-- Merged into the snacks spec (same name -> lazy merges them; snacks is lazy=false so keymaps
-- register immediately). Logic lives in lua/customize/aiterm.lua, discovery of old on-disk sessions
-- in lua/customize/aiterm_history.lua.

-- Bootstrap inlay hints "on by default" WITHOUT requiring the module early: register one autocmd
-- when lazy imports this file (startup), then require + setup_hints on VeryLazy.
vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		require("customize.aiterm").setup_hints()
	end,
})

require("customize.aiterm_ecc").setup_account()

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
			-- Same picker, scoped to every directory. Press <A-a> in the picker to toggle.
			"<leader>aA",
			function()
				require("customize.aiterm").pick({ scope = "all" })
			end,
			desc = "AI terminal: sessions (all dirs)",
			mode = "n",
		},
		{
			-- Same menu as tmux prefix E: use/add/edit token/rename/delete a Claude account.
			"<leader>au",
			function()
				require("customize.ai_account").menu()
			end,
			desc = "AI: Claude accounts",
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
			-- Hide the AI pane (close the window); the session keeps running -> <C-w>p reopens it.
			"<leader>ah",
			function()
				require("customize.aiterm").hide()
			end,
			desc = "AI terminal: hide pane (keeps running)",
			mode = "n",
		},
		{
			-- History diagnostics (cwd scoping / missing sqlite3, useful in containers).
			"<leader>ad",
			function()
				require("customize.aiterm").doctor()
			end,
			desc = "AI terminal: history doctor",
			mode = "n",
		},
		{
			-- Override the default <C-w>p: focus the AI sidebar instead of "previous window".
			"<C-w>p",
			function()
				require("customize.aiterm").focus()
			end,
			desc = "AI terminal: focus",
			mode = "n",
		},
		{
			"<C-w>l",
			function()
				local aiterm = package.loaded["customize.aiterm"]
				if not (aiterm and aiterm.focus_if_right()) then
					vim.cmd(vim.v.count1 .. "wincmd l")
				end
			end,
			desc = "Right: focus AI terminal if adjacent",
			mode = "n",
		},
		{
			-- Send the file/selection to the running AI session: explain/ask/fix/... menu
			-- (CodeCompanion style). Visual = @ref + fenced selection; normal = @ref +
			-- the function/class under the cursor (treesitter), top level = @ref of the whole file.
			"<leader>ai",
			function()
				require("customize.aiterm").actions()
			end,
			desc = "AI: code actions (explain/ask/fix)",
			mode = { "n", "x" },
		},
		{
			-- Toggle the inlay hint (virtual line above the function/class under the cursor).
			"<leader>aT",
			function()
				require("customize.aiterm").toggle_hints()
			end,
			desc = "AI: toggle code hints",
			mode = "n",
		},
		{
			-- Browse the tool's SKILLs (ECC + built-in + hand-written) and apply one to the selected
			-- code. Skills are guidance docs, so they fit a selection, unlike the repo-level
			-- commands on <leader>aw.
			"<leader>aS",
			function()
				require("customize.aiterm").skill_pick()
			end,
			desc = "AI: use a skill",
			mode = { "n", "x" },
		},
		{
			-- REPO-LEVEL ECC commands (/code-review, /build-fix, /quality-gate...). Separate from
			-- <leader>ai because they run git diff / npx on the whole project and ignore the
			-- selection -> sent without file context.
			"<leader>aw",
			function()
				require("customize.aiterm").workflows()
			end,
			desc = "AI: ECC workflow (repo-wide)",
			mode = "n",
		},
		{
			-- ECC status (skills/commands for AI tools) + install/update per tool.
			-- Tools without ECC still get a row in the <leader>aa picker.
			"<leader>aE",
			function()
				require("customize.aiterm").ecc()
			end,
			desc = "AI: ECC skills (install/update)",
			mode = "n",
		},
		{
			-- Menu skills (vercel-labs/skills CLI): Add / Find / Use / Init / Browse.
			"<leader>aV",
			function()
				require("customize.aiterm").skills()
			end,
			desc = "AI: skills (add/find/use/init)",
			mode = "n",
		},
		{
			-- Pin the default tool (auto-created when there is no session), persisted across nvim runs.
			"<leader>aD",
			function()
				require("customize.aiterm").pick_default()
			end,
			desc = "AI: set default tool",
			mode = "n",
		},
		-- Agent workflow (kunchenguid); logic in lua/customize/aiterm_flow.lua; shares
		-- the tmux ai-workflow.sh script with the prefix F menu.
		{
			-- Push the current branch through the no-mistakes gate (review/test/lint -> PR).
			"<leader>ap",
			function()
				require("customize.aiterm_flow").push_gate()
			end,
			desc = "AI flow: push through no-mistakes",
			mode = "n",
		},
		{
			"<leader>aP",
			function()
				require("customize.aiterm_flow").pipelines()
			end,
			desc = "AI flow: no-mistakes pipelines (TUI)",
			mode = "n",
		},
		{
			-- gnhf --worktree loop on a goal, in its own tmux window.
			"<leader>ag",
			function()
				require("customize.aiterm_flow").gnhf()
			end,
			desc = "AI flow: gnhf overnight loop",
			mode = "n",
		},
		{
			-- treehouse worktree + a new AI session in it. Not <leader>at:
			-- supermaven already owns that key.
			"<leader>aW",
			function()
				require("customize.aiterm_flow").worktree()
			end,
			desc = "AI flow: new session in treehouse worktree",
			mode = "n",
		},
		{
			"<leader>aF",
			function()
				require("customize.aiterm_flow").firstmate()
			end,
			desc = "AI flow: firstmate",
			mode = "n",
		},
		{
			-- Review crew changes: pick a worker worktree -> new tab + diffview
			-- (read-only). <A-g> in the picker opens lazygit.
			"<leader>aR",
			function()
				require("customize.aiterm_flow").crew_review()
			end,
			desc = "AI flow: review crew worktree",
			mode = "n",
		},
	},
}
