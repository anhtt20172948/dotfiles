-- Group bar titles (.config/hypr/groupbar.lua): each title colour is computed
-- from its tab colour, and anything unreadable leaves the looknfeel.lua value.
-- `hl` is a stand-in recording hl.config calls.
local root = assert(arg[1])
package.path = root .. "/.config/hypr/?.lua;" .. package.path
local groupbar = require("groupbar")

local function lum(hex)
	local function linear(pair)
		local c = tonumber(pair, 16) / 255
		return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(hex:sub(1, 2)) + 0.7152 * linear(hex:sub(3, 4)) + 0.0722 * linear(hex:sub(5, 6))
end
local function contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end
local function hex_of(rgb)
	return assert(rgb:match("^rgb%((%x%x%x%x%x%x)%)$"), "not rgb(rrggbb): " .. tostring(rgb))
end

-- Live DMS values (hyprctl repl on Hyprland 0.57.1): light primary, grey
-- inactive, red locked tab.
local function stand_in(options)
	local set = {}
	return {
		get_config = function(key)
			local value = options[key]
			if value == "error" then
				error("boom")
			end
			return value
		end,
		config = function(tbl)
			for k, v in pairs(tbl.group.groupbar) do
				set[k] = v
			end
		end,
	},
		set
end

local hl, set = stand_in({
	["group.groupbar.col.active"] = { colors = { "0xFFA7CBE7" }, angle = 0 },
	["group.groupbar.col.inactive"] = { colors = { "0xFF6F767D" }, angle = 0 },
	["group.groupbar.col.locked_active"] = { colors = { "0xFFFA746F" }, angle = 0 },
	["group.groupbar.col.locked_inactive"] = { colors = { "0xFF6F767D" }, angle = 0 },
})
groupbar.apply(hl)
for tab, title in pairs({
	active = "text_color",
	inactive = "text_color_inactive",
	locked_active = "text_color_locked_active",
	locked_inactive = "text_color_locked_inactive",
}) do
	local bg = ({ active = "a7cbe7", inactive = "6f767d", locked_active = "fa746f", locked_inactive = "6f767d" })[tab]
	local ratio = contrast(hex_of(assert(set[title], title .. " not set")), bg)
	assert(ratio >= 4.5, ("%s on %s is %.2f:1"):format(title, bg, ratio))
end
-- Light tabs get a dark shade of their own hue, dark tabs white.
assert(set.text_color == "rgb(2a333a)", "active title: " .. tostring(set.text_color))
assert(set.text_color_inactive == "rgb(ffffff)", "inactive title: " .. tostring(set.text_color_inactive))

-- Every stop of a gradient counts: the worst case decides.
local mixed = groupbar.text_color({ colors = { "0xFFFFFFFF", "0xFF000000" } })
assert(mixed == "rgb(ffffff)" or mixed == "rgb(404040)")
assert(groupbar.text_color("rgb(a7cbe7)") == "rgb(2a333a)", "plain rgb() string")
assert(groupbar.text_color("rgba(a7cbe7ff)") == "rgb(2a333a)", "rgba() string")

-- Unreadable or missing values leave the looknfeel.lua titles alone.
hl, set = stand_in({
	["group.groupbar.col.active"] = { colors = { "0xFFA7CBE7", "not-a-colour" } },
	["group.groupbar.col.inactive"] = "error",
	["group.groupbar.col.locked_active"] = { colors = {} },
})
groupbar.apply(hl)
assert(next(set) == nil, "unreadable colours must not set any title")

-- The entry point wires it in after the DMS overrides.
local entry = assert(io.open(root .. "/.config/hypr/hyprland.lua")):read("*a")
local dms = assert(entry:find('"dms.colors"', 1, true), "hyprland.lua loads dms.colors")
local wired = assert(entry:find('require("groupbar").apply(hl)', 1, true), "hyprland.lua applies groupbar")
assert(wired > dms, "groupbar must run after dms.colors")
print("hypr_groupbar: OK")
