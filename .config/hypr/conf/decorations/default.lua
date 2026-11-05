hl.config({
    decoration = {
        rounding = 15,
        active_opacity = 1.0,
        inactive_opacity = 0.9,
        fullscreen_opacity = 1.0,
        blur = {
            enabled = true,
            size = 3,
            passes = 4,
            new_optimizations = true,
            ignore_opacity = true,
            xray = true,
        },
        shadow = {
            enabled = true,
            range = 100,
            render_power = 4,
            color = "rgba(00000033)",
        },
    },
})
