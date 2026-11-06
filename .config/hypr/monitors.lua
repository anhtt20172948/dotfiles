-- Physical layout, matched by EDID description so it survives connector
-- renumbering across docks and ports:
--   LG (landscape) in the middle, Dell (portrait) on the right.
-- The laptop panel is only disabled while an external monitor is attached, so
-- a laptop-only session still shows the built-in screen.
local LAPTOP = "eDP-1"
local LG = "desc:LG Electronics LG IPS QHD"
local DELL = "desc:Dell Inc. DELL U2419H"

hl.monitor({ output = LG, mode = "2560x1440@74.97", position = "2218x278", scale = 1 })
hl.monitor({ output = DELL, mode = "1920x1080@60", position = "4778x0", scale = 1, transform = 1 })
-- Fallback for any other output.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

for workspace = 1, 5 do
	hl.workspace_rule({
		workspace = tostring(workspace),
		monitor = LG,
		default = workspace == 1,
		persistent = true,
	})
end
for workspace = 6, 7 do
	hl.workspace_rule({
		workspace = tostring(workspace),
		monitor = DELL,
		default = workspace == 6,
		persistent = true,
		-- The tall portrait monitor stacks windows with the scrolling layout.
		layout = "scrolling",
		layout_opts = { direction = "down" },
	})
end

-- True when any monitor other than the laptop panel (and `ignored`, a monitor
-- that is going away) is known.
local function docked(ignored)
	for _, monitor in ipairs(hl.get_monitors({ all = true })) do
		if monitor.name ~= LAPTOP and monitor.name ~= ignored then
			return true
		end
	end
	return false
end

-- Only touch the laptop panel when its desired state changes: enabling or
-- disabling it fires monitor events itself, and this keeps that from looping.
local laptop_disabled
local function sync_laptop(ignored)
	local disabled = docked(ignored)
	if disabled == laptop_disabled then
		return
	end
	laptop_disabled = disabled
	if disabled then
		hl.monitor({ output = LAPTOP, disabled = true })
	else
		hl.monitor({ output = LAPTOP, mode = "preferred", position = "0x0", scale = 1.5 })
	end
end

sync_laptop()
hl.on("monitor.added", function(monitor)
	if monitor.name ~= LAPTOP then
		sync_laptop()
	end
end)
hl.on("monitor.removed", function(monitor)
	if monitor.name ~= LAPTOP then
		sync_laptop(monitor.name)
	end
end)
