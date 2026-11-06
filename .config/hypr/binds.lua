local mod = "SUPER"

local function key(combo)
	return mod .. " + " .. combo
end
local function run(cmd)
	return hl.dsp.exec_cmd(cmd)
end
local function dms(call)
	return run("dms ipc call " .. call)
end

-- Register a table of { combo, action, opts } entries.
local function bind_all(entries)
	for _, entry in ipairs(entries) do
		hl.bind(entry[1], entry[2], entry[3])
	end
end

-- Run a different layout message depending on the active workspace's layout
-- (dwindle messages are errors on a scrolling workspace and vice versa).
-- Layouts without a handler do nothing.
local function by_layout(handlers)
	return function()
		local workspace = hl.get_active_workspace()
		local message = workspace and handlers[workspace.tiled_layout]
		if message then
			hl.dispatch(hl.dsp.layout(message))
		end
	end
end

local function zoom_by(delta)
	return function()
		hl.config({ cursor = { zoom_factor = hl.get_config("cursor.zoom_factor") + delta } })
	end
end

-- Resize the active window by a percentage of its current size.
local function resize_by_percent(x, y)
	return function()
		local window = hl.get_active_window()
		if not window then
			return
		end
		hl.dispatch(hl.dsp.window.resize({
			window = window,
			x = math.modf(window.size.x * (1 + x / 100)),
			y = math.modf(window.size.y * (1 + y / 100)),
		}))
	end
end

-- Apps
bind_all({
	{ key("RETURN"), run("kitty") },
	{ key("B"), run("google-chrome-stable") },
	{ key("E"), run("nautilus") },
	{ key("CTRL + C"), run("gnome-calculator") },
	{ key("grave"), hl.dsp.workspace.toggle_special("term"), { description = "Toggle kitty scratchpad" } },
})

-- DMS shell
bind_all({
	{ key("space"), dms("spotlight toggle") },
	{ key("V"), dms("clipboardPlus openPanel") },
	{ key("comma"), dms("settings toggle") },
	{ key("N"), dms("notifications toggle") },
	{ key("SHIFT + N"), dms("notepad toggle") },
	{ key("Y"), dms("dankdash wallpaper") },
	{ key("TAB"), dms("hypr toggleOverview") },
	{ key("CTRL + L"), dms("widget toggle powerMenuButton") },
	{ key("SHIFT + Slash"), dms("keybinds toggle hyprland") },
	{ key("ALT + L"), dms("lock lock") },
	{ "CTRL + ALT + Delete", dms("processlist toggle") },
})

-- DMS toggles (function keys, so they never collide with the letter binds)
bind_all({
	{ key("SHIFT + C"), dms("color-picker toggle") },
	{ key("F1"), dms("night toggle") },
	{ key("F2"), dms("inhibit toggle") },
	{ key("F3"), dms("theme toggle") },
	{ key("F4"), dms("powerprofile cycle") },
	{ key("F5"), dms("outputs cycleProfile") },
	{ key("F6"), dms("lock lockAndOutputsOff") },
	{ key("F7"), dms("workspace-rename toggle") },
	{ key("F8"), dms("tmux toggle") },
})

-- Session
bind_all({
	{ key("CTRL + R"), hl.dsp.reload_config() },
	{ key("SHIFT + E"), hl.dsp.exit() },
})

-- Window state
bind_all({
	{ key("Q"), hl.dsp.window.close() },
	{ key("SHIFT + Q"), hl.dsp.window.kill() },
	{ key("F"), hl.dsp.window.fullscreen({ mode = "fullscreen" }) },
	{ key("M"), hl.dsp.window.fullscreen({ mode = "maximized" }) },
	{ key("T"), hl.dsp.window.float() },
	{ key("G"), hl.dsp.group.toggle() },
	{ "ALT + Tab", hl.dsp.window.cycle_next(), { repeating = true } },
	{ "ALT + Tab", hl.dsp.window.alter_zorder({ mode = "top" }), { repeating = true } },
})

-- Layout (dwindle on the landscape monitor, scrolling on the portrait one)
bind_all({
	{ key("J"), by_layout({ dwindle = "togglesplit", scrolling = "promote" }) },
	{ key("K"), by_layout({ dwindle = "swapsplit", scrolling = "swapcol r" }) },
	{ key("bracketleft"), by_layout({ dwindle = "preselect l", scrolling = "move -col" }) },
	{ key("bracketright"), by_layout({ dwindle = "preselect r", scrolling = "move +col" }) },
	{ key("period"), by_layout({ scrolling = "move +col" }) },
	{ key("SHIFT + period"), by_layout({ scrolling = "fit active" }) },
	{ key("CTRL + H"), by_layout({ scrolling = "swapcol l" }) },
	{ key("CTRL + J"), by_layout({ scrolling = "consume_or_expel next" }) },
})

-- Focus
local directions = { left = "l", right = "r", up = "u", down = "d" }
for name, dir in pairs(directions) do
	hl.bind(key(name), hl.dsp.focus({ direction = dir }))
	hl.bind(key("ALT + " .. name), hl.dsp.window.swap({ direction = dir }))
end
bind_all({
	{ key("SHIFT + h"), hl.dsp.focus({ direction = "l" }) },
	{ key("SHIFT + l"), hl.dsp.focus({ direction = "r" }) },
	{ key("SHIFT + k"), hl.dsp.focus({ direction = "u" }) },
	{ key("SHIFT + j"), hl.dsp.focus({ direction = "d" }) },
	{ key("Home"), hl.dsp.focus({ window = "first" }) },
	{ key("End"), hl.dsp.focus({ window = "last" }) },
})

-- Resize: percent binds, plus a resize mode (SUPER + R, leave with Escape)
bind_all({
	{ key("minus"), resize_by_percent(-10, 0), { repeating = true } },
	{ key("equal"), resize_by_percent(10, 0), { repeating = true } },
	{ key("SHIFT + minus"), resize_by_percent(0, -10), { repeating = true } },
	{ key("SHIFT + equal"), resize_by_percent(0, 10), { repeating = true } },
	{ key("R"), hl.dsp.submap("resize"), { description = "Resize mode (Escape to leave)" } },
})

local resize_step = 40
local function resize_step_by(x, y)
	return hl.dsp.window.resize({ x = x * resize_step, y = y * resize_step, relative = true })
end
hl.define_submap("resize", "escape", function()
	bind_all({
		{ "right", resize_step_by(1, 0), { repeating = true } },
		{ "left", resize_step_by(-1, 0), { repeating = true } },
		{ "down", resize_step_by(0, 1), { repeating = true } },
		{ "up", resize_step_by(0, -1), { repeating = true } },
		{ "l", resize_step_by(1, 0), { repeating = true } },
		{ "h", resize_step_by(-1, 0), { repeating = true } },
		{ "j", resize_step_by(0, 1), { repeating = true } },
		{ "k", resize_step_by(0, -1), { repeating = true } },
		{ "return", hl.dsp.submap("reset") },
	})
end)

-- Mouse
bind_all({
	{ key("mouse:272"), hl.dsp.window.drag(), { description = "Move window", mouse = true } },
	{ key("mouse:273"), hl.dsp.window.resize(), { description = "Resize window", mouse = true } },
	{ key("mouse_down"), hl.dsp.focus({ workspace = "e+1" }) },
	{ key("mouse_up"), hl.dsp.focus({ workspace = "e-1" }) },
	{ key("SHIFT + mouse_down"), zoom_by(0.5) },
	{ key("SHIFT + mouse_up"), zoom_by(-0.5) },
	{
		key("SHIFT + Z"),
		function()
			hl.config({ cursor = { zoom_factor = 1 } })
		end,
	},
})

-- Workspaces
for i = 1, 10 do
	local number = i % 10
	hl.bind(key(number), hl.dsp.focus({ workspace = tostring(i) }))
	hl.bind(key("SHIFT + " .. number), hl.dsp.window.move({ workspace = tostring(i) }))
end
bind_all({
	{ key("l"), hl.dsp.focus({ workspace = "m+1" }) },
	{ key("h"), hl.dsp.focus({ workspace = "m-1" }) },
	{ key("CTRL + down"), hl.dsp.focus({ workspace = "empty" }) },
})

-- Screenshots (DMS: region / focused output / focused window, clipboard only)
for _, trigger in ipairs({ key("C"), "XF86Launch1", "Print" }) do
	hl.bind(trigger, run("dms screenshot region --no-file"))
end
for _, prefix in ipairs({ "XF86Launch1", "Print" }) do
	hl.bind("CTRL + " .. prefix, run("dms screenshot full --no-file"))
	hl.bind("ALT + " .. prefix, run("dms screenshot window --no-file"))
end

-- Media and hardware keys
bind_all({
	{ "XF86AudioRaiseVolume", dms("audio increment 3"), { repeating = true, locked = true } },
	{ "XF86AudioLowerVolume", dms("audio decrement 3"), { repeating = true, locked = true } },
	{ "XF86AudioMute", dms("audio mute"), { locked = true } },
	{ "XF86AudioMicMute", dms("audio micmute"), { locked = true } },
	{ "XF86MonBrightnessUp", dms('brightness increment 5 ""'), { repeating = true, locked = true } },
	{ "XF86MonBrightnessDown", dms('brightness decrement 5 ""'), { repeating = true, locked = true } },
})
