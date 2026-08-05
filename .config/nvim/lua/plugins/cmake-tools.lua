-- CMake integration: build/run/debug + auto compile_commands.json for clangd
return {
	{
		"Civitasv/cmake-tools.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		ft = { "cpp", "c", "cmake" },
		cmd = {
			"CMakeGenerate",
			"CMakeBuild",
			"CMakeRun",
			"CMakeDebug",
			"CMakeSelectBuildTarget",
			"CMakeSelectLaunchTarget",
			"CMakeSelectBuildType",
		},
		keys = {
			{ "<leader>mg", "<cmd>CMakeGenerate<cr>", desc = "CMake: Generate" },
			{ "<leader>mb", "<cmd>CMakeBuild<cr>", desc = "CMake: Build" },
			{ "<leader>mr", "<cmd>CMakeRun<cr>", desc = "CMake: Run" },
			{ "<leader>md", "<cmd>CMakeDebug<cr>", desc = "CMake: Debug (DAP)" },
			{ "<leader>mt", "<cmd>CMakeSelectBuildTarget<cr>", desc = "CMake: Select Build Target" },
			{ "<leader>ml", "<cmd>CMakeSelectLaunchTarget<cr>", desc = "CMake: Select Launch Target" },
			{ "<leader>mT", "<cmd>CMakeSelectBuildType<cr>", desc = "CMake: Select Build Type" },
		},
		opts = {
			cmake_command = "cmake",
			cmake_build_directory = "build",
			-- exports compile_commands.json so clangd understands the project
			cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=1" },
			cmake_regenerate_on_save = true,
			cmake_soft_link_compile_commands = true, -- symlink compile_commands.json to project root
			cmake_dap_configuration = { -- reuses codelldb from dap.lua
				name = "cpp",
				type = "codelldb",
				request = "launch",
				stopOnEntry = false,
				runInTerminal = false,
				console = "integratedTerminal",
			},
			cmake_executor = { name = "overseer" }, -- run builds through overseer if present
			cmake_runner = { name = "terminal" },
		},
	},
}
