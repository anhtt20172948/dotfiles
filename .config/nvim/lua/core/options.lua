vim.opt.fillchars = { eob = " " }
vim.opt.fillchars:append({ foldopen = "-", foldclose = "+", foldsep = " " })
vim.opt.signcolumn = "yes:1"
vim.opt.foldcolumn = "1"
vim.opt.foldlevelstart = 99
if vim.fn.exists("+winborder") == 1 then
	vim.opt.winborder = "rounded"
end
require("customize.ui").setup()

-- undo history
vim.opt.undofile = true

-- Use system clipboard
vim.opt.clipboard:append({ "unnamed", "unnamedplus" })

-- Tab and indent
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.ai = true -- Auto indent
vim.opt.si = true -- Smart indent
vim.opt.wrap = true -- Wrap lines

-- Set relative number
vim.opt.relativenumber = true

-- filetype plugin/indent and syntax are enabled by default in Neovim.

-- Use magic for regex
vim.opt.magic = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- NOTE: lazyredraw is intentionally left to init.lua (set to false there to fix noice).
-- ttyfast removed: it is a no-op on Neovim.

-- Split windows to right and below
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Detect OS ("Linux", "Darwin" or "Windows_NT")
vim.g.os = vim.uv.os_uname().sysname

-- Get ~ directory path
HOME = os.getenv("HOME")
--}}}

------------------------------------------------------------------------------
-- {{{ => UI
-- Show line numbers
vim.opt.number = true

-- Ruler
-- vim.opt.textwidth = 79
-- vim.api.nvim_set_option_value("colorcolumn", "79", {})

-- Highlight search results
vim.opt.hlsearch = true

-- Incremental search
vim.opt.incsearch = true

-- Show current position
vim.opt.ruler = true

-- No annoying error sound
vim.opt.errorbells = false
vim.opt.visualbell = false
vim.cmd("set t_vb=")
vim.opt.tm = 500

-- Per-window statusline: each split (neo-tree, code buffer...) gets its own bar at
-- its bottom, so the file name sits right under its buffer instead of the far left/neo-tree.
-- (Set back to 3 for one global bar.)
vim.opt.laststatus = 2

-- set cusorline
vim.opt.cursorline = true

vim.g.clipboard = {
	name = "OSC 52",
	copy = {
		["+"] = require("vim.ui.clipboard.osc52").copy("+"),
		["*"] = require("vim.ui.clipboard.osc52").copy("*"),
	},
	paste = {
		["+"] = require("vim.ui.clipboard.osc52").paste("+"),
		["*"] = require("vim.ui.clipboard.osc52").paste("*"),
	},
}
