-- Baselines; DMS (dms.colors, dms.layout) overrides colors, gaps and rounding.
hl.config({
	general = {
		layout = "dwindle",
		gaps_in = 4,
		gaps_out = 4,
		border_size = 2,
		resize_on_border = true,
		allow_tearing = false,
		snap = {
			enabled = true,
			window_gap = 10,
			monitor_gap = 10,
		},
		col = {
			active_border = "rgb(bbc3ff)",
			inactive_border = "rgb(90909a)",
		},
	},
	decoration = {
		rounding = 12,
		rounding_power = 4,
		active_opacity = 1.0,
		inactive_opacity = 0.95,
		blur = {
			enabled = true,
			size = 6,
			passes = 3,
			vibrancy = 0.17,
			noise = 0.02,
			popups = true,
			xray = true,
		},
		shadow = {
			enabled = true,
			range = 24,
			render_power = 3,
			color = "rgba(00000055)",
		},
	},
	dwindle = {
		preserve_split = true,
	},
	binds = {
		workspace_back_and_forth = false,
		allow_workspace_cycles = true,
		pass_mouse_when_bound = false,
	},
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		initial_workspace_tracking = 1,
		animate_manual_resizes = true,
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
		enable_swallow = true,
		swallow_regex = "^(kitty)$",
		middle_click_paste = false,
	},
	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
	},
	render = {
		new_render_scheduling = true,
	},
	-- Scrolling layout, used on the portrait workspaces (see rules.lua).
	scrolling = {
		column_width = 0.5,
		explicit_column_widths = "0.333, 0.5, 0.667, 1.0",
		focus_fit_method = 1,
		follow_focus = 1,
		wrap_focus = true,
	},
})
