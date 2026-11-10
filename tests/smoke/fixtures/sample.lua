local M = {}

local function add(a, b)
	if a > b then
		return a + b
	end
	for i = 1, 3 do
		print(i)
	end
	return b
end

function M.run(x)
	local y = add(x, 2)
	return y
end

return M
