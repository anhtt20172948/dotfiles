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

local function linear(channel)
	channel = channel / 255
	return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
end

-- Highlight scans compare thousands of groups that share a few hundred colours.
local luminances = {}
local function luminance(color)
	local cached = luminances[color]
	if not cached then
		local r, g, b = rgb(color)
		cached = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
		luminances[color] = cached
	end
	return cached
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

-- WCAG AA (4.5:1) is the floor for every text colour. Dark text on a light
-- background reads fainter than the same ratio inverted (thin strokes at kitty's
-- 9pt font), and Catppuccin Latte's pastel accents all land exactly on the
-- floor, so light palettes hold syntax further from the background. Muted
-- layers (comments, line numbers, punctuation, inlay hints) stay quieter than
-- syntax. Dark palettes keep the AA floor and their colours.
M.TEXT_FLOOR = 4.5
M.LIGHT_SYNTAX_FLOOR = 6
M.LIGHT_MUTED_FLOOR = 5
local muted = { overlay0 = true, overlay1 = true, overlay2 = true, subtext0 = true, subtext1 = true }

-- The contrast floor a palette key keeps against the background.
function M.floor(key)
	if not (M.active and M.active.flavour == "latte") then
		return M.TEXT_FLOOR
	end
	return muted[key] and M.LIGHT_MUTED_FLOOR or M.LIGHT_SYNTAX_FLOOR
end

-- Called after lazy.nvim adds Catppuccin to runtimepath. Never require the
-- plugin while reading the plugin specs, or startup depends on load order.
function M.colors(stock)
	local colors = vim.tbl_extend("force", {}, stock, M.active and M.active.colors or {})
	local foreground = colors.text
	for key, color in pairs(colors) do
		if not vim.tbl_contains({ "base", "mantle", "crust", "surface0", "surface1", "surface2" }, key) then
			colors[key] = M.ensure_contrast(color, colors.base, foreground, M.floor(key))
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

local function ssh_session()
	return vim.env.SSH_CONNECTION and vim.env.SSH_CONNECTION ~= ""
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
		local path = dir .. "remote-palette-" .. source .. ".conf"
		local values = read_encoded_file(path)
		if values then
			return values, "remote-palette-" .. source, path
		end
	end
	local newest, newest_time, newest_source, newest_path
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
					newest, newest_time, newest_source, newest_path = values, mtime, candidate, path
				end
			end
		end
	end
	if newest then
		return newest, "remote-palette-" .. newest_source, newest_path
	end
end

local function kitty_dir()
	local config = vim.env.XDG_CONFIG_HOME
	return (config and config ~= "" and config or (vim.env.HOME .. "/.config")) .. "/kitty/"
end

-- Resolve symlinks: install.sh links the kitty directory into this checkout.
local function read_file()
	local dir = kitty_dir()
	local file, source, source_path
	local names = { "dank-theme.conf", "current-theme.conf" }
	if ssh_session() then
		table.insert(names, 1, "remote-palette.conf")
	end
	for _, name in ipairs(names) do
		local path = vim.uv.fs_realpath(dir .. name)
		if path then
			file = io.open(path, "r")
			if file then
				source, source_path = name, path
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
	return values, source, source_path
end

-- The terminal palette Neovim follows, before any derivation: its raw values
-- (background, foreground, color0-15, optional cursor), a label naming where it
-- came from and the file path, if any. nil means plain Catppuccin Mocha.
-- Labels: remote-palette-<src>, "LC_KITTY_PALETTE (tmux)", LC_KITTY_PALETTE,
-- remote-palette.conf, dank-theme.conf, current-theme.conf.
function M.resolve()
	if ssh_session() then
		local environment = tmux_environment()
		local values, source, path = read_remote(environment)
		if values then
			return values, source, path
		end
		values = parse_encoded(environment.LC_KITTY_PALETTE)
		if values then
			return values, "LC_KITTY_PALETTE (tmux)"
		end
		values = parse_encoded(vim.env.LC_KITTY_PALETTE)
		if values then
			return values, "LC_KITTY_PALETTE"
		end
		return read_file()
	end
	-- Locally the kitty files are live and LC_KITTY_PALETTE is only the shell's
	-- start-time copy of them: a pane (or tmux's global environment) that predates
	-- a DMS theme change still holds the old palette, so it is a last resort.
	local values, source, path = read_file()
	if values then
		return values, source, path
	end
	values = parse_encoded(vim.env.LC_KITTY_PALETTE)
	if values then
		return values, "LC_KITTY_PALETTE"
	end
end

-- Derive the Catppuccin overrides and accents from resolved palette values.
function M.from_values(values)
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

function M.read()
	local values = M.resolve()
	return values and M.from_values(values) or nil
end

M.active = M.read()

-- Re-resolve the palette. Returns true when it changed, after storing it.
function M.refresh()
	local active = M.read()
	if vim.deep_equal(active, M.active) then
		return false
	end
	M.active = active
	return true
end

-- DMS rewrites dank-theme.conf and the workflow push replaces
-- remote-palette-<src>.conf by rename, so watch their directories, not files.
local function watch_dirs()
	local dirs = { kitty_dir(), vim.env.HOME .. "/.config/kitty/" }
	local _, _, path = M.resolve()
	if path then
		dirs[#dirs + 1] = vim.fs.dirname(path) .. "/"
	end
	local unique, seen = {}, {}
	for _, dir in ipairs(dirs) do
		local real = vim.uv.fs_realpath(dir)
		if real and not seen[real] then
			seen[real] = true
			unique[#unique + 1] = real
		end
	end
	return unique
end

-- One burst of writes (DMS writes several kitty files) becomes one refresh.
M.FOLLOW_DEBOUNCE_MS = 150
local following = { handles = {} }

function M.unfollow()
	for _, handle in ipairs(following.handles) do
		if not handle:is_closing() then
			handle:close()
		end
	end
	following.handles = {}
	pcall(vim.api.nvim_del_augroup_by_name, "DotfilesKittyPalette")
end

-- The 'background' a palette implies.
function M.background()
	return M.active and M.active.flavour == "latte" and "light" or "dark"
end

-- Re-theme a running Neovim when the terminal palette changes: on any write to
-- the palette directories, and on FocusGained (a pane switch in tmux, or a
-- palette that only reached the tmux session environment). on_change runs on
-- the main loop after M.active holds the new palette.
--
-- Something else setting 'background' (the terminal's theme notification, a
-- plugin, :set bg) makes Neovim reload catppuccin-<flavour> without these
-- overrides, so a 'background' that disagrees with the palette re-applies it
-- too, once per palette so a colorscheme that insists cannot loop.
function M.follow(on_change)
	M.unfollow()
	local timer = assert(vim.uv.new_timer())
	following.handles[1] = timer
	-- reapply: run on_change on the next check even if the palette is unchanged.
	local reapply, retried, asserted = false, false, false
	local check
	local function queue()
		timer:stop()
		timer:start(M.FOLLOW_DEBOUNCE_MS, 0, vim.schedule_wrap(check))
	end
	check = function()
		if M.refresh() then
			asserted = false
		elseif not reapply then
			return
		end
		reapply = false
		local ok, err = pcall(on_change)
		if ok then
			retried = false
		elseif not retried then
			-- Every Neovim re-themes at once and Catppuccin shares one compile
			-- cache, so a reload can read another instance's half-written cache.
			retried, reapply = true, true
			queue()
		else
			retried = false
			vim.notify("kitty palette: re-theming failed: " .. tostring(err), vim.log.levels.WARN)
		end
	end
	for _, dir in ipairs(watch_dirs()) do
		local handle = vim.uv.new_fs_event()
		if handle then
			local ok = handle:start(dir, {}, function(err)
				if not err then
					queue()
				end
			end)
			if ok then
				following.handles[#following.handles + 1] = handle
			else
				handle:close()
			end
		end
	end
	local group = vim.api.nvim_create_augroup("DotfilesKittyPalette", { clear = true })
	vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = queue })
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "background",
		callback = function()
			if vim.o.background ~= M.background() and not asserted then
				asserted, reapply = true, true
				queue()
			end
		end,
	})
end

function M.palette()
	return require("catppuccin.palettes").get_palette(M.active and M.active.flavour or "mocha")
end

return M
