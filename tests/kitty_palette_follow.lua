-- A running Neovim follows palette changes: DMS rewriting dank-theme.conf (in
-- place or by rename), FocusGained, and with CATPPUCCIN_TEST_RTP the real
-- current-theme.lua reload (background, Catppuccin flavour, readable text).
local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.opt.termguicolors = true
vim.env.SSH_CONNECTION = nil
vim.env.TMUX = nil
vim.env.LC_KITTY_PALETTE_SRC = nil
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
local fixtures = root .. "/tests/fixtures/palettes/"
local dark = vim.fn.readfile(fixtures .. "dms-dark.conf")
local light = vim.fn.readfile(fixtures .. "dms-light-recorded.conf")
local file = dir .. "/dank-theme.conf"
vim.fn.writefile(dark, file)
-- The stale dark snapshot a long-lived pane still exports.
local entries = { "0b0f11", "dfe6ee" }
for i = 0, 15 do
	entries[#entries + 1] = ("%06x"):format(i * 65793)
end
vim.env.LC_KITTY_PALETTE = table.concat(entries, ":")

local kitty = require("customize.kitty_palette")
assert(kitty.active.flavour == "mocha", "starts dark")
local changes = 0
kitty.follow(function()
	changes = changes + 1
end)
local function wait_for(count, message)
	assert(
		vim.wait(3000, function()
			return changes >= count
		end, 20),
		message .. " (changes=" .. changes .. ")"
	)
end
local function settle()
	vim.wait(kitty.FOLLOW_DEBOUNCE_MS * 3, function()
		return false
	end, 20)
end

-- DMS writing the file in place.
vim.fn.writefile(light, file)
wait_for(1, "in-place write must re-theme")
assert(kitty.active.flavour == "latte" and kitty.active.colors.base == "#f7f9fd")
settle()
assert(changes == 1, "one burst of writes must re-theme once")

-- A rename into place (atomic writers, the workflow palette push).
vim.fn.writefile(dark, file .. ".tmp")
assert(vim.uv.fs_rename(file .. ".tmp", file))
wait_for(2, "rename must re-theme")
assert(kitty.active.flavour == "mocha")

-- Writes that do not change the palette do not re-theme.
vim.fn.writefile(dark, file)
vim.fn.writefile({ "unrelated" }, dir .. "/dank-tabs.conf")
settle()
assert(changes == 2, "unchanged palette must not re-theme")

-- FocusGained re-reads without any file event: with no kitty files only the
-- environment palette applies, and here only the environment changes.
kitty.unfollow()
vim.fn.delete(file)
kitty.active = kitty.read()
assert(kitty.active.colors.base == "#0b0f11" and select(2, kitty.resolve()) == "LC_KITTY_PALETTE")
kitty.follow(function()
	changes = changes + 1
end)
entries[1] = "f7f9fd"
vim.env.LC_KITTY_PALETTE = table.concat(entries, ":")
settle()
assert(changes == 2, "an environment change alone fires no file event")
vim.api.nvim_exec_autocmds("FocusGained", {})
wait_for(3, "FocusGained must re-read the palette")
assert(kitty.active.colors.base == "#f7f9fd")
vim.env.LC_KITTY_PALETTE = nil

-- unfollow stops both.
kitty.unfollow()
vim.fn.writefile(light, file)
vim.api.nvim_exec_autocmds("FocusGained", {})
settle()
assert(changes == 3, "unfollow must stop watching")
assert(#vim.api.nvim_get_autocmds({ event = "FocusGained" }) == 0)

-- 'background' disagreeing with the palette re-applies it, once per palette.
vim.fn.writefile(dark, file)
kitty.active = kitty.read()
assert(kitty.background() == "dark")
local reapplied = 0
kitty.follow(function()
	reapplied = reapplied + 1
end)
vim.o.background = "light"
assert(
	vim.wait(3000, function()
		return reapplied == 1
	end, 20),
	"a foreign 'background' must re-apply the palette"
)
vim.o.background = "dark"
vim.o.background = "light"
settle()
assert(reapplied == 1, "a colorscheme insisting on its own background must not loop")
vim.o.background = "dark"
kitty.unfollow()

-- A failing re-theme is retried once, then reported, never raised.
local attempts, warnings = 0, {}
local notify = vim.notify
vim.notify = function(message)
	warnings[#warnings + 1] = message
end
vim.fn.writefile(dark, file)
kitty.active = kitty.read()
kitty.follow(function()
	attempts = attempts + 1
	error("compile cache busy")
end)
vim.fn.writefile(light, file)
assert(
	vim.wait(3000, function()
		return #warnings > 0
	end, 20),
	"a failing re-theme must be reported"
)
assert(attempts == 2 and warnings[1]:find("compile cache busy", 1, true), vim.inspect({ attempts, warnings }))
vim.notify = notify
kitty.unfollow()

local plugin = vim.env.CATPPUCCIN_TEST_RTP
if not plugin then
	print("skip: Catppuccin reload needs CATPPUCCIN_TEST_RTP")
	print("kitty palette follow: OK (watcher only)")
	return
end
vim.opt.rtp:prepend(plugin)
-- Real reload through current-theme.lua and the ColorScheme hooks in ui.lua.
vim.fn.writefile(dark, file)
kitty.active = kitty.read()
require("customize.ui").setup()
-- lazy.nvim runs the spec's config when `colorscheme catppuccin` loads it.
require("plugins.themes")[2].config()
dofile(root .. "/.config/nvim/lua/current-theme.lua")
local function normal_fg()
	return ("#%06x"):format(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg)
end
local function comment()
	return ("#%06x"):format(vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg)
end
assert(vim.o.background == "dark" and normal_fg() == "#dfe6ee", vim.o.background .. " " .. normal_fg())
vim.fn.writefile(light, file)
assert(
	vim.wait(5000, function()
		return vim.o.background == "light"
	end, 20),
	"light DMS file must switch a running Neovim to background=light"
)
assert(normal_fg() == "#2c3339", "Normal must follow the light foreground: " .. normal_fg())
assert(kitty.contrast(comment(), "#f7f9fd") >= kitty.LIGHT_MUTED_FLOOR - 0.01, "comments readable on light")
vim.fn.writefile(dark, file)
assert(
	vim.wait(5000, function()
		return vim.o.background == "dark"
	end, 20),
	"switching back must restore background=dark"
)
assert(normal_fg() == "#dfe6ee")
-- Neovim reloads catppuccin-<flavour> when anything else sets 'background';
-- the DMS palette must come back instead of stock Latte.
vim.o.background = "light"
assert(
	vim.wait(5000, function()
		return vim.o.background == "dark" and normal_fg() == "#dfe6ee"
	end, 20),
	"foreign 'background' must restore the DMS palette: " .. vim.o.background .. " " .. normal_fg()
)
kitty.unfollow()
print("kitty palette follow: OK (Catppuccin reload)")
