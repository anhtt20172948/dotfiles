-- neo-tree drawn like yazi: folders, named folder icons and the current row
-- come from the ANSI slots yazi names (.config/yazi/theme.toml), resolved
-- through kitty's palette, with Neovim's contrast floors on top. Which slot is
-- which is checked against yazi in tests/test_material_folder_icons.py.
-- CATPPUCCIN_TEST_RTP=<catppuccin checkout> also applies the real colorscheme
-- and checks the groups survive its integrations and the light-mode lift.
local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.opt.termguicolors = true
vim.env.SSH_CONNECTION = nil
vim.env.LC_KITTY_PALETTE = nil
vim.env.TMUX = nil
local plugin = vim.env.CATPPUCCIN_TEST_RTP
if plugin then
	vim.opt.rtp:prepend(plugin)
end
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
local kitty = require("customize.kitty_palette")
local tree = require("customize.tree_colors")

local fixtures = {
	{ file = "tests/fixtures/palettes/dms-light.conf", light = true },
	{ file = "tests/fixtures/palettes/dms-light-recorded.conf", light = true },
	{ file = "tests/fixtures/palettes/dms-dark.conf", light = false },
	{ file = ".config/kitty/current-theme.conf", light = false },
}

local function use(fixture)
	vim.fn.writefile(vim.fn.readfile(root .. "/" .. fixture.file), dir .. "/dank-theme.conf")
	kitty.active = kitty.read()
	assert(kitty.active, fixture.file .. " must resolve")
	assert((kitty.active.flavour == "latte") == fixture.light, fixture.file .. " flavour")
	return kitty.active
end

-- HSL hue in degrees and saturation.
local function hue(color)
	local r, g, b =
		tonumber(color:sub(2, 3), 16) / 255, tonumber(color:sub(4, 5), 16) / 255, tonumber(color:sub(6, 7), 16) / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	if delta == 0 then
		return nil, 0
	end
	local h = max == r and ((g - b) / delta) % 6 or max == g and (b - r) / delta + 2 or (r - g) / delta + 4
	return h * 60, delta / (1 - math.abs(max + min - 1))
end

-- group -> { slot, quiet }: icons keep the muted floor, names the text floor.
local expected = {
	NeoTreeDirectoryIcon = { tree.DIRECTORY, true },
	NeoTreeDirectoryName = { tree.DIRECTORY, false },
	NeoTreeRootName = { tree.DIRECTORY, false },
}
for group, slot in pairs(tree.ICONS) do
	expected[group] = { slot, true }
end

local function check(fixture, highlights)
	local active = kitty.active
	local backdrop = kitty.backdrop(active.colors.base)
	for group, spec in pairs(expected) do
		local raw, floor = active.ansi[spec[1]], kitty.text_floor(spec[2])
		local fg = assert(highlights[group], fixture.file .. " has no " .. group).fg
		local ratio = kitty.contrast(fg, backdrop)
		local where = ("%s %s (ANSI %d %s -> %s)"):format(fixture.file, group, spec[1], raw, fg)
		assert(ratio >= floor - 0.01, ("%s is %.2f:1, below %s:1"):format(where, ratio, floor))
		if kitty.contrast(raw, backdrop) >= floor then
			-- Readable as it is: exactly the colour yazi draws.
			assert(fg == raw, where .. " must be the slot itself")
		elseif fixture.light then
			-- Darkened along OKLab lightness: still yazi's hue.
			local stock_hue, saturation = hue(raw)
			if stock_hue and saturation > 0.2 then
				local lifted = hue(fg)
				local drift = math.abs(lifted - stock_hue)
				drift = math.min(drift, 360 - drift)
				assert(drift <= 15, ("%s hue drifted %.1f degrees"):format(where, drift))
			end
		end
	end
	-- The current row is yazi's pill: the cyan slot, its text readable on it.
	local pill = highlights.NeoTreeCursorLine
	assert(pill.bg == active.ansi[tree.CURSOR.bg], fixture.file .. " NeoTreeCursorLine must be the cyan slot")
	assert(pill.fg, fixture.file .. " NeoTreeCursorLine needs a foreground to colour the whole row")
	-- The pill keeps yazi's colour, so its text aims at the text floor and, when
	-- even white or black cannot reach it on that cyan, is the extreme; never
	-- below the floor every text group on its own background keeps.
	local ratio = kitty.contrast(pill.fg, pill.bg)
	local where = ("%s pill text %s on %s is %.2f:1"):format(fixture.file, pill.fg, pill.bg, ratio)
	assert(ratio >= kitty.text_floor(true) - 0.01, where)
	assert(
		ratio >= kitty.text_floor() - 0.01 or pill.fg == "#ffffff" or pill.fg == "#000000",
		where .. ", below the text floor without being the extreme"
	)
	assert(pill.bold == tree.CURSOR.bold, fixture.file .. " NeoTreeCursorLine bold")
end

-- Catppuccin's highlight_overrides take { fg, bg, style = { "bold" } }.
local function flatten(highlights)
	local result = {}
	for group, hl in pairs(highlights) do
		result[group] = { fg = hl.fg, bg = hl.bg, bold = vim.tbl_contains(hl.style or {}, "bold") }
	end
	return result
end

for _, fixture in ipairs(fixtures) do
	use(fixture)
	check(fixture, flatten(tree.highlights(kitty.colors({}))))
end
-- Dark palettes clear the 4.5:1 floor as they are: neo-tree draws yazi's exact colours.
for _, fixture in ipairs(fixtures) do
	if not fixture.light then
		local active = use(fixture)
		local highlights = tree.highlights(kitty.colors({}))
		for group, spec in pairs(expected) do
			assert(
				highlights[group].fg == active.ansi[spec[1]],
				fixture.file .. " " .. group .. " changed in dark mode"
			)
		end
	end
end
-- No palette at all: plain Catppuccin.
kitty.active = nil
assert(vim.tbl_isempty(tree.highlights({ base = "#1e1e2e", text = "#cdd6f4" })), "no palette, no overrides")

if not plugin then
	print("skip: real highlight groups need CATPPUCCIN_TEST_RTP")
	print("nvim tree colors: OK (derivation only)")
	return
end

-- Real Catppuccin: the overrides win over its neotree and mini integrations
-- and survive the light-mode lift.
local ui = require("customize.ui")
local function apply()
	package.loaded["plugins.themes"] = nil
	for _, spec in ipairs(require("plugins.themes")) do
		if spec.name == "catppuccin" then
			spec.config()
		end
	end
	vim.cmd.colorscheme("catppuccin")
	ui.decorations()
	ui.light_contrast()
end
local function hex(value)
	return value and ("#%06x"):format(value)
end
for _, fixture in ipairs(fixtures) do
	use(fixture)
	apply()
	local applied = {}
	for group in pairs(vim.tbl_extend("force", expected, { NeoTreeCursorLine = true })) do
		local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
		applied[group] = { fg = hex(hl.fg), bg = hex(hl.bg), bold = hl.bold or false }
	end
	check(fixture, applied)
end
print("nvim tree colors: OK (Catppuccin highlight groups)")
