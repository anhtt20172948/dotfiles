return {
    {
        "folke/persistence.nvim",
        event = "BufReadPre",
        opts = {},
        -- stylua: ignore
        keys = {
            { "<leader>qs", function() require("persistence").load() end,                desc = "Restore Session" },
            { "<leader>qS", function() require("persistence").select() end,              desc = "Select Session" },
            { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore Last Session" },
            { "<leader>qd", function() require("persistence").stop() end,                desc = "Don't Save Current Session" },
        },
    },
    {
      "rmagatti/auto-session",
      ---enables autocomplete for opts
      ---@module "auto-session"
      ---@type AutoSession.Config
     dependencies = { "nvim-telescope/telescope.nvim" },

      lazy = false,
      opts = {
        -- ⚠️ This will only work if Telescope.nvim is installed
        -- The following are already the default values, no need to provide them if these are already the settings you want.
        auto_restore_last_session = true,
        session_lens = {
          -- If load_on_setup is false, make sure you use `:SessionSearch` to open the picker as it will initialize everything first
          load_on_setup = true,
          previewer = false,
          mappings = {
            -- Mode can be a string or a table, e.g. {"i", "n"} for both insert and normal mode
            delete_session = { "i", "<C-D>" },
            alternate_session = { "i", "<C-S>" },
            copy_session = { "i", "<C-Y>" },
          },
          -- Can also set some Telescope picker options
          -- For all options, see: https://github.com/nvim-telescope/telescope.nvim/blob/master/doc/telescope.txt#L112
          theme_conf = {
            border = true,
            -- layout_config = {
            --   width = 0.8, -- Can set width and height as percent of window
            --   height = 0.5,
            -- },
          },
        },
      },
      config = function()
    vim.o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions'
    vim.keymap.set('n', '<leader>P', require('auto-session.session-lens').search_session)
    require('auto-session').setup {
      pre_save_cmds = { 'Neotree close' },
      post_restore_cmds = { 'Neotree filesystem show' },
    }
  end,}
}
