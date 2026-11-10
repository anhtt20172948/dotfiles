-- lazy.nvim's lockfile and update checker per host role.
--
-- The workstation owns the tracked .config/nvim/lazy-lock.json: :Lazy update
-- rewrites it there and lock bumps reach the servers through pull requests.
-- lazy.nvim rewrites its lockfile after every install, update, sync, restore
-- and clean, recording the commits the host has on disk, so a server writing
-- the tracked file dirties its dotfiles checkout and blocks the next pull.
-- A server therefore points lazy.nvim at a private copy in stdpath("state"),
-- replaced by the tracked lock on every start: missing plugins install at the
-- tracked pin, :Lazy restore returns to it, and :Lazy update/sync only change
-- the copy. The update checker is off there.
--
-- Role: DOTFILES_HOST_ROLE=server|workstation when set; otherwise "server" in
-- an SSH session (SSH_CONNECTION, the signal kitty_palette.lua,
-- status-context.sh and dotfiles-diagnose use) and "workstation" otherwise.
-- Inside tmux, SSH_CONNECTION is the one of the client that started the tmux
-- server; export DOTFILES_HOST_ROLE=server on a server whose tmux or Neovim
-- starts outside an SSH session.
local M = {}

local ROLES = { server = true, workstation = true }

---@param env? table<string, string> environment to read (default: vim.env)
---@return "server"|"workstation"
function M.role(env)
	env = env or vim.env
	local role = env.DOTFILES_HOST_ROLE
	if role and role ~= "" then
		if ROLES[role] then
			return role
		end
		vim.notify(
			("DOTFILES_HOST_ROLE=%q is neither server nor workstation; detecting the role from SSH_CONNECTION"):format(
				role
			),
			vim.log.levels.WARN
		)
	end
	local ssh = env.SSH_CONNECTION
	return (ssh and ssh ~= "") and "server" or "workstation"
end

-- lazy.nvim's default lockfile: the tracked file in the dotfiles checkout.
function M.tracked_lockfile()
	return vim.fn.stdpath("config") .. "/lazy-lock.json"
end

function M.server_lockfile()
	return vim.fn.stdpath("state") .. "/lazy-lock.json"
end

-- Replaces the server's private lock with the tracked one. Without a tracked
-- lock there is nothing to pin; lazy.nvim then creates the private one itself.
local function seed(from, to)
	if not vim.uv.fs_stat(from) then
		return
	end
	vim.fn.mkdir(vim.fn.fnamemodify(to, ":h"), "p")
	local ok, err = vim.uv.fs_copyfile(from, to)
	if not ok then
		vim.notify(("lazy-lock: cannot copy %s to %s: %s"):format(from, to, err), vim.log.levels.ERROR)
	end
end

-- The lazy.setup() options for the role. On a server this also refreshes the
-- private lock from the tracked one, so call it before lazy.setup().
---@param role "server"|"workstation"
---@return { lockfile?: string, checker: { enabled: boolean } }
function M.options(role)
	if role ~= "server" then
		return { checker = { enabled = true } }
	end
	local lockfile = M.server_lockfile()
	seed(M.tracked_lockfile(), lockfile)
	return { lockfile = lockfile, checker = { enabled = false } }
end

return M
