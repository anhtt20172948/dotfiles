return {
    "github/copilot.vim",
    lazy = false,
    config = function()
        vim.keymap.set('i', '<S-Right>', 'copilot#Accept("\\<CR>")', {
            expr = true,
            replace_keycodes = false
        })
        vim.g.copilot_no_tab_map = true
    end
}
