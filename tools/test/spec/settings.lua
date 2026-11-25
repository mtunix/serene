-- Settings agree everywhere: what the files read is declared in Core.lua's DEFAULTS (or is a known piece of saved
-- state), every default is used, a setting is never also used as a table of saved state (the barUse bug), the
-- settings panel and /serene only touch real settings, and the migrations at login turn old saved values into
-- valid ones.

local ns = wow.load()

-- Saved, but not settings: state the files keep in SereneDB (so no default). A new one goes here, on purpose.
local STATE = {
	ungrouped = true, topHover = true,                 -- migration flags (Core.lua)
	toastAt = true,                                   -- where the toasts appear (Toasts.lua)
	auraAt = true, auraDebuffFree = true, auraShortSpells = true, -- AuraFrame.lua
	topPos = true, gold = true,                       -- TopBar.lua (gold: money per character)
	settingsPage = true,                              -- the settings panel's page last open
	supplies = true,                                  -- BarSupplies.lua
	ranks = true,                                     -- Ranks.lua
	keyLearn = true,                                  -- BarKeys.lua
	barUseBy = true,                                  -- BarUse.lua, per character
	barSetsBy = true,                                 -- BarSets.lua, per character
	namesSaved = true, namesKeyGiven = true,          -- Names.lua
	tipCompare = true, tipCompareDone = true,         -- Tooltip.lua
	merchantNoted = true, bagsNoted = true,           -- one-time notes said
	bankPos = true, bagsPos = true,                   -- Bags.lua windows placed by hand
	unitsDump = true, capture = true, capturing = true, -- debug dumps, Capture.lua
}
local function IsState(key) return STATE[key] or key:find("^probe") ~= nil end

local function Files()
	local list = {}
	for _, file in ipairs(wow.tocFiles()) do
		local text = assert(io.open(wow.root .. "/" .. file)):read("*a")
		list[#list + 1] = { name = file, text = text }
	end
	return list
end

local function Line(text, at)
	local _, count = text:sub(1, at):gsub("\n", "")
	return count + 1
end

-- Every setting a file reads, with where: { key, file, line }.
local function Reads()
	local found = {}
	local patterns = { 'ns%.On%("([%w_]+)"%)', "ns%.db%.([%w_]+)", "SereneDB%.([%w_]+)", '[^%w_]S%("([%w_]+)"',
		'[^%w_]Num%("([%w_]+)"', '[^%w_]Setting%("([%w_]+)"' }
	for _, f in ipairs(Files()) do
		local list = { unpack(patterns) }
		-- (files that read through a local db = ns.db)
		if f.text:find("local db = ns%.db") then list[#list + 1] = "[^%w_%.]db%.([%w_]+)" end
		for _, pattern in ipairs(list) do
			local at = 1
			while true do
				local s, e, key = f.text:find(pattern, at)
				if not s then break end
				found[#found + 1] = { key = key, file = f.name, line = Line(f.text, s) }
				at = e + 1
			end
		end
	end
	return found
end

test("every setting the files read is in DEFAULTS, or known saved state", function()
	local unknown = {}
	for _, r in ipairs(Reads()) do
		if ns.DEFAULTS[r.key] == nil and not IsState(r.key) then
			unknown[#unknown + 1] = ("%s:%d %s"):format(r.file, r.line, r.key)
		end
	end
	eq(unknown, {}, "read but not declared (a typo, or a new piece of state for STATE above)")
end)

test("every default is used by some file", function()
	local all = {}
	for _, f in ipairs(Files()) do
		local text = f.text
		if f.name == "Core.lua" then
			-- (Core.lua without its DEFAULTS block)
			local s, e = text:find("ns%.DEFAULTS = %b{}")
			text = text:sub(1, s - 1) .. text:sub(e + 1)
		end
		all[#all + 1] = text
	end
	local text = table.concat(all, "\n")
	local unused = {}
	for key in pairs(ns.DEFAULTS) do
		if not text:find("%f[%w_]" .. key .. "%f[^%w_]") then unused[#unused + 1] = key end
	end
	table.sort(unused)
	eq(unused, {}, "declared in DEFAULTS but read nowhere")
end)

test("no setting is also used as a table of saved state", function()
	local clashes = {}
	for _, f in ipairs(Files()) do
		for _, pattern in ipairs({ "ns%.db%.([%w_]+)%s*%[", "ns%.db%.([%w_]+)%.[%a_]", "ns%.db%.([%w_]+)%s*=%s*{" }) do
			local at = 1
			while true do
				local s, e, key = f.text:find(pattern, at)
				if not s then break end
				local default = ns.DEFAULTS[key]
				if default ~= nil and type(default) ~= "table" then
					clashes[#clashes + 1] = ("%s:%d %s (its default is %s)"):format(f.name, Line(f.text, s), key, tostring(default))
				end
				at = e + 1
			end
		end
	end
	eq(clashes, {}, "a setting indexed like a table")
end)

-- The settings panel: every Toggle/Choice/Slider path and every `depends` names a real setting of the right kind,
-- and a Choice offers only values the setting's comment in DEFAULTS lists.
local function Panel()
	local text = assert(io.open(wow.root .. "/Settings.lua")):read("*a")
	local controls = {}
	local at = 1
	while true do
		local s, e, kind, path = text:find('\n%s+(%a+)%([%w_]+, "[^"\n]*", "([%w_%.]+)"', at)
		if not s then break end
		if kind == "Toggle" or kind == "Choice" or kind == "Slider" then
			-- (the call runs until the next statement)
			local stop = text:find("\n%s+[%a_][%w_]*%(", e) or #text
			controls[#controls + 1] = { kind = kind, path = path, body = text:sub(e, stop), line = Line(text, s + 1) }
		end
		at = e + 1
	end
	return controls, text
end

local function Default(path)
	local first, rest = path:match("^([%w_]+)%.([%w_]+)$")
	if first then return type(ns.DEFAULTS[first]) == "table" and ns.DEFAULTS[first][rest] or nil end
	return ns.DEFAULTS[path]
end

local function Comment(key)
	for line in io.lines(wow.root .. "/Core.lua") do
		local k, comment = line:match("^%s+([%w_]+)%s*=.-%-%-(.*)$")
		if k == key then return comment end
	end
end

test("the settings panel's controls name real settings of the right kind", function()
	local controls, text = Panel()
	ok(#controls > 60, "found the panel's controls (" .. #controls .. ")")
	local wrong = {}
	local want = { Toggle = "boolean", Choice = "string", Slider = "number" }
	for _, c in ipairs(controls) do
		local default = Default(c.path)
		if type(default) ~= want[c.kind] then
			wrong[#wrong + 1] = ("Settings.lua:%d %s %q: default is %s"):format(c.line, c.kind, c.path, tostring(default))
		end
	end
	for list in text:gmatch("depends = (%b{})") do
		for key in list:gmatch('"!?([%w_%.]+)"') do
			if type(Default(key)) ~= "boolean" then wrong[#wrong + 1] = "depends on " .. key .. ": not a boolean setting" end
		end
	end
	eq(wrong, {})
end)

test("a Choice in the panel offers only what its setting's comment lists", function()
	local wrong = {}
	for _, c in ipairs(Panel()) do
		if c.kind == "Choice" and not c.path:find("%.") then
			local comment = Comment(c.path) or ""
			local body = c.body:gsub("depends = %b{}", "")
			for value in body:gmatch('{%s*"([%w_]+)",%s*"') do
				if not comment:find('"' .. value .. '"', 1, true) then
					wrong[#wrong + 1] = ("Settings.lua:%d %s offers %q; Core.lua's comment doesn't list it"):format(c.line, c.path, value)
				end
			end
		end
	end
	eq(wrong, {})
end)

test("the panel opens and every control's setting survives a round of clicks", function()
	wow.login(nil)
	wow.advance(1)
	ok(ns.OpenSettings, "ns.OpenSettings")
	ns.OpenSettings()
	wow.advance(0.5)
	-- (click every check button and every button the panel made: each changes or applies a setting)
	for _, f in ipairs(wow.frames) do
		if f:IsObjectType("Button") and not f:GetName() and wow.state(f).scripts.OnClick then
			local p, inside = f, false
			while p do
				if p:GetName() == "SereneSettingsPanel" then inside = true break end
				p = p:GetParent()
			end
			if inside then f:Click() end
		end
	end
	wow.advance(0.5)
	for key, value in pairs(ns.DEFAULTS) do
		if type(value) ~= "table" then eq(type(ns.db[key]), type(value), "type of " .. key) end
	end
	clean()
end)

-- /serene <word> on|off: every word in the help changes exactly one boolean setting from DEFAULTS.
test("each /serene switch changes exactly one boolean setting", function()
	wow.login(nil)
	wow.advance(1)
	local core = assert(io.open(wow.root .. "/Core.lua")):read("*a")
	local order = core:match("local ORDER = (%b{})")
	local wrong, count = {}, 0
	for word in order:gmatch('"([%w_]+)"') do
		count = count + 1
		local before = {}
		for key, value in pairs(ns.db) do if type(value) ~= "table" then before[key] = value end end
		-- (on, then off: one of them changes it, whatever it was)
		local changed, seen = {}, {}
		for _, state in ipairs({ "on", "off" }) do
			wow.slash("/serene " .. word .. " " .. state)
			for key, value in pairs(ns.db) do
				if type(value) ~= "table" and before[key] ~= value and not seen[key] then
					seen[key] = true
					changed[#changed + 1] = key
				end
			end
		end
		if #changed ~= 1 then
			wrong[#wrong + 1] = word .. " changed " .. #changed .. " settings"
		elseif type(ns.DEFAULTS[changed[1]]) ~= "boolean" then
			wrong[#wrong + 1] = word .. " changed " .. changed[1] .. ", not a boolean setting"
		end
	end
	ok(count > 30, "read ORDER from Core.lua")
	eq(wrong, {})
	clean()
end)

-- Migrations ------------------------------------------------------------------------------------------------------------

local MIGRATIONS = {
	{ "an old glow reveal becomes none", { hintReveal = "glow" }, { hintReveal = "none" } },
	{ "names grouped before 'ungrouped' existed: ungrouped once", { group = true }, { group = false, ungrouped = true } },
	{ "after that, grouping is the player's choice", { group = true, ungrouped = true }, { group = true } },
	{ "the top bar rests under the mouse once", { topShow = "always" }, { topShow = "hover", topHover = true } },
	{ "after that, the top bar's choice stays", { topShow = "always", topHover = true }, { topShow = "always" } },
	{ "an unknown aura time becomes outline", { auraTime = "bubble" }, { auraTime = "outline" } },
	{ "a valid aura time stays", { auraTime = "plate" }, { auraTime = "plate" } },
	{ "an unknown unit border becomes line", { unitBorder = "thick" }, { unitBorder = "line" } },
	{ "a setting the player chose is never overwritten", { rest = 35, lineTime = 90 }, { rest = 35, lineTime = 90 } },
	{ "a missing nested default is filled in", { topItems = { gold = false } }, { topItems = { gold = false, clock = true } } },
}

for _, m in ipairs(MIGRATIONS) do
	test("migration: " .. m[1], function()
		wow.login(m[2])
		for key, value in pairs(m[3]) do
			if type(value) == "table" then
				for k, v in pairs(value) do eq(ns.db[key][k], v, key .. "." .. k) end
			else
				eq(ns.db[key], value, key)
			end
		end
	end)
end

test("logging in with your real saved settings (fixtures/saved_settings.lua)", function()
	local chunk = loadfile(wow.root .. "/tools/test/fixtures/saved_settings.lua")
	if not chunk then skip("no fixtures/saved_settings.lua: run tools/test/import_saved.py") end
	local saved = chunk()
	local copy = {}
	for key, value in pairs(saved) do copy[key] = value end
	wow.login(saved)
	wow.advance(3)
	wow.fight(true)
	wow.advance(2)
	wow.fight(false)
	wow.advance(2)
	-- (every value the player chose survives login)
	for key, value in pairs(copy) do
		if type(value) ~= "table" and key ~= "auraTime" and key ~= "unitBorder" and key ~= "hintReveal" then
			eq(ns.db[key], value, "kept " .. key)
		end
	end
	-- (and keys no file reads any more, said, not failed: they only take room)
	local stale = {}
	for key in pairs(copy) do
		if ns.DEFAULTS[key] == nil and not IsState(key) and key ~= "hintLast" then stale[#stale + 1] = key end
	end
	table.sort(stale)
	if #stale > 0 then print("  note: saved keys no file reads any more: " .. table.concat(stale, ", ")) end
	clean()
end)
