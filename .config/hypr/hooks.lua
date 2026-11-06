-- Event hooks that replace external scripts.
hl.on("window.urgent", function(window)
	local title = window and window.title or ""
	hl.notification.create({ text = "Urgent: " .. title, timeout = 2500 })
end)

-- The event payload shape is not documented, so only announce the change.
hl.on("screenshare.state", function()
	hl.notification.create({ text = "Screen sharing state changed", timeout = 3000 })
end)
