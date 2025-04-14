return { {
    "nvim-treesitter/nvim-treesitter",
    dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
    lazy = false,
    opts = {
        ensure_installed = { "vim", "lua", "vimdoc", "python", "cpp", "json", "yaml" }
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
