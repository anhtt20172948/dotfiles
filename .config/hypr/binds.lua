local mod = "SUPER"

local function key(combo) return mod .. " + " .. combo end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end
local function dms(call) return run("dms ipc call " .. call) end

local function zoom_by(delta)
    return function()
        hl.config({ cursor = { zoom_factor = hl.get_config("cursor.zoom_factor") + delta } })
    end
end

-- Resize the active window by a percentage of its current size.
local function resize_by_percent(x, y)
    return function()
        local window = hl.get_active_window()
        if not window then return end
        hl.dispatch(hl.dsp.window.resize({
            window = window,
            x = math.modf(window.size.x * (1 + x / 100)),
            y = math.modf(window.size.y * (1 + y / 100)),
        }))
    end
end

-- Apps
hl.bind(key("RETURN"), run("kitty"))
hl.bind(key("B"), run("google-chrome-stable"))
hl.bind(key("E"), run("nautilus"))
hl.bind(key("CTRL + C"), run("gnome-calculator"))

-- DMS shell
hl.bind(key("space"), dms("spotlight toggle"))
hl.bind(key("V"), dms("clipboardPlus openPanel"))
hl.bind(key("comma"), dms("settings toggle"))
hl.bind(key("N"), dms("notifications toggle"))
hl.bind(key("SHIFT + N"), dms("notepad toggle"))
hl.bind(key("Y"), dms("dankdash wallpaper"))
hl.bind(key("TAB"), dms("hypr toggleOverview"))
hl.bind(key("CTRL + L"), dms("widget toggle powerMenuButton"))
hl.bind(key("SHIFT + Slash"), dms("keybinds toggle hyprland"))
hl.bind(key("ALT + L"), dms("lock lock"))
hl.bind("CTRL + ALT + Delete", dms("processlist toggle"))

-- Session
hl.bind(key("CTRL + R"), hl.dsp.reload_config())
hl.bind(key("SHIFT + E"), hl.dsp.exit())

-- Window state
hl.bind(key("Q"), hl.dsp.window.close())
hl.bind(key("SHIFT + Q"), hl.dsp.window.kill())
hl.bind(key("F"), hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(key("M"), hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(key("T"), hl.dsp.window.float())
hl.bind(key("G"), hl.dsp.group.toggle())
hl.bind(key("W"), hl.dsp.group.toggle())
hl.bind(key("J"), hl.dsp.layout("togglesplit"))
hl.bind(key("R"), hl.dsp.layout("togglesplit"))
hl.bind(key("K"), hl.dsp.layout("swapsplit"))
hl.bind(key("bracketleft"), hl.dsp.layout("preselect l"))
hl.bind(key("bracketright"), hl.dsp.layout("preselect r"))
hl.bind("ALT + Tab", hl.dsp.window.cycle_next(), { repeating = true })
hl.bind("ALT + Tab", hl.dsp.window.alter_zorder({ mode = "top" }), { repeating = true })

-- Focus
local directions = { left = "l", right = "r", up = "u", down = "d" }
for name, dir in pairs(directions) do
    hl.bind(key(name), hl.dsp.focus({ direction = dir }))
    hl.bind(key("ALT + " .. name), hl.dsp.window.swap({ direction = dir }))
end
hl.bind(key("SHIFT + h"), hl.dsp.focus({ direction = "l" }))
hl.bind(key("SHIFT + l"), hl.dsp.focus({ direction = "r" }))
hl.bind(key("SHIFT + k"), hl.dsp.focus({ direction = "u" }))
hl.bind(key("SHIFT + j"), hl.dsp.focus({ direction = "d" }))
hl.bind(key("Home"), hl.dsp.focus({ window = "first" }))
hl.bind(key("End"), hl.dsp.focus({ window = "last" }))

-- Resize (SUPER + SHIFT + arrows moved the edge 100 + 20 px via two binds)
local resize_step = 120
hl.bind(key("SHIFT + right"), hl.dsp.window.resize({ x = resize_step, y = 0, relative = true }))
hl.bind(key("SHIFT + left"), hl.dsp.window.resize({ x = -resize_step, y = 0, relative = true }))
hl.bind(key("SHIFT + down"), hl.dsp.window.resize({ x = 0, y = resize_step, relative = true }))
hl.bind(key("SHIFT + up"), hl.dsp.window.resize({ x = 0, y = -resize_step, relative = true }))
hl.bind(key("code:20"), hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { description = "Expand window left" })
hl.bind(key("code:21"), hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { description = "Shrink window left" })
hl.bind(key("minus"), resize_by_percent(-10, 0), { repeating = true })
hl.bind(key("equal"), resize_by_percent(10, 0), { repeating = true })
hl.bind(key("SHIFT + minus"), resize_by_percent(0, -10), { repeating = true })
hl.bind(key("SHIFT + equal"), resize_by_percent(0, 10), { repeating = true })

-- Mouse
hl.bind(key("mouse:272"), hl.dsp.window.drag(), { description = "Move window", mouse = true })
hl.bind(key("mouse:273"), hl.dsp.window.resize(), { description = "Resize window", mouse = true })
hl.bind(key("mouse_down"), hl.dsp.focus({ workspace = "e+1" }))
hl.bind(key("mouse_up"), hl.dsp.focus({ workspace = "e-1" }))
hl.bind(key("SHIFT + mouse_down"), zoom_by(0.5))
hl.bind(key("SHIFT + mouse_up"), zoom_by(-0.5))
hl.bind(key("SHIFT + Z"), function() hl.config({ cursor = { zoom_factor = 1 } }) end)

-- Workspaces
for i = 1, 10 do
    local number = i % 10
    hl.bind(key(number), hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(key("SHIFT + " .. number), hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind(key("l"), hl.dsp.focus({ workspace = "m+1" }))
hl.bind(key("h"), hl.dsp.focus({ workspace = "m-1" }))
hl.bind(key("Tab"), hl.dsp.focus({ workspace = "m+1" }))
hl.bind(key("SHIFT + Tab"), hl.dsp.focus({ workspace = "m-1" }))
hl.bind(key("CTRL + down"), hl.dsp.focus({ workspace = "empty" }))

-- Screenshots
for _, trigger in ipairs({ key("C"), "XF86Launch1", "Print" }) do
    hl.bind(trigger, run("grimblast copy area"))
end
for _, prefix in ipairs({ "XF86Launch1", "Print" }) do
    hl.bind("CTRL + " .. prefix, run("grimblast copy screen"))
    hl.bind("ALT + " .. prefix, run("grimblast copy active"))
end

-- Media and hardware keys
hl.bind("XF86AudioRaiseVolume", dms("audio increment 3"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", dms("audio decrement 3"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", dms("audio mute"), { locked = true })
hl.bind("XF86AudioMicMute", dms("audio micmute"), { locked = true })
hl.bind("XF86MonBrightnessUp", dms('brightness increment 5 ""'), { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown", dms('brightness decrement 5 ""'), { repeating = true, locked = true })
