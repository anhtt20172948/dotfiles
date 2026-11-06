local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
local theme = require("customize.kitty_palette")
local dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/kitty"
vim.fn.mkdir(dir, "p")
assert(theme.read() == nil, "missing files must fall back to plain mocha")
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
print("kitty palette: OK")
