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
        "cmake",
        "make",
        "doxygen",
        "comment",
        "printf",
        "toml",
        "json",
        "yaml",
        "bash"
      },

      highlight = {
        enable = true,
      },

      -- Pinned to a specific commit above, so parsers are frozen intentionally.
      -- auto_install stays off to avoid fighting the pin; parsers are listed explicitly.
      auto_install = false,
    },

    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}
