-- Testing: neotest with pytest (Python) and GoogleTest (C/C++)
return {
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-neotest/nvim-nio",
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-treesitter/nvim-treesitter",
			-- adapters
			"nvim-neotest/neotest-python",
			-- GoogleTest adapter for C/C++. Swap for "Backdround/neotest-catch2" if you use Catch2.
			{
				"alfaix/neotest-gtest",
				-- neotest-gtest needs a one-time :Neotest gtest configure per project
			},
		},
		keys = {
			{ "<leader>tr", function() require("neotest").run.run() end, desc = "Test: Run Nearest" },
			{
				"<leader>tf",
				function() require("neotest").run.run(vim.fn.expand("%")) end,
				desc = "Test: Run File",
			},
			{
				"<leader>ta",
				function() require("neotest").run.run(vim.uv.cwd()) end,
				desc = "Test: Run All (cwd)",
			},
			{
				"<leader>td",
				function() require("neotest").run.run({ strategy = "dap" }) end,
				desc = "Test: Debug Nearest",
			},
			{ "<leader>tS", function() require("neotest").run.stop() end, desc = "Test: Stop" },
			{ "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Test: Toggle Summary" },
			{
				"<leader>to",
				function() require("neotest").output.open({ enter = true, auto_close = true }) end,
				desc = "Test: Show Output",
			},
			{ "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Test: Toggle Output Panel" },
			{ "<leader>tw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Test: Toggle Watch" },
		},
		config = function()
			require("neotest").setup({
				adapters = {
					require("neotest-python")({
						runner = "pytest",
						-- allow debugging into library code when using <leader>td
						dap = { justMyCode = false },
					}),
					require("neotest-gtest").setup({}),
				},
				status = { virtual_text = true },
				output = { open_on_run = true },
			})
		end,
	},
}
