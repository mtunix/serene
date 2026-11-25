-- The few words a spec is written in (loaded by run.py before each spec, after wow.lua):
--
--   test("what it checks", function() ... end)
--   eq(actual, expected, [what])   deep equality (tables compared by their contents)
--   ok(value, [what])              truthy
--   no(value, [what])              falsy
--   raises(fn, [pattern])          fn errors (and its message has the pattern)
--   clean()                        no errors caught in the addon's scripts, timers or hooks so far
--
-- Every test runs in a fresh Lua with a fresh stub of the game: a spec's top level (loading the addon, filling
-- wow.items...) runs again before each test, so tests can't leak into each other.

local tests = {}
_G.__tests = tests

function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function show(value, depth)
	depth = depth or 0
	if type(value) == "string" then return string.format("%q", value) end
	if wow.isSecret(value) then return "<secret>" end
	if type(value) ~= "table" or depth > 3 then return tostring(value) end
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = (type(key) == "string" and key or ("[" .. tostring(key) .. "]")) .. " = " .. show(value[key], depth + 1)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end
_G.show = show

local function same(a, b, seen)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	seen = seen or {}
	if seen[a] == b then return true end
	seen[a] = b
	for key, value in pairs(a) do if not same(value, b[key], seen) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

function eq(actual, expected, what)
	if not same(actual, expected) then
		error((what and (what .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
	end
end

function ok(value, what)
	if not value then error((what or "expected a true value") .. " (got " .. show(value) .. ")", 2) end
	return value
end

function no(value, what)
	if value then error((what or "expected a false value") .. " (got " .. show(value) .. ")", 2) end
end

function raises(fn, pattern)
	local good, problem = pcall(fn)
	if good then error("expected an error" .. (pattern and (" matching " .. pattern) or ""), 2) end
	if pattern and not tostring(problem):find(pattern) then
		error("expected an error matching " .. pattern .. ", got: " .. tostring(problem), 2)
	end
end

-- Leave the test without a verdict (e.g. a fixture not captured yet): reported as skipped, not failed.
function skip(reason) error({ skipped = reason or "skipped" }, 2) end

function clean()
	if #wow.errors > 0 then
		local lines = {}
		for _, e in ipairs(wow.errors) do lines[#lines + 1] = e.where .. ": " .. e.message end
		error(#wow.errors .. " error(s) in the addon's scripts:\n" .. table.concat(lines, "\n"), 2)
	end
	local red = wow.redLines()
	if #red > 0 then error("a module's init failed:\n" .. table.concat(red, "\n"), 2) end
end

-- Run one test (by its index); returns true, or false and the message.
function __run(index)
	local t = tests[index]
	local traced
	local skipped
	local good = xpcall(t.fn, function(problem)
		if type(problem) == "table" and problem.skipped then skipped = problem.skipped return end
		traced = debug.traceback(tostring(problem), 2)
	end)
	if skipped then return "skip", skipped end
	return good, traced
end
