-- Things this client won't take, checked in the source.

local function Code(file)
	local lines = {}
	for line in io.lines(wow.root .. "/" .. file) do lines[#lines + 1] = (line:gsub("%-%-.*$", "")) end
	return lines
end

test("no texture is given the TRILINEAR filter (it crashes this client at login)", function()
	local found = {}
	for _, file in ipairs(wow.tocFiles()) do
		for number, line in ipairs(Code(file)) do
			if line:find("TRILINEAR", 1, true) then found[#found + 1] = file .. ":" .. number end
		end
	end
	eq(found, {})
end)
