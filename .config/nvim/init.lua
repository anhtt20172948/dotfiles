vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
    local repo = "https://github.com/folke/lazy.nvim.git"
    vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
    {
        "NvChad/NvChad",
        lazy = false,
        branch = "v2.5",
        import = "nvchad.plugins",
    },

    { import = "plugins" },
}, lazy_config)

-- nvim tree
require("nvim-tree").setup {
    update_focused_file = {
        enable = true
    },
    filters = {
        enable = true,
        git_ignored = false,
        dotfiles = false,
        git_clean = false,
        no_buffer = false,
        no_bookmark = false,
        custom = {},
        exclude = {}
    },
    view = {
        width = 50,
    },

}

-- copilot
vim.keymap.set('i', '<S-Right>', 'copilot#Accept("\\<CR>")', {
    expr = true,
    replace_keycodes = false
})
vim.g.copilot_no_tab_map = true


-- load treesitter
require 'nvim-treesitter.configs'.setup {
    highlight = {
        enable = true,
        -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
        -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
        -- Using this option may slow down your editor, and you may see some duplicate highlights.
        -- Instead of true it can also be a list of languages
        additional_vim_regex_highlighting = false,
    },
}

-- load theme
vim.opt.termguicolors = true
vim.cmd('colorscheme bluloco')

dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "nvchad.autocmds"

vim.schedule(function()
    require "mappings"
end)

-- NVIM Menu
-- Keyboard users
vim.keymap.set("n", "<C-t>", function()
    require("menu").open("default")
end, {})

-- mouse users + nvimtree users!
vim.keymap.set({ "n", "v" }, "<RightMouse>", function()
    require('menu.utils').delete_old_menus()

    vim.cmd.exec '"normal! \\<RightMouse>"'

    -- clicked buf
    local buf = vim.api.nvim_win_get_buf(vim.fn.getmousepos().winid)
    local options = vim.bo[buf].ft == "NvimTree" and "nvimtree" or "default"

    require("menu").open(options, { mouse = true })
end, {})

-- Use system clipboard
vim.opt.clipboard:append { "unnamed", "unnamedplus" }

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

-- Quickly replace in all quickfixes
function RP(search, replace)
    local command = ":cdo s/" .. search .. "/" .. replace .. "/g | update"
    vim.cmd(command)
end

-- Quickly find in all project files using grep
function FP(phrase, path, include, exclude)
    if not path then path = "**" end
    local command = [[:silent grep! -r "]] .. phrase .. [[" ]] .. path
    if include then
        command = command .. " --include " .. include
    end
    if exclude then
        command = command .. " --exclude" .. exclude
    end

    vim.cmd(command)
    print("Done searching! :copen to see the results!")
end

-- Quickly find in all project files using grep and replace all results
function FRP(phrase, replace_phrase, path, include, exclude)
    FP(phrase, path, include, exclude)
    RP(phrase, replace_phrase)
end

--  config for session management
--  load the session for the current directory
vim.keymap.set("n", "<leader>qs", function() require("persistence").load() end,
    { desc = "Load session for current directory" })

-- select a session to load
vim.keymap.set("n", "<leader>qS", function() require("persistence").select() end, { desc = "Select session to load" })

-- load the last session
vim.keymap.set("n", "<leader>ql", function() require("persistence").load({ last = true }) end,
    { desc = "Load last session" })

-- stop Persistence => session won't be saved on exit
vim.keymap.set("n", "<leader>qd", function() require("persistence").stop() end,
    { desc = "session won't be save when exit" })

-- Run auto forcus nvim tree
vim.cmd([[
    :NvimTreeFocus
]])


require('mini.cursorword').setup({
    delay = 100,
})
