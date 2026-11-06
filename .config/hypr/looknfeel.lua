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
			-- 8 = acrylic (frosted glass). Size and passes stay modest to keep
			-- the iGPU cost low; video windows opt out of blur in rules.lua.
			variant = 8,
			-- Baseline tint; DMS (dms.colors) overrides it with the theme color.
			acrylic = {
				tint = "rgba(bdc4ee14)",
			},
		},
		shadow = {
			enabled = true,
			range = 24,
			render_power = 3,
			color = "rgba(00000055)",
		},
		-- Dim the background behind the special-workspace scratchpad (SUPER+grave).
		dim_special = 0.3,
		-- Subtle glow around the focused window only; DMS (dms.colors) supplies
		-- the accent color, and hyprland.lua clears color_inactive after it loads.
		glow = {
			enabled = true,
			range = 12,
			render_power = 4,
			color = "rgba(bbc3ff99)",
			color_inactive = "rgba(00000000)",
		},
	},
	-- Tab bar for grouped windows (SUPER+G). DMS (dms.colors) supplies the bar
	-- and border colors; these set shape, titles and scroll-to-switch.
	group = {
		groupbar = {
			enabled = true,
			font_size = 11,
			height = 22,
			gaps_in = 3,
			gaps_out = 2,
			indicator_height = 0,
			gradients = true,
			gradient_rounding = 8,
			rounding = 8,
			render_titles = true,
			text_color = "rgb(ffffff)",
			text_color_inactive = "rgb(d0d0d8)",
			scrolling = true,
			middle_click_close = true,
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
		-- A window requesting activation (e.g. a browser opened from a link)
		-- takes focus instead of only flagging urgent.
		focus_on_activate = true,
	},
	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
	},
	render = {
		new_render_scheduling = true,
		-- 2 = direct scan-out only for fullscreen windows that report content
		-- type "game"; video and everything else keep normal compositing, so
		-- there is no risk of glitches or missed effects.
		direct_scanout = 2,
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
