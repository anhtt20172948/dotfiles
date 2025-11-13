return {
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		lazy = false,
		dependencies = {
			{ "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
			{ "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
		},
		build = "make tiktoken", -- Only on MacOS or Linux
		config = function()
			local user = vim.env.USER or "User"
			user = user:sub(1, 1):upper() .. user:sub(2)
			require("CopilotChat").setup({

				question_header = "  " .. user .. " ",
				answer_header = "  Copilot ",
				-- Shared config starts here (can be passed to functions at runtime and configured via setup function)

				system_prompt = "You are an expert AI engineering assistant, specializing in Python and C++. You help with building, debugging, optimizing, and explaining AI and ML systems. Your responses are concise, accurate, and structured. Use clear formatting and code examples where appropriate.You are not just answering questions — you are a coding copilot.", -- System prompt to use (can be specified manually in prompt via /).

				-- model = "claude-3.7-sonnet-thought", -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
				agent = "copilot", -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
				context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
				sticky = nil, -- Default sticky prompt or array of sticky prompts to use at start of every new chat.

				temperature = 0.1, -- GPT result temperature
				headless = false, -- Do not write to chat buffer and use history (useful for using custom processing)
				stream = nil, -- Function called when receiving stream updates (returned string is appended to the chat buffer)
				callback = nil, -- Function called when full response is received (retuned string is stored to history)
				remember_as_sticky = true, -- Remember model/agent/context as sticky prompts when asking questions

				-- default selection
				-- see select.lua for implementation
				-- selection = function(source)
				--   return select.visual(source) or select.buffer(source)
				-- end,

				-- default window options
				window = {
					layout = "vertical", -- 'vertical', 'horizontal', 'float', 'replace'
					width = 0.5, -- fractional width of parent, or absolute width in columns when > 1
					height = 0.5, -- fractional height of parent, or absolute height in rows when > 1
					-- Options below only apply to floating windows
					relative = "editor", -- 'editor', 'win', 'cursor', 'mouse'
					border = "single", -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
					row = nil, -- row position of the window, default is centered
					col = nil, -- column position of the window, default is centered
					title = "Copilot Chat", -- title of chat window
					footer = nil, -- footer of chat window
					zindex = 1, -- determines if window is on top or below other floating windows
				},

				show_help = true, -- Shows help message as virtual lines when waiting for user input
				highlight_selection = true, -- Highlight selection
				highlight_headers = true, -- Highlight headers in chat, disable if using markdown renderers (like render-markdown.nvim)
				references_display = "virtual", -- 'virtual', 'write', Display references in chat as virtual text or write to buffer
				auto_follow_cursor = true, -- Auto-follow cursor in chat
				auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
				insert_at_end = false, -- Move cursor to end of buffer when inserting text
				clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

				-- Static config starts here (can be configured only via setup function)

				debug = false, -- Enable debug logging (same as 'log_level = 'debug')
				log_level = "info", -- Log level to use, 'trace', 'debug', 'info', 'warn', 'error', 'fatal'
				proxy = nil, -- [protocol://]host[:port] Use this proxy
				allow_insecure = false, -- Allow insecure server connections

				chat_autocomplete = true, -- Enable chat autocompletion (when disabled, requires manual `mappings.complete` trigger)

				log_path = vim.fn.stdpath("state") .. "/CopilotChat.log", -- Default path to log file
				history_path = vim.fn.stdpath("data") .. "/copilotchat_history", -- Default path to stored history

				error_header = "# Error ", -- Header to use for errors
				separator = "───", -- Separator to use in chat

				-- default prompts
				-- see config/prompts.lua for implementation
				prompts = {
					Explain = {
						prompt = "Write an explanation for the selected code as paragraphs of text.",
						system_prompt = "COPILOT_EXPLAIN",
					},
					Review = {
						prompt = "Review the selected code.",
						system_prompt = "COPILOT_REVIEW",
					},
					Fix = {
						prompt = "There is a problem in this code. Identify the issues and rewrite the code with fixes. Explain what was wrong and how your changes address the problems.",
					},
					Optimize = {
						prompt = "Optimize the selected code to improve performance and readability. Explain your optimization strategy and the benefits of your changes.",
					},
					Docs = {
						prompt = "Please add documentation comments to the selected code.",
					},
					Tests = {
						prompt = "Please generate tests for my code.",
					},
					Commit = {
						prompt = "Write commit message for the change with commitizen convention. Keep the title under 50 characters and wrap message at 72 characters. Format as a gitcommit code block.",
						context = "git:staged",
					},
				},
			})

			vim.api.nvim_set_keymap("n", "<leader>cc", ":CopilotChatToggle <CR>", { noremap = true, silent = true })
			vim.api.nvim_set_keymap("n", "<leader>l", ":CopilotChatReset <CR>", { noremap = true, silent = true })
			vim.api.nvim_set_keymap("i", "<S-Tab>", 'copilot#Accept("<Tab>")', { silent = true, expr = true })
		end,
		-- See Commands section for default commands if you want to lazy load on them
	},
}
