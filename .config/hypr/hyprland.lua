-- Hyprland 0.57 Lua config entry point.
-- Module order matters: DMS-generated overrides are loaded last.
require("env")
require("autostart")
require("monitors")
require("input")
require("looknfeel")
require("animations")
require("rules")
require("binds")
require("hooks")

-- DMS (DankMaterialShell) regenerates these files at runtime. They are not
-- tracked, so each one is optional and a missing or broken file must never
-- break startup. They load last, so DMS-managed values win over the baselines
-- above. dms/outputs.lua is deliberately skipped: it would replace the
-- monitor layout in monitors.lua.
for _, name in ipairs({ "dms.colors", "dms.layout", "dms.input", "dms.windowrules" }) do
	local ok, err = pcall(require, name)
	if not ok and not tostring(err):find("module '" .. name .. "' not found", 1, true) then
		hl.exec_cmd("notify-send -u critical 'Hyprland' " .. string.format("%q", name .. " failed to load"))
	end
end

-- Only the focused window glows: dms.colors tints color_inactive, so clear it
-- again once the DMS overrides are in.
hl.config({ decoration = { glow = { color_inactive = "rgba(00000000)" } } })

-- Group bar titles follow the tab colours dms.colors just set (dark or light,
-- whichever reads better). On failure the looknfeel.lua titles stay.
local groupbar_ok = pcall(function()
	require("groupbar").apply(hl)
end)
if not groupbar_ok then
	hl.exec_cmd("notify-send -u critical 'Hyprland' 'groupbar title colours failed'")
end
