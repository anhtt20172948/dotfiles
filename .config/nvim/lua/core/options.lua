vim.opt.fillchars = { eob = " " }

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
vim.g.os = vim.loop.os_uname().sysname

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

-- Statusline theo TỪNG window: mỗi split (neo-tree, buffer code...) có bar riêng ở
-- đáy của nó -> tên file hiện ngay dưới buffer đang mở, không dồn về mép trái/neo-tree.
-- (Đổi về 3 nếu muốn một bar chung cho toàn màn hình.)
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
