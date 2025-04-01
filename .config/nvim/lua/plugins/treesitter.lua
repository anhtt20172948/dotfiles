return { {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    opts = {
        ensure_installed = { "vim", "lua", "vimdoc", "python", "cpp" }
    },
    config = function()
        require 'nvim-treesitter.configs'.setup {
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },
        }
    end
} }
