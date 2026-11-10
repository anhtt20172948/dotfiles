-- AI terminal (tmux-style): runs Codex / Claude / opencode in a right vsplit.
-- Several sessions per tool (codex-1, codex-2, claude-1...). The <leader>aa picker lists:
--   ● live    sessions running in nvim       -> attach
--    past    OLD on-disk sessions of the cwd -> resume (read from customize.aiterm_history)
--    new     create a new session
--    browse  fallback: the tool's own picker (claude --resume, codex resume)
--
-- Keybindings outside the picker:
--   <C-Space> (in the AI pane) -> back to code (pane stays open, session keeps running)
--   <C-h>/<C-w>h (in the AI pane) -> the code directly to the left, if any
--   <C-j/k>/<C-w>j/k (in the AI pane) -> the pane directly below/above, if any
--   <C-l>/<C-w>l (in the editor) -> the AI pane if it is directly to the right
--   <C-w>p    (in the editor)  -> attach/focus the AI pane (most recent session)
--
-- !! ICONS: this file holds NO raw glyphs, all are built from CODEPOINTS !!
-- Raw PUA glyphs get destroyed every time the file goes through a copy/encode round. It happened twice:
-- U+F0D0 turned into U+EE0D (a codepoint missing from the font -> a box), and the
-- other icons all collapsed into blank spaces. ASCII-only source cannot break
-- that way - see M.icon_sets below.
local M = {}

-- Build a string from a list of codepoints.
local function c(...)
	local out = {}
	for _, cp in ipairs({ ... }) do
		out[#out + 1] = vim.fn.nr2char(cp)
	end
	return table.concat(out)
end

-- Three icon sets, picked with M.config.icon_style:
--   nerd    - Nerd Font glyphs. ONLY codepoints <= U+FFFF (PUA U+E000-U+F8FF):
--             'SFMono Nerd Font' is a Nerd Fonts v2 patch whose cmap stops at U+FD46, so
--             every MDI-v3 glyph like U+F0xxx falls back to another font ->
--             different typeface, different advance width, visibly off.
--   unicode - Geometric Shapes + Arrows, present in almost every monospace font.
--             For terminals/SSH without a Nerd Font.
--   ascii   - pure ASCII, works everywhere including the Linux console.
-- All three sets were checked for nvim_strwidth == 1 per glyph (ambiwidth=single), so
-- switching sets never shifts columns.
M.icon_sets = {
	nerd = {
		claude = c(0xF0D0), -- magic
		codex = c(0xF121), -- code
		opencode = c(0xF489), -- terminal
		live = c(0x25CF), -- ●
		past = c(0xF1DA), -- history
		new = c(0xF067), -- plus
		browse = c(0xF002), -- search
		install = c(0xF019), -- download
		ecc = c(0xF1B2), -- cube (ECC's skill/command set)
		branch = c(0xF418), -- git-branch
		all_dirs = c(0xF07C), -- folder-open
		-- per-field icons of the preview (f_ = field)
		f_model = c(0xF2DB), -- microchip
		f_tokens = c(0xF1C0), -- database
		f_cost = c(0xF155), -- dollar
		f_updated = c(0xF017), -- clock
		f_created = c(0xF073), -- calendar
		f_version = c(0xF02B), -- tag
		f_agent = c(0xF007), -- user
		f_id = c(0xF292), -- hashtag
		f_cwd = c(0xF07B), -- folder
		f_prompt = c(0xF075), -- comment
		f_cmd = c(0xF120), -- terminal
		-- action icons (used in the inlay hint + <leader>ai menu). All classic Font Awesome
		-- U+F0xx (<= U+F0C3), so they are surely in the SFMono NF v2 cmap.
		explain = c(0xF05A), -- info-circle
		ask = c(0xF059), -- question-circle
		fix = c(0xF0AD), -- wrench
		review = c(0xF06E), -- eye
		tests = c(0xF0C3), -- flask
		refactor = c(0xF021), -- refresh
		docs = c(0xF02D), -- book
		security = c(0xF132), -- shield
		plan = c(0xF0AE), -- tasks
		quality = c(0xF14A), -- check-square
		star = c(0xF005), -- fa-star (favorites/pin)
	},
	-- The "works everywhere" set: EVERY codepoint below was checked to exist in BOTH SFMono NF and
	-- JetBrainsMono NF. Careful when changing: nvim_strwidth returns 1 even for a glyph the font
	-- LACKS (it only consults Unicode width tables, not the cmap), so measuring strwidth
	-- is NOT enough. The previous version had 5 icons missing from the font for exactly this reason:
	-- ◆ U+25C6, ◼ U+25FC, ↺ U+21BA, ↳ U+21B3, ▤ U+25A4 are all MISSING from SFMono.
	unicode = {
		claude = c(0x25CE), -- ◎
		codex = c(0x25A1), -- □
		opencode = c(0x25B2), -- ▲
		live = c(0x25CF), -- ●
		past = c(0x2022), -- •
		new = "+",
		browse = c(0x00BB), -- »
		-- NOT U+26A0 warning: checked MISSING from SFMono NF.
		install = c(0x2193), -- ↓
		ecc = c(0x2318), -- ⌘
		branch = "*", -- git usually marks the current branch with *
		all_dirs = c(0x00A4), -- ¤
		-- Preview fields already have a TEXT LABEL next to them, so the icon is just a leader:
		-- one shared neutral character beats inventing 11 cryptic symbols.
		f_model = c(0x00B7), -- ·
		f_tokens = c(0x00B7),
		f_cost = c(0x00B7),
		f_updated = c(0x00B7),
		f_created = c(0x00B7),
		f_version = c(0x00B7),
		f_agent = c(0x00B7),
		f_id = c(0x00B7),
		f_cwd = c(0x00B7),
		f_prompt = c(0x00B7),
		f_cmd = c(0x203A), -- ›
		explain = c(0x00A7), -- §
		ask = "?",
		fix = c(0x00B1), -- ±
		review = c(0x25CB), -- ○
		tests = c(0x2713), -- ✓
		refactor = c(0x2192), -- →
		docs = c(0x2261), -- ≡
		security = c(0x2020), -- †
		plan = c(0x00B6), -- ¶
		quality = c(0x25A0), -- ■
		star = c(0x2605), -- ★ (width 1 under ambiwidth=single)
	},
	ascii = {
		claude = "C",
		codex = "X",
		opencode = "O",
		live = "*",
		past = "~",
		new = "+",
		browse = "?",
		install = "!",
		ecc = "E",
		branch = "*",
		all_dirs = "/",
		f_model = "-",
		f_tokens = "-",
		f_cost = "-",
		f_updated = "-",
		f_created = "-",
		f_version = "-",
		f_agent = "-",
		f_id = "-",
		f_cwd = "-",
		f_prompt = "-",
		f_cmd = ">",
		explain = "i",
		ask = "?",
		fix = "!",
		review = "o",
		tests = "v",
		refactor = "~",
		docs = "=",
		security = "S",
		plan = "P",
		quality = "Q",
		star = "*",
	},
}

-- Active icon set. "auto" -> follows vim.g.have_nerd_font (unset counts as present).
function M.icons()
	local style = M.config.icon_style
	if style == "auto" or style == nil then
		style = vim.g.have_nerd_font == false and "unicode" or "nerd"
	end
	return M.icon_sets[style] or M.icon_sets.nerd
end

-- A tool's icon, looked up by tool name. Glyphs no longer live in M.config.tools.
local function tool_icon(tool)
	return M.icons()[tool.name] or ""
end

M.config = {
	icon_style = "auto", -- "auto" | "nerd" | "unicode" | "ascii"
	tools = {
		{
			name = "claude",
			cmd = "claude",
			-- nvim's PATH is fixed at startup -> after an install whose target dir is
			-- not on PATH, executable() keeps saying missing until a restart.
			-- path is the fallback so tool_cmd() sees the tool right after the install.
			path = vim.fn.expand("~/.local/bin/claude"),
			install = "curl -fsSL https://claude.ai/install.sh | bash",
			-- icon comes from M.icons()[name], NO glyph stored here (see the top of the file).
			resume = function(id)
				return { "--resume", id }
			end,
			fork = function(id)
				return { "--resume", id, "--fork-session" }
			end,
			-- the prompt is passed AT launch -> M.send does not paste into a TUI that is still
			-- booting (see M.send). claude: positional, still interactive.
			prompt_args = function(text)
				return { text }
			end,
			browse = { "--resume" }, -- claude's own interactive picker
			browse_label = "claude's own picker",
		},
		{
			name = "codex",
			cmd = "codex",
			path = vim.fn.expand("~/.local/bin/codex"),
			install = "curl -fsSL https://chatgpt.com/codex/install.sh | sh",
			-- icon comes from M.icons()[name], NO glyph stored here (see the top of the file).
			resume = function(id)
				return { "resume", id }
			end,
			fork = function(id)
				return { "fork", id }
			end,
			prompt_args = function(text) -- codex: positional [PROMPT]
				return { text }
			end,
			browse = { "resume" },
			browse_label = "codex's own picker",
		},
		{
			name = "opencode",
			cmd = "opencode",
			-- ~/.zshrc adds ~/.opencode/bin to PATH, but nvim launched from a GUI/launchd
			-- does not get it -> path is the fallback for tool_cmd(). Measured: nvim's PATH
			-- LACKS ~/.opencode/bin, so opencode alone relies on this path.
			path = vim.fn.expand("~/.opencode/bin/opencode"),
			install = "curl -fsSL https://opencode.ai/install | bash",
			-- icon comes from M.icons()[name], NO glyph stored here (see the top of the file).
			resume = function(id)
				return { "--session", id }
			end,
			fork = function(id)
				return { "--session", id, "--fork" }
			end,
			prompt_args = function(text) -- opencode: via a flag, not positional
				return { "--prompt", text }
			end,
			-- opencode has NO CLI picker (only `session list|delete`) -> the fallback is --continue
			browse = { "--continue" },
			browse_label = "resume most recent",
		},
	},
	win = { width = 0.4 }, -- width ratio of the vsplit
	start_insert = true,
	history = { scope = "cwd" }, -- default picker scope: "cwd" | "all"

	-- Send context (file/selection + instruction) to the running session. See M.actions().
	--   default_tools - PRIORITY LIST when there is NO live session yet: the first INSTALLED
	--                   tool wins. Overridden per session/persistently via M.set_default_tool (<leader>aD).
	--   ready         - detects that a just-created session is "ready" (terminal drawn + quiet)
	--                   before the first send, instead of a fixed delay (which often lost requests).
	--                   min_ms boot floor, quiet_ms how long quiet counts as done, max_ms
	--                   fallback ceiling, interval_ms poll period.
	--   submit_delay  - ms between finishing the paste and sending <CR>; gives the TUI (claude's
	--                   Ink/React) time to process the bracketed paste before Enter submits.
	send = {
		default_tools = { "codex", "opencode", "claude" },
		-- Above this size the message no longer fits in argv -> fall back to the
		-- create-session-then-paste path. macOS ARG_MAX is 1048576; 344 lines of code
		-- are only ~15KB, so this is rarely hit.
		max_arg_bytes = 100000,
		-- ONLY for the FALLBACK path (pasting into a booting session). The main path is
		-- tool.prompt_args: the prompt is embedded in the launch command, so there is no race.
		-- Do not mistake this for the main mechanism and tune the numbers: a quiescence heuristic
		-- fundamentally cannot tell "TUI is done" from "quiet mid-boot" - exactly the
		-- bug that lost requests with opencode.
		ready = { min_ms = 800, quiet_ms = 1200, max_ms = 10000, interval_ms = 120 },
		submit_delay = 120,
		-- Tools that RUN ECC /slash commands natively. codex 0.146 does NOT expand
		-- ~/.codex/prompts/*.md into /commands (measured: "Unrecognized command"; ECC's own
		-- CODEX-NAVIGATION-GUIDE also says "may not execute slash commands
		-- natively ... read the command file"). false -> M.workflows() PASTES THE CONTENT of the
		-- command file instead of the /token. Tools missing from the table count as native.
		slash_native = { claude = true, opencode = true, codex = false },
	},

	-- SECOND skill source (besides ECC): the vercel-labs/skills CLI (`npx skills add`). It installs
	-- SKILL.md into the exact dirs aiterm scans -> shows up in <leader>aS (origin=user).
	-- Xem M.skills_add() (<leader>aV).
	--   sources  - suggested seed list in the picker; the picker adds an "Enter source…" free-input entry.
	--   scope    - "global" -> -g flag (shared by every repo); "project" -> into the repo.
	--   copy     - --copy: copy real files (self-contained) instead of symlinking into the CLI cache.
	--   agent_id - maps aiterm tool names -> the CLI's --agent id (claude vs claude-code).
	skills = {
		-- Seed sources for developers (verified on skills.sh). The picker shows "src - desc"
		-- plus an "Enter source…" entry for any owner/repo or URL.
		sources = {
			{ src = "mattpocock/skills", desc = "TDD, code-review, git-guardrails, debugging" },
			{ src = "anthropics/skills", desc = "skill-creator, webapp-testing, mcp-builder, docs" },
			{ src = "vercel-labs/agent-skills", desc = "React/Next best-practices, composition" },
			{ src = "prisma/skills", desc = "Prisma ORM: setup, client, cli, postgres" },
			{ src = "supabase/agent-skills", desc = "Supabase / Postgres best practices" },
		},
		registry = "https://skills.sh", -- where skills are discovered (skills find queries it)
		scope = "global", -- -g: shared by every repo
		copy = true, -- --copy: copy real files (self-contained)
		agent_id = { claude = "claude-code", codex = "codex", opencode = "opencode" },
	},

	-- Treesitter nodes treated as a "code block" to use as context in normal mode. Matched
	-- by type SUBSTRING, so it covers many languages without a per-language
	-- query (function_declaration, method_definition, class_specifier, struct_specifier...).
	ts_node_types = { "function", "method", "class", "struct", "constructor", "impl" },

	-- Inlay hint on code buffers (CodeCompanion-style code lens): 1 virtual line above
	-- the function/class CONTAINING the cursor. Badge = icon+name of the default tool (colored
	-- per tool) + a few actions with icons + dimmed shortcuts. actions is the list of action.key
	-- to advertise; icons come from M.icons(), so they degrade to text in the unicode/ascii styles.
	hints = {
		enabled = false,
		actions = { "explain", "fix", "tests" },
		key = "<leader>ai",
	},

	-- Presets for the M.actions() picker. `key` matches an icon in M.icons() (shown in the
	-- menu + hint). `prompt` is the fixed instruction; `input` (if set) asks a free-form question
	-- via vim.fn.input and uses it instead of prompt.
	--
	-- `skill` (optional) is the ECC SKILL matching the job. On send it is looked up on disk
	-- (aiterm_ecc.skills): when present a "Follow the `x` skill." line is added, otherwise
	-- the plain `prompt` is sent as before. The message still carries @ref + the code block.
	--
	-- Why NOT ECC commands here: commands are REPO-LEVEL workflows -
	-- /code-review runs `git diff --name-only HEAD`, /build-fix runs `npx tsc --noEmit`,
	-- /refactor-clean runs `npx knip` - they ignore the selected code entirely.
	-- They live in M.workflows() (<leader>aw), which sends without context.
	--
	-- Why only 3 actions have a `skill`: all 207 skill descriptions were read, none fits
	-- "explain this" / "review this" / "write a docstring". code-tour creates a .tour
	-- file, plankton-code-quality runs a formatter on write, plan-canvas opens a
	-- plan in the browser. A forced match only makes the prompt worse.
	actions = {
		{ key = "explain", label = "Explain", prompt = "Explain what this code does, step by step." },
		{ key = "ask", label = "Ask a question", input = "Ask about this code: " },
		{ key = "fix", label = "Fix bugs", prompt = "Find and fix any bugs in this code. Explain the fix." },
		{
			key = "review",
			label = "Review",
			prompt = "Review this code for correctness, edge cases, and style issues.",
		},
		{
			key = "tests",
			label = "Write tests",
			prompt = "Write tests for this code.",
			skill = "tdd-workflow",
		},
		{
			key = "refactor",
			label = "Refactor",
			prompt = "Refactor this code to be clearer and more idiomatic, without changing its behavior.",
		},
		{ key = "docs", label = "Add docs", prompt = "Add documentation/docstrings to this code." },
		{
			key = "security",
			label = "Security scan",
			prompt = "Audit this code for security vulnerabilities. Report severity and a fix for each.",
			skill = "security-review",
		},
		{
			key = "plan",
			label = "Plan",
			prompt = "Write an implementation plan for a change to this code. Do not write code yet.",
		},
		{
			key = "quality",
			label = "Quality gate",
			prompt = "Run the quality checks for this code: lint, types, tests. Report what fails.",
			skill = "verification-loop",
		},
	},

	-- Exceptions when sending ECC commands from M.workflows(). Default sends a plain "/name".
	--   path - commands taking a path (`/quality-gate [path|.]`) -> append "."
	--   ask  - commands taking free text via $ARGUMENTS -> ask with vim.fn.input
	workflow_args = {
		path = { "quality-gate", "security-scan" },
		ask = { plan = "Plan what? ", ["plan-prd"] = "PRD for: ", tdd = "TDD for: " },
	},
}

-- state ------------------------------------------------------------------
local win = nil -- shared vsplit handle (one pane, buffers swapped)
local sessions = {} -- array: { id, tool, buf, job, cwd, title, label }
local counters = {} -- tool.name -> counter for ids
local last_session = nil -- id of the most recently attached session

local function history()
	return require("customize.aiterm_history")
end

-- The ECC module is OPTIONAL: when missing/broken remember the error and return nil (no re-probe each time).
-- Every caller degrades to "no ECC" instead of breaking the picker/doctor.
local ecc_mod, ecc_err
local function ecc()
	if ecc_mod or ecc_err then
		return ecc_mod
	end
	-- pcall returns (ok, result) - assigning straight to (ecc_mod, ecc_err) leaves ecc_mod as the
	-- boolean `true`, and every caller then indexes a boolean. Keep two variables.
	local ok, mod = pcall(require, "customize.aiterm_ecc")
	if ok then
		ecc_mod = mod
	else
		ecc_err = true
	end
	return ecc_mod
end

-- helpers ----------------------------------------------------------------
local function win_valid()
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

-- 0.11-safe: prefer jobstart{term=true}, fall back to termopen on older versions.
-- cmd is a LIST (no shell) -> session ids / paths with spaces or quotes are safe.
local function start_term(buf, cmd, cwd)
	return vim.api.nvim_buf_call(buf, function()
		local o = { term = true, cwd = cwd }
		if vim.fn.has("nvim-0.11") == 1 then
			return vim.fn.jobstart(cmd, o)
		end
		return vim.fn.termopen(cmd, o)
	end)
end

local function find_tool(name)
	for _, t in ipairs(M.config.tools) do
		if t.name == name then
			return t
		end
	end
end

-- Binary on PATH; otherwise try tool.path (see the opencode comment).
local function tool_cmd(tool)
	if vim.fn.executable(tool.cmd) == 1 then
		return tool.cmd
	end
	if tool.path and vim.fn.executable(tool.path) == 1 then
		return tool.path
	end
	return nil
end

-- Terminal mode: <C-Space> (and the <C-@>/<Nul> aliases kitty sometimes sends) returns to
-- code. The rhs is noremap, so <C-w>p here is the builtin previous-window (back to code),
-- NOT the global <C-w>p map again. <Esc>/<Space> pass straight to the AI app;
-- a lone <C-w> still reaches the app after timeoutlen since only <C-w>h sequences are mapped.
local function set_term_keymaps(buf)
	local o = { buffer = buf, silent = true, nowait = true }
	vim.keymap.set("t", "<C-Space>", [[<C-\><C-n><C-w>p]], o)
	vim.keymap.set("t", "<C-@>", [[<C-\><C-n><C-w>p]], o)
	local function focus_direction(direction)
		local current = vim.api.nvim_get_current_win()
		local target = vim.fn.win_getid(vim.fn.winnr(direction))
		if target == current then
			return -- no pane in that direction: stay in terminal mode
		end
		vim.cmd("stopinsert")
		vim.api.nvim_set_current_win(target)
	end
	for _, direction in ipairs({ "h", "j", "k" }) do
		local d = direction
		local function focus()
			focus_direction(d)
		end
		vim.keymap.set("t", "<C-" .. d .. ">", focus, { buffer = buf, silent = true })
		vim.keymap.set("t", "<C-w>" .. d, focus, { buffer = buf, silent = true })
	end
end

local function is_alive(s)
	return s ~= nil and s.buf and vim.api.nvim_buf_is_valid(s.buf) and s.job and vim.fn.jobwait({ s.job }, 0)[1] == -1
end

local function find(id)
	for _, s in ipairs(sessions) do
		if s.id == id then
			return s
		end
	end
end

local function remove_session(id)
	for i, s in ipairs(sessions) do
		if s.id == id then
			table.remove(sessions, i)
			return
		end
	end
end

local function notify(msg, level)
	if _G.Snacks and Snacks.notifier then
		Snacks.notifier.notify(msg, level, { title = "AI terminal" })
	else
		vim.notify(msg, vim.log.levels[level:upper()] or vim.log.levels.INFO)
	end
end

-- window (right vsplit) ---------------------------------------------------
local function open_split(buf)
	vim.cmd("botright vsplit") -- full-height pane on the right edge
	win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * M.config.win.width))
	vim.wo[win].winfixwidth = true -- opening neo-tree does not squeeze the AI pane
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
end

-- Reuse the pane (swap buffer) if it still exists; otherwise open a new split. Updates the winbar label.
local function ensure_win(buf, label)
	if win_valid() then
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_set_current_win(win)
	else
		open_split(buf)
	end
	pcall(function()
		vim.wo[win].winbar = "%=" .. label .. "%="
	end)
end

-- session lifecycle ------------------------------------------------------

-- Session ids stay "<tool>-<n>": a 36-char uuid is unusable as a buffer name / winbar.
-- The human-readable part lives in session.label (winbar) and session.title.
---@param tool table
---@param opts? { args?: string[], cwd?: string, title?: string, cmd?: string[], real_id?: string, on_exit?: fun(code:number) }
local function new_session(tool, opts)
	opts = opts or {}

	-- jobstart throws E475 when cwd does not exist (an old session of a deleted repo).
	local cwd = opts.cwd
	if cwd and not vim.uv.fs_stat(cwd) then
		notify(("cwd no longer exists: %s"):format(cwd), "warn")
		cwd = nil
	end

	-- opts.cmd: arbitrary argv, SKIPS tool_cmd and the binary-not-found guard. Only
	-- for install (when the tool's binary naturally does not exist yet).
	local cmd
	if opts.cmd then
		cmd = opts.cmd
	else
		local exe = tool_cmd(tool)
		if not exe then
			notify(("binary '%s' not found in PATH"):format(tool.cmd), "warn")
			return nil
		end
		cmd = { exe }
		vim.list_extend(cmd, opts.args or {})
	end

	counters[tool.name] = (counters[tool.name] or 0) + 1
	local id = tool.name .. "-" .. counters[tool.name]

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide"
	local ok, job = pcall(start_term, buf, cmd, cwd)
	if not ok or type(job) ~= "number" or job <= 0 then
		notify(("failed to start: %s"):format(table.concat(cmd, " ")), "error")
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return nil
	end
	pcall(vim.api.nvim_buf_set_name, buf, "aiterm://" .. id)

	local session = {
		id = id,
		tool = tool,
		buf = buf,
		job = job,
		cwd = cwd,
		title = opts.title,
		-- real_id: the session's REAL on-disk id (uuid/thread). Resume knows it up front
		-- (set via opts.real_id); a just-created session (new/fork/browse) leaves it nil until
		-- build_items finds it in history and pins it. Used to drop duplicate past entries.
		real_id = opts.real_id,
		-- launch_time (epoch seconds, same unit as history's e.time): the anchor for
		-- build_items to match a history entry <=> this very session.
		launch_time = os.time(),
		label = tool_icon(tool) .. " " .. id .. (opts.title and (" · " .. opts.title) or ""),
	}
	sessions[#sessions + 1] = session
	-- set_term_keymaps here -> every path (new/resume/fork/browse) gets <C-Space>.
	set_term_keymaps(buf)
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = buf,
		callback = function()
			if M.config.start_insert and is_alive(session) and vim.api.nvim_get_current_buf() == buf then
				vim.cmd("startinsert")
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		once = true,
		callback = function()
			remove_session(id)
			if opts.on_exit then
				-- vim.v.event.status = exit code of the process that just ended.
				opts.on_exit(tonumber(vim.v.event.status) or 0)
			end
		end,
	})

	return session
end

local function attach(session)
	if not session then
		return
	end
	ensure_win(session.buf, session.label or (tool_icon(session.tool) .. " " .. session.id))
	last_session = session.id
	if M.config.start_insert then
		vim.cmd("startinsert")
	end
end

-- Install a missing tool. tool.install is a SHELL command (with pipes), so it runs through a shell.
-- It downloads a script from the network and runs it -> ALWAYS show the full command and ask
-- for confirmation, defaulting to No: one mis-press in the picker is hard to undo.
-- Runs in the AI pane (not in the background) so output and errors can be read.
local function install_tool(tool)
	if not tool or not tool.install then
		notify(("no install script configured for '%s'"):format(tool and tool.name or "?"), "warn")
		return
	end
	local prompt = ("Install %s?\n\n%s\n\nThis downloads and runs a remote script."):format(tool.name, tool.install)
	if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
		return
	end
	attach(new_session(tool, {
		-- Explicit argv { shell, -c, command } instead of a plain string, to keep
		-- start_term's "cmd is a list" contract.
		cmd = { vim.o.shell, "-c", tool.install },
		cwd = history().project_cwd(),
		title = "install",
		on_exit = function(code)
			if code == 0 then
				notify(("%s installed - reopen the picker to use it"):format(tool.name), "info")
			else
				notify(("%s install failed (exit %d) - see the pane output"):format(tool.name, code), "warn")
			end
		end,
	}))
end

-- Install/update ECC for a tool. Riskier than install_tool: clones a third-party repo,
-- `npm install` runs arbitrary lifecycle scripts, then the installer WRITES into ~/.claude / ~/.codex
-- (the codex sync also edits AGENTS.md + config.toml, with a timestamped backup). So
-- show the WHOLE command list, confirm defaults to No, run in the pane so output can be read.
local function install_ecc(tool)
	if not tool then
		return
	end
	local e = ecc()
	if not e then
		notify("ECC module unavailable - cannot install", "warn")
		return
	end
	local steps, why = e.steps(tool.name)
	if not steps then
		notify(why or "ECC install not supported here", "warn")
		return
	end
	local miss = e.missing_deps()
	if #miss > 0 then
		notify(("ECC needs %s on PATH - install %s first"):format(table.concat(miss, " + "), miss[1]), "warn")
		return
	end

	local lines = { ("Install ECC for %s?"):format(tool.name), "" }
	vim.list_extend(lines, steps)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "This clones a third-party repo and runs its installer."
	if tool.name == "codex" then
		-- No silent change: codex's sync path generates prompts from ALL of commands/, without
		-- a profile filter -> codex gets every command whatever M.config.profile is.
		lines[#lines + 1] = "Note: codex sync copies ALL commands (profile does not apply)."
	end
	if vim.fn.confirm(table.concat(lines, "\n"), "&Yes\n&No", 2) ~= 1 then
		return
	end

	attach(new_session(tool, {
		cmd = { vim.o.shell, "-c", table.concat(steps, " && ") },
		cwd = history().project_cwd(),
		title = "ecc",
		on_exit = function(code)
			e.refresh() -- re-scan disk: the picker row disappears, actions start using /command
			if code == 0 then
				notify(("ECC installed for %s (%d commands)"):format(tool.name, e.count(tool.name)), "info")
			else
				notify(("ECC install failed (exit %d) - see the pane output"):format(code), "warn")
			end
		end,
	}))
end

-- vercel-labs/skills CLI (`npx skills add/find/use/init`) --------------------
-- The CLI keeps NO source/lockfile -> aiterm records provenance itself (diff of the skill dir
-- before/after add) so <leader>aS can show "which source this skill came from".
local function xdg_config()
	local x = vim.env.XDG_CONFIG_HOME
	return (x and x ~= "") and x or vim.fn.expand("~/.config")
end

-- "Universal" dir the vercel skills CLI often writes to; claude/codex/opencode do NOT read it.
-- M.skills_activate() symlinks from here into the tool's real dir.
local AGENTS_SKILLS = vim.fn.expand("~/.agents/skills")

local function have_npx()
	if vim.fn.executable("npx") == 1 then
		return true
	end
	notify("aiterm: `npx` not on PATH (Node is needed) to run the skills CLI", "warn")
	return false
end

-- Tool used to label the pane for find/init (the real command is npx, tool-independent):
-- prefer a live session, else the first tool.
local function pane_tool()
	for _, s in ipairs(sessions) do
		if is_alive(s) then
			return s.tool
		end
	end
	return M.config.tools[1]
end

-- Dir the vercel skills CLI writes to for (tool, scope) - matches the CLI's path table.
local function skills_target_dir(tool, scope, cwd)
	local name = tool.name
	if scope == "project" then
		local p = {
			claude = cwd .. "/.claude/skills",
			codex = cwd .. "/.agents/skills",
			opencode = cwd .. "/.agents/skills",
		}
		return p[name]
	end
	local g = {
		claude = vim.fn.expand("~/.claude/skills"),
		codex = vim.fn.expand("~/.codex/skills"),
		opencode = xdg_config() .. "/opencode/skills",
	}
	return g[name]
end

-- Skill names (subdirectories) in a skills dir - the basis for the diff.
local function skill_dir_names(dir)
	local set = {}
	if not dir then
		return set
	end
	local ok, it = pcall(vim.fs.dir, dir)
	if not ok then
		return set
	end
	for n, kind in it do
		if kind == "directory" then
			set[n] = true
		end
	end
	return set
end

-- provenance: tool -> { skillName -> { source, scope } }. Persisted across nvim runs.
local skill_src = {}
local function skill_src_file()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "aiterm-skill-sources.json")
end
local function load_skill_src()
	local ok, lines = pcall(vim.fn.readfile, skill_src_file())
	if not ok or not lines or #lines == 0 then
		return
	end
	local ok2, d = pcall(vim.json.decode, table.concat(lines, "\n"))
	if ok2 and type(d) == "table" then
		skill_src = d
	end
end
local function save_skill_src()
	pcall(vim.fn.writefile, { vim.json.encode(skill_src) }, skill_src_file())
end
-- Provenance of 1 skill (nil when it was not added by aiterm).
local function skill_source(tool, name)
	return (skill_src[tool] or {})[name]
end

-- Record provenance for skills that NEWLY appear in the dir after add.
local function record_new_skills(tname, dir, before, source, scope)
	local after = skill_dir_names(dir)
	skill_src[tname] = skill_src[tname] or {}
	local n = 0
	for name in pairs(after) do
		if not before[name] then
			skill_src[tname][name] = { source = source, scope = scope }
			n = n + 1
		end
	end
	if n > 0 then
		save_skill_src()
	end
	return n
end

-- add: confirm -> run `npx skills add` in the pane (the skill selection TUI is interactive,
-- so NO -y) -> on_exit records provenance + refreshes the ECC cache.
function M.skills_add()
	if not have_npx() then
		return
	end
	local cfg = M.config.skills
	-- items: each source is {src,desc}; plus an {enter=true} sentinel.
	local items = {}
	for _, s in ipairs(cfg.sources or {}) do
		items[#items + 1] = s
	end
	items[#items + 1] = { enter = true }
	vim.ui.select(items, {
		prompt = "Skills source:",
		format_item = function(it)
			if it.enter then
				return "Enter source…"
			end
			return it.src .. "  —  " .. (it.desc or "")
		end,
	}, function(it)
		if not it then
			return
		end
		local src
		if it.enter then
			src = vim.fn.input("owner/repo or URL: ")
			if src == "" then
				return
			end
		else
			src = it.src
		end
		local names = {}
		for _, t in ipairs(M.config.tools) do
			names[#names + 1] = t.name
		end
		vim.ui.select(names, { prompt = "Install skills into which tool?" }, function(tname)
			if not tname then
				return
			end
			local tool = find_tool(tname)
			if not tool then
				return
			end
			local agent = (cfg.agent_id or {})[tname] or tname
			local argv = { "npx", "skills", "add", src, "-a", agent }
			if cfg.scope == "global" then
				argv[#argv + 1] = "-g"
			end
			if cfg.copy then
				argv[#argv + 1] = "--copy"
			end
			local prompt = ("Run: %s\n\nDownload & install third-party skills into %s (scope %s)."):format(
				table.concat(argv, " "),
				tname,
				cfg.scope
			)
			if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
				return
			end
			-- snapshot the target dir BEFORE installing to diff out the new skills.
			local dir = skills_target_dir(tool, cfg.scope, history().project_cwd())
			local before = skill_dir_names(dir)
			attach(new_session(tool, {
				cmd = argv,
				cwd = history().project_cwd(),
				title = "skills add",
				on_exit = function()
					local added = record_new_skills(tname, dir, before, src, cfg.scope)
					local e = ecc()
					if e then
						e.refresh() -- new skills show up in <leader>aS
					end
					notify(("skills add: +%d skill(s) from %s -> %s"):format(added, src, tname), "info")
				end,
			}))
		end)
	end)
end

-- find: `npx skills find [query]` - fzf TUI to discover skills (skills.sh + GitHub) in the pane.
function M.skills_find()
	if not have_npx() then
		return
	end
	local q = vim.fn.input("skills find (query, empty = browse): ")
	local argv = { "npx", "skills", "find" }
	if q ~= "" then
		argv[#argv + 1] = q
	end
	attach(new_session(pane_tool(), {
		cmd = argv,
		cwd = history().project_cwd(),
		title = "skills find",
		on_exit = function()
			local e = ecc()
			if e then
				e.refresh()
			end
		end,
	}))
end

-- use: `npx skills use <source[@skill]>` generates a prompt (does NOT install) and sends it
-- to the AI session.
-- Runs via vim.system (no TTY), so @skill SHOULD be given; a timeout prevents hangs.
function M.skills_use()
	if not have_npx() then
		return
	end
	local cfg = M.config.skills
	local first = cfg.sources and cfg.sources[1]
	local default = type(first) == "table" and first.src or (first or "")
	local spec = vim.fn.input({ prompt = "skills use source[@skill]: ", default = default })
	if spec == "" then
		return
	end
	notify(("skills use: resolving %s…"):format(spec), "info")
	vim.system(
		{ "npx", "skills", "use", spec },
		{ text = true, timeout = 60000 },
		vim.schedule_wrap(function(r)
			local out = r.stdout and vim.trim(r.stdout) or ""
			if r.code ~= 0 or out == "" then
				local why = (r.stderr and vim.trim(r.stderr) ~= "") and vim.trim(r.stderr)
					or ("exit " .. tostring(r.code))
				notify(("skills use failed (%s) - try adding @skill"):format(why), "warn")
				return
			end
			M.send(r.stdout, { submit = true })
		end)
	)
end

-- init: `npx skills init [name]` scaffolds a SKILL.md in the repo (project-level skill).
function M.skills_init()
	if not have_npx() then
		return
	end
	local name = vim.fn.input("new skill name (empty = current directory): ")
	local argv = { "npx", "skills", "init" }
	if name ~= "" then
		argv[#argv + 1] = name
	end
	attach(new_session(pane_tool(), {
		cmd = argv,
		cwd = history().project_cwd(),
		title = "skills init",
	}))
end

-- Skill names (subdirectories with a SKILL.md) in ~/.agents/skills.
local function agents_skill_names()
	local out = {}
	local ok, it = pcall(vim.fs.dir, AGENTS_SKILLS)
	if not ok then
		return out
	end
	for n, kind in it do
		if (kind == "directory" or kind == "link") and vim.uv.fs_stat(AGENTS_SKILLS .. "/" .. n .. "/SKILL.md") then
			out[#out + 1] = n
		end
	end
	return out
end

-- Symlink ~/.agents/skills/<name> -> <the tool's real global skill dir>/<name> so the tool
-- can READ it. Returns "ok" | "exists" | "error". Idempotent.
local function activate_skill(tool, name)
	local dst = skills_target_dir(tool, "global") .. "/" .. name
	if vim.uv.fs_stat(dst) then
		return "exists"
	end
	vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
	local ok = vim.uv.fs_symlink(AGENTS_SKILLS .. "/" .. name, dst)
	return ok and "ok" or "error"
end

-- Activate a 'shared' skill (~/.agents/skills) into the tool's real dir: pick a skill (or
-- all) + tool -> symlink. Afterwards the skill shows scope=global and the tool reads it.
function M.skills_activate()
	local names = agents_skill_names()
	if #names == 0 then
		notify("~/.agents/skills is empty - no skill to activate", "info")
		return
	end
	local ALL = "★ all"
	local choices = { ALL }
	vim.list_extend(choices, names)
	vim.ui.select(choices, { prompt = "Activate shared skill:" }, function(pick)
		if not pick then
			return
		end
		local toolnames = {}
		for _, t in ipairs(M.config.tools) do
			toolnames[#toolnames + 1] = t.name
		end
		vim.ui.select(toolnames, { prompt = "Activate into which tool?" }, function(tn)
			if not tn then
				return
			end
			local tool = find_tool(tn)
			if not tool then
				return
			end
			local list = pick == ALL and names or { pick }
			local ok = 0
			for _, n in ipairs(list) do
				if activate_skill(tool, n) ~= "error" then
					ok = ok + 1
				end
			end
			local e = ecc()
			if e then
				e.refresh()
			end
			notify(("activated %d skill(s) -> %s (open <leader>aS)"):format(ok, tn), "info")
		end)
	end)
end

-- Menu skills (<leader>aV): Add / Find / Use / Init / Activate / Browse.
function M.skills()
	vim.ui.select({
		{ k = "add", label = "Add skills…" },
		{ k = "find", label = "Find / discover…" },
		{ k = "use", label = "Use one-off (send to session)…" },
		{ k = "init", label = "Init new skill…" },
		{ k = "activate", label = "Activate shared (~/.agents/skills)…" },
		{ k = "browse", label = "Browse installed  (<leader>aS)" },
	}, {
		prompt = "Skills:",
		format_item = function(a)
			return a.label
		end,
	}, function(c)
		if not c then
			return
		end
		local fn = ({
			add = M.skills_add,
			find = M.skills_find,
			use = M.skills_use,
			init = M.skills_init,
			activate = M.skills_activate,
			browse = M.skill_pick,
		})[c.k]
		if fn then
			fn()
		end
	end)
end

-- codex archive CAN be undone (codex unarchive); opencode session delete and deleting
-- claude's jsonl file can NOT -> the caller must confirm before calling.
local function delete_entry(tool, e)
	local exe = tool_cmd(tool)
	if tool.name == "codex" then
		return exe ~= nil and vim.system({ exe, "archive", e.id }, { text = true }):wait(5000).code == 0
	elseif tool.name == "opencode" then
		return exe ~= nil and vim.system({ exe, "session", "delete", e.id }, { text = true }):wait(5000).code == 0
	elseif e.jsonl then
		return vim.fn.delete(e.jsonl) == 0 -- claude has no CLI delete
	end
	return false
end

-- picker -----------------------------------------------------------------
-- hl group per kind; glyphs come from M.icons() at render time (not hardcoded).
local KIND_HL = {
	live = "SnacksPickerGitStatusStaged",
	past = "SnacksPickerTime",
	new = "SnacksPickerLabel",
	browse = "SnacksPickerSpecial",
	install = "DiagnosticWarn", -- amber, distinct from every other color on the line
	ecc = "SnacksPickerSpecial", -- not a warning: the tool works fine without ECC
}

-- Left tool column: "opencode" (8) + icon (1) + space (1) = 10, plus 1 padding column.
local TOOL_W = 11
-- Line prefix before the title: kind icon (2 cols) + tool column + 1 padding column.
local LEAD_W = 2 + TOOL_W + 1

-- One color per tool. LINKS to semantic groups instead of hardcoded hex:
-- switching colorscheme follows the new theme automatically.
-- Constant/String/Keyword keep their semantic role across light and dark palettes.
local TOOL_HL = { claude = "AitermClaude", codex = "AitermCodex", opencode = "AitermOpencode" }

-- Snacks.util.set_hl registers its own ColorScheme augroup to re-apply, so NO custom
-- autocmd is needed. No default = true (a `default` group gets overridden by colorschemes).
-- Called lazily because Snacks may not be loaded when this module is required.
local hl_done = false
local function ensure_hl()
	if hl_done or not (_G.Snacks and Snacks.util) then
		return
	end
	hl_done = true
	Snacks.util.set_hl({
		AitermClaude = "Constant", -- peach
		AitermCodex = "String", -- mint
		AitermOpencode = "Keyword", -- mauve
	})
end

local function cmdline(tool, args)
	local parts = { tool.cmd }
	vim.list_extend(parts, args or {})
	return table.concat(parts, " ")
end

-- 22017 -> "22,017"
local function commafy(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Preview builder: each line is "<icon> <aligned label> <value>", with extmarks
-- coloring icon + label. snacks takes item.preview.extmarks (picker/preview.lua) with
-- 1-indexed rows and 0-indexed BYTE cols.
local LABEL_W = 9

local function new_doc()
	return { lines = {}, marks = {} }
end

local function doc_raw(d, text)
	d.lines[#d.lines + 1] = text or ""
end

-- Skip the line entirely when value is empty -> fields a tool lacks are hidden, never
-- faked as "n/a". col uses #s (bytes), not strwidth: icons are multibyte.
local function doc_row(d, icon, label, value, icon_hl)
	if value == nil or value == "" then
		return
	end
	local ic = M.icons()[icon] or " "
	local pad = string.rep(" ", math.max(1, LABEL_W - vim.api.nvim_strwidth(label)))
	local line = (" %s %s%s%s"):format(ic, label, pad, value)
	d.lines[#d.lines + 1] = line
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 1, end_col = 1 + #ic, hl_group = icon_hl or "SnacksPickerSpecial" }
	d.marks[#d.marks + 1] = { row = row, col = 2 + #ic, end_col = 2 + #ic + #label, hl_group = "SnacksPickerDimmed" }
end

local function doc_title(d, icon, text, icon_hl)
	local ic = M.icons()[icon] or " "
	d.lines[#d.lines + 1] = (" %s %s"):format(ic, text)
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 1, end_col = 1 + #ic, hl_group = icon_hl or "SnacksPickerSpecial" }
	d.marks[#d.marks + 1] = { row = row, col = 2 + #ic, end_col = #d.lines[row], hl_group = "SnacksPickerBold" }
end

local function doc_section(d, icon, text)
	doc_raw(d, "")
	local ic = M.icons()[icon] or " "
	d.lines[#d.lines + 1] = (" %s %s"):format(ic, text)
	local row = #d.lines
	d.marks[#d.marks + 1] = { row = row, col = 0, end_col = #d.lines[row], hl_group = "SnacksPickerLabel" }
end

-- Indented text block (prompt, description). Takes a list of lines or a string.
local function doc_block(d, text, hl)
	local lines = type(text) == "table" and text or vim.split(tostring(text), "\n", { plain = true })
	for _, s in ipairs(lines) do
		d.lines[#d.lines + 1] = "    " .. s
		d.marks[#d.marks + 1] =
			{ row = #d.lines, col = 0, end_col = #d.lines[#d.lines], hl_group = hl or "SnacksPickerCode" }
	end
end

local function doc_done(d)
	return { text = table.concat(d.lines, "\n"), extmarks = d.marks }
end

-- Preview built inside the finder (data already in RAM from discovery)
-- -> the 5 MB jsonl is not re-read while the cursor moves.
-- Label + color + verb per ECC status. For "current", <CR> REINSTALLS rather than
-- updates; say so, so nobody spends minutes re-running the process thinking there is
-- work to do.
local ECC_STATE = {
	current = { "up to date", "SnacksPickerGitStatusStaged", "reinstall" },
	outdated = { "OUTDATED", "DiagnosticWarn", "update" },
	missing = { "not installed", "SnacksPickerDimmed", "install" },
	unknown = { "unknown", "SnacksPickerDimmed", "reinstall" },
}

-- Preview for M.ecc. Takes clone/remote as parameters instead of reading them: the finder calls it
-- many times, and clone_info() spawns git - re-reading per row is wasteful.
local function ecc_preview(item, e, clone, remote)
	local d = new_doc()
	local s = ECC_STATE[item.state] or ECC_STATE.unknown
	local i = item.info
	doc_title(d, "ecc", ("ECC · %s"):format(item.tool.name), TOOL_HL[item.tool.name])
	doc_row(d, "f_updated", "status", s[1], s[2])
	doc_row(d, "f_version", "version", i and i.version)
	doc_row(d, "f_id", "commit", i and i.short)
	doc_row(d, "f_agent", "profile", i and i.profile)
	doc_row(d, "f_created", "since", i and i.at)
	doc_row(d, "f_cmd", "commands", tostring(item.cmds))
	doc_row(d, "f_prompt", "skills", tostring(item.skills))
	doc_row(d, "f_cwd", "reads", vim.fn.fnamemodify(e.source_dirs(item.tool.name)[1] or "?", ":~"))
	doc_section(d, "f_version", "Clone")
	doc_block(d, {
		clone and ("%s · %s (%s)"):format(clone.version or "?", clone.short or "?", clone.branch or "?")
			or "not cloned yet",
		vim.fn.fnamemodify(e.dir(), ":~"),
		remote and ("origin: " .. remote) or "origin: press <A-u> to ask GitHub",
	}, "SnacksPickerDimmed")
	doc_section(d, "f_cmd", ("Commands to run (%s)"):format(s[3]))
	doc_block(d, e.steps(item.tool.name) or { "(unsupported target)" })
	return doc_done(d)
end

local function preview_text(item)
	local d = new_doc()
	local tool = item.tool
	local thl = TOOL_HL[tool.name]

	-- install REQUIRES an early return: the past branch at the end reads item.entry
	-- (nil for install) -> an error inside the finder, and the picker cannot open.
	if item.kind == "install" then
		doc_title(d, "install", "Install " .. tool.name, "DiagnosticWarn")
		doc_row(d, "f_cmd", "command", tool.install, "DiagnosticWarn")
		doc_section(d, "install", "Heads up")
		doc_block(d, {
			"Downloads and runs a remote script.",
			"Read the URL before continuing.",
			"<CR> runs it in the AI pane - you will be asked to confirm first.",
		}, "SnacksPickerDimmed")
		return doc_done(d)
	end

	-- Also REQUIRES an early return, same reason as install: no item.entry.
	if item.kind == "ecc" then
		local e = ecc()
		if not e then
			return doc_done(d)
		end
		doc_title(d, "ecc", "Install ECC for " .. tool.name, "SnacksPickerSpecial")
		doc_row(d, "f_prompt", "what", "281 skills + 94 commands for AI coding")
		doc_row(d, "f_cwd", "clone to", vim.fn.fnamemodify(e.dir(), ":~"))
		doc_row(d, "f_cmd", "reads", vim.fn.fnamemodify(e.source_dirs(tool.name)[1] or "?", ":~"))
		doc_section(d, "f_cmd", "Commands to run")
		doc_block(d, e.steps(tool.name) or { "(unsupported target)" })
		doc_section(d, "install", "Heads up")
		doc_block(d, {
			"Third-party repo: it is cloned, then npm install runs",
			"its lifecycle scripts and the installer writes into",
			"your ~/.claude / ~/.codex config.",
			"<CR> runs it in the AI pane - you will confirm first.",
		}, "SnacksPickerDimmed")
		doc_section(d, "f_prompt", "After installing")
		doc_block(d, {
			"<leader>ai actions switch from hand-written prompts",
			"to ECC commands (/code-review, /build-fix, ...).",
		}, "SnacksPickerDimmed")
		return doc_done(d)
	end

	if item.kind == "new" then
		doc_title(d, tool.name, "New " .. tool.name .. " session", thl)
		doc_row(d, "f_cwd", "cwd", vim.fn.fnamemodify(history().project_cwd(), ":~"))
		doc_section(d, "f_cmd", "Command")
		doc_block(d, cmdline(tool))
		return doc_done(d)
	end

	if item.kind == "browse" then
		doc_title(d, "browse", tool.name .. " · " .. (tool.browse_label or "own picker"), thl)
		doc_section(d, "f_prompt", "What this is")
		doc_block(d, {
			"Fallback when discovery finds nothing —",
			"schema changed, another machine's DB, etc.",
		}, "SnacksPickerDimmed")
		doc_section(d, "f_cmd", "Command")
		doc_block(d, cmdline(tool, tool.browse))
		return doc_done(d)
	end

	if item.kind == "live" then
		local s = item.session
		doc_title(d, "live", s.title or s.id, "SnacksPickerGitStatusStaged")
		doc_row(d, tool.name, "tool", tool.name, thl)
		doc_row(d, "f_id", "session", s.id)
		doc_row(d, "f_cwd", "cwd", item.cwd and vim.fn.fnamemodify(item.cwd, ":~"))
		doc_row(d, "f_agent", "job", tostring(s.job))
		doc_row(d, "f_updated", "state", "running")
		return doc_done(d)
	end

	local e = item.entry
	doc_title(d, tool.name, e.title or e.id, thl)

	local tool_line = e.tool .. (e.version and (" " .. e.version) or "")
	doc_row(d, tool.name, "tool", tool_line, thl)
	doc_row(d, "f_model", "model", e.model and (e.model .. (e.effort and (" (" .. e.effort .. ")") or "")))
	doc_row(d, "f_agent", "agent", e.agent)
	doc_row(d, "f_tokens", "tokens", e.tokens and commafy(e.tokens))
	doc_row(d, "f_cost", "cost", e.cost and ("$%.4f"):format(e.cost))
	doc_row(d, "branch", "branch", e.branch and (e.branch .. (e.sha and (" · " .. e.sha) or "")))
	doc_row(d, "f_cwd", "cwd", e.cwd and vim.fn.fnamemodify(e.cwd, ":~"))
	if e.time and e.time > 0 then
		doc_row(
			d,
			"f_updated",
			"updated",
			Snacks.picker.util.reltime(e.time) .. " · " .. os.date("%Y-%m-%d %H:%M", e.time)
		)
	end
	if e.created and e.created > 0 then
		doc_row(d, "f_created", "created", Snacks.picker.util.reltime(e.created))
	end
	doc_row(d, "f_id", "id", e.id)

	-- prompt_lines KEEPS line breaks (aiterm_history). e.prompt is the 1-line join
	-- for the matcher -> only a fallback when prompt_lines is missing.
	local prompt = e.prompt_lines or (e.prompt and { e.prompt })
	if prompt then
		doc_section(d, "f_prompt", "Last prompt")
		doc_block(d, prompt)
	end

	doc_section(d, "f_cmd", "Resume")
	doc_block(d, cmdline(tool, tool.resume(e.id)))
	return doc_done(d)
end

-- Display width of a {text, hl} list.
local function meta_width(meta)
	local w = 0
	for _, chunk in ipairs(meta) do
		w = w + vim.api.nvim_strwidth(chunk[1])
	end
	return w
end

local MIN_TITLE = 24 -- the title is never squeezed below this

-- Join metadata segments into a {text, hl} list, DROPPING low-priority segments
-- until it fits. nvim does NOT push right_align virt_text aside, so without trimming
-- the meta overlaps the title in narrow windows (the list is only ~38 cols in an 80-col terminal).
--   segs = { { text, hl, drop = <higher is dropped first> }, ... }
local function fit_meta(segs, budget)
	local keep = vim.deepcopy(segs)
	local function build()
		local out = {}
		for _, s in ipairs(keep) do
			if #out > 0 then
				out[#out + 1] = { " · ", "SnacksPickerDelim" }
			end
			out[#out + 1] = { s[1], s[2] }
		end
		out[#out + 1] = { " " } -- 1 column before the right border
		return out
	end
	local meta = build()
	while meta_width(meta) > budget and #keep > 1 do
		-- drop the segment with the highest `drop` (the first one on ties)
		local worst, worst_i = -1, nil
		for i, s in ipairs(keep) do
			if (s.drop or 0) > worst then
				worst, worst_i = s.drop or 0, i
			end
		end
		if not worst_i or worst <= 0 then
			break
		end
		table.remove(keep, worst_i)
		meta = build()
	end
	return meta
end

-- The title sits right after the icon; metadata is pinned to the RIGHT EDGE with a right_align
-- extmark, so the right edge stays straight whatever the title length (snacks format.file_git_status recipe).
--
-- Two deliberate points:
--   * the icon uses virtual = true -> rendered as a virt_text overlay, the real buffer only
--     has a space => the icon NEVER enters the text the matcher scores, nor
--     yanks. (typing "magic"/"code"/"terminal" will not mis-match on icons)
--   * the title must be truncated by (list width - meta width) because nvim does NOT push
--     right_align virt_text aside; without subtracting they overlap.
local function format_item(item, picker)
	local ret = {}
	local ic = M.icons()
	local tool = item.tool

	-- a 1-column icon + 1 space -> always exactly 2 columns with all 3 icon sets.
	ret[#ret + 1] = { (ic[item.kind] or ic.past) .. " ", KIND_HL[item.kind] or KIND_HL.past, virtual = true }

	-- FIXED tool column on the left. The tool used to sit in the right-aligned meta, so it landed
	-- at different positions on each row -> the eye had to scan every row to find the tool.
	-- Kept as REAL TEXT (not virtual): snacks' match highlighting runs over the
	-- rendered text of the whole line, so typing "codex" highlights this column too.
	ret[#ret + 1] = {
		Snacks.picker.util.align(tool_icon(tool) .. " " .. tool.name, TOOL_W),
		TOOL_HL[tool.name] or "SnacksPickerDimmed",
	}

	-- segs: metadata in display order; higher `drop` is dropped first when narrow.
	-- The tool is NO longer here (it has the left column) -> more room for the title.
	local segs = {}
	-- title is prebuilt in build_items (item.title is a real field for `title:` filtering).
	local title, title_hl = item.title or "", "SnacksPickerFile"

	if item.kind == "live" then
		segs[#segs + 1] = { item.session.id, "SnacksPickerBold", drop = 2 }
		segs[#segs + 1] = { "running", "SnacksPickerGitStatusStaged" }
	elseif item.kind == "past" then
		local e = item.entry
		if e.branch then
			segs[#segs + 1] = { ic.branch .. " " .. e.branch, "SnacksPickerGitBranch", drop = 2 }
		end
		if e.time and e.time > 0 then
			segs[#segs + 1] = { Snacks.picker.util.reltime(e.time), "SnacksPickerTime", drop = 1 }
		end
		-- Show cwd even in cwd scope: it exposes the codex/opencode edge case of recording the
		-- parent dir as cwd, instead of letting it confuse silently. Dropped first when narrow.
		if e.cwd then
			segs[#segs + 1] = { vim.fn.fnamemodify(e.cwd, ":~"), "SnacksPickerDir", drop = 3 }
		end
	elseif item.kind == "new" then
		-- the left column already names the tool -> the title does not repeat it ("New session").
		title_hl = "SnacksPickerLabel"
	elseif item.kind == "install" then
		-- needs its own branch: falling into else reads tool.browse_label -> wrong meta.
		title_hl = "DiagnosticWarn"
		segs[#segs + 1] = { "install", "DiagnosticWarn", drop = 1 }
	elseif item.kind == "ecc" then
		-- also needs its own branch, same reason as install.
		title_hl = "SnacksPickerSpecial"
		segs[#segs + 1] = { "not installed", "SnacksPickerDimmed", drop = 1 }
	else
		-- the title is just the args; the binary is in the tool column -> reads as "claude  --resume".
		title_hl = "SnacksPickerCode"
		segs[#segs + 1] = { tool.browse_label or "own picker", "SnacksPickerSpecial", drop = 1 }
	end

	-- Measure the list window's REAL width (win:size() recomputes from config rather than
	-- the current size). Before the window opens, 80 is the safe default.
	local list_w = 80
	local lwin = picker and picker.list and picker.list.win and picker.list.win.win
	if lwin and vim.api.nvim_win_is_valid(lwin) then
		list_w = vim.api.nvim_win_get_width(lwin)
	end

	local meta = fit_meta(segs, math.max(0, list_w - LEAD_W - MIN_TITLE))
	local avail = list_w - LEAD_W - meta_width(meta)
	if avail > 0 then
		title = Snacks.picker.util.truncate(title, avail)
	end
	ret[#ret + 1] = { title, title_hl, field = "title" }

	ret[#ret + 1] = {
		col = 0,
		virt_text = meta,
		virt_text_pos = "right_align",
		hl_mode = "combine", -- keeps CursorLine on the selected row
	}
	return ret
end

-- Key hints live in the bottom border. Three snacks conditions must hold:
--   * the footer MUST be attached to a BOX with a border: win="list" in the default preset has
--     border="none", and snacks clears the title/footer of borderless windows
--     (win.lua M:win_opts).
--   * the footer must NOT be templated (update_titles only touches the title) -> static tuple.
--   * win:update() re-applies self.opts, so the footer survives layout updates.
-- Key symbols use vim notation (plain ASCII): "⏎"/"⌥" are not in every font,
-- and "⌥" is macOS-specific, so on Linux/Windows it reads as the wrong key.
local FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "open  ", "SnacksPickerDimmed" },
	{ "C-x ", "SnacksPickerLabel" },
	{ "new  ", "SnacksPickerDimmed" },
	{ "C-o ", "SnacksPickerLabel" },
	{ "fork  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "scope  ", "SnacksPickerDimmed" },
	{ "Tab ", "SnacksPickerLabel" },
	{ "mark  ", "SnacksPickerDimmed" },
	{ "dd ", "SnacksPickerLabel" },
	{ "del  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- Footer for M.workflows: a completely different key set (no resume/fork/delete), and sharing
-- FOOTER would advertise keys that do not exist. M-t is the ONLY key in that picker
-- that cannot be guessed from the content, so it must be shown.
local WF_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "run  ", "SnacksPickerDimmed" },
	{ "M-f ", "SnacksPickerLabel" },
	{ "pin  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "all  ", "SnacksPickerDimmed" },
	{ "M-t ", "SnacksPickerLabel" },
	{ "tool  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

local SKILL_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "use  ", "SnacksPickerDimmed" },
	{ "M-f ", "SnacksPickerLabel" },
	{ "pin  ", "SnacksPickerDimmed" },
	{ "M-a ", "SnacksPickerLabel" },
	{ "all  ", "SnacksPickerDimmed" },
	{ "M-t ", "SnacksPickerLabel" },
	{ "tool  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- M.ecc footer. M-u is the ONLY key in the whole plugin that hits the network, so it must be visible.
local ECC_FOOTER = {
	{ " <CR> ", "SnacksPickerLabel" },
	{ "run  ", "SnacksPickerDimmed" },
	{ "M-u ", "SnacksPickerLabel" },
	{ "github  ", "SnacksPickerDimmed" },
	{ "? ", "SnacksPickerLabel" },
	{ "keys ", "SnacksPickerDimmed" },
}

-- Declaring layout.layout makes snacks SKIP all preset resolution
-- (config/init.lua: `if not (layout.layout and layout.layout[1])`), which also loses
-- the fallback to "vertical" in narrow terminals. So branch here, using the same
-- 120-column threshold snacks' default preset uses.
---@param footer table[] key hints of the calling picker (see FOOTER / WF_FOOTER)
local function build_layout(footer)
	if vim.o.columns < 120 then
		return {
			layout = {
				box = "vertical",
				width = 0.7,
				min_width = 70,
				height = 0.8,
				border = "rounded",
				title = "{title} {flags}",
				title_pos = "center",
				footer = footer,
				footer_pos = "center",
				{ win = "input", height = 1, border = "bottom" },
				{ win = "list", border = "none" },
				{ win = "preview", title = "{preview}", height = 0.4, border = "top" },
			},
		}
	end
	return {
		layout = {
			box = "horizontal",
			width = 0.85,
			min_width = 120,
			height = 0.8,
			{
				box = "vertical",
				border = "rounded",
				title = "{title} {flags}",
				title_pos = "center",
				footer = footer,
				footer_pos = "center",
				{ win = "input", height = 1, border = "bottom" },
				{ win = "list", border = "none" },
			},
			{ win = "preview", title = "{preview}", border = "rounded", width = 0.5 },
		},
	}
end

-- Group order: live -> past (newest first) -> new -> browse. Holds with an empty prompt
-- because snacks' default matcher.sort_empty = false -> no extra sort needed.
local function build_items(all_dirs)
	local items = {}

	for _, s in ipairs(sessions) do
		if is_alive(s) then
			items[#items + 1] = {
				kind = "live",
				session = s,
				tool = s.tool,
				cwd = s.cwd,
				-- item.text is REQUIRED: the matcher scores on it.
				text = table.concat({ "live", s.tool.name, s.id, s.title or "" }, " "),
			}
		end
	end

	-- Do NOT write `all_dirs and nil or cwd`: nil is falsy, so the and branch collapses and the
	-- expression always returns cwd -> the "all dirs" scope never takes effect. Use if.
	local scope_cwd
	if not all_dirs then
		-- scope_cwd() returns the RAW cwd; history adds the realpath to the candidate set, so
		-- both the mount path (e.g. /app in a container) and the realpath match.
		scope_cwd = history().scope_cwd()
	end

	-- A running live session IS ALSO WRITTEN TO DISK BY THE TOOL ITSELF (claude jsonl,
	-- codex threads, opencode session), so history() returns it again in the
	-- past group -> one session shows 2 rows (1 live + 1 past with the same name). Drop
	-- the duplicate past entries from the picker:
	--   * an entry whose (tool, id) matches a live session's real_id -> resume knew it up front.
	--   * new/fork/browse sessions with an unknown id -> find an entry of the same tool in the list,
	--     the newest unclaimed one, at or after launch time; pin it on the first match.
	local function tool_key(tool_name, id)
		return tool_name .. "\0" .. tostring(id)
	end
	local hist = history().list(scope_cwd)
	local live_ids, claimed = {}, {}
	for _, s in ipairs(sessions) do
		if is_alive(s) then
			if s.real_id then
				-- id already known -> claim it first so another session's discovery cannot
				-- steal this entry.
				claimed[s.real_id] = true
			else
				local best, best_d
				for _, e in ipairs(hist) do
					if e.tool == s.tool.name and not claimed[e.id] and (e.time or 0) >= s.launch_time then
						local d = (e.time or 0) - s.launch_time
						if not best_d or d < best_d then
							best, best_d = e.id, d
						end
					end
				end
				if best then
					claimed[best] = true
					s.real_id = best
				end
			end
			if s.real_id then
				live_ids[tool_key(s.tool.name, s.real_id)] = true
			end
		end
	end

	for _, e in ipairs(hist) do
		local tool = find_tool(e.tool)
		-- Do NOT add past entries that duplicate a running session (already in the live group).
		if tool and not live_ids[tool_key(e.tool, e.id)] then
			items[#items + 1] = {
				kind = "past",
				tool = tool,
				entry = e,
				cwd = e.cwd,
				-- pack tool + title + cwd + branch + id -> queries "codex redis" and
				-- "dotfiles main" both hit. Do NOT use item.file for e.jsonl:
				-- matcher.filename_bonus would award a fake filename bonus.
				text = table.concat({ e.tool, e.title or "", e.cwd or "", e.branch or "", e.id }, " "),
			}
		end
	end

	-- Tool not installed but has an install script -> replace new + browse with EXACTLY 1 install row.
	-- Pressing new/browse of a missing tool only yields "binary not found", so keeping
	-- them just adds dead rows. Compute the state once and use it for both loops.
	local needs_install = {}
	for _, t in ipairs(M.config.tools) do
		needs_install[t.name] = tool_cmd(t) == nil and t.install ~= nil
	end

	for _, t in ipairs(M.config.tools) do
		if needs_install[t.name] then
			items[#items + 1] = { kind = "install", tool = t, text = "install " .. t.name }
		else
			items[#items + 1] = { kind = "new", tool = t, text = "new " .. t.name }
		end
	end
	for _, t in ipairs(M.config.tools) do
		if t.browse and not needs_install[t.name] then
			items[#items + 1] = { kind = "browse", tool = t, text = "browse " .. t.name }
		end
	end

	-- Binary present but no ECC commands -> offer an install. After installing, the re-scan finds
	-- commands so this row disappears; later updates go through M.ecc() (<leader>aE).
	for _, t in ipairs(M.config.tools) do
		if not needs_install[t.name] then
			local e = ecc()
			if e and not e.installed(t.name) then
				items[#items + 1] = { kind = "ecc", tool = t, text = "ecc " .. t.name }
			end
		end
	end

	-- item.title is a REAL field on the item, not just for display: the matcher filters
	-- `title:redis` via item[field] (matcher.lua M:match -> item[mods.field]),
	-- NOT the rendered text. Without it here `title:` always yields 0 results.
	for _, it in ipairs(items) do
		if it.kind == "live" then
			it.title = it.session.title or it.session.id
		elseif it.kind == "past" then
			it.title = it.entry.title or it.entry.id
		elseif it.kind == "new" then
			it.title = "New session"
		elseif it.kind == "install" then
			-- own branch: the else below returns browse args -> wrong for install.
			it.title = "not installed"
		elseif it.kind == "ecc" then
			it.title = "Add ECC skills & commands"
		else
			it.title = table.concat(it.tool.browse or {}, " ")
		end
		-- preview_text returns { text, extmarks }. NO ft: the layout is a column-aligned
		-- table, and markdown would read indented lines as code blocks.
		it.preview = preview_text(it)
	end
	return items
end

-- public -----------------------------------------------------------------

-- Create a new session for a tool (by name) and attach. Used by quick-create commands/keymaps.
---@param name string
---@param opts? { args?: string[], cwd?: string, title?: string }
function M.open(name, opts)
	local tool = find_tool(name)
	if not tool then
		vim.notify("aiterm: unknown tool '" .. tostring(name) .. "'", vim.log.levels.ERROR)
		return
	end
	opts = opts or {}
	opts.cwd = opts.cwd or history().project_cwd()
	attach(new_session(tool, opts))
end

--- Resume an old on-disk session into the AI pane.
---@param e table entry from aiterm_history.list()
function M.resume(e)
	local tool = e and find_tool(e.tool)
	if not (tool and tool.resume) then
		notify("aiterm: tool does not support resume: " .. tostring(e and e.tool), "warn")
		return
	end
	attach(new_session(tool, { args = tool.resume(e.id), cwd = e.cwd, title = e.title, real_id = e.id }))
end

-- Resume the newest session of the cwd, without the picker. Nothing yet -> open the picker.
function M.resume_last()
	local e = history().list(history().scope_cwd(), 1)[1]
	if not e then
		return M.pick()
	end
	M.resume(e)
end

-- Diagnose why the picker does not see a session (cwd scoping / missing sqlite3...).
function M.doctor()
	-- The ECC section is appended to the same buffer as the history doctor. It exists because
	-- "the installer finished but the tool still sees no commands" (opencode lays files out in ~/.opencode,
	-- not where it reads) looks exactly like "not installed" - there is no way to detect it automatically.
	local e = ecc()
	local lines
	if e then
		lines = { "## ECC (skills/commands for AI tools)", "clone       : " .. e.dir() }
		for _, t in ipairs(M.config.tools) do
			local n = e.count(t.name)
			-- commands = repo-level workflows (<leader>aw); skills = docs applied to the selected
			-- code (<leader>ai). These two numbers differing is normal.
			local sk = vim.tbl_count(e.skills(t.name))
			local dir = e.source_dirs(t.name)[1] or "?"
			lines[#lines + 1] = ("%-12s: %3d commands  %3d skills  %s"):format(t.name, n, sk, dir)
			local pinned, pn = e.anthropic_pins(t.name)
			if pinned then
				lines[#lines + 1] = ("%-12s  ! %d anthropic/* model pin(s) in %s"):format("", pn, pinned)
				lines[#lines + 1] = ("%-12s    -> run <leader>aE again to remove the pins"):format("")
			end
		end
		lines[#lines + 1] = "Hint: 0 commands -> <leader>ai sends a hand-written prompt instead of a /command."
		lines[#lines + 1] = "Install/update with <leader>aE, or the ECC row in the <leader>aa picker."
	else
		lines = {
			"## ECC (skills/commands for AI tools)",
			"module 'customize.aiterm_ecc' failed to load - section skipped.",
		}
	end
	-- treehouse / no-mistakes / gnhf / firstmate status (<leader>ap/ag/aW/aF).
	local ok_flow, flow = pcall(require, "customize.aiterm_flow")
	if ok_flow then
		vim.list_extend(lines, flow.doctor_lines())
	end
	history().doctor(lines)
end

--- Main picker: live sessions + old on-disk sessions + create new + fallback.
---@param opts? { scope?: "cwd"|"all" }
function M.pick(opts)
	if not (_G.Snacks and Snacks.picker) then
		vim.notify("aiterm: snacks.nvim picker required", vim.log.levels.ERROR)
		return
	end
	ensure_hl()
	local scope = (opts and opts.scope) or M.config.history.scope

	-- Close the picker BEFORE opening the terminal: avoids a focus fight with the AI pane.
	local function run(picker, fn)
		picker:close()
		vim.schedule(fn)
	end

	Snacks.picker({
		title = "AI Sessions",
		-- Scope is a BOOLEAN opt, not a closure upvalue. snacks generates the
		-- `toggle_all_dirs` action + an hl group for each toggles entry, and
		-- `{flags}` in the title inserts a badge when all_dirs = true.
		-- Important: the finder reads opts.all_dirs (its first parameter IS picker.opts),
		-- so there is a single path reading the state -> no more "title changed but the list did not" bugs.
		all_dirs = scope == "all",
		toggles = { all_dirs = { icon = M.icons().all_dirs, value = true } },
		finder = function(popts)
			return build_items(popts.all_dirs)
		end,
		format = format_item,
		preview = "preview",
		layout = build_layout(FOOTER),
		confirm = function(picker, item)
			if not item then
				return
			end
			run(picker, function()
				if item.kind == "live" then
					attach(item.session)
				elseif item.kind == "past" then
					M.resume(item.entry)
				elseif item.kind == "install" then
					install_tool(item.tool)
				elseif item.kind == "ecc" then
					install_ecc(item.tool)
				elseif item.kind == "browse" then
					attach(new_session(item.tool, {
						args = item.tool.browse,
						cwd = history().project_cwd(),
						title = "browse",
					}))
				else
					attach(new_session(item.tool, { cwd = history().project_cwd() }))
				end
			end)
		end,
		actions = {
			-- <C-x>: skip resume, open a BLANK session with the item's tool + cwd.
			aiterm_fresh = function(picker, item)
				if not item then
					return
				end
				-- on an install row new_session only yields "binary not found"
				-- -> install instead, so <C-x> is not a dead end.
				if item.kind == "install" then
					run(picker, function()
						install_tool(item.tool)
					end)
					return
				end
				if item.kind == "ecc" then
					run(picker, function()
						install_ecc(item.tool)
					end)
					return
				end
				local cwd = item.cwd or history().project_cwd()
				run(picker, function()
					attach(new_session(item.tool, { cwd = cwd }))
				end)
			end,
			-- <C-o>: fork an old session -> the original history is not appended to.
			aiterm_fork = function(picker, item)
				if not (item and item.kind == "past" and item.tool.fork) then
					return
				end
				local e = item.entry
				run(picker, function()
					attach(new_session(item.tool, {
						args = item.tool.fork(e.id),
						cwd = e.cwd,
						title = e.title,
					}))
				end)
			end,
			-- Tab marks several sessions; Esc then dd deletes the selected old sessions.
			-- Codex archive is undoable; opencode/claude are NOT -> confirm defaults to No.
			aiterm_delete = function(picker, item)
				local marked = picker:selected()
				local candidates = #marked > 0 and marked or (item and { item } or {})
				local targets, skipped, counts = {}, 0, {}
				for _, candidate in ipairs(candidates) do
					if candidate.kind == "past" then
						targets[#targets + 1] = candidate
						local name = candidate.tool.name
						counts[name] = (counts[name] or 0) + 1
					else
						skipped = skipped + 1
					end
				end
				if #targets == 0 then
					if skipped > 0 then
						notify(("No past sessions to delete; skipped %d non-past item(s)."):format(skipped), "warn")
					end
					return
				end
				local tools, lines = {}, {}
				for name, count in pairs(counts) do
					tools[#tools + 1] = ("%s: %d"):format(name, count)
				end
				table.sort(tools)
				for _, target in ipairs(targets) do
					local e = target.entry
					lines[#lines + 1] = ("  %s: %s [%s]"):format(target.tool.name, e.title or e.id, e.id)
				end
				local prompt = ("Delete %d past session(s) (%s)?\n%s"):format(
					#targets,
					table.concat(tools, ", "),
					table.concat(lines, "\n")
				)
				if skipped > 0 then
					prompt = prompt .. ("\nSkipped %d non-past item(s)."):format(skipped)
				end
				if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
					return
				end
				local deleted, failed = 0, {}
				for _, target in ipairs(targets) do
					if delete_entry(target.tool, target.entry) then
						deleted = deleted + 1
					else
						failed[#failed + 1] = target.entry.id
					end
				end
				if deleted > 0 then
					history().invalidate()
					picker:refresh() -- clear stale marks, then re-run finder once
				end
				local summary = ("Deleted %d/%d past session(s)"):format(deleted, #targets)
				if #failed > 0 then
					summary = summary .. ("; failed: %s"):format(table.concat(failed, ", "))
				end
				if skipped > 0 then
					summary = summary .. ("; skipped %d non-past item(s)"):format(skipped)
				end
				notify(summary, #failed > 0 and "warn" or "info")
			end,
		},
		-- `desc` is not decoration: the `?` overlay (toggle_help_input) reads the buffer's
		-- REAL keymaps and renders desc. Without it snacks derives one from the action name
		-- ("aiterm_fresh" -> "aiterm fresh"), which reads badly.
		-- `?` only works in normal mode by default, but the picker opens in insert -> add
		-- <a-?> to see keys while typing (`?` is not mapped in insert since it would type
		-- a ? into the query).
		-- desc <= ~18 chars: snacks.win's help overlay cuts at the default col_width.
		win = {
			input = {
				keys = {
					["<c-x>"] = { "aiterm_fresh", mode = { "i", "n" }, desc = "new blank session" },
					["<c-o>"] = { "aiterm_fork", mode = { "i", "n" }, desc = "fork session" },
					["<a-a>"] = { "toggle_all_dirs", mode = { "i", "n" }, desc = "cwd / all dirs" },
					["dd"] = { "aiterm_delete", mode = "n", desc = "delete session" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<c-x>"] = { "aiterm_fresh", desc = "new blank session" },
					["<c-o>"] = { "aiterm_fork", desc = "fork session" },
					["<a-a>"] = { "toggle_all_dirs", desc = "cwd / all dirs" },
					["dd"] = { "aiterm_delete", mode = "n", desc = "delete session" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
	})
end

-- <C-w>p in the editor: focus the pane if open; otherwise attach the most recent session
-- or the first live one; nothing yet -> open the picker.
function M.focus()
	if win_valid() then
		vim.api.nvim_set_current_win(win)
		if M.config.start_insert then
			vim.cmd("startinsert")
		end
		return
	end
	local s = last_session and find(last_session)
	if not is_alive(s) then
		s = nil
		for _, cand in ipairs(sessions) do
			if is_alive(cand) then
				s = cand
				break
			end
		end
	end
	if s then
		attach(s)
	else
		M.pick()
	end
end

-- Focus AI only if it is the window directly to the right; the caller keeps the original navigation on false.
function M.focus_if_right()
	if not win_valid() or vim.api.nvim_get_current_win() == win or vim.fn.win_getid(vim.fn.winnr("l")) ~= win then
		return false
	end
	M.focus()
	return true
end

-- Hide the AI pane: CLOSE the window but do NOT touch the job.
-- The buffer has bufhidden="hide", so the terminal keeps running in the background; <C-w>p / <leader>aa
-- reattach that same session (it stays in `sessions`, is_alive is still true).
-- Callable from anywhere, no need to be focused in the pane.
function M.hide()
	if not win_valid() then
		return
	end
	-- nvim_win_close errors with "cannot close last window" if this is the only window.
	if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
		notify("cannot hide: AI pane is the only window", "warn")
		return
	end
	-- leave terminal mode first, otherwise the cursor stays stuck in insert after closing.
	if vim.api.nvim_get_current_win() == win and vim.fn.mode() == "t" then
		vim.cmd("stopinsert")
	end
	pcall(vim.api.nvim_win_close, win, false)
	win = nil
end

-- Close the AI pane before auto-session saves: keeps mksession from writing the terminal buffer ->
-- setlocal buftype=terminal (E474) breaks restore. The job dies with nvim on exit,
-- so nothing needs keeping. Make sure it is not the last window so nvim_win_close does not error.
function M.close_for_session()
	if not win_valid() then
		return
	end
	if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
		vim.cmd("new") -- leave 1 empty window so the pane can close
	end
	if vim.api.nvim_get_current_win() == win and vim.fn.mode() == "t" then
		vim.cmd("stopinsert")
	end
	pcall(vim.api.nvim_win_close, win, true)
	win = nil
end

-- Move focus off the pane but KEEP it open. This is <C-Space>'s behavior in
-- terminal mode (mapped straight to <C-w>p, not through this function).
function M.blur()
	if win_valid() and vim.api.nvim_get_current_win() == win then
		vim.cmd("wincmd p")
	end
end

-- Toggle: pane open -> hide; not open -> focus/attach.
function M.toggle()
	if win_valid() then
		M.hide()
	else
		M.focus()
	end
end

-- code interaction (ask / explain ... CodeCompanion style) ------------------
-- No LLM plugin needed: aiterm runs CLIs in a PTY, so "interacting with source code" =
-- building a message (file/selection + instruction) and CHANSENDing it to the session's job.

-- default tool (fallback list + override persisted across startups) ------
-- default_override: the tool name the user pinned (via M.set_default_tool / <leader>aD),
-- read back from the state file on require. Takes priority over M.config.send.default_tools.
local default_override
local refresh_hints -- forward declaration: defined in the inline hints section below

local function state_file()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "aiterm-default-tool")
end

-- Tool for auto-created sessions: the override (if valid) first, then the first INSTALLED tool
-- in default_tools; none installed -> the first valid tool (new_session will suggest installing).
local function resolve_default_tool()
	local order, first = {}, nil
	if default_override then
		order[#order + 1] = default_override
	end
	vim.list_extend(order, M.config.send.default_tools or {})
	for _, name in ipairs(order) do
		local t = find_tool(name)
		if t then
			first = first or t
			if tool_cmd(t) then
				return t
			end
		end
	end
	return first or M.config.tools[1]
end

-- Default tool name (same rules as picker/send) for external modules, e.g. aiterm_flow
-- opening a session in a treehouse worktree.
---@return string
function M.default_tool_name()
	return resolve_default_tool().name
end

-- Read the saved choice (pcall-safe: missing/garbage file -> no override).
local function load_default()
	local ok, lines = pcall(vim.fn.readfile, state_file())
	local name = ok and lines[1] and vim.trim(lines[1]) or ""
	if name ~= "" and find_tool(name) then
		default_override = name
	end
end

-- favorites (pins) for the skill/command picker --------------------------
-- Pins by NAME, split by kind ("skills"/"commands"). Persisted across nvim runs, same
-- state file shape as the default tool. The picker shows only pinned entries by default (see M.skill_pick).
local fav = { skills = {}, commands = {} } -- kind -> { name -> true }
local function fav_file()
	return vim.fs.joinpath(vim.fn.stdpath("state"), "aiterm-favorites.json")
end
local function load_favorites()
	local ok, lines = pcall(vim.fn.readfile, fav_file())
	if not ok or not lines or #lines == 0 then
		return
	end
	local ok2, d = pcall(vim.json.decode, table.concat(lines, "\n"))
	if ok2 and type(d) == "table" then
		fav.skills = type(d.skills) == "table" and d.skills or {}
		fav.commands = type(d.commands) == "table" and d.commands or {}
	end
end
local function is_fav(kind, name)
	return fav[kind][name] == true
end
local function toggle_fav(kind, name)
	fav[kind][name] = (not fav[kind][name]) or nil
	pcall(vim.fn.writefile, { vim.json.encode(fav) }, fav_file())
end
local function fav_count(kind)
	return vim.tbl_count(fav[kind])
end

--- Pin the default (auto-create) tool and PERSIST it across startups.
---@param name string
function M.set_default_tool(name)
	if not find_tool(name) then
		notify("aiterm: unknown tool " .. tostring(name), "warn")
		return
	end
	default_override = name
	pcall(vim.fn.writefile, { name }, state_file())
	notify("AI default tool: " .. name, "info")
end

--- Default tool menu (<leader>aD), with icons + a (current) marker.
function M.pick_default()
	local ic, names = M.icons(), {}
	for _, t in ipairs(M.config.tools) do
		names[#names + 1] = t.name
	end
	vim.ui.select(names, {
		prompt = "Default AI tool:",
		format_item = function(n)
			return (ic[n] and ic[n] .. " " or "") .. n .. (default_override == n and "  (current)" or "")
		end,
	}, function(choice)
		if choice then
			M.set_default_tool(choice)
			refresh_hints() -- the badge reflects the just-picked tool immediately
		end
	end)
end

-- The live session a send targets. Priority:
--   1. the session shown in the AI pane (if the pane is focused)
--   2. last_session if alive
--   3. the first live session
-- Returns nil when no session is alive. Does NOT create one: M.send needs to know "no
-- session" to embed the prompt in the launch command instead of pasting into a booting TUI.
-- `tool` (optional) restricts the result to that tool. Needed by M.workflows: ECC commands have
-- per-tool prefixes (codex's /ecc-code-review), and pasting into an opencode session by mistake
-- sends a meaningless line. The filter must apply to ALL THREE branches - missing one makes it
-- silently return a session of the wrong tool.
local function target_session(tool)
	local function usable(s)
		return is_alive(s) and (tool == nil or s.tool == tool)
	end
	if win_valid() then
		local buf = vim.api.nvim_win_get_buf(win)
		for _, s in ipairs(sessions) do
			if s.buf == buf and usable(s) then
				return s
			end
		end
	end
	local s = last_session and find(last_session)
	if usable(s) then
		return s
	end
	for _, cand in ipairs(sessions) do
		if usable(cand) then
			return cand
		end
	end
	return nil -- ONLY looks, never creates: M.send decides how to create (see M.send).
end

-- Terminal content signature to detect "finished drawing, now quiet" (quiescence): line count
-- + the last few lines. Sensitive enough to see the CLI print something, cheap enough to poll every ~120ms.
local function term_signature(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	local n = vim.api.nvim_buf_line_count(buf)
	return n .. "\0" .. table.concat(vim.api.nvim_buf_get_lines(buf, math.max(0, n - 3), n, false), "\n")
end

-- Wait for the session to be "ready", then call cb. Ready = the terminal HAS changed since it
-- opened (the CLI printed something -> booted) AND the content stayed quiet for quiet_ms, after min_ms;
-- at max_ms flush anyway. Replaces the old fixed delay (sending early -> lost/garbled requests).
local function when_ready(session, cb)
	local r = M.config.send.ready
	local start = vim.uv.now()
	local initial = term_signature(session.buf)
	local last, stable_since, seen_change = initial, nil, false
	local timer = vim.uv.new_timer()
	local function stop()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end
	timer:start(
		r.interval_ms,
		r.interval_ms,
		vim.schedule_wrap(function()
			if not is_alive(session) then
				stop()
				return
			end
			local now = vim.uv.now()
			local sig = term_signature(session.buf)
			if sig ~= last then
				last, stable_since = sig, now
				if sig ~= initial then
					seen_change = true
				end
			end
			local quiet = seen_change and stable_since and (now - stable_since) >= r.quiet_ms
			if (now - start) >= r.max_ms or ((now - start) >= r.min_ms and quiet) then
				stop()
				cb()
			end
		end)
	)
end

-- Bracketed paste: the TUI treats the whole block (newlines included) as ONE paste and does not
-- submit line by line. \27[200~ ... \27[201~ are the standard bracketed-paste codes.
local function chan_paste(job, text)
	vim.fn.chansend(job, "\27[200~" .. text .. "\27[201~")
end

--- Send text to the running AI session (creating one if needed), optionally submitting it.
---@param text string
---@param opts? { submit?: boolean, tool?: table }
function M.send(text, opts)
	opts = opts or {}
	-- opts.tool: restrict the target to that tool (M.workflows). Omitted -> same behavior as
	-- before: any live session.
	local session = target_session(opts.tool) -- ONLY finds a live session

	if not session then
		-- MAIN PATH when there is no session: embed the prompt straight in the launch command.
		-- No paste => no race with the TUI booting. This is where requests used to get
		-- lost: opencode boots slowly, the paste landed while it was still negotiating
		-- capabilities with the terminal, so the request vanished and the process exited.
		local tool = opts.tool or resolve_default_tool()
		if tool.prompt_args and #text <= M.config.send.max_arg_bytes then
			attach(new_session(tool, {
				args = tool.prompt_args(text),
				cwd = history().project_cwd(),
				title = "ask",
			}))
			return
		end
		-- The tool does not support a launch prompt, or the message is too big for argv
		-- -> old path: create, wait for boot, then paste.
		session = new_session(tool, { cwd = history().project_cwd() })
		if not session then
			return -- new_session already notified the reason (binary not found ...)
		end
		session.ready = false
	end

	attach(session) -- open + focus the pane; the job takes input regardless of focus, so no race.
	local function deliver()
		if not is_alive(session) then
			return
		end
		chan_paste(session.job, text)
		if opts.submit then
			-- Enter one beat after the paste: claude's Ink needs time to process the paste.
			vim.defer_fn(function()
				if is_alive(session) then
					vim.fn.chansend(session.job, "\r")
				end
			end, M.config.send.submit_delay)
		end
	end
	-- just-created session (ready=false): the CLI has not finished booting -> sending early is lost/garbled
	-- (bracketed paste not enabled yet). Wait until the terminal is drawn + quiet before sending; flip ready
	-- so later sends to the same session are instant. Old sessions (ready=nil) send immediately.
	if session.ready == false then
		notify(("waiting for %s to start…"):format(session.tool.name), "info")
		when_ready(session, function()
			session.ready = true
			deliver()
		end)
	else
		deliver()
	end
end

-- Treesitter node around the cursor in the current window, walking up to a type matching
-- M.config.ts_node_types. nil when the buffer has no parser or the cursor is at top level.
local function enclosing_node()
	local ok, node = pcall(vim.treesitter.get_node) -- defaults to cursor + curbuf
	if not ok or not node then
		return nil
	end
	while node do
		local t = node:type()
		for _, pat in ipairs(M.config.ts_node_types) do
			if t:find(pat, 1, true) then
				return node
			end
		end
		node = node:parent()
	end
	return nil
end

-- Capture context AT CALL TIME (still in visual mode, to read the selection).
-- A Lua function keymap keeps visual mode, so getpos('v')/getpos('.') can read
-- the selection. Scratch/unnamed buffer -> drop the @ref, keep only the code (if any).
local function capture_context()
	local file = vim.fn.expand("%:.") -- relative to cwd; "" when unnamed
	if file == "" then
		file = nil
	end
	local lang = vim.bo.filetype
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then -- v / V / <C-v> (\22 = <C-v>)
		local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
		local region = vim.fn.getregion(a, b, { type = mode })
		return {
			file = file,
			lang = lang,
			code = table.concat(region, "\n"),
			l1 = math.min(a[2], b[2]),
			l2 = math.max(a[2], b[2]),
		}
	end
	-- normal mode: try the function/class under the cursor via treesitter (CodeCompanion-style
	-- act-on-scope); at top level / without a parser -> fall back to @ref of the whole file.
	local node = enclosing_node()
	if node then
		local sr, _, er = node:range() -- 0-indexed rows, er includes the node's last line
		local lines = vim.api.nvim_buf_get_lines(0, sr, er + 1, false)
		return { file = file, lang = lang, code = table.concat(lines, "\n"), l1 = sr + 1, l2 = er + 1 }
	end
	return { file = file, lang = lang }
end

-- Hybrid message: @ref (the agent reads the whole file) + a fenced block pinned to the selected lines.
local function build_message(instruction, ctx)
	local l = { instruction, "" }
	if ctx.file then
		l[#l + 1] = ctx.l1 and ("@%s (lines %d-%d)"):format(ctx.file, ctx.l1, ctx.l2) or ("@%s"):format(ctx.file)
	end
	if ctx.code then
		l[#l + 1] = "```" .. (ctx.lang or "")
		vim.list_extend(l, vim.split(ctx.code, "\n", { plain = true }))
		l[#l + 1] = "```"
	end
	return table.concat(l, "\n")
end

-- The tool the message WILL reach, resolved exactly like M.send: the live session first, else the
-- default tool. Must match, because ECC command prefixes differ per tool.
local function target_tool()
	local s = target_session()
	return (s and s.tool) or resolve_default_tool()
end

-- The ECC skill for this action on this tool, or nil. Looks up the table DETECTED ON DISK, so it
-- never names a skill the tool lacks: naming a nonexistent one only makes the
-- agent go looking and then make up its content.
local function ecc_skill(action, tool)
	if not (action.skill and tool) then
		return nil
	end
	local e = ecc()
	if not e then
		return nil
	end
	return e.skills(tool.name)[action.skill] and action.skill or nil
end

-- Action picker (explain/ask/fix...). Called from normal + visual (<leader>ai).
-- Everything here is SELECTION-LEVEL: the message always carries @ref + the selected code block.
-- ECC's repo-level commands live in M.workflows() - see the comment at M.config.actions.
function M.actions()
	local ctx = capture_context() -- CAPTURE before opening the menu (the menu leaves visual mode)
	if not (ctx.file or ctx.code) then
		notify("aiterm: no file or selection to send", "warn")
		return
	end
	-- Resolve ONCE before opening the menu: format_item runs per row, so doing it there would
	-- stat directories on every menu redraw.
	local tool = target_tool()
	vim.ui.select(M.config.actions, {
		prompt = "AI action:",
		format_item = function(a)
			local icon = a.key and M.icons()[a.key]
			-- Show the skill that will be referenced -> at a glance, which entries ECC backs.
			local skill = ecc_skill(a, tool)
			return (icon and icon .. "  " or "") .. a.label .. (skill and ("   " .. skill) or "")
		end,
	}, function(choice)
		if not choice then
			return
		end
		local instr = choice.prompt
		if choice.input then
			instr = vim.fn.input(choice.input)
			if instr == "" then
				return
			end
		else
			-- A free-form question (input) gets no skill: the user decides what to ask.
			local skill = ecc_skill(choice, tool)
			if skill then
				instr = instr .. ("\nFollow the `%s` skill."):format(skill)
			end
		end
		M.send(build_message(instr, ctx), { submit = true })
	end)
end

-- REPO-LEVEL ECC commands (<leader>aw). Fully separate from M.actions because they ignore context:
-- the /code-review template starts with `git diff --name-only HEAD`, /build-fix with
-- `npx tsc --noEmit`, /refactor-clean with `npx knip` - sending @ref or a code block is just
-- noise. A Snacks picker rather than vim.ui.select: there are hundreds of commands, fuzzy is needed.
-- Whether the tool runs /slash commands natively (default: yes, unless the table says false).
local function slash_native(tool)
	return M.config.send.slash_native[tool.name] ~= false
end

-- Content of the ECC command file (exactly what the /command expands to), for tools that do NOT run
-- slash commands natively (codex). Replaces $ARGUMENTS with arg; with no placeholder but an arg,
-- appends "Input: arg". nil when reading the file fails -> the caller falls back to sending the /token.
local function command_body(cm, arg)
	local ok, lines = pcall(vim.fn.readfile, cm.path)
	if not ok or not lines or #lines == 0 then
		return nil
	end
	local body = table.concat(lines, "\n")
	if body:find("$ARGUMENTS", 1, true) then
		-- %$ escapes $ in the pattern; % is escaped in the replacement (gsub treats % as special).
		-- Assign repl to a local FIRST: (...):gsub returns (string, count); passing it straight into the outer
		-- gsub puts count=0 into the n parameter -> gsub replaces 0 times. The local keeps 1 value.
		local repl = (arg or ""):gsub("%%", "%%%%")
		body = body:gsub("%$ARGUMENTS", repl)
	elseif arg and arg ~= "" then
		body = body .. "\n\nInput: " .. arg
	end
	return body
end

function M.workflows()
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	local e = ecc()
	if not e then
		notify("aiterm: ECC module unavailable", "warn")
		return
	end
	-- cwd to include the repo's LOCAL commands (scope=project). Uses project_cwd (the real realpath).
	local cwd = history().project_cwd()
	-- Only cycle through tools that HAVE ECC commands: cycling into an empty list makes <A-t> look
	-- broken.
	local tools = {}
	for _, t in ipairs(M.config.tools) do
		if #e.command_list(t.name, cwd) > 0 then
			tools[#tools + 1] = t
		end
	end
	if #tools == 0 then
		notify("ECC not installed for any tool - use <leader>aE", "warn")
		return
	end
	-- Start from the tool that will receive the message if it has ECC (live session > default tool).
	local idx = 1
	local cur = target_tool()
	for i, t in ipairs(tools) do
		if cur and t.name == cur.name then
			idx = i
		end
	end
	ensure_hl()

	local path_args = {}
	for _, n in ipairs(M.config.workflow_args.path) do
		path_args[n] = true
	end
	local ask_args = M.config.workflow_args.ask
	local ic = M.icons()
	-- Commands shown in pinned mode: pinned OR the repo's own (project always shows).
	local function shown_in_pinned(cm)
		return is_fav("commands", cm.name) or cm.scope == "project"
	end
	-- Whether any pinned/project command is visible in this cwd -> do NOT open pinned when empty (avoids
	-- "No Results" when only another repo's project command is pinned).
	local function pinned_has_items(t)
		for _, cm in ipairs(e.command_list(t.name, cwd)) do
			if shown_in_pinned(cm) then
				return true
			end
		end
		return false
	end
	local function title_for(t, pinned)
		local n_show, n_all = 0, 0
		for _, cm in ipairs(e.command_list(t.name, cwd)) do
			n_all = n_all + 1
			if shown_in_pinned(cm) then
				n_show = n_show + 1
			end
		end
		local mode = pinned and (ic.star .. " %d pinned"):format(n_show) or ("all %d"):format(n_all)
		return ("ECC workflows (%s) · %s"):format(t.name, mode)
	end

	-- Open pinned only when a pinned/project command IS visible in this cwd (avoids "No Results").
	local start_pinned = fav_count("commands") > 0 and pinned_has_items(tools[idx])
	Snacks.picker({
		title = title_for(tools[idx], start_pinned),
		-- The tool lives in the PICKER OPTS, not an upvalue: the finder reads popts, so there is only
		-- one path reading the state. The scope's earlier "title changed but the list did not" bug came
		-- from exactly having two paths.
		wf_tool = tools[idx].name,
		pinned = start_pinned,
		finder = function(popts)
			local t = find_tool(popts.wf_tool) or tools[1]
			local list = e.command_list(t.name, cwd)
			-- pinned: filter to pinned + project. If that is EMPTY (or all) -> show everything, sorting
			-- project/pinned first. The empty -> all fallback means never "No Results".
			local shown = {}
			if popts.pinned then
				for _, cm in ipairs(list) do
					if shown_in_pinned(cm) then
						shown[#shown + 1] = cm
					end
				end
			end
			if not popts.pinned or #shown == 0 then
				shown = {}
				for _, cm in ipairs(list) do
					shown[#shown + 1] = cm
				end
				table.sort(shown, function(a, b)
					local ra = a.scope == "project" and 0 or (is_fav("commands", a.name) and 1 or 2)
					local rb = b.scope == "project" and 0 or (is_fav("commands", b.name) and 1 or 2)
					if ra ~= rb then
						return ra < rb
					end
					return a.name < b.name
				end)
			end
			-- Align columns on THIS TOOL's longest command: codex's prefix is /ecc-*,
			-- so it is noticeably longer than claude/opencode.
			local w = 0
			for _, cm in ipairs(shown) do
				w = math.max(w, #cm.invoke)
			end
			local items = {}
			for _, cm in ipairs(shown) do
				items[#items + 1] = {
					cmd = cm,
					-- tool + pad attached to the item: format/confirm do not read an upvalue that went stale
					-- after switching tools.
					tool = t,
					pad = string.rep(" ", w - #cm.invoke + 2),
					-- desc + "fav" in text so typing "dead code"/"fav" filters too.
					text = (is_fav("commands", cm.name) and "fav " or "") .. cm.name .. " " .. cm.desc,
					-- file = the real path -> reuse snacks' file preview, no custom
					-- doc and no reading hundreds of markdown files when the picker opens.
					file = cm.path,
				}
			end
			return items
		end,
		format = function(item)
			local cm = item.cmd
			local star = is_fav("commands", cm.name) and ic.star or " "
			local row = {
				{ star .. " ", "SnacksPickerSpecial" },
				{ ic.f_cmd .. " ", TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ cm.invoke, "SnacksPickerLabel" },
				{ item.pad },
				{ cm.desc, "SnacksPickerDimmed" },
			}
			if cm.scope == "project" then
				row[#row + 1] = { "  project", "SnacksPickerGitBranch" }
			end
			-- Tool without native slash commands: /ecc-* is sent as the file CONTENT, not
			-- a slash command -> say so, so the /ecc-… shown does not mislead.
			if not slash_native(item.tool) then
				row[#row + 1] = { "  " .. ic.f_prompt .. " prompt", "SnacksPickerDimmed" }
			end
			return row
		end,
		preview = "file",
		-- Same layout as the session picker (with the vertical fallback for narrow terminals), but
		-- its own footer: M-t is the only key here that cannot be guessed from the content.
		layout = build_layout(WF_FOOTER),
		actions = {
			-- <A-t>: cycle the tool. Change opts + title then find() - find() calls update_titles
			-- and update_titles reads picker.title, so both always change in the same beat.
			aiterm_wf_tool = function(picker)
				if #tools < 2 then
					notify(("only %s has ECC commands"):format(tools[1].name), "info")
					return
				end
				idx = idx % #tools + 1
				picker.opts.wf_tool = tools[idx].name
				picker.title = title_for(tools[idx], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-f>: pin/unpin the command under the cursor, saved immediately.
			aiterm_fav_toggle = function(picker, item)
				if not item then
					return
				end
				toggle_fav("commands", item.cmd.name)
				picker.title = title_for(find_tool(picker.opts.wf_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-a>: toggle between pinned-only and all.
			aiterm_fav_all = function(picker)
				picker.opts.pinned = not picker.opts.pinned
				picker.title = title_for(find_tool(picker.opts.wf_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
		},
		win = {
			input = {
				keys = {
					["<a-t>"] = { "aiterm_wf_tool", mode = { "i", "n" }, desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", mode = { "i", "n" }, desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", mode = { "i", "n" }, desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-t>"] = { "aiterm_wf_tool", desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			local cm = item.cmd
			-- Compute ARG once: path commands -> "."; ask commands -> prompt (cancel sends nothing).
			local arg
			if path_args[cm.name] then
				arg = "." -- the command takes [path]; "." = the whole project
			elseif ask_args[cm.name] then
				arg = vim.fn.input(ask_args[cm.name])
				if arg == "" then
					return -- a cancelled input does NOT send a truncated command
				end
			end
			-- Tool runs slash commands natively -> send the /token (+arg). Otherwise (codex) PASTE
			-- THE CONTENT of the command file (exactly what the /command expands to); on a read
			-- error fall back to the /token best-effort.
			local msg
			if slash_native(item.tool) then
				msg = cm.invoke .. (arg and (" " .. arg) or "")
			else
				msg = command_body(cm, arg)
				if not msg then
					notify(("could not read %s; sending slash token"):format(cm.name), "warn")
					msg = cm.invoke .. (arg and (" " .. arg) or "")
				end
			end
			picker:close()
			vim.schedule(function()
				-- the tool COMES FROM THE ITEM, not target_tool(): after <A-t> the shown tool
				-- differs from the default, and codex's /ecc-* pasted into an opencode session is meaningless.
				M.send(msg, { submit = true, tool = item.tool })
			end)
		end,
	})
end

-- Skill picker (<leader>as). UNLIKE M.workflows: commands are repo-level workflows (running
-- git diff / npx), while skills are GUIDANCE DOCS that apply to the selected code
-- -> the message is built from context just like <leader>ai.
-- Shows EVERY skill, grouped by source: ecc (installed by ECC) / builtin (the tool's own skills,
-- e.g. codex's 6 .system ones) / user (hand-written).
local SKILL_ORIGIN = {
	project = { "project", "SnacksPickerGitBranch" }, -- the repo's LOCAL skills, shown first
	ecc = { "ECC", nil }, -- nil -> colored per tool
	builtin = { "built-in", "SnacksPickerSpecial" },
	user = { "user", "SnacksPickerLabel" },
	shared = { "shared", "DiagnosticWarn" }, -- ~/.agents/skills, not activated (amber)
}

function M.skill_pick()
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	local e = ecc()
	if not e then
		notify("aiterm: ECC module unavailable", "warn")
		return
	end
	-- cwd to include the repo's LOCAL skills (origin=project). Uses project_cwd (the real realpath).
	local cwd = history().project_cwd()
	-- Only cycle through tools WITH skills: cycling into an empty list makes <A-t> look broken.
	local tools = {}
	for _, t in ipairs(M.config.tools) do
		if #e.skill_list(t.name, cwd) > 0 then
			tools[#tools + 1] = t
		end
	end
	if #tools == 0 then
		notify("no skills found for any tool - use <leader>aE", "warn")
		return
	end
	local idx = 1
	local cur = target_tool()
	for i, t in ipairs(tools) do
		if cur and t.name == cur.name then
			idx = i
		end
	end
	-- CAPTURE context BEFORE opening the picker: opening it switches buffer/window, so capture_context
	-- at confirm time would read the picker window itself.
	local ctx = capture_context()
	ensure_hl()

	-- Entries shown in pinned mode: pinned OR the repo's own skills (project always shows).
	local function shown_in_pinned(s)
		return is_fav("skills", s.name) or s.origin == "project"
	end
	-- Whether any pinned/project entry is visible in the current cwd. Used to NOT open pinned
	-- mode when the pinned set is empty here (e.g. only another repo's project skill is pinned) -> avoids
	-- picker "No Results".
	local function pinned_has_items(t)
		for _, s in ipairs(e.skill_list(t.name, cwd)) do
			if shown_in_pinned(s) then
				return true
			end
		end
		return false
	end
	local function title_for(t, pinned)
		local n_show, n_all = 0, 0
		for _, s in ipairs(e.skill_list(t.name, cwd)) do
			n_all = n_all + 1
			if shown_in_pinned(s) then
				n_show = n_show + 1
			end
		end
		local mode = pinned and (M.icons().star .. " %d pinned"):format(n_show) or ("all %d"):format(n_all)
		return ("Skills (%s) · %s"):format(t.name, mode)
	end

	-- Open pinned only when a pinned/project entry IS visible in this cwd (avoids "No Results"
	-- when only another repo's project skill is pinned).
	local start_pinned = fav_count("skills") > 0 and pinned_has_items(tools[idx])
	Snacks.picker({
		title = title_for(tools[idx], start_pinned),
		sk_tool = tools[idx].name,
		pinned = start_pinned,
		finder = function(popts)
			local t = find_tool(popts.sk_tool) or tools[1]
			local list = e.skill_list(t.name, cwd)
			-- pinned: filter to pinned + project. If that is EMPTY (or all mode) -> show
			-- everything, sorting project/pinned first. The empty -> all fallback means never "No Results".
			local shown = {}
			if popts.pinned then
				for _, s in ipairs(list) do
					if shown_in_pinned(s) then
						shown[#shown + 1] = s
					end
				end
			end
			if not popts.pinned or #shown == 0 then
				shown = {}
				for _, s in ipairs(list) do
					shown[#shown + 1] = s
				end
				table.sort(shown, function(a, b)
					local ra = a.origin == "project" and 0 or (is_fav("skills", a.name) and 1 or 2)
					local rb = b.origin == "project" and 0 or (is_fav("skills", b.name) and 1 or 2)
					if ra ~= rb then
						return ra < rb
					end
					return a.name < b.name
				end)
			end
			local w = 0
			for _, s in ipairs(shown) do
				w = math.max(w, #s.name)
			end
			local items = {}
			for _, s in ipairs(shown) do
				-- scope: project / shared (~/.agents/skills, not activated) / global.
				-- source: provenance if aiterm added the skill via the skills CLI.
				local scope = (s.origin == "project" or s.origin == "shared") and s.origin or "global"
				local prov = skill_source(t.name, s.name)
				local source = prov and prov.source or nil
				items[#items + 1] = {
					skill = s,
					tool = t,
					scope = scope,
					source = source,
					pad = string.rep(" ", w - #s.name + 2),
					-- origin/scope/source/"fav" in text -> typing "ecc"/"project"/"global"/
					-- "vercel"/"fav" filters by group.
					text = table.concat({
						s.origin,
						scope,
						source or "",
						is_fav("skills", s.name) and "fav" or "",
						s.name,
						s.desc,
					}, " "),
					file = s.path, -- preview SKILL.md directly, no custom doc
				}
			end
			return items
		end,
		format = function(item)
			local o = SKILL_ORIGIN[item.skill.origin] or SKILL_ORIGIN.user
			local star = is_fav("skills", item.skill.name) and M.icons().star or " "
			local row = {
				{ star .. " ", "SnacksPickerSpecial" },
				{ ("%-9s "):format(o[1]), o[2] or TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ item.skill.name, "SnacksPickerLabel" },
				{ item.pad },
				{ item.skill.desc, "SnacksPickerDimmed" },
			}
			-- scope badge (project/shared/global) + the real source (if there is provenance).
			local scope_hl = "SnacksPickerDimmed"
			if item.scope == "project" then
				scope_hl = "SnacksPickerGitBranch"
			elseif item.scope == "shared" then
				scope_hl = "DiagnosticWarn" -- amber: not activated for this tool
			end
			row[#row + 1] = { "  " .. item.scope, scope_hl }
			if item.source then
				row[#row + 1] = { "  " .. item.source, "SnacksPickerSpecial" }
			end
			return row
		end,
		preview = "file",
		layout = build_layout(SKILL_FOOTER),
		actions = {
			aiterm_skill_tool = function(picker)
				if #tools < 2 then
					notify(("only %s has skills"):format(tools[1].name), "info")
					return
				end
				idx = idx % #tools + 1
				picker.opts.sk_tool = tools[idx].name
				picker.title = title_for(tools[idx], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-f>: pin/unpin the skill under the cursor, saved immediately.
			aiterm_fav_toggle = function(picker, item)
				if not item then
					return
				end
				toggle_fav("skills", item.skill.name)
				picker.title = title_for(find_tool(picker.opts.sk_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
			-- <A-a>: toggle between pinned-only and all.
			aiterm_fav_all = function(picker)
				picker.opts.pinned = not picker.opts.pinned
				picker.title = title_for(find_tool(picker.opts.sk_tool) or tools[1], picker.opts.pinned)
				picker:find({ refresh = true })
			end,
		},
		win = {
			input = {
				keys = {
					["<a-t>"] = { "aiterm_skill_tool", mode = { "i", "n" }, desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", mode = { "i", "n" }, desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", mode = { "i", "n" }, desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-t>"] = { "aiterm_skill_tool", desc = "switch tool" },
					["<a-f>"] = { "aiterm_fav_toggle", desc = "pin / unpin" },
					["<a-a>"] = { "aiterm_fav_all", desc = "pinned / all" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			local s = item.skill
			-- A 'shared' skill (~/.agents/skills) is not in a dir the tool READS -> the tool cannot see "Use the x
			-- skill". Symlink it into the tool's dir first, then send.
			if s.origin == "shared" then
				local yes = vim.fn.confirm(
					("'%s' is not active for %s.\nSymlink it into the tool's dir and use it?"):format(
						s.name,
						item.tool.name
					),
					"&Yes\n&No",
					1
				)
				if yes ~= 1 then
					return
				end
				if activate_skill(item.tool, s.name) == "error" then
					notify(("could not symlink %s into %s"):format(s.name, item.tool.name), "warn")
					return
				end
				local e = ecc()
				if e then
					e.refresh()
				end
			end
			local instr = ("Use the `%s` skill."):format(s.name)
			if s.hint then
				-- A skill declaring argument-hint NEEDS an argument (tdd-workflow needs a
				-- plan path). A cancelled input sends nothing; never send a truncated command.
				local answer = vim.fn.input(("%s %s: "):format(s.name, s.hint))
				if answer == "" then
					return
				end
				instr = instr .. " " .. answer
			end
			picker:close()
			vim.schedule(function()
				-- Without context send instr directly: build_message always inserts a blank line
				-- after the instruction (to separate it from @ref); without @ref that blank line
				-- becomes trailing junk. M.actions never hits this case because it refuses up front when
				-- both file and code are missing.
				local msg = (ctx.file or ctx.code) and build_message(instr, ctx) or instr
				-- the tool COMES FROM THE ITEM: <A-t> allows a tool other than the open session's.
				M.send(msg, { submit = true, tool = item.tool })
			end)
		end,
	})
end

-- Per-tool ECC status + install/update. The "ecc" picker row disappears after
-- installing, so this is the path for later updates (git pull). <leader>aE.
function M.ecc()
	local e = ecc()
	if not e then
		notify("ECC module unavailable", "warn")
		return
	end
	if not (_G.Snacks and Snacks.picker) then
		notify("aiterm: snacks.nvim picker required", "warn")
		return
	end
	ensure_hl()

	local clone = e.clone_info()
	-- The <A-u> result is kept here so a find() redraw keeps it. nil = GitHub never asked;
	-- NOT asked when the picker opens: ls-remote measured ~1s, blocking that long is noticeable.
	local remote, remote_err
	local function title()
		if not clone then
			return "ECC  (not cloned)"
		end
		local t = ("ECC  %s"):format(clone.version or "?")
		if clone.short then
			t = t .. " · " .. clone.short
		end
		if remote_err then
			return t .. "  (github: " .. remote_err .. ")"
		elseif remote then
			-- ASCII in literals: odd characters slipped into this file three times, so the glyph gate
			-- stays at 0 for new lines. Arrows/ellipses are not worth an exception.
			return t .. (remote == clone.short and "  = origin" or ("  <- origin " .. remote))
		end
		return t
	end
	Snacks.picker({
		title = title(),
		finder = function()
			local items = {}
			for _, t in ipairs(M.config.tools) do
				local st = e.status(t.name)
				local it = {
					tool = t,
					state = st,
					info = e.installed_info(t.name),
					cmds = e.count(t.name),
					skills = vim.tbl_count(e.skills(t.name)),
					text = t.name .. " " .. st,
				}
				it.preview = ecc_preview(it, e, clone, remote)
				items[#items + 1] = it
			end
			return items
		end,
		format = function(item)
			local s = ECC_STATE[item.state] or ECC_STATE.unknown
			local ver = item.info and item.info.version or "-"
			if item.info and item.info.short then
				ver = ver .. " · " .. item.info.short
			end
			return {
				{ (M.icons()[item.tool.name] or " ") .. " ", TOOL_HL[item.tool.name] or "SnacksPickerSpecial" },
				{ ("%-9s "):format(item.tool.name), "SnacksPickerLabel" },
				{ ("%-14s"):format(s[1]), s[2] },
				{ ("%-18s"):format(ver), "SnacksPickerDimmed" },
				{ ("%4d cmd  %4d skills"):format(item.cmds, item.skills), "SnacksPickerDimmed" },
			}
		end,
		-- item.preview = { text, extmarks } prebuilt in the finder, the same shape M.pick
		-- uses: no need to touch snacks' preview-function API.
		preview = "preview",
		layout = build_layout(ECC_FOOTER),
		actions = {
			-- <A-u>: the ONLY time the plugin hits the network, and only when you press it. ls-remote only asks
			-- for origin's HEAD, downloads nothing.
			aiterm_ecc_remote = function(picker)
				notify("asking GitHub...", "info")
				e.remote_head(function(sha, err)
					remote, remote_err = sha, err
					if not picker.closed then
						picker.title = title()
						picker:find({ refresh = true })
					end
				end)
			end,
		},
		win = {
			input = {
				keys = {
					["<a-u>"] = { "aiterm_ecc_remote", mode = { "i", "n" }, desc = "check github" },
					["<a-?>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "show keys" },
				},
			},
			list = {
				keys = {
					["<a-u>"] = { "aiterm_ecc_remote", desc = "check github" },
					["<a-?>"] = { "toggle_help_list", desc = "show keys" },
				},
			},
		},
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()
			vim.schedule(function()
				install_ecc(item.tool)
			end)
		end,
	})
end

-- inline hints (code-lens style inlays) ------------------------------------
-- 1 virtual line above the function/class CONTAINING the cursor, advertising <leader>ai.
-- Terminal virt_text is NOT clickable -> the hint is only a visual cue; activation
-- still goes through <leader>ai (acting on the node under the cursor, see capture_context).
local hint_ns = vim.api.nvim_create_namespace("aiterm_hints")
local hints_on -- nil until the first read -> taken from M.config.hints.enabled
local hint_state = {} -- buf -> start row of the drawn node (skip redraws while the node is unchanged)

local function hints_enabled()
	if hints_on == nil then
		hints_on = M.config.hints.enabled
	end
	return hints_on
end

-- Regular file buffer (empty buftype) with a treesitter parser.
local function hintable_buf(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
		return false
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	return ok and parser ~= nil
end

local function clear_hints(buf)
	pcall(vim.api.nvim_buf_clear_namespace, buf, hint_ns, 0, -1)
	hint_state[buf] = nil
end

-- Redraw the hint for buf. Only draws when buf is in the current window (the hint follows the cursor).
refresh_hints = function(buf) -- assigned to the local forward-declared in the default tool section
	buf = buf or vim.api.nvim_get_current_buf()
	if not (hints_enabled() and hintable_buf(buf) and buf == vim.api.nvim_get_current_buf()) then
		clear_hints(buf)
		return
	end
	local node = enclosing_node()
	local sr = node and select(1, node:range()) or nil
	if sr == hint_state[buf] then -- same node -> no flicker
		return
	end
	pcall(vim.api.nvim_buf_clear_namespace, buf, hint_ns, 0, -1)
	hint_state[buf] = sr
	if not sr then
		return
	end
	-- align with the indent of the node's first line so the virtual line lines up with the code.
	local first = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
	local indent = first:match("^%s*") or ""

	-- Badge: icon+name of the default tool (colored per tool) + actions with icons + dimmed keys.
	local tool = resolve_default_tool()
	local ic = M.icons()
	local thl = TOOL_HL[tool.name] or "Special"
	local vt = {
		{ indent, "Normal" },
		{ tool_icon(tool) .. " ", thl },
		{ tool.name .. "   ", thl },
	}
	for i, akey in ipairs(M.config.hints.actions or {}) do
		if i > 1 then
			vt[#vt + 1] = { " · ", "NonText" }
		end
		if ic[akey] then
			vt[#vt + 1] = { ic[akey] .. " ", thl }
		end
		vt[#vt + 1] = { akey, "Comment" }
	end
	if M.config.hints.key then
		vt[#vt + 1] = { "   " .. M.config.hints.key, "NonText" }
	end

	pcall(vim.api.nvim_buf_set_extmark, buf, hint_ns, sr, 0, {
		virt_lines = { vt },
		virt_lines_above = true,
		hl_mode = "combine",
	})
end

-- Register the refresh autocmds (idempotent). Called from the VeryLazy bootstrap and toggle.
local hints_group
function M.setup_hints()
	ensure_hl() -- registers AitermClaude/Codex/Opencode so the badge gets tool colors (Snacks is loaded at VeryLazy)
	if not hints_enabled() or hints_group then
		return
	end
	hints_group = vim.api.nvim_create_augroup("AitermHints", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold", "BufEnter", "TextChanged", "InsertLeave" }, {
		group = hints_group,
		callback = function(args)
			refresh_hints(args.buf)
		end,
	})
	refresh_hints()
end

-- Toggle hints. Off -> clear every extmark in every buffer.
function M.toggle_hints()
	hints_on = not hints_enabled()
	if hints_on then
		M.setup_hints()
		refresh_hints()
	else
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			clear_hints(b)
		end
	end
	notify("AI code hints " .. (hints_on and "on" or "off"), "info")
end

-- Read the saved default tool + favorites + skill provenance right on require.
load_default()
load_favorites()
load_skill_src()

return M
