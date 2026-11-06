hl.config({
	input = {
		kb_layout = "us",
		kb_options = "caps:swapescape",
		numlock_by_default = true,
		follow_mouse = 1,
		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			disable_while_typing = true,
		},
	},
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
