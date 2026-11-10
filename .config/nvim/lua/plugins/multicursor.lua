-- Key handler that calls multicursor-nvim's `fn` (loaded on first use) with an optional argument.
local function call(fn, arg)
	return function()
		require("multicursor-nvim")[fn](arg)
	end
end

return {
	{
		"jake-stewart/multicursor.nvim",
		branch = "1.0",
		event = "VeryLazy",
		keys = {
			-- Add or skip cursor above/below the main cursor.
			{ "<up>", call("lineAddCursor", -1), mode = { "n", "x" }, desc = "Add cursor above" },
			{ "<down>", call("lineAddCursor", 1), mode = { "n", "x" }, desc = "Add cursor below" },
			{ "<leader><up>", call("lineSkipCursor", -1), mode = { "n", "x" }, desc = "Skip cursor above" },
			{ "<leader><down>", call("lineSkipCursor", 1), mode = { "n", "x" }, desc = "Skip cursor below" },

			-- Add or skip adding a new cursor by matching word/selection
			{ "<leader>/n", call("matchAddCursor", 1), mode = { "n", "x" }, desc = "Add cursor at next match" },
			{ "<leader>/s", call("matchSkipCursor", 1), mode = { "n", "x" }, desc = "Skip cursor at next match" },
			{ "<leader>/N", call("matchAddCursor", -1), mode = { "n", "x" }, desc = "Add cursor at previous match" },
			{ "<leader>/S", call("matchSkipCursor", -1), mode = { "n", "x" }, desc = "Skip cursor at previous match" },

			-- Add a cursor for all matches of cursor word/selection in the document.
			{ "<leader>A", call("matchAllAddCursors"), mode = { "n", "x" }, desc = "Add cursor at all matches" },

			-- Add a cursor to every search result in the buffer.
			{ "<leader>/A", call("searchAllAddCursors"), desc = "Add cursor at all search results" },

			-- Disable and enable cursors.
			{ "<c-q>", call("toggleCursor"), mode = { "n", "x" }, desc = "Toggle cursor" },

			-- Add and remove cursors with control + left click.
			-- { "<c-leftmouse>", call("handleMouse") },
			-- { "<c-leftdrag>", call("handleMouseDrag") },
			-- { "<c-leftrelease>", call("handleMouseRelease") },
		},
		config = function()
			local mc = require("multicursor-nvim")
			mc.setup()

			-- Mappings defined in a keymap layer only apply when there are
			-- multiple cursors. This lets you have overlapping mappings.
			mc.addKeymapLayer(function(layerSet)
				-- Select a different cursor as the main one.
				layerSet({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Select cursor previous" })
				layerSet({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Select cursor next" })

				-- Delete the main cursor.
				layerSet({ "n", "x" }, "<leader>x", mc.deleteCursor, { desc = "Delete cursor" })

				-- Enable and clear cursors using escape.
				layerSet("n", "<esc>", function()
					if not mc.cursorsEnabled() then
						mc.enableCursors()
					else
						mc.clearCursors()
					end
				end)
			end)

			-- Customize how cursors look.
			local hl = vim.api.nvim_set_hl
			hl(0, "MultiCursorCursor", { link = "Cursor" })
			hl(0, "MultiCursorVisual", { link = "Visual" })
			hl(0, "MultiCursorSign", { link = "SignColumn" })
			hl(0, "MultiCursorMatchPreview", { link = "Search" })
			hl(0, "MultiCursorDisabledCursor", { link = "Visual" })
			hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
			hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
		end,
	},
}
