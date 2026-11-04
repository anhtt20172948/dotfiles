--- Runs duckdb.yazi only when the duckdb CLI is installed.
--- Otherwise previews fall back to Yazi's built-in code previewer, so a host
--- without duckdb shows plain text instead of a Lua error.

local M = {}

local installed

local function has_duckdb()
	if installed == nil then
		local _, err = Command("duckdb"):arg("--version"):stdout(Command.PIPED):stderr(Command.PIPED):output()
		installed = err == nil
	end
	return installed
end

function M:peek(job)
	return require(has_duckdb() and "duckdb" or "code"):peek(job)
end

-- seek runs in a sync context where Command:output() cannot yield, so it only
-- reads the result peek/preload cached (peek always runs before the first seek).
function M:seek(job)
	return require(installed == false and "code" or "duckdb"):seek(job)
end

function M:preload(job)
	if has_duckdb() then
		return require("duckdb"):preload(job)
	end
	return true
end

return M
