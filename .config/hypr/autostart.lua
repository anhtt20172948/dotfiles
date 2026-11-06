-- The DMS shell (and its polkit agent) is started by the dms.service user unit,
-- so it must not be launched from here as well.
hl.on("hyprland.start", function()
	-- Make the compositor environment visible to D-Bus activated services such
	-- as xdg-desktop-portal(-hyprland), which provides screen sharing.
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("fcitx5 -d")
	-- Kitty used by the SUPER + grave scratchpad, see binds.lua and rules.lua.
	hl.exec_cmd("kitty --class scratch-term")
end)
