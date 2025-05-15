return {
    "thePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        local harpoon = require("harpoon")

        harpoon:setup({
            global_settings = {
                save_on_toggle = true,
                save_on_change = true,
            },
        })

        -- picker
        local function generate_harpoon_picker()
            local file_paths = {}
            for _, item in ipairs(harpoon:list().items) do
                table.insert(file_paths, {
                    text = item.value,
                    file = item.value
                })
            end
            return file_paths
        end

        --Harpoon Nav Interface
        vim.keymap.set("n", "<leader>a", function()
            harpoon:list():add()
        end, { desc = "Harpoon add file" })
        vim.keymap.set("n", "<C-e>", function()
            harpoon.ui:toggle_quick_menu(harpoon:list())
        end)

        -- Toggle previous & next buffers stored within Harpoon list
        vim.keymap.set("n", "<C-S-P>", function()
            harpoon:list():prev()
        end)
        vim.keymap.set("n", "<C-S-N>", function()
            harpoon:list():next()
        end)

        -- Telescope inside Harpoon Window
        vim.keymap.set("n", "<leader>fh", function()
            Snacks.picker({
                finder = generate_harpoon_picker,
                win = {
                    input = {
                        keys = {
                            ["dd"] = { "harpoon_delete", mode = { "n", "x" } }
                        }
                    },
                    list = {
                        keys = {
                            ["dd"] = { "harpoon_delete", mode = { "n", "x" } }
                        }
                    },
                },
                actions = {
                    harpoon_delete = function(picker, item)
                        local to_remove = item or picker:selected()
                        table.remove(harpoon:list().items, to_remove.idx)
                        picker:find({
                            refresh = true -- refresh picker after removing values
                        })
                    end
                },
            })
        end)
    end,
}
