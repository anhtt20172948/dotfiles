return {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
        "nvim-tree/nvim-web-devicons", -- optional, for file icons
    },
    config = function()
        require("nvim-tree").setup({
            update_focused_file = {
                enable = true
            },
            filters = {
                enable = true,
                git_ignored = false,
                dotfiles = false,
                git_clean = false,
                no_buffer = false,
                no_bookmark = false,
                custom = {},
                exclude = {}
            },
            view = {
                width = 50,
            },

        })
    end,
}
