vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

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

-- Run auto forcus nvim tree
-- vim.cmd([[
--     :NvimTreeFocus
-- ]])

--- CMP configuration
local cmp = require 'cmp'
cmp.setup({
    sources = {
        -- Copilot Source
        { name = "copilot",  group_index = 2 },
        -- Other Sources
        { name = "nvim_lsp", group_index = 2 },
        { name = "path",     group_index = 2 },
        { name = "luasnip",  group_index = 2 },
    },
    sorting = {
        priority_weight = 2,
        comparators = {
            require("copilot_cmp.comparators").prioritize,

            -- Below is the default comparitor list and order for nvim-cmp
            cmp.config.compare.offset,
            -- cmp.config.compare.scopes, --this is commented in nvim-cmp too
            cmp.config.compare.exact,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.locality,
            cmp.config.compare.kind,
            cmp.config.compare.sort_text,
            cmp.config.compare.length,
            cmp.config.compare.order,
        },
    }
})
cmp.event:on("menu_opened", function()
    vim.b.copilot_suggestion_hidden = true
end)

cmp.event:on("menu_closed", function()
    vim.b.copilot_suggestion_hidden = false
end)

-- transparent background
vim.api.nvim_set_hl(0, 'Normal', { bg = 'none' })
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })
vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Terminal', { bg = 'none' })
vim.api.nvim_set_hl(0, 'EndOfBuffer', { bg = 'none' })
vim.api.nvim_set_hl(0, 'FoldColumn', { bg = 'none' })
vim.api.nvim_set_hl(0, 'Folded', { bg = 'none' })
vim.api.nvim_set_hl(0, 'SignColumn', { bg = 'none' })

-- transparent background for nvim-tree
-- vim.api.nvim_set_hl(0, 'NvimTreeNormal', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'NvimTreeVertSplit', { bg = 'none' })
-- vim.api.nvim_set_hl(0, 'NvimTreeEndOfBuffer', { bg = 'none' })

-- set hlsearch color
vim.api.nvim_set_hl(0, 'Search', { bg = '#8BCD5B', fg = '#202020' })
vim.api.nvim_set_hl(0, 'CurSearch', { bg = '#EFBD5D', fg = '#000000' })
vim.api.nvim_set_hl(0, 'IncSearch', { bg = '#F15664', fg = '#000000' })

-- set cursorline color
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#1A1A1F' })
vim.api.nvim_set_hl(0, 'CursorColumn', { bg = '#1A1A1F' })

-- set visual highlight
vim.api.nvim_set_hl(0, 'Visual', { bg = '#103070' })
