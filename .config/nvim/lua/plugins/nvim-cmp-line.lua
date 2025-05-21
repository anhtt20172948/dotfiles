return {{
    "hrsh7th/cmp-cmdline",
    event = "InsertEnter",
    config = function()
        local cmp = require("cmp")
        local config = cmp.get_config()

        table.insert(config.sources, {
            name = "cmdline",
            option = {
                ignore_cmds = {"Man", "!"}
            }
        })
        config.mapping = cmp.mapping.preset.cmdline()
        config.completion = {
            completeopt = 'menu,menuone,noselect'
        }
        -- `:` cmdline setup.
        cmp.setup.cmdline(":", config)
        -- `/` cmdline setup.
        cmp.setup.cmdline("/", {
            mapping = cmp.mapping.preset.cmdline(),
            completion = {
                completeopt = 'menu,menuone,noselect'
            },
            sources = {{
                name = "buffer"
            }}
        })
        cmp.setup(config)
    end
}, {
    "dmitmel/cmp-cmdline-history",
    event = "InsertEnter",
    config = function()
        local cmp = require("cmp")
        local config = cmp.get_config()
        config.completion = {
            completeopt = 'menu,menuone,noselect'
        }
        table.insert(config.sources, {
            name = "cmdline_history"
        })
        config.mapping = cmp.mapping.preset.cmdline()
        cmp.setup.cmdline(":", config)
        cmp.setup(config)
    end
}}
