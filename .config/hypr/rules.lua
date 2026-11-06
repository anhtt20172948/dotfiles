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
		class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|\\.blueman-manager-wrapped|nm-connection-editor|org\\.gnome\\.Calculator|org\\.freedesktop\\.impl\\.portal\\.desktop\\.gtk|xdg-desktop-portal-gtk)$",
	},
	float = true,
	center = true,
})

-- Screen sharing picker of xdg-desktop-portal-hyprland.
hl.window_rule({
	name = "float-screenshare-picker",
	match = { class = "^(hyprland-share-picker)$" },
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

-- Tags: one rule per concept, behaviour attached to the tag.
hl.window_rule({
	name = "tag-video",
	match = { class = "^(mpv|vlc|org\\.gnome\\.Totem)$" },
	tag = "+video",
})
hl.window_rule({
	name = "tag-browser",
	match = { class = "^(google-chrome|firefox|zen)$" },
	tag = "+browser",
})

-- Screen-share privacy: windows tagged "private" are hidden from screencasts
-- (Meet, OBS, ...) only; they stay fully visible on the local screen, and
-- sharing needs no state tracking. To protect another app, add its window
-- class (find it with `hyprctl clients`) to the pattern below.
hl.window_rule({
	name = "tag-private",
	match = {
		class = "^(org\\.keepassxc\\.KeePassXC|keepassxc|Bitwarden|1Password|1password|Proton Pass|proton-pass|Slack|slack|org\\.telegram\\.desktop|telegram-desktop|TelegramDesktop|Signal|signal|discord|Discord|thunderbird|org\\.mozilla\\.Thunderbird|net\\.thunderbird\\.Thunderbird)$",
	},
	tag = "+private",
})
hl.window_rule({ name = "private-no-screen-share", match = { tag = "private" }, no_screen_share = true })

-- Do not let the screen idle while video plays or a browser is fullscreen.
hl.window_rule({ name = "video-idle-inhibit", match = { tag = "video" }, idle_inhibit = "focus" })
hl.window_rule({ name = "browser-idle-inhibit", match = { tag = "browser" }, idle_inhibit = "fullscreen" })
hl.window_rule({ name = "video-opaque", match = { tag = "video" }, opaque = true, no_blur = true })

-- Kitty scratchpad (SUPER + grave), launched from autostart.lua.
hl.window_rule({
	name = "scratch-term",
	match = { class = "^scratch-term$" },
	workspace = "special:term silent",
	float = true,
	size = "1200 700",
	center = true,
})

-- Kitty columns on the scrolling workspaces are half a monitor wide.
hl.window_rule({ name = "kitty-column-width", match = { class = "^kitty$" }, scrolling_width = 0.5 })

-- Blur for DMS popouts and modals (layer namespaces taken from the DMS shell).
hl.layer_rule({
	name = "dms-blur",
	match = {
		namespace = "^dms:(popout|modal|slideout|control-center|app-launcher|clipboard|clipboard-popout|dash|notification-center-popout|notification-center-modal|power-menu|keybinds|process-list-popout)$",
	},
	blur = true,
	ignore_alpha = 0.3,
})
