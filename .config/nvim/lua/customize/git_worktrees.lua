local M = {}

function M.pick()
	local cwd = vim.fn.getcwd()
	local result = vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain", "-z" }):wait()
	if result.code ~= 0 then
		vim.notify("Cannot list Git worktrees: " .. vim.trim(result.stderr or "Git failed"), vim.log.levels.WARN)
		return
	end

	local entries, current_entry = {}, nil
	local current = vim.uv.fs_realpath(cwd) or cwd
	for _, record in ipairs(vim.split(result.stdout, "\0\0", { plain = true, trimempty = true })) do
		local fields = vim.split(record, "\0", { plain = true, trimempty = true })
		local path = fields[1]:match("^worktree (.*)$")
		local branch, bare, labels = "detached", false, {}
		for _, field in ipairs(fields) do
			branch = field:match("^branch refs/heads/(.*)$") or branch
			bare = bare or field == "bare"
			if field:match("^locked") then
				labels[#labels + 1] = "locked"
			elseif field:match("^prunable") then
				labels[#labels + 1] = "prunable"
			end
		end
		if path and not bare then
			local entry = { path = path, branch = branch, labels = labels }
			entries[#entries + 1] = entry
			-- So sánh đường dẫn thật để nhận cả cwd nằm trong thư mục con; worktree lồng sâu nhất thắng.
			local actual = vim.uv.fs_realpath(path) or path
			if
				(current == actual or vim.startswith(current, actual .. "/"))
				and (not current_entry or #actual > #current_entry.actual)
			then
				current_entry, entry.actual = entry, actual
			end
		end
	end
	if current_entry then
		current_entry.labels[#current_entry.labels + 1] = "current"
	end

	local items = {}
	for _, entry in ipairs(entries) do
		local suffix = #entry.labels > 0 and (" [" .. table.concat(entry.labels, ", ") .. "]") or ""
		items[#items + 1] = { file = entry.path, text = entry.branch .. "  " .. entry.path .. suffix }
	end

	return Snacks.picker({
		title = "Git Worktrees",
		items = items,
		format = "text",
		preview = "none",
		confirm = function(picker, item)
			if not item then
				return
			end
			picker:close()
			-- Không xóa buffer: giữ nguyên cả các thay đổi chưa lưu.
			local ok, err = pcall(vim.cmd.cd, item.file)
			if not ok then
				vim.notify("Cannot switch Git worktree: " .. tostring(err), vim.log.levels.ERROR)
			end
		end,
	})
end

return M
