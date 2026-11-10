local function list()
	return require("harpoon"):list()
end

-- Snacks picker over the harpoon list; `dd` removes the entry under the cursor.
local function pick()
	Snacks.picker({
		-- Rebuilt on every refresh so deletions show up immediately.
		finder = function()
			local items = {}
			for _, item in ipairs(list().items) do
				table.insert(items, { text = item.value, file = item.value })
			end
			return items
		end,
		win = {
			input = { keys = { ["dd"] = { "harpoon_delete", mode = { "n", "x" } } } },
			list = { keys = { ["dd"] = { "harpoon_delete", mode = { "n", "x" } } } },
		},
		actions = {
			harpoon_delete = function(picker, item)
				local to_remove = item or picker:selected()
				table.remove(list().items, to_remove.idx)
				picker:find({ refresh = true })
			end,
		},
	})
end

local keys = {
	-- NOTE: <leader>a is the AI (supermaven) prefix, so harpoon add lives on <leader>H.
	{
		"<leader>H",
		function()
			list():add()
		end,
		desc = "Harpoon add file",
	},
	{
		"<C-e>",
		function()
			local harpoon = require("harpoon")
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end,
		desc = "Harpoon quick menu",
	},
	-- Toggle previous & next buffers stored within Harpoon list
	{
		"<C-S-P>",
		function()
			list():prev()
		end,
		desc = "Harpoon previous file",
	},
	{
		"<C-S-N>",
		function()
			list():next()
		end,
		desc = "Harpoon next file",
	},
	{ "<leader>fh", pick, desc = "Harpoon files (picker)" },
}

-- Jump straight to marks 1-4
for i = 1, 4 do
	table.insert(keys, {
		"<leader>" .. i,
		function()
			list():select(i)
		end,
		desc = "Harpoon to file " .. i,
	})
end

return {
	"thePrimeagen/harpoon",
	branch = "harpoon2",
	-- VeryLazy (not keys-only) so harpoon's autocmds track cursor positions from the start.
	event = "VeryLazy",
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	keys = keys,
	config = function()
		require("harpoon"):setup({
			global_settings = {
				save_on_toggle = true,
				save_on_change = true,
			},
		})
	end,
}
