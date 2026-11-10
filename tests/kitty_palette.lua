local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.env.TMUX = nil
vim.env.SSH_CONNECTION = nil
vim.env.LC_KITTY_PALETTE = nil
vim.env.LC_KITTY_PALETTE_SRC = nil
local theme = require("customize.kitty_palette")
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
assert(theme.read() == nil, "missing files must fall back to plain mocha")
assert(theme.resolve() == nil, "no source without a palette")
local function env_palette(bg)
	local entries = { bg, "dddddd" }
	for i = 0, 15 do
		entries[#entries + 1] = ("%06x"):format(i * 65793)
	end
	return table.concat(entries, ":")
end
vim.env.LC_KITTY_PALETTE = env_palette("123456")
local env_only = assert(theme.read(), "forwarded palette must work without any kitty files")
assert(env_only.colors.base == "#123456" and env_only.flavour == "mocha")
assert(select(2, theme.resolve()) == "LC_KITTY_PALETTE", "env source label")
assert(env_only.colors.red == nil, "ANSI slots must not replace syntax accents")
assert(env_only.primary == nil and env_only.cursor == nil, "18 entries must retain the lavender fallback")
vim.env.LC_KITTY_PALETTE = env_palette("123456") .. ":abcdef"
local with_cursor = assert(theme.read(), "19-entry env palette must work")
assert(with_cursor.primary == "#abcdef" and with_cursor.cursor == "#abcdef")
vim.env.LC_KITTY_PALETTE = nil
local function fixture(bg)
	local lines = {
		"background " .. bg,
		"foreground #dddddd",
		"cursor #abcdef",
		"selection_background #123456",
		"selection_foreground #fedcba",
	}
	for i = 0, 15 do
		lines[#lines + 1] = ("color%d #%06x"):format(i, i * 65793)
	end
	return lines
end
vim.fn.writefile(fixture("#111111"), dir .. "/current-theme.conf")
local dark = assert(theme.read())
assert(dark.flavour == "mocha" and dark.colors.base == "#111111")
assert(dark.colors.red == nil, "syntax accents come from Catppuccin at setup")
assert(dark.primary == "#abcdef", "cursor must provide the primary UI accent")
assert(dark.selection_background == "#123456" and dark.cursor == "#abcdef")
local _, dark_source, dark_path = theme.resolve()
assert(dark_source == "current-theme.conf" and dark_path == vim.uv.fs_realpath(dir .. "/current-theme.conf"))
-- Identical terminal inputs must produce identical search groups on every transport.
local function search_groups(active)
	theme.active = active
	local colors = theme.colors({})
	local highlights = require("customize.transparent").highlights(colors, active.primary)
	return { highlights.Search, highlights.CurSearch, highlights.IncSearch }
end
local local_search = search_groups(dark)
local encoded = env_palette("111111") .. ":abcdef"
vim.env.LC_KITTY_PALETTE = encoded
assert(vim.deep_equal(local_search, search_groups(assert(theme.read()))), "local/env search parity")
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
assert(vim.deep_equal(local_search, search_groups(assert(theme.read()))), "SSH env search parity")
local search_remote_dir = vim.env.HOME .. "/.config/kitty"
vim.fn.mkdir(search_remote_dir, "p")
local search_remote_file = search_remote_dir .. "/remote-palette-search-test.conf"
vim.fn.writefile({ encoded }, search_remote_file)
vim.env.LC_KITTY_PALETTE_SRC = "search-test"
vim.env.LC_KITTY_PALETTE = env_palette("222222")
assert(vim.deep_equal(local_search, search_groups(assert(theme.read()))), "pushed file search parity")
vim.fn.delete(search_remote_file)
vim.env.LC_KITTY_PALETTE_SRC = nil
vim.env.LC_KITTY_PALETTE = nil
vim.env.SSH_CONNECTION = nil
vim.fn.writefile(fixture("#eeeeee"), dir .. "/light.conf")
assert(vim.uv.fs_symlink(dir .. "/light.conf", dir .. "/dank-theme.conf"))
local light = assert(theme.read())
assert(light.flavour == "latte" and light.colors.base == "#eeeeee")
local _, light_source, light_path = theme.resolve()
assert(
	light_source == "dank-theme.conf" and light_path == vim.uv.fs_realpath(dir .. "/light.conf"),
	"DMS source resolves links"
)
vim.fn.writefile({ "background invalid" }, dir .. "/light.conf")
assert(theme.read() == nil, "incomplete palette must not partly override catppuccin")
vim.fn.delete(dir .. "/dank-theme.conf")
assert(theme.read().flavour == "mocha")
-- A Mac snapshot must supersede a previous Arch/DMS connection on the server.
vim.fn.writefile(fixture("#eeeeee"), dir .. "/dank-theme.conf")
vim.fn.writefile(fixture("#222222"), dir .. "/remote-palette.conf")
assert(theme.read().colors.base == "#eeeeee", "local DMS must ignore remote snapshots")
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
assert(theme.read().colors.base == "#222222", "SSH snapshot must override stale DMS")
assert(select(2, theme.resolve()) == "remote-palette.conf", "legacy snapshot source label")
vim.env.LC_KITTY_PALETTE = env_palette("fafafa")
local forwarded = assert(theme.read())
assert(forwarded.colors.base == "#fafafa" and forwarded.flavour == "latte", "env must override every file")
assert(forwarded.cursor == nil and forwarded.selection_background == nil, "env must not mix in stale file values")
package.loaded["customize.kitty_palette"] = nil
assert(require("customize.kitty_palette").active.colors.base == "#fafafa", "startup must use forwarded palette")
vim.env.SSH_CONNECTION = nil
-- Locally LC_KITTY_PALETTE is the shell's start-time copy of the kitty files,
-- so the live DMS file wins over it (a pane older than a theme switch).
assert(theme.read().colors.base == "#eeeeee", "local DMS file must override the env snapshot")
assert(select(2, theme.resolve()) == "dank-theme.conf", "local DMS source label")
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
local remote_dir = vim.env.HOME .. "/.config/kitty"
vim.fn.mkdir(remote_dir, "p")
vim.env.LC_KITTY_PALETTE_SRC = "arch-local"
vim.fn.writefile({ env_palette("333333") }, remote_dir .. "/remote-palette-arch-local.conf")
vim.fn.writefile({ env_palette("444444") }, remote_dir .. "/remote-palette-mac-local.conf")
assert(theme.read().colors.base == "#333333", "matching source file must override env")
local _, pushed_source, pushed_path = theme.resolve()
assert(pushed_source == "remote-palette-arch-local" and pushed_path == remote_dir .. "/remote-palette-arch-local.conf")
assert(theme.read().primary == nil, "18-entry pushed palette must retain lavender fallback")
for _, newline in ipairs({ "", "\n" }) do
	local file = assert(io.open(remote_dir .. "/remote-palette-arch-local.conf", "w"))
	file:write(env_palette("333333") .. ":abcdef" .. newline)
	file:close()
	local pushed = assert(theme.read(), "19-entry pushed palette must work")
	assert(pushed.colors.base == "#333333" and pushed.primary == "#abcdef" and pushed.cursor == "#abcdef")
end
vim.fn.writefile({ env_palette("555555") }, remote_dir .. "/remote-palette-arch-local.conf")
package.loaded["customize.kitty_palette"] = nil
assert(require("customize.kitty_palette").active.colors.base == "#555555", "restart must read fresh file")
vim.env.SSH_CONNECTION = nil
assert(theme.read().colors.base == "#eeeeee", "local sessions must ignore pushed files and the env snapshot")
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
-- A pane with no source and an old 18-entry environment must use the last push.
vim.env.LC_KITTY_PALETTE_SRC = nil
assert(vim.uv.fs_utime(remote_dir .. "/remote-palette-arch-local.conf", 100, 100))
assert(vim.uv.fs_utime(remote_dir .. "/remote-palette-mac-local.conf", 200, 200))
package.loaded["customize.kitty_palette"] = nil
assert(require("customize.kitty_palette").active.colors.base == "#444444", "restart in stale pane must use newest push")
for _, source in ipairs({
	"missing",
	"",
	"../arch-local",
	"Arch-local",
	"arch_local",
	string.rep("a", 33),
	"arch-local\n",
}) do
	vim.env.LC_KITTY_PALETTE_SRC = source
	assert(theme.read().colors.base == "#444444", "missing or invalid source must use newest valid push")
	local _, newest_source, newest_path = theme.resolve()
	assert(
		newest_source == "remote-palette-mac-local" and newest_path == remote_dir .. "/remote-palette-mac-local.conf"
	)
end
local original_system = vim.system
local session_output = "LC_KITTY_PALETTE_SRC=mac-local\n"
local session_code = 0
local calls = 0
vim.system = function(command, options)
	calls = calls + 1
	assert(vim.deep_equal(command, { "tmux", "show-environment" }), "read session environment in one invocation")
	assert(options.timeout > 0 and options.timeout <= 200, "tmux must have a short timeout")
	return {
		wait = function()
			return { code = session_code, stdout = session_output }
		end,
	}
end
vim.env.TMUX = "/tmp/test-tmux,123,0"
vim.env.LC_KITTY_PALETTE_SRC = "arch-local"
assert(theme.read().colors.base == "#444444", "tmux source must override stale process source")
assert(calls == 1, "one tmux invocation per read")
for _, output in ipairs({ "-LC_KITTY_PALETTE_SRC\n", "LC_KITTY_PALETTE_SRC=../bad\n" }) do
	session_output = output
	assert(theme.read().colors.base == "#555555", "removed or invalid tmux source must fall back to process source")
end
vim.fn.delete(remote_dir .. "/remote-palette-mac-local.conf")
vim.env.LC_KITTY_PALETTE_SRC = "arch-local"
for _, lines in ipairs({
	{ "invalid" },
	{ env_palette("333333"), "extra" },
	{ env_palette("333333") .. " " },
	{ env_palette("333333") .. ":abcdef", "extra" },
	{ env_palette("333333") .. ":abcdef:123456" },
}) do
	vim.fn.writefile(lines, remote_dir .. "/remote-palette-arch-local.conf")
	vim.fn.writefile({ env_palette("666666") .. ":abcdef" }, remote_dir .. "/remote-palette-valid.conf")
	assert(vim.uv.fs_utime(remote_dir .. "/remote-palette-valid.conf", 50, 50))
	assert(theme.read().colors.base == "#666666", "malformed newer files must be skipped")
	vim.fn.delete(remote_dir .. "/remote-palette-valid.conf")
	assert(theme.read().colors.base == "#fafafa", "malformed pushed files must fall back to env")
end
vim.fn.delete(remote_dir .. "/remote-palette-arch-local.conf")
vim.env.LC_KITTY_PALETTE_SRC = nil
session_output = "-LC_KITTY_PALETTE_SRC\nLC_KITTY_PALETTE=" .. env_palette("777777") .. ":abcdef\n"
assert(
	theme.read().primary == "#abcdef" and theme.read().colors.base == "#777777",
	"tmux palette must override process palette"
)
assert(select(2, theme.resolve()) == "LC_KITTY_PALETTE (tmux)", "tmux env source label")
for _, output in ipairs({ "-LC_KITTY_PALETTE\n", "LC_KITTY_PALETTE=invalid\n" }) do
	session_output = output
	assert(theme.read().colors.base == "#fafafa", "removed or malformed tmux palette must fall back to process env")
end
session_code = 124
assert(theme.read().colors.base == "#fafafa", "tmux timeout must fall back")
vim.system = function()
	error("tmux unavailable")
end
assert(theme.read().colors.base == "#fafafa", "spawn failure must fall back")
vim.env.TMUX = nil
assert(theme.read().colors.base == "#fafafa", "skip tmux outside tmux")
vim.env.TMUX = "/tmp/test-tmux,123,0"
vim.env.SSH_CONNECTION = nil
assert(theme.read().colors.base == "#eeeeee", "skip tmux in local sessions")
vim.env.TMUX = nil
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
vim.system = original_system
local valid = env_palette("abcdef")
for _, invalid in ipairs({
	"",
	valid:upper(),
	"#" .. valid,
	" " .. valid,
	valid .. " ",
	valid .. "\n",
	valid .. "\r",
	valid .. ":000000:111111",
	valid .. ":ABCDEF",
	valid .. ":abcdeg",
	valid .. ":abcde",
	valid .. ":abcdef0",
	valid:sub(1, -8),
	":" .. valid,
	valid .. ":",
	valid:gsub(":", "::", 1),
	valid:gsub("abcdef", "abcde"),
	valid:gsub("abcdef", "abcdef0"),
	valid:gsub("abcdef", "abcde:"),
	valid:gsub("abcdef", "abcde") .. "0",
	(valid:gsub("abcdef", "abcdeg")),
}) do
	vim.env.LC_KITTY_PALETTE = invalid
	assert(theme.read().colors.base == "#222222", "malformed env must fall back: " .. vim.inspect(invalid))
end
vim.env.LC_KITTY_PALETTE = nil
vim.fn.delete(dir .. "/remote-palette.conf")
assert(theme.read().colors.base == "#eeeeee", "plain SSH retains the existing fallback")
vim.env.SSH_CONNECTION = nil
assert(theme.contrast("#000000", "#ffffff") == 21, "WCAG reference contrast")
-- Contrast must hold even when the source foreground itself is unreadable.
for _, case in ipairs({
	{ bg = "#111111", fg = "#2e576b" },
	{ bg = "#eeeeee", fg = "#dddddd" },
}) do
	for _, color in ipairs({ "#2e576b", "#eeeeee", "#111111", "#fab387" }) do
		local corrected = theme.ensure_contrast(color, case.bg, case.fg, 4.5)
		assert(theme.contrast(corrected, case.bg) >= 4.5)
	end
end
assert(theme.ensure_contrast("#fab387", "#111111", "#dddddd", 4.5) == "#fab387")
-- Regression: DMS switched dark -> light while the shell (or tmux's global
-- environment) still exports the dark snapshot. Locally the live file wins.
local fixtures = root .. "/tests/fixtures/palettes/"
local dms_dark = vim.fn.readfile(fixtures .. "dms-dark.conf")
local dms_light = vim.fn.readfile(fixtures .. "dms-light.conf")
vim.fn.writefile(dms_dark, dir .. "/dank-theme.conf")
local function encode(values)
	local entries = { values.background:sub(2), values.foreground:sub(2) }
	for i = 0, 15 do
		entries[#entries + 1] = values["color" .. i]:sub(2)
	end
	return table.concat(entries, ":")
end
vim.env.LC_KITTY_PALETTE = encode(assert(theme.resolve()))
vim.env.LC_KITTY_PALETTE_SRC = "archlinux"
vim.env.TMUX = "/tmp/test-tmux,123,0"
assert(theme.read().flavour == "mocha", "dark DMS file")
vim.fn.writefile(dms_light, dir .. "/dank-theme.conf")
local switched = assert(theme.read())
assert(switched.flavour == "latte" and switched.colors.base == "#f8f8f8", "light DMS file must beat the dark snapshot")
assert(select(2, theme.resolve()) == "dank-theme.conf")
vim.fn.delete(dir .. "/dank-theme.conf")
assert(select(2, theme.resolve()) == "current-theme.conf", "kitty fallback file must beat the snapshot too")
vim.fn.delete(dir .. "/current-theme.conf")
assert(theme.read().colors.base == "#0b0f11", "without kitty files the snapshot still applies")
assert(select(2, theme.resolve()) == "LC_KITTY_PALETTE")
vim.env.TMUX = nil
vim.env.LC_KITTY_PALETTE = nil
vim.env.LC_KITTY_PALETTE_SRC = nil
-- Light palettes hold syntax further from the background; dark ones keep AA.
theme.active = { flavour = "latte", colors = { base = "#f8f8f8", text = "#191c1e" } }
assert(theme.floor("blue") == theme.LIGHT_SYNTAX_FLOOR and theme.floor("overlay2") == theme.LIGHT_MUTED_FLOOR)
assert(theme.LIGHT_SYNTAX_FLOOR > theme.LIGHT_MUTED_FLOOR and theme.LIGHT_MUTED_FLOOR > theme.TEXT_FLOOR)
theme.active = { flavour = "mocha", colors = { base = "#0b0f11", text = "#dfe6ee" } }
assert(theme.floor("blue") == theme.TEXT_FLOOR and theme.floor("overlay2") == theme.TEXT_FLOOR)
theme.active = nil
assert(theme.floor("blue") == theme.TEXT_FLOOR, "plain Mocha keeps AA")
print("kitty palette: OK")
