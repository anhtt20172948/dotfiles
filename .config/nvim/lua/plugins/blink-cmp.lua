local trigger_text = ";"
local icons = require("lib.icons")

return {
	"saghen/blink.cmp",
	event = "InsertEnter",
	-- version = "v0.13.1",
	dependencies = {
		"moyiz/blink-emoji.nvim",
		"Kaiser-Yang/blink-cmp-dictionary",
		"L3MON4D3/LuaSnip",
		"kristijanhusak/vim-dadbod-completion",
		"fang2hou/blink-copilot",
		"onsails/lspkind.nvim",
		"rafamadriz/friendly-snippets",
	},
	opts = function(_, opts)
		-- I noticed that telescope was extremeley slow and taking too long to open,
		-- assumed related to blink, so disabled blink and in fact it was related
		-- :lua print(vim.bo[0].filetype)
		-- So I'm disabling blink.cmp for Telescope
		opts.enabled = function()
			-- Get the current buffer's filetype
			local filetype = vim.bo[0].filetype
			-- Disable for Telescope buffers
			if filetype == "TelescopePrompt" or filetype == "minifiles" or filetype == "snacks_picker_input" then
				return false
			end
			return true
		end

		-- NOTE: The new way to enable LuaSnip
		-- Merge custom sources with the existing ones from lazyvim
		-- NOTE: by default lazyvim already includes the lazydev source, so not adding it here again
		opts.sources = vim.tbl_deep_extend("force", opts.sources or {}, {
			default = { "copilot", "lsp", "path", "snippets", "buffer", "dadbod", "emoji", "dictionary" },
			providers = {
				copilot = {
					name = "copilot",
					module = "blink-copilot",
					score_offset = 100,
					async = true,
					opts = {
						max_completions = 3,
						max_attempts = 4,
						kind_name = "Copilot", ---@type string | false
						kind_icon = " ", ---@type string | false
						kind_hl = false, ---@type string | false
						debounce = 200, ---@type integer | false
						auto_refresh = {
							backward = true,
							forward = true,
						},
					},
				},
				lsp = {
					name = "lsp",
					enabled = true,
					module = "blink.cmp.sources.lsp",
					kind = "LSP",
					-- min_keyword_length = 0,
					-- fallbacks = { "snippets", "buffer" },
					score_offset = 90, -- the higher the number, the higher the priority
				},
				path = {
					name = "Path",
					module = "blink.cmp.sources.path",
					score_offset = 25,
					-- When typing a path, I would get snippets and text in the
					-- suggestions, I want those to show only if there are no path
					-- suggestions
					fallbacks = { "snippets", "buffer" },
					-- min_keyword_length = 2,
					opts = {
						trailing_slash = false,
						label_trailing_slash = true,
						get_cwd = function(context)
							return vim.fn.expand(("#%d:p:h"):format(context.bufnr))
						end,
						show_hidden_files_by_default = true,
					},
				},
				buffer = {
					name = "Buffer",
					enabled = true,
					max_items = 10,
					module = "blink.cmp.sources.buffer",
					min_keyword_length = 1,
					score_offset = 15, -- the higher the number, the higher the priority
				},
				snippets = {
					name = "snippets",
					enabled = true,
					max_items = 15,
					min_keyword_length = 2,
					module = "blink.cmp.sources.snippets",
					score_offset = 85, -- the higher the number, the higher the priority
					-- Only show snippets if I type the trigger_text characters, so
					-- to expand the "bash" snippet, if the trigger_text is ";" I have to
					should_show_items = function()
						local col = vim.api.nvim_win_get_cursor(0)[2]
						local before_cursor = vim.api.nvim_get_current_line():sub(1, col)
						-- NOTE: remember that `trigger_text` is modified at the top of the file
						return before_cursor:match(trigger_text .. "%w*$") ~= nil
					end,
					-- After accepting the completion, delete the trigger_text characters
					-- from the final inserted text
					-- Modified transform_items function based on suggestion by `synic` so
					-- that the luasnip source is not reloaded after each transformation
					-- https://github.com/linkarzu/dotfiles-latest/discussions/7#discussion-7849902
					-- NOTE: I also tried to add the ";" prefix to all of the snippets loaded from
					-- friendly-snippets in the luasnip.lua file, but I was unable to do
					-- so, so I still have to use the transform_items here
					-- This removes the ";" only for the friendly-snippets snippets
					transform_items = function(_, items)
						local line = vim.api.nvim_get_current_line()
						local col = vim.api.nvim_win_get_cursor(0)[2]
						local before_cursor = line:sub(1, col)
						local start_pos, end_pos = before_cursor:find(trigger_text .. "[^" .. trigger_text .. "]*$")
						if start_pos then
							for _, item in ipairs(items) do
								if not item.trigger_text_modified then
									---@diagnostic disable-next-line: inject-field
									item.trigger_text_modified = true
									item.textEdit = {
										newText = item.insertText or item.label,
										range = {
											start = { line = vim.fn.line(".") - 1, character = start_pos - 1 },
											["end"] = { line = vim.fn.line(".") - 1, character = end_pos },
										},
									}
								end
							end
						end
						return items
					end,
				},
				-- Example on how to configure dadbod found in the main repo
				-- https://github.com/kristijanhusak/vim-dadbod-completion
				dadbod = {
					name = "Dadbod",
					module = "vim_dadbod_completion.blink",
					min_keyword_length = 2,
					score_offset = 85, -- the higher the number, the higher the priority
				},
				-- https://github.com/moyiz/blink-emoji.nvim
				emoji = {
					module = "blink-emoji",
					name = "Emoji",
					score_offset = 93, -- the higher the number, the higher the priority
					min_keyword_length = 2,
					opts = { insert = true }, -- Insert emoji (default) or complete its name
				},
				-- https://github.com/Kaiser-Yang/blink-cmp-dictionary
				-- In macOS to get started with a dictionary:
				-- cp /usr/share/dict/words ~/github/dotfiles-latest/dictionaries/words.txt
				--
				-- NOTE: For the word definitions make sure "wn" is installed
				-- brew install wordnet
				dictionary = {
					module = "blink-cmp-dictionary",
					name = "Dict",
					score_offset = 20, -- the higher the number, the higher the priority
					-- https://github.com/Kaiser-Yang/blink-cmp-dictionary/issues/2
					enabled = true,
					max_items = 8,
					min_keyword_length = 3,
					opts = {
						-- -- The dictionary by default now uses fzf, make sure to have it
						-- -- installed
						-- -- https://github.com/Kaiser-Yang/blink-cmp-dictionary/issues/2
						--
						-- Do not specify a file, just the path, and in the path you need to
						-- have your .txt files
						dictionary_directories = { vim.fn.expand("~/github/dotfiles-latest/dictionaries") },
						-- Notice I'm also adding the words I add to the spell dictionary
						dictionary_files = {
							vim.fn.expand("~/github/dotfiles-latest/neovim/neobean/spell/en.utf-8.add"),
							vim.fn.expand("~/github/dotfiles-latest/neovim/neobean/spell/es.utf-8.add"),
						},
						-- --  NOTE: To disable the definitions uncomment this section below
						--
						-- separate_output = function(output)
						--   local items = {}
						--   for line in output:gmatch("[^\r\n]+") do
						--     table.insert(items, {
						--       label = line,
						--       insert_text = line,
						--       documentation = nil,
						--     })
						--   end
						--   return items
						-- end,
					},
				},
			},
		})

		opts.cmdline = {
			enabled = true,
		}

		opts.completion = {
			accept = {
				auto_brackets = {
					enabled = true,
					default_brackets = { ";", "" },
					override_brackets_for_filetypes = {
						markdown = { ";", "" },
					},
				},
			},
			keyword = {
				-- 'prefix' will fuzzy match on the text before the cursor
				-- 'full' will fuzzy match on the text before *and* after the cursor
				-- example: 'foo_|_bar' will match 'foo_' for 'prefix' and 'foo__bar' for 'full'
				range = "full",
			},
			menu = {
				border = "rounded", -- or "single", "double", "rounded", "solid", "shadow"
				-- The menu is the completion popup, so this is the border of the popup
				-- and not the documentation popup
				cmdline_position = function()
					if vim.g.ui_cmdline_pos ~= nil then
						local pos = vim.g.ui_cmdline_pos -- (1, 0)-indexed
						return { pos[1] - 1, pos[2] }
					end
					local height = (vim.o.cmdheight == 0) and 1 or vim.o.cmdheight
					return { vim.o.lines - height, 0 }
				end,
				draw = {
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon", "label", gap = 1 },
						{ "kind" },
					},
					components = {
						label = {
							width = { fill = true, max = 60 },
							text = function(ctx)
								local highlights_info = require("colorful-menu").blink_highlights(ctx)
								if highlights_info ~= nil then
									-- Or you want to add more item to label
									return highlights_info.label
								else
									return ctx.label
								end
							end,
							highlight = function(ctx)
								local highlights = {}
								local highlights_info = require("colorful-menu").blink_highlights(ctx)
								if highlights_info ~= nil then
									highlights = highlights_info.highlights
								end
								for _, idx in ipairs(ctx.label_matched_indices) do
									table.insert(highlights, { idx, idx + 1, group = "BlinkCmpLabelMatch" })
								end
								-- Do something else
								return highlights
							end,
						},
					},
				},
			},
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 250,
				treesitter_highlighting = true,
				window = { border = "rounded" },
			},
			ghost_text = {
				enabled = vim.g.ai_cmp,
			},
		}
		opts.appearance = opts.appearance or {}
		opts.appearance.kind_icons = vim.tbl_extend("force", opts.appearance.kind_icons or {}, icons.kind)
		opts.appearance.nerd_font_variant = "mono"
		opts.appearance.use_nvim_cmp_as_default = false

		-- opts.fuzzy = {
		--   -- Disabling this matches the behavior of fzf
		--   use_typo_resistance = false,
		--   -- Frecency tracks the most recently/frequently used items and boosts the score of the item
		--   use_frecency = true,
		--   -- Proximity bonus boosts the score of items matching nearby words
		--   use_proximity = false,
		-- }

		opts.snippets = {
			preset = "luasnip", -- Choose LuaSnip as the snippet engine
		}
		opts.signature = {
			enabled = true,
			window = { border = "rounded" },
		}
		opts.keymap = {
			preset = "default",
			["<Tab>"] = { "select_next", "fallback" },
			["<S-Tab>"] = { "select_prev", "fallback" },

			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<C-p>"] = { "select_prev", "fallback" },
			["<C-n>"] = { "select_next", "fallback" },

			["<S-k>"] = { "scroll_documentation_up", "fallback" },
			["<S-j>"] = { "scroll_documentation_down", "fallback" },
			["<CR>"] = { "accept", "fallback" },

			-- ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "hide", "fallback" },
		}

		return opts
	end,
}
