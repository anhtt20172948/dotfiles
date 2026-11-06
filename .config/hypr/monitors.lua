-- Physical layout: DP-2 (landscape) in the middle, HDMI-A-1 (portrait) on the
-- right, laptop panel disabled while docked.
hl.monitor({ output = "eDP-1", disabled = true })
hl.monitor({ output = "DP-2", mode = "2560x1440@74.97", position = "2218x278", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.0", position = "4778x0", scale = 1, transform = 1 })
-- Fallback for any other output.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

for workspace = 1, 5 do
	hl.workspace_rule({ workspace = tostring(workspace), monitor = "DP-2" })
end
for workspace = 6, 7 do
	hl.workspace_rule({ workspace = tostring(workspace), monitor = "HDMI-A-1" })
end
