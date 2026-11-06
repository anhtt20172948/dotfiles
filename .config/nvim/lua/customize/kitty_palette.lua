local M = {}

local function rgb(color)
	return tonumber(color:sub(2, 3), 16), tonumber(color:sub(4, 5), 16), tonumber(color:sub(6, 7), 16)
end

local function blend(a, b, amount)
	local ar, ag, ab = rgb(a)
	local br, bg, bb = rgb(b)
	return ("#%02x%02x%02x"):format(
		math.floor(ar + (br - ar) * amount + 0.5),
		math.floor(ag + (bg - ag) * amount + 0.5),
		math.floor(ab + (bb - ab) * amount + 0.5)
	)
end

-- Resolve symlinks: install.sh links the kitty directory into this checkout.
function M.read()
	local config = vim.env.XDG_CONFIG_HOME
	local dir = (config and config ~= "" and config or (vim.env.HOME .. "/.config")) .. "/kitty/"
	local file
	for _, name in ipairs({ "dank-theme.conf", "current-theme.conf" }) do
		local path = vim.uv.fs_realpath(dir .. name)
		if path then
			file = io.open(path, "r")
			if file then
				break
			end
		end
	end
	if not file then
		return nil
	end
	local values = {}
	for line in file:lines() do
		local key, color = line:match("^%s*([%w_]+)%s+(#%x+)%s*")
		if color and (#color == 7 or #color == 4) then
			if #color == 4 then
				color = "#" .. color:sub(2, 2):rep(2) .. color:sub(3, 3):rep(2) .. color:sub(4, 4):rep(2)
			end
			values[key] = color:lower()
		end
	end
	file:close()
	if not values.background or not values.foreground then
		return nil
	end
	for i = 0, 15 do
		if not values["color" .. i] then
			return nil
		end
	end
	local bg, fg = values.background, values.foreground
	local r, g, b = rgb(bg)
	local light = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.5
	local colors = { base = bg, text = fg }
	-- Layers move toward the foreground, preserving contrast in either mode.
	local layers = {
		surface0 = 0.08,
		surface1 = 0.14,
		surface2 = 0.22,
		overlay0 = 0.38,
		overlay1 = 0.46,
		overlay2 = 0.54,
		subtext0 = 0.7,
		subtext1 = 0.85,
	}
	for key, amount in pairs(layers) do
		colors[key] = blend(bg, fg, amount)
	end
	local edge = light and string.format("#%06x", 16777215) or string.format("#%06x", 0)
	colors.mantle, colors.crust = blend(bg, edge, 0.15), blend(bg, edge, 0.3)
	local accents = {
		red = 1,
		maroon = 9,
		green = 2,
		yellow = 3,
		peach = 11,
		blue = 4,
		sapphire = 12,
		mauve = 5,
		pink = 13,
		teal = 6,
		sky = 14,
		lavender = 12,
		rosewater = 7,
		flamingo = 15,
	}
	for key, slot in pairs(accents) do
		colors[key] = values["color" .. slot]
	end
	return {
		flavour = light and "latte" or "mocha",
		colors = colors,
		cursor = values.cursor,
		selection_background = values.selection_background,
		selection_foreground = values.selection_foreground,
	}
end

M.active = M.read()

function M.palette()
	return require("catppuccin.palettes").get_palette(M.active and M.active.flavour or "mocha")
end

return M
