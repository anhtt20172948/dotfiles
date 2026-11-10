-- Group bar title colours computed from the tab colours.
--
-- dms.colors paints the group bar tabs with the wallpaper accent but leaves the
-- title colours alone, so fixed light titles (looknfeel.lua) end up on whatever
-- DMS picks: white on a light primary such as DMS's default blue is 1.7:1.
-- apply() reads each tab colour back (hl.get_config returns a gradient as
-- { colors = { "0xAARRGGBB", ... }, angle = n }) and sets its title to white or
-- to a dark shade of the tab's own hue, whichever reads better (WCAG contrast,
-- worst case over the gradient's stops). Any colour it cannot read leaves that
-- title at its looknfeel.lua value.
local M = {}

-- How far the dark title shade is darkened from the tab colour; it keeps the
-- hue, like Material's on-primary, at roughly 7:1 on a light accent.
local DARK_SHADE = 0.25

-- tab colour option -> title colour option, both under group.groupbar
local TITLES = {
	{ "col.active", "text_color" },
	{ "col.inactive", "text_color_inactive" },
	{ "col.locked_active", "text_color_locked_active" },
	{ "col.locked_inactive", "text_color_locked_inactive" },
}

-- "0xAARRGGBB" (what get_config returns), "rgb(rrggbb)" or "rgba(rrggbbaa)" ->
-- r, g, b in 0-255, or nil.
local function channels(color)
	if type(color) ~= "string" then
		return nil
	end
	local hex = color:match("^0[xX]%x%x(%x%x%x%x%x%x)$")
		or color:match("^rgb%((%x%x%x%x%x%x)%)$")
		or color:match("^rgba%((%x%x%x%x%x%x)%x%x%)$")
	if not hex then
		return nil
	end
	return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function luminance(r, g, b)
	local function linear(c)
		c = c / 255
		if c <= 0.04045 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

local function contrast(a, b)
	if a < b then
		a, b = b, a
	end
	return (a + 0.05) / (b + 0.05)
end

-- Worst-case contrast of a text luminance over every stop.
local function worst(text, stops)
	local min = math.huge
	for _, stop in ipairs(stops) do
		min = math.min(min, contrast(text, stop))
	end
	return min
end

-- The title colour ("rgb(rrggbb)") for a tab painted with `value`, a gradient
-- table or a single colour string; nil when it cannot be read.
function M.text_color(value)
	local colors = type(value) == "table" and value.colors or { value }
	if type(colors) ~= "table" or #colors == 0 then
		return nil
	end
	local stops = {}
	for i, color in ipairs(colors) do
		local r, g, b = channels(color)
		if not r then
			return nil
		end
		stops[i] = luminance(r, g, b)
	end
	local r, g, b = channels(colors[1])
	r, g, b = math.floor(r * DARK_SHADE + 0.5), math.floor(g * DARK_SHADE + 0.5), math.floor(b * DARK_SHADE + 0.5)
	if worst(luminance(r, g, b), stops) > worst(1, stops) then
		return ("rgb(%02x%02x%02x)"):format(r, g, b)
	end
	return "rgb(ffffff)"
end

-- Set every group bar title colour from its tab colour. `hl` is Hyprland's API
-- table (a parameter so tests can pass a stand-in).
function M.apply(hl)
	for _, pair in ipairs(TITLES) do
		local ok, value = pcall(hl.get_config, "group.groupbar." .. pair[1])
		local text = ok and value ~= nil and M.text_color(value)
		if text then
			hl.config({ group = { groupbar = { [pair[2]] = text } } })
		end
	end
end

return M
