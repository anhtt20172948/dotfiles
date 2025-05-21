vim.opt.fillchars = { eob = " " }


-- undo history
vim.opt.undofile = true

-- Use system clipboard
vim.opt.clipboard:append { "unnamed", "unnamedplus" }
vim.opt.undofile = true

-- Tab and indent
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.ai = true   -- Auto indent
vim.opt.si = true   -- Smart indent
vim.opt.wrap = true -- Wrap lines

-- Set relative number
vim.opt.relativenumber = true

-- Enable filetype plugins
vim.api.nvim_command("filetype plugin indent on")

-- Use magic for regex
vim.opt.magic = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- Make scrolling and painting fast
-- ttyfast kept for vim compatibility but not needed for nvim
vim.opt.ttyfast = true
vim.opt.lazyredraw = true

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

-- Always show the status line
vim.opt.laststatus = 2

-- Syntax highlight
vim.cmd("syntax enable")

-- set cusorline
vim.opt.cursorline = true
