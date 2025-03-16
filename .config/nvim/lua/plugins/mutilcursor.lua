return {
    {
        "jake-stewart/multicursor.nvim",
        branch = "1.0",
        lazy = false,
        config = function()
            local mc = require("multicursor-nvim")
            mc.setup()

            local set = vim.keymap.set

            -- Add or skip cursor above/below the main cursor.
            set({ "n", "x" }, "<up>", function() mc.lineAddCursor(-1) end, { desc = "Add cursor above" })
            set({ "n", "x" }, "<down>", function() mc.lineAddCursor(1) end, { desc = "Add cursor below" })
            set({ "n", "x" }, "<leader><up>", function() mc.lineSkipCursor(-1) end, { desc = "Skip cursor above" })
            set({ "n", "x" }, "<leader><down>", function() mc.lineSkipCursor(1) end, { desc = "Skip cursor below" })

            -- Add or skip adding a new cursor by matching word/selection
            set({ "n", "x" }, "<leader>/n", function() mc.matchAddCursor(1) end, { desc = "add cursor at next match" })
            set({ "n", "x" }, "<leader>/s", function() mc.matchskipcursor(1) end, { desc = "Skip cursor at next match" })
            set({ "n", "x" }, "<leader>/N", function() mc.matchAddCursor(-1) end,
                { desc = "Add cursor at previous match" })
            set({ "n", "x" }, "<leader>/S", function() mc.matchSkipCursor(-1) end,
                { desc = "Skip cursor at previous match" })
            -- Add all matches in the document
            set({ "n", "v" }, "<leader>A", mc.matchAllAddCursors, { desc = "Add cursors all matches" })

            -- Add and remove cursors with control + left click.
            set("n", "<c-leftmouse>", mc.handleMouse)
            set("n", "<c-leftdrag>", mc.handleMouseDrag)
            set("n", "<c-leftrelease>", mc.handleMouseRelease)

            -- Disable and enable cursors.
            set({ "n", "x" }, "<c-q>", mc.toggleCursor)

            -- Mappings defined in a keymap layer only apply when there are
            -- multiple cursors. This lets you have overlapping mappings.
            mc.addKeymapLayer(function(layerSet)
                -- Select a different cursor as the main one.
                layerSet({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Previous cursor" })
                layerSet({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Next cursor" })

                -- Delete the main cursor.
                layerSet({ "n", "x" }, "<leader>x", mc.deleteCursor, { desc = "Delete cursor" })

                -- Enable and clear cursors using escape.
                layerset("n", "<esc>", function()
                    if not mc.cursorsenabled() then
                        mc.enablecursors()
                    else
                        mc.clearcursors()
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
        end
    }
}
