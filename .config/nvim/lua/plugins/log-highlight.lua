return {
    {
        'fei6409/log-highlight.nvim',
        lazy = false,
        config = function()
            require('log-highlight').setup {
                -- The following options support either a string or a table of strings.

                -- The file extensions.
                extension = 'log',

            }
        end,
    },
}
