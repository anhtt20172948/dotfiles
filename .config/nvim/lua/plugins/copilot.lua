return {
    "zbirenbaum/copilot.lua",
    lazy = false,
    config = function()
        require("copilot").setup({
            panel = {
                enabled = false,
                auto_refresh = true,
                keymap = {
                    jump_prev = "<C-[>",
                    jump_next = "<C-]>",
                    accept = "<C-e>",
                    refresh = "r",
                    open = "<C-\\>",
                },
            },
            suggestion = {
                enabled = false,
                auto_trigger = true,
                debounce = 75,
                keymap = {
                    accept = "<C-e>",
                    next = "<C-]>",
                    prev = "<C-[>",
                    dismiss = "<C-c>",
                },
            },
        })
        vim.api.nvim_set_keymap('n', '<leader>ce', ':Copilot enable<CR>', { noremap = true, silent = true })
        vim.api.nvim_set_keymap('n', '<leader>cd', ':Copilot disable<CR>', { noremap = true, silent = true })
    end,
}
