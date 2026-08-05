local map = vim.keymap.set

map("n", "<C-s>", "<cmd>w<CR>", { desc = "general save file" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "general copy whole file" })
map("n", "<Esc>", "<cmd>noh<CR>", { desc = "general clear highlights" })

-- Toggle Term
map("n", "<C-q>", ":Lspsaga term_toggle<cr>", { desc = "Floating Terminal", noremap = true, silent = true })

-- Move selected lines up/down (keeps selection, re-indents)
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down", silent = true })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up", silent = true })

-- Paste over a selection without clobbering the yank register
map("x", "p", '"_dP', { desc = "Paste (keep register)" })

-- Keep the cursor centered while searching / half-page scrolling
map("n", "n", "nzzzv", { desc = "Next match (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev match (centered)" })
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })

-- Buffer navigation
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Prev buffer" })

-- Diagnostic navigation
map("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Prev diagnostic" })
map("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
