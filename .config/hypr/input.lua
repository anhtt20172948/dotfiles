hl.config({
	input = {
		kb_layout = "us",
		kb_options = "caps:swapescape",
		numlock_by_default = true,
		follow_mouse = 1,
		focus_on_close = 1,
		repeat_rate = 40,
		repeat_delay = 250,
		accel_profile = "flat",
		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			disable_while_typing = true,
		},
	},
})

hl.config({
	cursor = {
		hide_on_key_press = true,
		inactive_timeout = 5,
		warp_on_change_workspace = 1,
	},
})

-- Gestures. Hyprland rejects a gesture shadowed by an earlier one with the same
-- fingers and direction, so the 3-finger horizontal swipe owns that slot.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" })
hl.gesture({ fingers = 4, direction = "down", action = "close" })
hl.gesture({ fingers = 4, direction = "pinch", action = "cursorZoom", zoom_level = 2, mode = "live" })
