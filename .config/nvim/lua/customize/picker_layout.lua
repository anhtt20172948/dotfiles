-- Snacks picker geometry. The preset is chosen from the editor size each time
-- a picker opens, so the preview keeps the same share of the space instead of
-- shrinking to a few unreadable rows in a short terminal or split.
local M = {}

M.WIDE_COLUMNS = 110 -- side-by-side list and preview from this width
M.PREVIEW_MIN_LINES = 25 -- stacked preview gets at least 8 rows from this height
M.PREVIEW_WIDTH = 0.45 -- share of the picker given to a side-by-side preview
M.PREVIEW_HEIGHT = 0.4 -- share of the picker given to a stacked preview

function M.preset(columns, lines)
	if columns >= M.WIDE_COLUMNS then
		return "default"
	end
	-- Too short to stack a useful preview: start list-only, <a-p> shows it.
	return lines >= M.PREVIEW_MIN_LINES and "vertical" or "vertical_list"
end

function M.layouts()
	return {
		default = {
			layout = {
				border = "none",
				backdrop = false,
				min_width = 0,
				width = 0.9,
				[2] = { width = M.PREVIEW_WIDTH },
			},
		},
		vertical = {
			layout = {
				backdrop = false,
				min_width = 0,
				width = 0.95,
				min_height = 0,
				[3] = { height = M.PREVIEW_HEIGHT },
			},
		},
		vertical_list = { preset = "vertical", hidden = { "preview" } },
	}
end

function M.config()
	return {
		preset = function()
			return M.preset(vim.o.columns, vim.o.lines)
		end,
	}
end

return M
