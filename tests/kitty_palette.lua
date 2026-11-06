local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.env.SSH_CONNECTION = nil
vim.env.LC_KITTY_PALETTE = nil
local theme = require("customize.kitty_palette")
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
assert(theme.read() == nil, "missing files must fall back to plain mocha")
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
assert(env_only.colors.red == "#010101" and env_only.colors.flamingo == "#0f0f0f")
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
assert(dark.colors.red == "#010101" and dark.colors.pink == "#0d0d0d")
assert(dark.selection_background == "#123456" and dark.cursor == "#abcdef")
vim.fn.writefile(fixture("#eeeeee"), dir .. "/light.conf")
assert(vim.uv.fs_symlink(dir .. "/light.conf", dir .. "/dank-theme.conf"))
local light = assert(theme.read())
assert(light.flavour == "latte" and light.colors.base == "#eeeeee")
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
vim.env.LC_KITTY_PALETTE = env_palette("fafafa")
local forwarded = assert(theme.read())
assert(forwarded.colors.base == "#fafafa" and forwarded.flavour == "latte", "env must override every file")
assert(forwarded.cursor == nil and forwarded.selection_background == nil, "env must not mix in stale file values")
package.loaded["customize.kitty_palette"] = nil
assert(require("customize.kitty_palette").active.colors.base == "#fafafa", "startup must use forwarded palette")
vim.env.SSH_CONNECTION = nil
assert(theme.read().colors.base == "#fafafa", "env precedence must not depend on SSH_CONNECTION")
vim.env.SSH_CONNECTION = "127.0.0.1 1234 127.0.0.1 22"
local valid = env_palette("abcdef")
for _, invalid in ipairs({
	"",
	valid:upper(),
	"#" .. valid,
	" " .. valid,
	valid .. " ",
	valid .. "\n",
	valid .. "\r",
	valid .. ":000000",
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
print("kitty palette: OK")
