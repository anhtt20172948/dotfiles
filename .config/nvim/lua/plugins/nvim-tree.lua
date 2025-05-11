local icons = require('lib.icons')
return {
    "nvim-tree/nvim-tree.lua",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
        local nvimtree = require("nvim-tree")

        vim.g.loaded_netrw = 1
        vim.g.loaded_netrwPlugin = 1

        nvimtree.setup({
            hijack_directories = {
                enable = true,    -- Set this to false if you want to disable it
                auto_open = true, -- Automatically open the tree when switching to a directory
            },

            view = {
                width = 35,
                relativenumber = false,
                side = "left",
            },
            update_focused_file = {
                enable = true,
                update_cwd = true,
                ignore_list = { ".git", "node_modules", ".cache" },
            },
            -- change folder arrow icons
            renderer = {
                indent_markers = {
                    enable = true,
                    inline_arrows = true,
                    icons = {
                        corner = "└",
                        edge = "│",
                        item = "│",
                        bottom = "─",
                        none = " ",
                    },
                },
                icons = {
                    glyphs = {
                        folder = {
                            -- arrow_closed = "→", -- arrow when folder is closed
                            -- arrow_open = "↓", -- arrow when folder is open
                            -- arrow_closed = icons.ui.ArrowRight, -- arrow when folder is closed
                            -- arrow_open = icons.ui.ArrowDown,    -- arrow when folder is open
                            -- arrow_closed = "", -- arrow when folder is closed
                            -- arrow_open = "",   -- arrow when folder is open
                            -- arrow_closed = "", -- arrow when folder is closed
                        },
                        git = {
                            unstaged = "✗",
                            staged = "✓",
                            unmerged = "",
                            renamed = "➜",
                            untracked = "★",
                            deleted = "",
                            ignored = "◌",
                        },
                    },
                    web_devicons = {
                        file = {
                            enable = true,
                            color = true,
                        },
                        folder = {
                            enable = true,
                            color = true,
                        },
                    },

                },
            },
            -- window splits
            actions = {
                open_file = {
                    window_picker = {
                        enable = true,
                    },
                },
            },
            filters = {
                enable = true,
                git_ignored = false,
                dotfiles = false,
                git_clean = false,
                no_buffer = false,
                no_bookmark = false,
                custom = { ".DS_Store" },
            },
            git = {
                ignore = false,
            },
        })

        -- ** Opens nvim file tree at start
        -- if vim.fn.argc(-1) == 0 then
        --     vim.cmd("NvimTreeFocus")
        -- end

        -- keymaps
        local keymap = vim
            .keymap                                                                                     -- for conciseness

        keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file explorer" })      -- toggle file explorer
        keymap.set("n", "<leader>ef", "<cmd>NvimTreeFindFileToggle<CR>",
            { desc = "Toggle file explorer on current file" })                                          -- toggle file explorer on current file
        keymap.set("n", "<leader>ec", "<cmd>NvimTreeCollapse<CR>", { desc = "Collapse file explorer" }) -- collapse file explorer
        keymap.set("n", "<leader>er", "<cmd>NvimTreeRefresh<CR>", { desc = "Refresh file explorer" })   -- refresh file explorer
    end

}
