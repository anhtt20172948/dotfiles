return { 'rasulomaroff/reactive.nvim',
    event = 'VeryLazy',
    keys = {
        { "<leader>uM", "<cmd>ReactiveToggle<cr>", desc = "Mode Lines" },
    },
    config = function()
        require('reactive').setup({
            builtin = {
                cursorline = true,
                cursor = true,
                modemsg = true
            },
        })
    end,
}
