-- Only the textobjects.scm queries are used: mini.ai's treesitter textobjects
-- (af/if, ac/ic, ao/io in plugins/mini.lua) read them, and mini.ai loads this
-- plugin as a dependency. The plugin follows its `main` branch, which has no
-- `nvim-treesitter.configs` module, so it sets no keymaps of its own.
return {
	"nvim-treesitter/nvim-treesitter-textobjects",
	lazy = true,
}
