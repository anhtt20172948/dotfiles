-- Pull in the wezterm API
local wezterm = require 'wezterm'
local mux = wezterm.mux
local act = wezterm.action

-- This will hold the configuration.

local config = wezterm.config_builder()
-- This is where you actually apply your config choices

-- For example, changing the color scheme:

-- config.color_scheme = "Tokyo Night"
-- config.color_scheme = "Catppuccin Macchiato"
-- config.color_scheme = 'Monokai Pro (Gogh)'
-- config.color_scheme = 'Tokyo Night Moon'
-- config.color_scheme = 'Tokyo Night Day'
-- config.color_scheme = 'Dark Ocean (terminal.sexy)'
-- config.color_scheme = 'Dark Violet (base16)'
-- config.color_scheme = 'darkermatrix'
-- config.color_scheme = 'matrix'
-- config.color_scheme = 'Matrix (terminal.sexy)'
-- config.color_scheme = 'darkmatrix'
-- config.color_scheme = 'Dracula (Gogh)'
config.color_scheme = 'Night Owl (Gogh)'
-- config.color_scheme = 'pinky (base16)'
-- config.color_scheme = 'Belge (terminal.sexy)'
-- config.color_scheme = 'Homebrew (Gogh)'
-- config.color_scheme = 'Homebrew'
config.colors = {
    -- The default text color
    foreground = '#86FFAF',
    -- The default background color
    background = '#0C1C25',
    -- cursor and the cursor style is set to Block
    cursor_bg = '#52ad70',
    -- The color of the scrollbar "thumb"; the portion that represents the current viewport
    scrollbar_thumb = '#222222'
}
config.font = wezterm.font_with_fallback({ {
    family = "SFMono Nerd Font",
    scale = 1.0,
    -- weight = "Bold"
    weight = "ExtraBold"
} })

wezterm.on('gui-startup', function(cmd)
    local hosts = { "rack", "strong", "jupyter", "jetson50", "jetson51", "jetson52", }
    local tab, pane, window = wezterm.mux.spawn_window(cmd or {})

    -- Create tabs for each host
    for _, host in ipairs(hosts) do
        local new_tab, new_pane, new_window = window:spawn_tab {
            cwd = wezterm.home_dir,
            args = { "ssh", host }
        }
        new_tab:set_title(host)
        -- local top_left = new_pane:split { direction = 'Right' }
        -- local bottom_left = new_pane:split { direction = 'Bottom' }
        -- top_left:split { direction = 'Bottom' }
    end
end)

config.font_size = 7.5
config.term = "xterm-256color"

config.window_decorations = "TITLE | RESIZE"
-- config.window_decorations = "RESIZE"
config.initial_rows = 80
config.initial_cols = 300

config.window_close_confirmation = "AlwaysPrompt"
config.scrollback_lines = 30000
config.default_workspace = "Hello Tiến Anh 🚀"
-- config.window_background_image = "/home/anhtran/Pictures/gray-grunge-surface-wall-texture-background.jpg"
-- config.window_background_opacity = 1
-- config.macos_window_background_blur = 9
-- config.window_background_gradient = {
--     -- Can be "Vertical" or "Horizontal".  Specifies the direction
--     -- in which the color gradient varies.  The default is "Horizontal",
--     -- with the gradient going from left-to-right.
--     -- Linear and Radial gradients are also supported; see the other
--     -- examples below
--     orientation = 'Horizontal',
--
--     -- Specifies the set of colors that are interpolated in the gradient.
--     -- Accepts CSS style color specs, from named colors, through rgb
--     -- strings and more
--     colors = {
--       '#0f0c29',
--       '#302b63',
--       '#24243e',
--     },
--     -- preset = "Warm",
--
--     -- Instead of specifying `colors`, you can use one of a number of
--     -- predefined, preset gradients.
--     -- A list of presets is shown in a section below.
--     -- preset = "Warm",
--
--     -- Specifies the interpolation style to be used.
--     -- "Linear", "Basis" and "CatmullRom" as supported.
--     -- The default is "Linear".
--     -- interpolation = 'CatmullRom',
--
--     -- How the colors are blended in the gradient.
--     -- "Rgb", "LinearRgb", "Hsv" and "Oklab" are supported.
--     -- The default is "Rgb".
--     -- blend = 'Rgb',
--
--     -- To avoid vertical color banding for horizontal gradients, the
--     -- gradient position is randomly shifted by up to the `noise` value
--     -- for each pixel.
--     -- Smaller values, or 0, will make bands more prominent.
--     -- The default value is 64 which gives decent looking results
--     -- on a retina macbook pro display.
--     noise = 1,
--
--     -- By default, the gradient smoothly transitions between the colors.
--     -- You can adjust the sharpness by specifying the segment_size and
--     -- segment_smoothness parameters.
--     -- segment_size configures how many segments are present.
--     -- segment_smoothness is how hard the edge is; 0.0 is a hard edge,
--     -- 1.0 is a soft edge.
--
--     -- segment_size = 11,
--     -- segment_smoothness = 0.0,
-- }

config.animation_fps = 75
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_ease_in = 'Linear'
config.cursor_blink_ease_out = 'Linear'
config.cursor_blink_rate = 800
config.cursor_thickness = 2
-- config.visual_bell = {
--   fade_in_function = 'EaseIn',
--   fade_in_duration_ms = 150,
--   fade_out_function = 'EaseOut',
--   fade_out_duration_ms = 150,
-- }
-- config.colors = {
--   visual_bell = '#202020',
-- }
config.window_frame = {
    border_left_width = '0.5cell',
    border_right_width = '0.5cell',
    border_bottom_height = '0.25cell',
    border_top_height = '0.25cell',
    -- border_left_color = 'gray',
    -- border_right_color = 'gray',
    -- border_bottom_color = 'gray',
    -- border_top_color = 'gray',

    inactive_titlebar_bg = '#2E3436',
    active_titlebar_bg = '#0C1C25',
    inactive_titlebar_fg = '#86FFAF',
    active_titlebar_fg = '#86FFAF',
    inactive_titlebar_border_bottom = '#0C1C25',
    active_titlebar_border_bottom = '#0C1C25',
    button_fg = '#cccccc',
    button_bg = '#0C1C25',
    button_hover_fg = '#ffffff',
    button_hover_bg = '#0C1C25',

    font = require('wezterm').font 'SF mono',
    font_size = 10
}

wezterm.on("update-status", function(window, pane)
    -- Workspace name
    local stat = window:active_workspace()
    local stat_color = "#0C1C25"
    -- It's a little silly to have workspace name all the time
    -- Utilize this to display LDR or current key table name
    if window:active_key_table() then
        stat = window:active_key_table()
        stat_color = "#0C1C25"
    end
    if window:leader_is_active() then
        stat = "LDR"
        stat_color = "#0C1C25"
    end

    local basename = function(s)
        -- Nothing a little regex can't fix
        return string.gsub(s, "(.*[/\\])(.*)", "%2")
    end

    -- Current working directory
    local cwd = pane:get_current_working_dir()
    if cwd then
        if type(cwd) == "userdata" then
            -- Wezterm introduced the URL object in 20240127-113634-bbcac864
            cwd = basename(cwd.file_path)
        else
            -- 20230712-072601-f4abf8fd or earlier version
            cwd = basename(cwd)
        end
    else
        cwd = ""
    end
    -- Current command
    local cmd = pane:get_foreground_process_name()
    -- CWD and CMD could be nil (e.g. viewing log using Ctrl-Alt-l)
    cmd = cmd and basename(cmd) or ""

    -- Time
    local time = wezterm.strftime("%H:%M:%S")

    -- Left status (left of the tab line)
    window:set_left_status(wezterm.format({ {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = " "
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = wezterm.nerdfonts.oct_table .. "  " .. stat
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = " "
    } }))

    -- Right status
    window:set_right_status(wezterm.format({ -- Wezterm has a built-in nerd fonts
        -- https://wezfurlong.org/wezterm/config/lua/wezterm/nerdfonts.html
        {
            Background = {
                Color = "#0C1C25"
            }
        }, {
        Text = " "
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = wezterm.nerdfonts.md_folder .. "  " .. cwd
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = " | "
    }, {
        Foreground = {
            Color = "#e0af68"
        }
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = wezterm.nerdfonts.fa_code .. "  " .. cmd
    }, "ResetAttributes", {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = " | "
    }, {
        Background = {
            Color = "#0C1C25"
        }
    }, {
        Text = wezterm.nerdfonts.md_clock .. "  " .. time
    }, {
        Text = " "
    } }))
end)

wezterm.on("toggle-opacity", function(window, pane)
    local overrides = window:get_config_overrides() or {}
    if not overrides.window_background_opacity then
        overrides.window_background_opacity = 0.8;
    else
        overrides.window_background_opacity = nil
    end
    window:set_config_overrides(overrides)
end)

-- config.enable_tab_bar = false
config.tab_bar_at_bottom = true
-- config.use_fancy_tab_bar = false
config.tab_max_width = 50

config.window_padding = {
    left = '0.5cell',
    right = '0.5cell',
    top = '0.5cell',
    bottom = '0cell'

}

-- Dim inactive panes
config.inactive_pane_hsb = {
    saturation = 0.24,
    brightness = 0.5
}

-- Keyboard

config.keys = { {
    key = "_",
    mods = "CTRL|SHIFT",
    action = wezterm.action {
        SplitVertical = {
            domain = "CurrentPaneDomain"
        }
    }
}, {
    key = "|",
    mods = "CTRL|SHIFT",
    action = wezterm.action {
        SplitHorizontal = {
            domain = "CurrentPaneDomain"
        }
    }
}, {
    key = 'w',
    mods = 'CMD',
    action = wezterm.action.CloseCurrentPane {
        confirm = true
    }
}, {
    key = 'l',
    mods = 'CTRL|SHIFT',
    action = act.ActivateTabRelative(1)
}, {
    key = 'h',
    mods = 'CTRL|SHIFT',
    action = act.ActivateTabRelative(-1)
},
    -- {
    --     key = 'k',
    --     mods = 'CTRL',
    --     action = act.ActivatePaneDirection 'Up'
    -- }, {
    --     key = 'l',
    --     mods = 'CTRL',
    --     action = act.ActivatePaneDirection 'Right'
    -- }, {
    --     key = 'j',
    --     mods = 'CTRL',
    --     action = act.ActivatePaneDirection 'Down'
    -- }, {
    --     key = 'h',
    --     mods = 'CTRL',
    --     action = act.ActivatePaneDirection 'Left'
    -- },
}

config.enable_kitty_keyboard = true
-- ssh config
config.ssh_domains = { {
    -- This name identifies the domain
    name = 'jupyter',
    -- The hostname or address to connect to. Will be used to match settings
    -- from your ssh config file
    remote_address = 'jupyter',
    -- The username to use on the remote host
    username = 'anhtran',
    -- remote_wezterm_path = "/home/anhtran/bin/wezterm/usr/bin/wezter",
    local_echo_threshold_ms = 10
} }
-- on start up

return config
