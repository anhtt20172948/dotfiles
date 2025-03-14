return {
    'MeanderingProgrammer/render-markdown.nvim',
    lazy = false,
    dependencies = {'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim'}, -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {},
    config = function()
        require('render-markdown').setup({
            completions = { lsp = { enabled = true } },
            heading = {
                enabled = true,
                render_modes = false,
                sign = true,
                icons = {'󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 '},
                position = 'overlay',
                signs = {'󰫎 '},
                width = 'full',
                left_margin = 0,
                left_pad = 0,
                right_pad = 0,
                min_width = 0,
                border = false,
                border_virtual = false,
                border_prefix = true,
                above = '▄',
                below = '▀',
                backgrounds = {'RenderMarkdownH1Bg', 'RenderMarkdownH2Bg', 'RenderMarkdownH3Bg', 'RenderMarkdownH4Bg',
                               'RenderMarkdownH5Bg', 'RenderMarkdownH6Bg'},
                foregrounds = {'RenderMarkdownH1', 'RenderMarkdownH2', 'RenderMarkdownH3', 'RenderMarkdownH4',
                               'RenderMarkdownH5', 'RenderMarkdownH6'},
                custom = {}
            },
            paragraph = {
                -- Turn on / off paragraph rendering.
                enabled = true,
                -- Additional modes to render paragraphs.
                render_modes = false,
                -- Amount of margin to add to the left of paragraphs.
                -- If a float < 1 is provided it is treated as a percentage of available window space.
                left_margin = 0,
                -- Minimum width to use for paragraphs.
                min_width = 0
            },
            code = {
                enabled = true,
                render_modes = false,
                sign = true,
                style = 'full',
                position = 'left',
                language_pad = 0,
                language_name = true,
                disable_background = { 'diff' },
                width = 'full',
                left_margin = 0,
                left_pad = 0,
                right_pad = 0,
                min_width = 0,
                border = 'thin',
                above = '▄',
                below = '▀',
                highlight = 'RenderMarkdownCode',
                highlight_language = nil,
                inline_pad = 0,
                highlight_inline = 'RenderMarkdownCodeInline',
            },
        })
    end

}
