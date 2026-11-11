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

-- OKLab (Björn Ottosson): darkening along OKLab lightness keeps a colour's hue
-- and as much chroma as sRGB allows, so lifted syntax colours stay apart
-- instead of all fading toward the same grey-black.
local function oklch(color)
	local r, g, b = rgb(color)
	r, g, b = linear(r), linear(g), linear(b)
	local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
	local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
	local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
	local L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	local A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	local B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return L, math.sqrt(A * A + B * B), math.atan2(B, A)
end

-- Linear sRGB channels for an OKLCH colour (may fall outside 0..1).
local function oklch_linear(L, C, h)
	local A, B = C * math.cos(h), C * math.sin(h)
	local l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
	local m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
	local s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function in_gamut(r, g, b)
	local e = 1e-6
	return r >= -e and r <= 1 + e and g >= -e and g <= 1 + e and b >= -e and b <= 1 + e
end

local function encode(channel)
	channel = math.min(1, math.max(0, channel))
	local value = channel <= 0.0031308 and channel * 12.92 or 1.055 * channel ^ (1 / 2.4) - 0.055
	return math.floor(value * 255 + 0.5)
end

-- The sRGB colour at OKLab lightness L with hue h, keeping chroma up to C.
local function oklch_hex(L, C, h)
	local r, g, b = oklch_linear(L, C, h)
	if not in_gamut(r, g, b) then
		local low, high = 0, C
		for _ = 1, 16 do
			local mid = (low + high) / 2
			if in_gamut(oklch_linear(L, mid, h)) then
				low = mid
			else
				high = mid
			end
		end
		r, g, b = oklch_linear(L, low, h)
	end
	return ("#%02x%02x%02x"):format(encode(r), encode(g), encode(b))
end

-- Darken toward black along OKLab lightness until `floor` holds against a
-- light background: the lightest same-hue colour that is readable.
local function darken(color, background, floor)
	local black = ("#%06x"):format(0)
	if M.contrast(black, background) < floor then
		return black
	end
	local L, C, h = oklch(color)
	local low, high = 0, L
	for _ = 1, 24 do
		local mid = (low + high) / 2
		if M.contrast(oklch_hex(mid, C, h), background) >= floor then
			low = mid
		else
			high = mid
		end
	end
	local result = oklch_hex(low, C, h)
	return M.contrast(result, background) >= floor and result or black
end

local function light()
	return M.active and M.active.flavour == "latte"
end

-- Blend toward the foreground until `floor` holds; when the foreground cannot
-- reach it, toward black on a bright background and white on a dark one.
local function blend_toward(color, background, foreground, floor)
	local target = foreground
	if M.contrast(target, background) < floor then
		target = luminance(background) > 0.179 and ("#%06x"):format(0) or ("#%06x"):format(0xffffff)
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

-- The colour, moved just far enough from `background` to hold `floor`. Light
-- palettes darken text on bright backgrounds along OKLab lightness (hue kept);
-- everything else, and every dark palette, blends as before. Results are
-- memoised: highlight scans repeat colours.
local lifted = {}
function M.ensure_contrast(color, background, foreground, floor)
	if M.contrast(color, background) >= floor then
		return color
	end
	local oklab = light() and luminance(background) > 0.179
	local key = table.concat({ color, background, foreground, floor, tostring(oklab) }, ":")
	if not lifted[key] then
		lifted[key] = oklab and darken(color, background, floor) or blend_toward(color, background, foreground, floor)
	end
	return lifted[key]
end

-- Contrast floors, in one place. WCAG AA (4.5:1) is the floor for every text
-- colour on a dark palette, which keeps its colours.
--
-- Light palettes need far more. Dark text on a light background reads fainter
-- than the same ratio inverted (thin strokes at kitty's 9pt font), Catppuccin
-- Latte's pastel accents sit on the AA floor, and kitty draws the default
-- background at background_opacity over the wallpaper, so the background text
-- actually sits on is darker than the palette's. Light floors are measured
-- against that backdrop: the palette background at LIGHT_OPACITY over
-- LIGHT_SHOW_THROUGH, a mid grey that is more conservative than the light
-- wallpapers DMS light mode pairs with. Normal text and syntax hold WCAG AAA
-- (7:1); muted layers (comments, line numbers, punctuation, inlay hints,
-- neo-tree's dim and git-ignored entries, whitespace) stay quieter but hold
-- LIGHT_MUTED_FLOOR, which is also the floor for every other text group.
-- Cells with their own background (pills, selections) are opaque in kitty and
-- are measured against that background.
M.TEXT_FLOOR = 4.5
M.LIGHT_SYNTAX_FLOOR = 7
M.LIGHT_MUTED_FLOOR = 6
M.LIGHT_OPACITY = 0.8
M.LIGHT_SHOW_THROUGH = ("#%06x"):format(0x808080)
local muted = { overlay0 = true, overlay1 = true, overlay2 = true, subtext0 = true, subtext1 = true }

-- The floor for text: syntax/normal text, or a muted layer when `quiet`.
function M.text_floor(quiet)
	if not light() then
		return M.TEXT_FLOOR
	end
	return quiet and M.LIGHT_MUTED_FLOOR or M.LIGHT_SYNTAX_FLOOR
end

-- The contrast floor a palette key keeps against the backdrop.
function M.floor(key)
	return M.text_floor(muted[key])
end

-- What text on a transparent cell is drawn over (see the floors above).
function M.backdrop(base)
	return light() and blend(base, M.LIGHT_SHOW_THROUGH, 1 - M.LIGHT_OPACITY) or base
end

-- Called after lazy.nvim adds Catppuccin to runtimepath. Never require the
-- plugin while reading the plugin specs, or startup depends on load order.
function M.colors(stock)
	local colors = vim.tbl_extend("force", {}, stock, M.active and M.active.colors or {})
	local foreground, backdrop = colors.text, M.backdrop(colors.base)
	for key, color in pairs(colors) do
		if not vim.tbl_contains({ "base", "mantle", "crust", "surface0", "surface1", "surface2" }, key) then
			colors[key] = M.ensure_contrast(color, backdrop, foreground, M.floor(key))
		end
	end
	return colors
end

-- The accent for borders, the cursor line number and search: the terminal's
-- cursor colour, readable as text on the backdrop.
function M.primary(colors)
	local color = M.active and M.active.primary or colors.lavender or colors.text
	return M.ensure_contrast(color, M.backdrop(colors.base), colors.text, M.text_floor())
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

-- The resolved palette's file, if any (watched for in-place rewrites).
local source_path

function M.read()
	local values, _, path = M.resolve()
	source_path = path
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

-- The directory itself, or its nearest existing ancestor: a server whose kitty
-- directory the first palette push creates must still see that push.
local function existing(dir)
	local current = vim.fs.normalize(dir)
	while current do
		local real = vim.uv.fs_realpath(current)
		if real then
			return real
		end
		local parent = vim.fs.dirname(current)
		current = parent ~= current and parent or nil
	end
end

-- DMS rewrites dank-theme.conf and the workflow push replaces
-- remote-palette-<src>.conf by rename, so watch their directories, not files.
local function watch_dirs()
	local dirs = { kitty_dir(), vim.env.HOME .. "/.config/kitty/" }
	if source_path then
		dirs[#dirs + 1] = vim.fs.dirname(source_path)
	end
	local unique = {}
	for _, dir in ipairs(dirs) do
		local real = existing(dir)
		if real then
			unique[real] = true
		end
	end
	return unique
end

-- One burst of writes (DMS writes several kitty files) becomes one refresh.
M.FOLLOW_DEBOUNCE_MS = 150
local following = { watchers = {} }

local function close(handle)
	if handle and not handle:is_closing() then
		handle:close()
	end
end

-- Watch exactly the current directories: a directory created since, or a
-- symlink pointing somewhere new, gets a watcher on the next check.
local function sync_watchers(on_event)
	local wanted = watch_dirs()
	for dir, handle in pairs(following.watchers) do
		if not wanted[dir] then
			close(handle)
			following.watchers[dir] = nil
		end
	end
	for dir in pairs(wanted) do
		if not following.watchers[dir] then
			local handle = vim.uv.new_fs_event()
			if handle and handle:start(dir, {}, function(err)
				if not err then
					on_event()
				end
			end) then
				following.watchers[dir] = handle
			else
				close(handle)
			end
		end
	end
end

function M.unfollow()
	close(following.timer)
	for _, handle in pairs(following.watchers) do
		close(handle)
	end
	following = { watchers = {} }
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
	following.timer = timer
	-- reapply: run on_change on the next check even if the palette is unchanged.
	local reapply, retried, asserted = false, false, false
	local check
	local function queue()
		timer:stop()
		timer:start(M.FOLLOW_DEBOUNCE_MS, 0, vim.schedule_wrap(check))
	end
	check = function()
		-- A check scheduled before unfollow (or a newer follow) must not revive watchers.
		if following.timer ~= timer then
			return
		end
		local changed = M.refresh()
		sync_watchers(queue)
		if changed then
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
	sync_watchers(queue)
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
