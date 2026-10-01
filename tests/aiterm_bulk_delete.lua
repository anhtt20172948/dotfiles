local root = assert(arg[1], "repository root is required")
package.path = root .. "/.config/nvim/lua/?.lua;" .. root .. "/.config/nvim/lua/?/init.lua;" .. package.path

local picker_spec
local notifications = {}
_G.Snacks = {
	picker = function(spec)
		picker_spec = spec
	end,
	util = { set_hl = function() end },
	notifier = {
		notify = function(message, level)
			notifications[#notifications + 1] = { message = message, level = level }
		end,
	},
}

local aiterm = require("customize.aiterm")
local history = require("customize.aiterm_history")
local original_invalidate = history.invalidate
local invalidations = 0
history.invalidate = function()
	invalidations = invalidations + 1
	original_invalidate()
end
aiterm.pick()
assert(picker_spec and picker_spec.actions.aiterm_delete, "delete action missing")
local action = picker_spec.actions.aiterm_delete
local original_confirm = vim.fn.confirm
local prompt, default, answer, confirms
vim.fn.confirm = function(message, _, choice)
	prompt, default = message, choice
	confirms = (confirms or 0) + 1
	return answer
end

local function session(title)
	local path = vim.fn.tempname() .. ".jsonl"
	vim.fn.writefile({ "{}" }, path)
	return { kind = "past", tool = { name = "claude", cmd = "missing-claude" }, entry = { id = title, title = title, jsonl = path } }
end

local function picker(marked)
	return {
		selected = function()
			return marked
		end,
		refresh = function(self)
			marked = {}
			self.refreshes = (self.refreshes or 0) + 1
		end,
	}
end

local function exists(item)
	return vim.fn.filereadable(item.entry.jsonl) == 1
end

-- No marks: dd still deletes the focused past session.
local single = session("single")
answer = 1
local p = picker({})
action(p, single)
assert(not exists(single) and p.refreshes == 1, "single-session delete regressed")
assert(invalidations == 1, "single delete must invalidate history once")
assert(default == 2, "confirmation must default to No")

-- Marks: one prompt, two deletions, one refresh.
local first, second = session("first"), session("second")
p = picker({ first, second })
local before = confirms
action(p, first)
assert(not exists(first) and not exists(second), "all marked past sessions should be deleted")
assert(p.refreshes == 1 and confirms == before + 1 and prompt:find("2", 1, true), "batch needs one confirmation and refresh")
assert(invalidations == 2 and prompt:find("claude: 2", 1, true), "batch needs one invalidation and tool counts")
assert(prompt:find("first", 1, true) and prompt:find("second", 1, true), "confirmation must name targets")

-- A mixed selection must not touch live sessions.
local past = session("mixed")
local live = { kind = "live", tool = past.tool, session = { id = "live" } }
p = picker({ past, live })
action(p, live)
assert(not exists(past) and p.refreshes == 1, "eligible marked session should be deleted")
assert(invalidations == 3, "mixed selection must invalidate once")
assert(prompt:lower():find("skip", 1, true), "confirmation must explain skipped non-past entries")

-- With no eligible marks, dd must never delete a live session or prompt.
p = picker({ live })
before = confirms
action(p, live)
assert(confirms == before and not p.refreshes, "live-only selection must be ignored")
assert(invalidations == 3, "live-only selection must not invalidate")

-- Cancellation preserves data and marks, with no refresh.
local cancelled = session("cancelled")
answer = 2
p = picker({ cancelled })
action(p, cancelled)
assert(exists(cancelled) and not p.refreshes, "cancel must not delete or refresh")
assert(#p:selected() == 1, "cancel must preserve marks")
assert(invalidations == 3, "cancel must not invalidate")
vim.fn.delete(cancelled.entry.jsonl)

-- Partial failure: continue to next target and report both outcomes.
local good, missing = session("good"), session("missing")
vim.fn.delete(missing.entry.jsonl)
answer = 1
p = picker({ missing, good })
action(p, good)
assert(not exists(good) and p.refreshes == 1, "partial failure must continue and refresh once")
assert(invalidations == 4, "partial failure with success must invalidate once")
assert(#notifications > 0 and notifications[#notifications].level == "warn" and notifications[#notifications].message:find("failed: missing", 1, true), "partial failure needs a warning with failed id")

vim.fn.confirm = original_confirm
history.invalidate = original_invalidate
print("aiterm bulk delete: OK")
