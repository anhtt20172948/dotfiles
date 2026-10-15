local M = {}

function M.pick()
	local cwd = vim.fn.getcwd()
	local result = vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain", "-z" }):wait()
	if result.code ~= 0 then
		vim.notify("Cannot list Git worktrees: " .. vim.trim(result.stderr or "Git failed"), vim.log.levels.WARN)
		return
	end

	local items = {}
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
			-- So sánh đường dẫn thật để nhận cả cwd nằm trong thư mục con.
			local current = vim.uv.fs_realpath(cwd) or cwd
			local actual = vim.uv.fs_realpath(path) or path
			if current == actual or vim.startswith(current, actual .. "/") then
				labels[#labels + 1] = "current"
			end
			local suffix = #labels > 0 and (" [" .. table.concat(labels, ", ") .. "]") or ""
			items[#items + 1] = { file = path, text = branch .. "  " .. path .. suffix }
		end
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
