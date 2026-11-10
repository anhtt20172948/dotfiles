-- lazy.nvim lockfile policy per host role (configs/lazy_lock.lua) and its wiring
-- into configs/lazy.lua. tests/smoke/nvim_lazy_lock.sh runs a real `Lazy! sync`.
local root = assert(arg[1])
vim.opt.rtp:prepend(root .. "/.config/nvim")
vim.env.SSH_CONNECTION = nil
vim.env.DOTFILES_HOST_ROLE = nil

local lock = require("configs.lazy_lock")
local ssh = "10.0.0.1 51234 10.0.0.2 22"

local warnings = {}
vim.notify = function(msg, level)
	warnings[#warnings + 1] = { msg = msg, level = level }
end

-- Role detection.
assert(lock.role({}) == "workstation", "no SSH session is the workstation")
assert(lock.role({ SSH_CONNECTION = "" }) == "workstation", "an empty SSH_CONNECTION is no SSH session")
assert(lock.role({ SSH_CONNECTION = ssh }) == "server", "an SSH session is a server")
assert(lock.role({ DOTFILES_HOST_ROLE = "server" }) == "server", "the override marks a server without SSH")
assert(
	lock.role({ DOTFILES_HOST_ROLE = "workstation", SSH_CONNECTION = ssh }) == "workstation",
	"the override wins over SSH detection"
)
assert(#warnings == 0, "valid roles do not warn")
assert(lock.role({ DOTFILES_HOST_ROLE = "laptop", SSH_CONNECTION = ssh }) == "server", "a bad override falls back")
assert(#warnings == 1 and warnings[1].level == vim.log.levels.WARN, "a bad override warns")
assert(warnings[1].msg:find("laptop", 1, true), "the warning names the bad value")
warnings = {}

local function read(path)
	local f = assert(io.open(path, "rb"))
	local data = f:read("*a")
	f:close()
	return data
end
local function write(path, data)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local f = assert(io.open(path, "wb"))
	f:write(data)
	f:close()
end

local tracked = vim.fn.stdpath("config") .. "/lazy-lock.json"
local private = vim.fn.stdpath("state") .. "/lazy-lock.json"
assert(lock.tracked_lockfile() == tracked, "the tracked lock is lazy.nvim's default path")
assert(lock.server_lockfile() == private, "the server lock lives in the state directory")
assert(not vim.startswith(private, vim.fn.stdpath("config")), "the server lock is outside the config checkout")

-- Workstation: lazy.nvim defaults, the tracked lock, the update checker on.
local workstation = lock.options("workstation")
assert(workstation.lockfile == nil, "the workstation keeps lazy.nvim's default lockfile")
assert(workstation.checker.enabled == true, "the workstation checks for updates")

-- Server: a private copy of the tracked lock, refreshed on every start; no checker.
local pinned = '{\n  "lazy.nvim": { "branch": "main", "commit": "aaaa" }\n}\n'
write(tracked, pinned)
local server = lock.options("server")
assert(server.lockfile == private, "the server points lazy.nvim at the private lock")
assert(server.checker.enabled == false, "the server never checks for updates")
assert(read(private) == pinned, "the private lock starts as the tracked lock")
write(private, '{\n  "lazy.nvim": { "branch": "main", "commit": "bbbb" }\n}\n')
lock.options("server")
assert(read(private) == pinned, "each start replaces a drifted private lock with the tracked one")
assert(read(tracked) == pinned, "seeding never writes the tracked lock")
os.remove(tracked)
os.remove(private)
lock.options("server")
assert(not vim.uv.fs_stat(private), "without a tracked lock there is nothing to seed")
assert(#warnings == 0, "seeding is silent")

-- configs/lazy.lua hands the role's options to lazy.setup.
vim.fn.mkdir(vim.fn.stdpath("data") .. "/lazy/lazy.nvim", "p")
local captured
package.loaded.lazy = {
	setup = function(opts)
		captured = opts
	end,
}
local function setup_opts(env)
	vim.env.SSH_CONNECTION = env.SSH_CONNECTION
	vim.env.DOTFILES_HOST_ROLE = env.DOTFILES_HOST_ROLE
	captured = nil
	package.loaded["configs.lazy"] = nil
	require("configs.lazy")
	return assert(captured, "configs.lazy must call lazy.setup")
end
local opts = setup_opts({})
assert(opts.lockfile == nil and opts.checker.enabled == true, "local session: tracked lock and checker")
assert(opts.spec[1].import == "plugins", "the plugin spec stays wired")
opts = setup_opts({ SSH_CONNECTION = ssh })
assert(opts.lockfile == private and opts.checker.enabled == false, "SSH session: private lock, no checker")
opts = setup_opts({ SSH_CONNECTION = ssh, DOTFILES_HOST_ROLE = "workstation" })
assert(opts.lockfile == nil and opts.checker.enabled == true, "the override restores workstation mode")

print("nvim lazy lock: OK")
