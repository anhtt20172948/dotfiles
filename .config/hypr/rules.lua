-- Ignore maximize requests from clients.
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

-- Fix XWayland drag ghost windows.
hl.window_rule({
	name = "fix-xwayland-drags",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- Utility dialogs and helpers float.
hl.window_rule({
	name = "float-utilities",
	match = {
		class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|\\.blueman-manager-wrapped|nm-connection-editor|org\\.gnome\\.Calculator|polkit-mate-authentication-agent-1|org\\.freedesktop\\.impl\\.portal\\.desktop\\.gtk|xdg-desktop-portal-gtk)$",
	},
	float = true,
	center = true,
})

-- File pickers.
hl.window_rule({
	name = "float-file-pickers",
	match = {
		title = "^(Open File|Open Folder|Save File|Save As|Select a File|Choose Files|File Upload|Open Files)(.*)$",
	},
	float = true,
	center = true,
	size = "900 600",
})

-- Picture-in-Picture stays on top in a corner.
hl.window_rule({
	name = "picture-in-picture",
	match = { title = "^(Picture-in-Picture)$" },
	float = true,
	pin = true,
	size = "480 270",
	move = "monitor_w-490 monitor_h-280",
	keep_aspect_ratio = true,
})

-- Hidden helper window of the xwayland video bridge.
hl.window_rule({
	name = "xwayland-video-bridge",
	match = { class = "^(xwaylandvideobridge)$" },
	opacity = 0.0,
	no_anim = true,
	no_initial_focus = true,
	max_size = "1 1",
	no_blur = true,
})

-- Do not let the screen idle while a video app is fullscreen.
hl.window_rule({
	name = "idle-inhibit-fullscreen-video",
	match = { class = "^(mpv|vlc|google-chrome|firefox|zen|org\\.gnome\\.Totem)$" },
	idle_inhibit = "fullscreen",
})
