return {
    "lewis6991/gitsigns.nvim",
    requires = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("gitsigns").setup({
            on_attach = function(bufnr)
                local gitsigns = require('gitsigns')

                local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                end

                -- Navigation
                map('n', ']c', function()
                    if vim.wo.diff then
                        vim.cmd.normal({ ']c', bang = true })
                    else
                        gitsigns.nav_hunk('next')
                    end
                end)

                map('n', '[c', function()
                    if vim.wo.diff then
                        vim.cmd.normal({ '[c', bang = true })
                    else
                        gitsigns.nav_hunk('prev')
                    end
                end)

                -- Actions
                map('n', '<leader>ghs', gitsigns.stage_hunk, { desc = ' Gitsigns Stage hunk' })
                map('n', '<leader>ghr', gitsigns.reset_hunk, { desc = ' Gitsigns Reset hunk' })

                map('v', '<leader>ghs', function()
                    gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                end, { desc = ' Gitsigns Stage hunk' })

                map('v', '<leader>ghr', function()
                    gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                end, { desc = ' Gitsigns Reset hunk' })

                map('n', '<leader>ghS', gitsigns.stage_buffer, { desc = ' Gitsigns Stage buffer' })
                map('n', '<leader>ghR', gitsigns.reset_buffer, { desc = ' Gitsigns Reset buffer' })
                map('n', '<leader>ghp', gitsigns.preview_hunk, { desc = ' Gitsigns Preview hunk' })
                map('n', '<leader>ghi', gitsigns.preview_hunk_inline, { desc = ' Gitsigns Preview hunk inline' })

                map('n', '<leader>ghb', function()
                    gitsigns.blame_line({ full = true })
                end, { desc = ' Gitsigns Blame line' })

                map('n', '<leader>ghd', gitsigns.diffthis, { desc = ' Gitsigns Diff this' })

                map('n', '<leader>ghD', function()
                    gitsigns.diffthis('~')
                end, { desc = ' Gitsigns Diff this (cached)' })

                map('n', '<leader>ghQ', function() gitsigns.setqflist('all') end,
                    { desc = ' Gitsigns Set quickfix list' })
                map('n', '<leader>ghq', gitsigns.setqflist, { desc = ' Gitsigns Set quickfix list (hunk)' })

                -- Toggles
                map('n', '<leader>gTb', gitsigns.toggle_current_line_blame,
                    { desc = ' Gitsigns Toggle current line blame' })
                map('n', '<leader>gTd', gitsigns.toggle_deleted, { desc = ' Gitsigns Toggle deleted' })
                map('n', '<leader>gTw', gitsigns.toggle_word_diff, { desc = ' Gitsigns Toggle word diff' })

                -- Text object
                map({ 'o', 'x' }, 'ih', gitsigns.select_hunk, { desc = ' Gitsigns Select hunk' })
            end
        })
    end,
}
