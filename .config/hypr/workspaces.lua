hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

for workspace = 1, 5 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = "DP-2" })
end
for workspace = 6, 7 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = "HDMI-A-1" })
end
