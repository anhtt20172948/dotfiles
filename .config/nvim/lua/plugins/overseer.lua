-- Task runner (overseer) + quick single-file compile/run for C/C++/Python
return {
	{
		"stevearc/overseer.nvim",
		cmd = {
			"OverseerRun",
			"OverseerToggle",
			"OverseerOpen",
			"OverseerQuickAction",
			"OverseerTaskAction",
			"OverseerRunCmd",
		},
		keys = {
			{ "<leader>or", "<cmd>OverseerRun<cr>", desc = "Overseer: Run Task" },
			{ "<leader>ot", "<cmd>OverseerToggle<cr>", desc = "Overseer: Toggle Output" },
			{ "<leader>oa", "<cmd>OverseerQuickAction<cr>", desc = "Overseer: Quick Action" },
			{ "<leader>oA", "<cmd>OverseerTaskAction<cr>", desc = "Overseer: Task Action" },
			{ "<leader>oc", "<cmd>OverseerRunCmd<cr>", desc = "Overseer: Run Command" },
			{ "<leader>ob", "<cmd>OverseerBuild<cr>", desc = "Overseer: Build Task" },
			-- Quick compile+run current file (no build system needed)
			{
				"<leader>rr",
				function()
					require("overseer").run_template({ name = "run current file" })
				end,
				desc = "Run: Current File",
			},
		},
		opts = {
			templates = { "builtin" },
			task_list = {
				direction = "bottom",
				min_height = 12,
				max_height = 20,
				default_detail = 1,
			},
		},
		config = function(_, opts)
			local overseer = require("overseer")
			overseer.setup(opts)

			-- One template that compiles+runs the current buffer based on filetype.
			overseer.register_template({
				name = "run current file",
				condition = { filetype = { "cpp", "c", "python" } },
				builder = function()
					local file = vim.fn.expand("%:p")
					local ft = vim.bo.filetype
					local out = vim.fn.expand("%:p:r")
					if ft == "cpp" then
						return {
							cmd = { "sh" },
							args = { "-c", string.format("g++ -std=c++20 -Wall -g %q -o %q && %q", file, out, out) },
							components = { "default" },
						}
					elseif ft == "c" then
						return {
							cmd = { "sh" },
							args = { "-c", string.format("gcc -std=c17 -Wall -g %q -o %q && %q", file, out, out) },
							components = { "default" },
						}
					else -- python (uses the active venv's `python` on PATH)
						return {
							cmd = { "python3" },
							args = { file },
							components = { "default" },
						}
					end
				end,
			})
		end,
	},
}
