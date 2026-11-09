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

local function luminance(color)
	local r, g, b = rgb(color)
	local function linear(channel)
		channel = channel / 255
		return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

function M.contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

function M.ensure_contrast(color, background, foreground, floor)
	if M.contrast(color, background) >= floor then
		return color
	end
	-- A malformed/low-contrast terminal foreground cannot be our endpoint.
	local target = foreground
	if M.contrast(target, background) < floor then
		target = luminance(background) > 0.179 and string.format("#%06x", 0) or string.format("#%06x", 16777215)
	end
	-- Find the smallest blend that meets the floor, including 8-bit rounding.
	local low, high = 0, 1
	for _ = 1, 24 do
		local mid = (low + high) / 2
		if M.contrast(blend(color, target, mid), background) >= floor then
			high = mid
		else
			low = mid
		end
	end
	return blend(color, target, high)
end

-- Called after lazy.nvim adds Catppuccin to runtimepath. Never require the
-- plugin while reading the plugin specs, or startup depends on load order.
function M.colors(stock)
	local colors = vim.tbl_extend("force", {}, stock, M.active and M.active.colors or {})
	local foreground = colors.text
	for key, color in pairs(colors) do
		if not vim.tbl_contains({ "base", "mantle", "crust", "surface0", "surface1", "surface2" }, key) then
			colors[key] = M.ensure_contrast(color, colors.base, foreground, 4.5)
		end
	end
	return colors
end

-- Keep syntax colours intact: reduce the selection tint, never recolour tokens.
function M.selection_background(colors, primary)
	if not M.active then
		return colors.surface2
	end
	local amount = 0.3
	while amount > 0 do
		local background = blend(colors.base, primary, amount)
		local readable = M.contrast(colors.text, background) >= 4.5
		for _, key in ipairs({
			"rosewater",
			"flamingo",
			"pink",
			"mauve",
			"red",
			"maroon",
			"peach",
			"yellow",
			"green",
			"teal",
			"sky",
			"sapphire",
			"blue",
			"lavender",
		}) do
			-- Syntax uses a 3:1 floor; normal text retains its 4.5:1 floor.
			if colors[key] and M.contrast(colors[key], background) < 3 then
				readable = false
			end
		end
		if readable then
			return background
		end
		amount = math.max(0, amount - 0.01)
	end
	return colors.base
end

-- Half the Visual tint keeps ordinary matches subordinate to the current match.
function M.search_background(colors, primary)
	local visual = M.selection_background(colors, primary)
	return blend(colors.base, visual, 0.5)
end

local function parse_encoded(encoded)
	if not encoded or (#encoded ~= 125 and #encoded ~= 132) then
		return nil
	end
	local entries = vim.split(encoded, ":", { plain = true })
	if #entries ~= 18 and #entries ~= 19 then
		return nil
	end
	local values = {}
	for i, color in ipairs(entries) do
		if #color ~= 6 or not color:match("^[0-9a-f]+$") then
			return nil
		end
		local key = i == 19 and "cursor" or (i == 1 and "background" or (i == 2 and "foreground" or "color" .. (i - 3)))
		values[key] = "#" .. color
	end
	return values
end

local function valid_source(source)
	return source and #source > 0 and #source <= 32 and source:match("^[a-z0-9-]+$")
end

local function tmux_environment()
	if not vim.env.TMUX or vim.env.TMUX == "" then
		return {}
	end
	-- Existing panes keep stale process variables; the session is refreshed on attach.
	local ok, result = pcall(function()
		return vim.system({ "tmux", "show-environment" }, { text = true, timeout = 100 }):wait()
	end)
	if not ok or result.code ~= 0 then
		return {}
	end
	local environment = {}
	for line in (result.stdout or ""):gmatch("[^\n]+") do
		local name, value = line:match("^(LC_KITTY_PALETTE[^=]*)=(.*)$")
		if name == "LC_KITTY_PALETTE_SRC" or name == "LC_KITTY_PALETTE" then
			environment[name] = value
		end
	end
	return environment
end

local function read_encoded_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	-- Bound reads and require exactly one encoded line, with an optional final newline.
	local encoded = file:read(134)
	file:close()
	if encoded and (#encoded == 126 or #encoded == 133) and encoded:sub(-1) == "\n" then
		encoded = encoded:sub(1, -2)
	end
	return parse_encoded(encoded)
end

local function read_remote(environment)
	local source = environment.LC_KITTY_PALETTE_SRC
	if not valid_source(source) then
		source = vim.env.LC_KITTY_PALETTE_SRC
	end
	local dir = vim.env.HOME .. "/.config/kitty/"
	if valid_source(source) then
		local values = read_encoded_file(dir .. "remote-palette-" .. source .. ".conf")
		if values then
			return values
		end
	end
	local newest, newest_time
	for _, path in ipairs(vim.fn.glob(dir .. "remote-palette-*.conf", false, true)) do
		local candidate = vim.fn.fnamemodify(path, ":t"):match("^remote%-palette%-(.*)%.conf$")
		local stat = valid_source(candidate) and vim.uv.fs_stat(path)
		if stat and stat.type == "file" then
			local mtime = stat.mtime
			if
				not newest_time
				or mtime.sec > newest_time.sec
				or (mtime.sec == newest_time.sec and mtime.nsec > newest_time.nsec)
			then
				local values = read_encoded_file(path)
				if values then
					newest, newest_time = values, mtime
				end
			end
		end
	end
	return newest
end

-- Resolve symlinks: install.sh links the kitty directory into this checkout.
local function read_file()
	local config = vim.env.XDG_CONFIG_HOME
	local dir = (config and config ~= "" and config or (vim.env.HOME .. "/.config")) .. "/kitty/"
	local file
	local names = { "dank-theme.conf", "current-theme.conf" }
	if vim.env.SSH_CONNECTION and vim.env.SSH_CONNECTION ~= "" then
		table.insert(names, 1, "remote-palette.conf")
	end
	for _, name in ipairs(names) do
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
	return values
end

function M.read()
	local remote, environment
	if vim.env.SSH_CONNECTION and vim.env.SSH_CONNECTION ~= "" then
		environment = tmux_environment()
		remote = read_remote(environment) or parse_encoded(environment.LC_KITTY_PALETTE)
	end
	local values = remote or parse_encoded(vim.env.LC_KITTY_PALETTE) or read_file()
	if not values then
		return nil
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

	return {
		flavour = light and "latte" or "mocha",
		colors = colors,
		primary = values.cursor or values.url_color,
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
