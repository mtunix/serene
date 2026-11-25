-- Setup.lua: on the account's first login the setup's welcome, after an update only what's new (once), nothing when
-- it was seen; the presets set what they say and give the rest of their keys back; the last page reloads only when a
-- setting read at login changed; and the lists the setup keeps agree with the panel, DEFAULTS and the TOC.

local ns = wow.load()

local LATEST = ns.Setup.news[#ns.Setup.news][1]

-- A shown text in the setup containing these words, and the frame holding it.
local function Seen(words)
	local function Walk(frame)
		for _, region in ipairs({ frame:GetRegions() }) do
			local text = region.GetText and region:GetText()
			if type(text) == "string" and text:find(words, 1, true) and region:IsVisible() then return region, frame end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			local region, owner = Walk(child)
			if region then return region, owner end
		end
	end
	if not (SereneSetup and SereneSetup:IsShown()) then return nil end
	return Walk(SereneSetup)
end

local function Press(words)
	local _, button = Seen(words)
	assert(button and button:IsObjectType("Button"), "no button saying " .. words)
	button:Click()
end

local function Card(key)
	for _, f in ipairs(wow.frames) do
		local preset = rawget(f, "preset")
		if preset and preset.key == key then return f end
	end
end

local function Preset(key)
	for _, preset in ipairs(ns.Setup.presets) do
		if preset.key == key then return preset end
	end
end

local function Settings()
	local copy = {}
	for key, value in pairs(ns.db) do
		if type(value) ~= "table" and key ~= "settingsPage" then copy[key] = value end
	end
	return copy
end

test("the first login opens the setup's welcome a moment later", function()
	wow.login(nil)
	wow.advance(1)
	no(SereneSetup and SereneSetup:IsShown(), "not at once")
	wow.advance(2)
	ok(Seen("Welcome to Serene"), "the welcome page")
	no(Seen("New in Serene"), "not the news")
	eq(ns.db.setupSeen, LATEST, "the news counts as seen")
	clean()
end)

test("Keep the defaults on the welcome page changes nothing", function()
	wow.login(nil)
	wow.advance(3)
	local before = Settings()
	Press("Keep the defaults")
	no(SereneSetup:IsShown(), "closed")
	eq(Settings(), before)
	no(wow.reloaded, "no reload")
	clean()
end)

test("an update shows only what's new, and only once", function()
	wow.login({ rest = 35 })
	wow.advance(3)
	ok(Seen("New in Serene " .. LATEST), "the news")
	no(Seen("Welcome to Serene"), "not the welcome")
	eq(ns.db.setupSeen, LATEST)
	Press("Done")
	no(SereneSetup:IsShown(), "closed")
	no(wow.reloaded, "no reload")
	clean()
end)

test("once seen, nothing opens", function()
	wow.login({ setupSeen = LATEST })
	wow.advance(5)
	no(SereneSetup and SereneSetup:IsShown())
	clean()
end)

test("the news since the version seen, versions in number order", function()
	local Note = ns.SettingsKit.Note
	local news = ns.Setup.news
	for i = #news, 1, -1 do news[i] = nil end
	news[1] = { "1.9.0", "Nine", function(c) Note(c, "Something from nine.") end }
	news[2] = { "1.10.0", "Ten", function(c) Note(c, "Something from ten.") end }
	wow.login({ setupSeen = "1.9.0" })
	wow.advance(3)
	ok(Seen("New in Serene 1.10.0"), "titled by the newest")
	ok(Seen("Something from ten."), "ten is new")
	no(Seen("Something from nine."), "nine was seen")
	eq(ns.db.setupSeen, "1.10.0")
	clean()
end)

test("the presets set what they say; picking another gives the rest back", function()
	wow.login({ setupSeen = LATEST, rest = 35, lineTime = 90 })
	ns.OpenSetup("setup")
	Press("Set up")
	ok(Seen("How much Serene"), "the presets' page")
	Card("light"):Click()
	for key, value in pairs(Preset("light").values) do eq(ns.db[key], value, "light: " .. key) end
	Card("serene"):Click()
	for key in pairs(Preset("light").values) do eq(ns.db[key], ns.DEFAULTS[key], "serene: " .. key) end
	Card("view"):Click()
	eq(ns.db.fade, false, "view: no fading")
	eq(ns.db.actionBars, true, "view: Serene's bars")
	eq(ns.db.rest, 35, "a setting no preset names stays")
	eq(ns.db.lineTime, 90, "a setting no preset names stays")
	clean()
end)

-- Through every page to the last; the last button's word, and whether it reloaded.
local function Through(key)
	ns.OpenSetup("setup")
	Press("Set up")
	Card(key):Click()
	for _ = 1, #ns.Setup.news + 10 do
		if not Seen("Next") then break end
		Press("Next")
		wow.advance(0.2)
	end
	ok(Seen("Ready"), "the last page")
end

test("the last page reloads only when a setting read at login changed", function()
	wow.login({ setupSeen = LATEST })
	Through("view")
	Press("Done")
	no(SereneSetup:IsShown(), "closed")
	no(wow.reloaded, "nothing needed a reload")
	Through("light")
	ok(Seen("put in place by a reload"), "says so")
	Press("Reload")
	ok(wow.reloaded, "reloaded")
	clean()
end)

test("Skip to the end, Back, and the pages in a fight", function()
	wow.login({ setupSeen = LATEST })
	ns.OpenSetup("setup")
	Press("Set up")
	Press("Next")
	ok(Seen("Fading"), "fading")
	wow.fight(true)
	Press("Fade what you don't need")
	eq(ns.db.fade, false, "a row changes its setting")
	Press("Back")
	ok(Seen("How much Serene"), "back")
	Press("Skip to the end")
	ok(Seen("Ready"), "the last page")
	wow.fight(false)
	clean()
end)

test("/serene setup and /serene news open it", function()
	wow.login({ setupSeen = LATEST })
	wow.slash("/serene setup")
	ok(Seen("Welcome to Serene"), "setup")
	wow.slash("/serene news")
	ok(Seen("New in Serene"), "news")
	no(Seen("Welcome to Serene"), "one page at a time")
	clean()
end)

test("every preset sets real settings, each of its own type", function()
	local wrong = {}
	for _, preset in ipairs(ns.Setup.presets) do
		for key, value in pairs(preset.values) do
			if type(ns.DEFAULTS[key]) ~= type(value) then
				wrong[#wrong + 1] = preset.key .. "." .. key
			end
		end
	end
	eq(wrong, {})
end)

test("the setup's reload settings are the panel's", function()
	local text = assert(io.open(wow.root .. "/Settings.lua")):read("*a")
	local panel = { auraFrame = true } -- (a Choice: the panel asks for its reload in `after`)
	for key, opts in text:gmatch('\n%s+Toggle%([%w_]+, "[^"\n]*", "([%w_]+)", (%b{})') do
		if opts:find("reload = true", 1, true) then panel[key] = true end
	end
	local setup = {}
	for _, key in ipairs(ns.Setup.reload) do setup[key] = true end
	eq(setup, panel)
end)

test("the newest news is no newer than the TOC's version", function()
	local toc = assert(io.open(wow.root .. "/Serene.toc")):read("*a")
	local version = toc:match("## Version: ([%d%.]+)")
	local function Parts(v)
		local list = {}
		for n in v:gmatch("%d+") do list[#list + 1] = tonumber(n) end
		return list
	end
	local a, b = Parts(LATEST), Parts(version)
	local newer = false
	for i = 1, math.max(#a, #b) do
		if (a[i] or 0) ~= (b[i] or 0) then newer = (a[i] or 0) > (b[i] or 0) break end
	end
	no(newer, ("news for %s, the TOC says %s"):format(LATEST, version))
end)
