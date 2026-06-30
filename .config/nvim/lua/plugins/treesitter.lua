return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPre", "BufNewFile" },
    commit = "cf12346a3414fa1b06af75c79faebe7f76df080a",
    opts = {
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "python",
        "cpp",
        "c",
        "json",
        "yaml",
      },

      highlight = {
        enable = true,
      },

      auto_install = true,
    },

    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}
