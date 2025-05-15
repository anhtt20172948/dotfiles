local map = vim.keymap.set

map("n", "<C-s>", "<cmd>w<CR>", { desc = "general save file" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "general copy whole file" })
map("n", "<Esc>", "<cmd>noh<CR>", { desc = "general clear highlights" })

-- Toggle Term
map("n", "<C-q>", ":Lspsaga term_toggle<cr>", { desc = "Floating Terminal", noremap = true, silent = true })
