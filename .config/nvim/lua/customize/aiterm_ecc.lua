-- ECC (https://github.com/affaan-m/ECC) cho claude / codex / opencode.
-- Pure data module: NO windows, NO Snacks calls - same shape as aiterm_history.
--
-- Two jobs:
--   1. DETECT on disk which tools already have ECC commands, and how they are typed.
--   2. Build the SHELL commands to install (customize/aiterm.lua runs them after a confirm).
--
-- Why detect instead of hardcoding: the command prefix DIFFERS per tool.
--   claude (manual)  ~/.claude/commands/code-review.md      -> /code-review
--   claude (plugin)  Claude Code plugin cache               -> /ecc:code-review
--   codex            ~/.codex/prompts/ecc-code-review.md    -> /ecc-code-review
--   opencode         ~/.config/opencode/command/*.md        -> /code-review
-- codex prefix source: scripts/sync-ecc-to-codex.sh generates "ecc-$name.md" files.
-- opencode's command directory is NOT verifiable from the repo -> probe several candidates and
-- return an empty table when none exists. Never produces a command that is not on disk.
local M = {}

M.config = {
	repo = "https://github.com/affaan-m/ECC",
	dir = nil, -- nil -> stdpath("data")/ecc
	-- developer = ECC's "default engineer" profile: minimal + framework-language +
	-- database + orchestration. More skills/commands than minimal; favorites/pins
	-- (<leader>aS/<leader>aw) keep the picker tidy. codex (sync) and opencode (full pin)
	-- ignore this value; only claude uses --profile.
	profile = "developer",
}

-- ECC commands used as DETECTION MARKERS. ~/.claude/commands/ may hold only the user's own
-- commands, so "directory not empty" is NOT enough to conclude ECC is installed.
local MARKERS = { "code-review", "build-fix", "refactor-clean", "update-docs" }
local MARKER_MIN = 2

-- Leading lines read from each command file to get the frontmatter `description:`.
local HEAD_LINES = 10

-- cache: tool -> { sig, cmds, paths }; sig joins the source dirs' mtimes, so an install
-- refreshes it automatically. skill_cache/desc_cache use the same sig mechanism.
local cache = {}
local skill_cache = {}
local desc_cache = {}
local owned_cache = {}

local function read_json(path)
	local ok, data = pcall(vim.fn.readfile, path)
	if not ok or not data or #data == 0 then
		return nil
	end
	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	return ok and type(decoded) == "table" and decoded or nil
end

-- helpers ----------------------------------------------------------------

local function home(p)
	return vim.fn.expand("~/" .. p)
end

local function config_home()
	local x = vim.env.XDG_CONFIG_HOME
	if x and x ~= "" then
		return x
	end
	return vim.fn.expand("~/.config")
end

-- The repo's LOCAL command directories (rooted at cwd), per tool. Placed BEFORE the HOME
-- sources so the repo's copy wins. scope="project" so command_list labels it and sorts it first.
local function project_command_srcs(tool, cwd)
	if not cwd then
		return {}
	end
	local by_tool = {
		claude = { { dir = cwd .. "/.claude/commands", prefix = "", invoke = "/%s" } },
		codex = { { dir = cwd .. "/.codex/prompts", prefix = "ecc-", invoke = "/ecc-%s" } },
		opencode = {
			{ dir = cwd .. "/.opencode/commands", prefix = "", invoke = "/%s" },
			{ dir = cwd .. "/.opencode/command", prefix = "", invoke = "/%s" },
		},
	}
	local out = by_tool[tool] or {}
	for _, s in ipairs(out) do
		s.scope = "project"
	end
	return out
end

-- Directories that may hold commands, in priority order. Also returns dirs that do NOT
-- exist: sig must tell "missing" from "just created" for the cache to expire on its own.
-- cwd (optional): prepend the repo's LOCAL sources (scope="project"). Omitted -> HOME only.
---@return { dir: string, prefix: string, invoke: string, scope?: string }[]
local function sources(tool, cwd)
	local home_srcs = {}
	if tool == "claude" then
		home_srcs = { { dir = home(".claude/commands"), prefix = "", invoke = "/%s" } }
		-- The plugin path (/plugin install ecc@ecc) is not how we install, but if the
		-- user installed that way it is still detected. FIXED-DEPTH glob, not recursive:
		-- ~/.claude/plugins may hold node_modules, a recursive scan here is a performance trap.
		for _, pat in ipairs({ ".claude/plugins/*/ecc", ".claude/plugins/*/*/ecc" }) do
			for _, d in ipairs(vim.fn.glob(home(pat) .. "/commands", false, true)) do
				home_srcs[#home_srcs + 1] = { dir = d, prefix = "", invoke = "/ecc:%s" }
			end
		end
	elseif tool == "codex" then
		home_srcs = { { dir = home(".codex/prompts"), prefix = "ecc-", invoke = "/ecc-%s" } }
	elseif tool == "opencode" then
		-- MEASURED on this machine: opencode treats ~/.opencode AS a config root - typing /code-rev
		-- in the TUI autocompletes fully even though ~/.config/opencode has no command
		-- directory. That is also why ECC's `install.sh --target opencode` writes here.
		-- ~/.config/opencode (the documented path) is kept for anyone copying there by hand.
		local c = config_home() .. "/opencode"
		home_srcs = {
			{ dir = home(".opencode/commands"), prefix = "", invoke = "/%s" },
			{ dir = home(".opencode/command"), prefix = "", invoke = "/%s" },
			{ dir = c .. "/command", prefix = "", invoke = "/%s" },
			{ dir = c .. "/commands", prefix = "", invoke = "/%s" },
		}
	else
		return {}
	end
	-- The repo's LOCAL sources come BEFORE the HOME ones: "first source wins" in M.commands(),
	-- so the repo's copy beats a global one with the same name.
	local out = project_command_srcs(tool, cwd)
	vim.list_extend(out, home_srcs)
	return out
end

local function signature(srcs)
	local parts = {}
	for _, s in ipairs(srcs) do
		local st = vim.uv.fs_stat(s.dir)
		parts[#parts + 1] = s.dir .. ":" .. (st and st.mtime.sec or 0)
	end
	return table.concat(parts, "|")
end

-- public -----------------------------------------------------------------

-- Clone directory shared by all three tools.
function M.dir()
	return M.config.dir or (vim.fn.stdpath("data") .. "/ecc")
end

-- Table "ECC command name" -> "string typed into the session". Empty when not installed.
-- cwd (optional): add the repo's LOCAL commands (scope="project"). Omitted -> HOME only
-- (installed/count/status/doctor call it that way -> install detection is unchanged).
---@param tool string
---@param cwd? string
---@return table<string, string>
function M.commands(tool, cwd)
	local srcs = sources(tool, cwd)
	local sig = signature(srcs)
	local c = cache[tool]
	if c and c.sig == sig then
		return c.cmds
	end

	local cmds, paths, scopes = {}, {}, {}
	for _, s in ipairs(srcs) do
		if vim.uv.fs_stat(s.dir) then
			-- Depth 1: all three harnesses keep commands as flat files in the directory.
			for name, kind in vim.fs.dir(s.dir) do
				local base = kind == "file" and name:match("^(.*)%.md$")
				if base and (s.prefix == "" or base:sub(1, #s.prefix) == s.prefix) then
					local key = base:sub(#s.prefix + 1)
					-- First source wins: the repo's LOCAL copy / a manual install takes priority.
					if key ~= "" and not cmds[key] then
						cmds[key] = s.invoke:format(key)
						paths[key] = s.dir .. "/" .. name
						scopes[key] = s.scope == "project" and "project" or "global"
					end
				end
			end
		end
	end

	cache[tool] = { sig = sig, cmds = cmds, paths = paths, scopes = scopes }
	return cmds
end

-- Skill directories the TOOL ACTUALLY READS. Unlike commands, skills are guidance docs and can
-- apply to a piece of code, while commands are repo-level workflows (see M.command_list).
--   codex: $CODEX_HOME/skills, default ~/.codex/skills - the source is codex's own
--   `skill-creator` skill ("default to $CODEX_HOME/skills ... so the skill is
--   auto-discovered"). ~/.agents/skills is NOT probed as ECC's README says: codex does
--   not read that dir, and listing what the tool cannot see is exactly the "advertise a
--   nonexistent command" failure this whole plugin avoids. codex's built-in skills sit one
--   level deeper in .system/, so they are scanned separately.
-- Returns a list of { dir, scope }. cwd (optional) -> prepend the repo's LOCAL skill dirs
-- (scope="project"); omitted -> HOME only (scope="global"). Not recursive.
local function skill_dirs(tool, cwd)
	local home_dirs
	if tool == "claude" then
		home_dirs = { home(".claude/skills") }
	elseif tool == "opencode" then
		-- ~/.opencode/skills: ECC writes here. ~/.config/opencode/skills: the vercel skills
		-- CLI (`npx skills add -a opencode -g`) writes here -> scan both.
		home_dirs = { home(".opencode/skills"), config_home() .. "/opencode/skills" }
	elseif tool == "codex" then
		home_dirs = { home(".codex/skills"), home(".codex/skills/.system") }
	else
		return {}
	end
	-- Project: the tool's path + `.agents/skills` (the vercel skills CLI writes codex/opencode
	-- LOCAL skills to <cwd>/.agents/skills).
	local proj = ({
		claude = cwd and { cwd .. "/.claude/skills" } or {},
		opencode = cwd and { cwd .. "/.opencode/skills", cwd .. "/.agents/skills" } or {},
		codex = cwd and { cwd .. "/.codex/skills", cwd .. "/.agents/skills" } or {},
	})[tool] or {}
	local out = {}
	for _, d in ipairs(proj) do
		out[#out + 1] = { dir = d, scope = "project" }
	end
	for _, d in ipairs(home_dirs) do
		out[#out + 1] = { dir = d, scope = "global" }
	end
	-- ~/.agents/skills: the "universal" dir the vercel skills CLI often writes to, but
	-- claude/codex/opencode do NOT read it. Listed LAST -> dedup by name keeps the copy in the
	-- tool's real dir first, so a skill shows scope="shared" only while NOT activated in the tool.
	out[#out + 1] = { dir = vim.fn.expand("~/.agents/skills"), scope = "shared" }
	return out
end

-- Files ECC wrote for this tool, from install-state. This is the AUTHORITATIVE trace of
-- which skills are ECC's: frontmatter `metadata.origin: ECC` is NOT enough - for claude alone
-- 13/44 skills lack that tag yet are ECC's (ecc-guide, santa-method, repo-scan...).
---@return table<string, true>
function M.ecc_owned(tool)
	local path = tool == "claude" and home(".claude/ecc/install-state.json")
		or tool == "opencode" and home(".opencode/ecc-install-state.json")
	local st = path and vim.uv.fs_stat(path)
	local sig = tostring(path) .. ":" .. (st and st.mtime.sec or 0)
	local c = owned_cache[tool]
	if c and c.sig == sig then
		return c.set
	end
	local set = {}
	local d = st and read_json(path)
	for _, op in ipairs(d and type(d.operations) == "table" and d.operations or {}) do
		if type(op) == "table" and type(op.destinationPath) == "string" then
			set[op.destinationPath] = true
		end
	end
	owned_cache[tool] = { sig = sig, set = set }
	return set
end

local ORIGIN_ORDER = { project = 0, ecc = 1, builtin = 2, user = 3, shared = 4 }

-- The tool's skills, with description + source. Sorted by GROUP, then name.
-- cwd (optional): include the repo's LOCAL skills, origin="project" (sorted first). Omitted -> HOME only.
---@param tool string
---@param cwd? string
---@return { name: string, desc: string, hint: string|nil, path: string, origin: string }[]
function M.skill_list(tool, cwd)
	local dirs = skill_dirs(tool, cwd)
	local sig = signature(dirs) -- dirs already have .dir -> used directly
	local c = skill_cache[tool]
	if c and c.sig == sig then
		return c.list
	end

	local owned = M.ecc_owned(tool)
	local list, seen = {}, {}
	for _, entry in ipairs(dirs) do
		local dir = entry.dir
		if vim.uv.fs_stat(dir) then
			for name, kind in vim.fs.dir(dir) do
				local path = dir .. "/" .. name .. "/SKILL.md"
				-- "link": an activated skill is a symlink -> vim.fs.dir reports type "link", not
				-- "directory". fs_stat follows the symlink, so a real SKILL.md is still confirmed.
				if (kind == "directory" or kind == "link") and not seen[name] and vim.uv.fs_stat(path) then
					seen[name] = true
					local desc, hint, tagged = "", nil, false
					local ok, lines = pcall(vim.fn.readfile, path, "", HEAD_LINES)
					for _, l in ipairs(ok and lines or {}) do
						desc = desc ~= "" and desc or (l:match("^description:%s*(.+)$") or "")
						hint = hint or l:match("^argument%-hint:%s*(.+)$")
						tagged = tagged or l:find("origin: ECC", 1, true) ~= nil
					end
					desc = desc:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
					-- Source resolution order: repo LOCAL -> .system (the tool's built-in skills) ->
					-- install-state (most authoritative) -> frontmatter (fallback for codex, which
					-- has no install-state) -> the rest are hand-written.
					local origin = "user"
					if entry.scope == "project" then
						origin = "project"
					elseif entry.scope == "shared" then
						origin = "shared" -- ~/.agents/skills, not activated in the tool's dir yet
					elseif dir:find("/.system", 1, true) then
						origin = "builtin"
					elseif owned[path] or tagged then
						origin = "ecc"
					end
					list[#list + 1] = { name = name, desc = desc, hint = hint, path = path, origin = origin }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.origin ~= b.origin then
			return (ORIGIN_ORDER[a.origin] or 9) < (ORIGIN_ORDER[b.origin] or 9)
		end
		return a.name < b.name
	end)

	local set = {}
	for _, s in ipairs(list) do
		set[s.name] = true
	end
	skill_cache[tool] = { sig = sig, list = list, set = set }
	return list
end

-- Set of skill names. Keeps the old signature for <leader>ai + doctor; built from skill_list
-- so there is only ONE detection path.
---@return table<string, true>
function M.skills(tool)
	M.skill_list(tool)
	return skill_cache[tool].set
end

-- Commands with descriptions, for the M.workflows() picker. Descriptions come from the frontmatter
-- `description:` - only the first HEAD_LINES lines of each file are read, enough to get past
-- the frontmatter without loading hundreds of markdown files into RAM.
-- cwd (optional): include the repo's LOCAL commands, tagged scope="project" (picker sorts first + label).
---@param tool string
---@param cwd? string
---@return { name: string, invoke: string, desc: string, path: string, scope: string }[]
function M.command_list(tool, cwd)
	local cmds = M.commands(tool, cwd) -- loads the cache first; cache[tool].paths/scopes exist right after
	local sig = cache[tool].sig
	local c = desc_cache[tool]
	if c and c.sig == sig then
		return c.list
	end
	local paths = cache[tool].paths or {}
	local scopes = cache[tool].scopes or {}
	local list = {}
	for name, invoke in pairs(cmds) do
		local path = paths[name]
		local desc = ""
		if path then
			local ok, lines = pcall(vim.fn.readfile, path, "", HEAD_LINES)
			if ok then
				for _, l in ipairs(lines) do
					local d = l:match("^description:%s*(.+)$")
					if d then
						-- ECC frontmatter sometimes has double quotes, sometimes not.
						desc = d:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
						break
					end
				end
			end
		end
		list[#list + 1] = { name = name, invoke = invoke, desc = desc, path = path, scope = scopes[name] or "global" }
	end
	-- project first, then by name: the picker surfaces the repo's conventions first.
	table.sort(list, function(a, b)
		if (a.scope == "project") ~= (b.scope == "project") then
			return a.scope == "project"
		end
		return a.name < b.name
	end)
	desc_cache[tool] = { sig = sig, list = list }
	return list
end

-- Whether ECC is installed. Counts MARKERS instead of "directory not empty" (see the MARKERS comment).
function M.installed(tool)
	local cmds = M.commands(tool)
	local hit = 0
	for _, m in ipairs(MARKERS) do
		if cmds[m] then
			hit = hit + 1
		end
	end
	return hit >= MARKER_MIN
end

function M.refresh()
	cache = {}
	skill_cache = {}
	owned_cache = {}
	desc_cache = {}
end

-- version / commit ------------------------------------------------------
-- Answers "does the installed tool match the clone" WITHOUT the network. All data is
-- already on disk; only M.remote_head goes to the network, and only when the user asks.

local function short(sha)
	return type(sha) == "string" and #sha >= 7 and sha:sub(1, 7) or nil
end

-- Where the shared clone is. nil = never cloned.
---@return { version: string|nil, commit: string|nil, short: string|nil, branch: string|nil }|nil
function M.clone_info()
	local dir = M.dir()
	if not vim.uv.fs_stat(dir) then
		return nil
	end
	local info = {}
	local ok, lines = pcall(vim.fn.readfile, dir .. "/VERSION", "", 1)
	if ok and lines and lines[1] then
		info.version = vim.trim(lines[1])
	end
	-- Without git only the commit is lost; the version can still be compared.
	if vim.fn.executable("git") == 1 then
		local function git(...)
			local r = vim.system({ "git", "-C", dir, ... }, { text = true }):wait(2000)
			return r.code == 0 and vim.trim(r.stdout or "") or nil
		end
		info.commit = git("rev-parse", "HEAD")
		info.short = short(info.commit)
		info.branch = git("rev-parse", "--abbrev-ref", "HEAD")
	end
	return info
end

-- Which ECC version is installed for this tool.
-- claude/opencode: the installer writes install-state.json with both version and commit.
-- codex: the sync writes NO state -> only the version can be dug out of the <!-- BEGIN ECC -->
-- block in ~/.codex/AGENTS.md, no commit.
---@return { version: string|nil, commit: string|nil, short: string|nil, profile: string|nil, at: string|nil }|nil
function M.installed_info(tool)
	if tool == "codex" then
		local agents = home(".codex/AGENTS.md")
		local ok, lines = pcall(vim.fn.readfile, agents, "", 40)
		if not ok or not lines then
			return nil
		end
		local inside = false
		for _, l in ipairs(lines) do
			if l:find("BEGIN ECC", 1, true) then
				inside = true
			elseif l:find("END ECC", 1, true) then
				break
			elseif inside then
				local v = l:match("^%*%*Version:%*%*%s*(%S+)")
				if v then
					local st = vim.uv.fs_stat(home(".codex/prompts/ecc-prompts-manifest.txt"))
					return { version = v, at = st and os.date("%Y-%m-%d", st.mtime.sec) or nil }
				end
			end
		end
		return nil
	end

	local path = tool == "claude" and home(".claude/ecc/install-state.json")
		or tool == "opencode" and home(".opencode/ecc-install-state.json")
	local d = path and read_json(path)
	if not d then
		return nil
	end
	local src = type(d.source) == "table" and d.source or {}
	return {
		version = src.repoVersion,
		commit = src.repoCommit,
		short = short(src.repoCommit),
		profile = type(d.request) == "table" and d.request.profile or nil,
		at = type(d.installedAt) == "string" and d.installedAt:sub(1, 10) or nil,
	}
end

-- "missing" not installed | "current" matches the clone | "outdated" differs | "unknown" not enough data.
-- Compare the COMMIT first because it is certain; the version changes only per release, so two
-- different commits can share a version. Missing data returns "unknown" and NEVER
-- guesses "current": a false "up to date" is worse than saying we do not know.
---@return "missing"|"current"|"outdated"|"unknown"
function M.status(tool)
	if not M.installed(tool) then
		return "missing"
	end
	local inst, clone = M.installed_info(tool), M.clone_info()
	if not (inst and clone) then
		return "unknown"
	end
	if inst.commit and clone.commit then
		return inst.commit == clone.commit and "current" or "outdated"
	end
	if inst.version and clone.version then
		return inst.version == clone.version and "current" or "outdated"
	end
	return "unknown"
end

-- origin's HEAD, WITHOUT fetching (ls-remote only asks, downloads nothing). Async because it was
-- measured at ~1s - blocking the UI that long is noticeable. cb gets a short sha or nil.
---@param cb fun(short: string|nil, err: string|nil)
function M.remote_head(cb)
	local dir = M.dir()
	if vim.fn.executable("git") ~= 1 or not vim.uv.fs_stat(dir) then
		cb(nil, "no git clone")
		return
	end
	vim.system({ "git", "-C", dir, "ls-remote", "origin", "HEAD" }, { text = true }, function(r)
		local sha = r.code == 0 and (r.stdout or ""):match("^(%x+)") or nil
		-- Do NOT write `sha and nil or err`: `sha and nil` is nil (falsy), so the or branch
		-- always falls through to err -> a sha was found yet an error is reported. Same and/or trap
		-- noted in build_items ("all_dirs and nil or cwd"). Use an explicit if.
		local err
		if not sha then
			-- Always non-empty: when git fails with an empty stderr there is at least the exit code;
			-- an empty "(github: )" gives nothing to go on.
			err = vim.trim(r.stderr or "")
			if err == "" then
				err = ("exit %d"):format(r.code or -1)
			end
		end
		vim.schedule(function()
			cb(short(sha), err)
		end)
	end)
end

-- Binaries required before installing. Returns the MISSING ones (empty = all present).
function M.missing_deps()
	local miss = {}
	for _, b in ipairs({ "git", "npm" }) do
		if vim.fn.executable(b) ~= 1 then
			miss[#miss + 1] = b
		end
	end
	return miss
end

-- Whether ECC's opencode config pins an Anthropic model.
-- ECC writes ~/.opencode/opencode.json with "model": "anthropic/claude-sonnet-4-5" at both
-- the top level and in ALL 26 agents. opencode really reads this file (measured), so without an
-- Anthropic account a red banner "Agent build's configured model ... is not valid" shows
-- and every command run through an ECC agent breaks. Returns the number of pinned spots.
---@return string|nil path, integer pinned
function M.anthropic_pins(tool)
	if tool ~= "opencode" then
		return nil, 0
	end
	local path = home(".opencode/opencode.json")
	local ok, data = pcall(vim.fn.readfile, path)
	if not ok or not data or #data == 0 then
		return nil, 0
	end
	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	if not ok or type(decoded) ~= "table" then
		return nil, 0
	end
	local n = 0
	for _, k in ipairs({ "model", "small_model" }) do
		if type(decoded[k]) == "string" and decoded[k]:match("^anthropic/") then
			n = n + 1
		end
	end
	for _, a in pairs(type(decoded.agent) == "table" and decoded.agent or {}) do
		if type(a) == "table" and type(a.model) == "string" and a.model:match("^anthropic/") then
			n = n + 1
		end
	end
	if n == 0 then
		return nil, 0
	end
	return path, n
end

-- Shell commands to install/update ECC for the tool. Safe to re-run (clone -> pull).
-- Returns the EXACT strings that will run, unabridged: the confirm box shows this list verbatim.
---@param tool string
---@return string[]|nil, string|nil  -- steps, reason when unsupported
function M.steps(tool)
	local d = vim.fn.shellescape(M.dir())
	local repo = vim.fn.shellescape(M.config.repo)
	local prof = vim.fn.shellescape(M.config.profile)
	local steps = {
		-- Put the path in a $D variable instead of repeating it 4 times: the picker preview does
		-- not wrap, and a 200-char line is unreadable. What runs is exactly what is shown.
		("D=%s"):format(d),
		('if [ -d "$D/.git" ]; then git -C "$D" pull --ff-only; else git clone --depth 1 %s "$D"; fi'):format(repo),
		'cd "$D" && npm install --no-audit --no-fund',
	}
	local function add(s)
		steps[#steps + 1] = s
	end

	if tool == "claude" then
		add(('cd "$D" && ./install.sh --profile %s --target claude'):format(prof))
		-- ECC is moving to "skills-first", so the installer MAY no longer lay down commands/;
		-- the README lists this cp as an optional compatibility step. Without it an install
		-- ends with 0 commands -> <leader>ai silently falls back to hand-written prompts.
		-- Runs only when the directory is EMPTY: existing commands of yours are left alone.
		add(
			'[ -n "$(ls -A ~/.claude/commands 2>/dev/null)" ] || '
				.. '{ mkdir -p ~/.claude/commands && cp "$D"/commands/*.md ~/.claude/commands/; }'
		)
	elseif tool == "codex" then
		-- Sync is ECC's recommended path for codex; the script makes a timestamped backup
		-- then merges into ~/.codex/AGENTS.md + config.toml. No profile parameter.
		-- It writes ~/.codex/prompts directly, so no link step is needed.
		add('cd "$D" && bash scripts/sync-ecc-to-codex.sh')
	elseif tool == "opencode" then
		-- install-apply.js accepts `--profile <name> --target opencode` for EVERY profile
		-- (usage line 29), so it shares M.config.profile with claude (now = developer).
		-- The README only shows the full example; developer is a valid subset with fewer modules.
		add(('cd "$D" && npm run build:opencode && ./install.sh --profile %s --target opencode'):format(prof))
		-- PATCH ECC'S CONFIG. Two bugs in ~/.opencode/opencode.json, a file opencode really
		-- READS (measured):
		--   1. an Anthropic model hard-pinned at the top level + all 26 agents -> without an
		--      Anthropic account a "configured model ... is not valid" banner shows, and every command
		--      run through an ECC agent breaks. Deleting `model` inherits the model in use.
		--   2. skills.paths = ["../skills"] -> points at ~/skills, which does NOT exist; the real skills
		--      live in ~/.opencode/skills. Write an ABSOLUTE path so it does not depend on how
		--      opencode resolves relative ones.
		-- Uses node (already present because the npm step above needs it), keeps a .bak backup.
		add(table.concat({
			"node -e '",
			'const fs=require("fs"),os=require("os"),f=os.homedir()+"/.opencode/opencode.json";',
			'if(fs.existsSync(f)){fs.copyFileSync(f,f+".bak");',
			'const d=JSON.parse(fs.readFileSync(f,"utf8"));delete d.model;delete d.small_model;',
			"for(const a of Object.values(d.agent||{}))delete a.model;",
			'if(d.skills&&Array.isArray(d.skills.paths))d.skills.paths=[os.homedir()+"/.opencode/skills"];',
			"fs.writeFileSync(f,JSON.stringify(d,null,2))}",
			"'",
		}, ""))
	else
		return nil, ("ECC has no install target for '%s'"):format(tostring(tool))
	end
	return steps
end

-- Where that tool READS commands, shown in the preview/doctor.
function M.source_dirs(tool)
	local out = {}
	for _, s in ipairs(sources(tool)) do
		out[#out + 1] = s.dir
	end
	return out
end

-- Number of commands detected (shown in the <leader>aE status menu).
function M.count(tool)
	return vim.tbl_count(M.commands(tool))
end

-- Account UI lives separately so ECC discovery stays focused.
function M.account_status()
	return require("customize.ai_account").status()
end

function M.setup_account()
	require("customize.ai_account").setup()
end

return M
