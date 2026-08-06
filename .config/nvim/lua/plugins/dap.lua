-- Debugging: nvim-dap for C/C++ (codelldb) and Python (debugpy)
return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			-- UI panels (scopes / breakpoints / repl / watches)
			{
				"rcarriga/nvim-dap-ui",
				dependencies = { "nvim-neotest/nvim-nio" },
			},
			-- inline virtual text showing variable values
			{
				"theHamsta/nvim-dap-virtual-text",
				opts = { commented = true },
			},
			-- auto-install & wire adapters from mason (codelldb, debugpy)
			{
				"jay-babu/mason-nvim-dap.nvim",
				dependencies = { "mason-org/mason.nvim" },
				opts = {
					ensure_installed = { "codelldb", "python" },
					-- false: ensure_installed đã là nguồn cài duy nhất. true sẽ chạy thêm
					-- một lượt install() song song trên cùng codelldb/debugpy -> mason
					-- assert "Package is already installing".
					automatic_installation = false,
					handlers = {}, -- use default handlers so codelldb is registered
				},
			},
			-- Python adapter (debugpy)
			{
				"mfussenegger/nvim-dap-python",
				ft = "python",
				config = function()
					-- debugpy installed via mason
					local mason_path = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
					require("dap-python").setup(mason_path)
					-- resolve the active venv's python at runtime so it follows venv-selector
					require("dap-python").resolve_python = function()
						return vim.fn.exepath("python3") ~= "" and vim.fn.exepath("python3") or vim.fn.exepath("python")
					end
				end,
			},
		},
		keys = {
			{
				"<leader>db",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = "Debug: Toggle Breakpoint",
			},
			{
				"<leader>dB",
				function()
					require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
				end,
				desc = "Debug: Conditional Breakpoint",
			},
			{
				"<leader>dc",
				function()
					require("dap").continue()
				end,
				desc = "Debug: Continue",
			},
			{
				"<leader>di",
				function()
					require("dap").step_into()
				end,
				desc = "Debug: Step Into",
			},
			{
				"<leader>do",
				function()
					require("dap").step_over()
				end,
				desc = "Debug: Step Over",
			},
			{
				"<leader>dO",
				function()
					require("dap").step_out()
				end,
				desc = "Debug: Step Out",
			},
			{
				"<leader>dr",
				function()
					require("dap").repl.toggle()
				end,
				desc = "Debug: Toggle REPL",
			},
			{
				"<leader>dl",
				function()
					require("dap").run_last()
				end,
				desc = "Debug: Run Last",
			},
			{
				"<leader>dt",
				function()
					require("dap").terminate()
				end,
				desc = "Debug: Terminate",
			},
			{
				"<leader>du",
				function()
					require("dapui").toggle()
				end,
				desc = "Debug: Toggle UI",
			},
			{
				"<leader>de",
				function()
					require("dapui").eval()
				end,
				mode = { "n", "v" },
				desc = "Debug: Eval",
			},
			-- Function-key style (VSCode-ish)
			{
				"<F5>",
				function()
					require("dap").continue()
				end,
				desc = "Debug: Continue",
			},
			{
				"<F10>",
				function()
					require("dap").step_over()
				end,
				desc = "Debug: Step Over",
			},
			{
				"<F11>",
				function()
					require("dap").step_into()
				end,
				desc = "Debug: Step Into",
			},
			{
				"<F12>",
				function()
					require("dap").step_out()
				end,
				desc = "Debug: Step Out",
			},
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			dapui.setup()

			-- Auto open/close the UI around a session
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end

			-- Pretty breakpoint / stopped signs
			vim.fn.sign_define("DapBreakpoint", { text = "", texthl = "DiagnosticError", linehl = "", numhl = "" })
			vim.fn.sign_define(
				"DapBreakpointCondition",
				{ text = "", texthl = "DiagnosticWarn", linehl = "", numhl = "" }
			)
			vim.fn.sign_define("DapStopped", { text = "", texthl = "DiagnosticInfo", linehl = "Visual", numhl = "" })
			vim.fn.sign_define("DapLogPoint", { text = "", texthl = "DiagnosticInfo", linehl = "", numhl = "" })

			-- ── C / C++ via codelldb ──────────────────────────────────────────
			-- mason-nvim-dap registers the `codelldb` adapter; define launch configs.
			dap.configurations.cpp = {
				{
					name = "Launch file (codelldb)",
					type = "codelldb",
					request = "launch",
					program = function()
						return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
					args = function()
						local input = vim.fn.input("Args (space separated): ")
						return vim.split(input, " ", { trimempty = true })
					end,
				},
			}
			-- reuse the same configs for C
			dap.configurations.c = dap.configurations.cpp
		end,
	},
}
