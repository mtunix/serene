local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Serene's setup: a small window of glass in the middle of the screen. On the account's first login it walks through
-- Serene in a few pages: a welcome, how much of Serene (three presets: all of it, always in view, a light touch), then
-- fading, the compass and top bar, the bars and frames, the chat and tooltips, bags and merchants, each already set
-- by the preset; at the end a reload when something chosen needs one. After an update that brings something new, only what's new: its
-- settings, each with its switch. The rows are the settings panel's own and apply at once, as there.
-- /serene setup and /serene news open it again (and two buttons on the panel's General page).

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local GOLD = { 1, 0.82, 0.35 }
local TEXT = { 0.92, 0.91, 0.88 }
local MUTED = ns.MUTED_RGB
local INK = ns.INK
local PAD = 28
local ROWS = 380     -- the rows' width (the panel's own controls); the window only as wide as they are
local WIDTH = ROWS + PAD * 2
local TOP = 92       -- above a page's words: the small heading and the title
local BOTTOM = 72    -- under the page: the dots and the buttons
local CARD_GAP = 8

local kit = ns.SettingsKit or {}
local Header, Toggle, Choice, Slider, Note = kit.Header, kit.Toggle, kit.Choice, kit.Slider, kit.Note

-- Settings a module only reads at login: changed here, the setup ends with a reload. (Settings.lua marks the same
-- ones "reload"; spec/setup.lua holds the two lists together.)
local RELOAD = { "chat", "minimap", "menuBar", "actionBars", "units", "castBar", "auras", "auraUnits", "auraPlates",
	"auraFrame", "bags", "toast" }

-- The presets: what each sets, the rest of the keys any of them touches going back to Serene's defaults (so picking
-- one after another never leaves a mix). Settings no preset names are left as they are.
local PRESETS = {
	{ key = "serene", name = "Serene",
		text = "All of it. The chat, bars, unit frames, buffs, bags and merchant on glass, and what you don't need fades away until it matters.",
		values = {} },
	{ key = "view", name = "Always in view",
		text = "Serene's look everywhere, but nothing fades or rests: the whole interface stays in sight, the quest tracker too.",
		values = { fade = false, idle = false, tracker = false } },
	{ key = "light", name = "A light touch",
		text = "The game's own bars, unit frames, buffs and bags. Serene calms the chat, the tooltips and the map.",
		values = { fade = false, idle = false, tracker = false, actionBars = false, units = false, castBar = false,
			auras = false, menuBar = false, bags = false, merchant = false, swing = false, toast = false, top = false,
			barReady = false, hints = false } },
}

local touched = {} -- every key some preset sets
for _, preset in ipairs(PRESETS) do
	for key in pairs(preset.values) do touched[key] = true end
end

local function Wanted(preset, key)
	local value = preset.values[key]
	if value == nil then value = ns.DEFAULTS[key] end
	return value
end

local function Matches(preset)
	for key in pairs(touched) do
		if ns.db[key] ~= Wanted(preset, key) then return false end
	end
	return true
end

local function Hints()
	if ns.HintsDirty then ns.HintsDirty() end
end

-- What each version brought: its settings as rows, newest last. A version with nothing to switch has no entry.
local NEWS = {
	{ "1.1.0", "Your cast bar", function(c)
		local on = { "castBar" }
		Choice(c, "The time", "castTime", { { "left", "Left" }, { "both", "Left / whole" }, { "none", "None" } },
			{ depends = on })
		Toggle(c, "Your lag at its end", "castLatency", { note = "muted", depends = on })
		Toggle(c, "A channel's ticks", "castTicks", { depends = on })
		Toggle(c, "A soft flash as it ends", "castFlash", { depends = on })
		Toggle(c, "In softly, away slowly", "castFade", { note = "no shake", depends = on })
	end },
}

-- Whether version a is newer than b ("1.10.0" after "1.9.2"; nothing yet is "0").
local function Newer(a, b)
	local x, y = {}, {}
	for n in tostring(a or "0"):gmatch("%d+") do x[#x + 1] = tonumber(n) end
	for n in tostring(b or "0"):gmatch("%d+") do y[#y + 1] = tonumber(n) end
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then return p > q end
	end
	return false
end

-- The setup's pages: the words at the top, then rows of the panel's controls (or the presets' cards).
local PAGES = {
	{ key = "welcome", title = "Welcome to Serene",
		text = "A calm interface: the game's own frames on dark glass, and what you don't need fades away until it matters. A few pages set it up; every choice can be changed later with /serene.",
		build = function(c)
			Note(c, "The chat, unit frames, action bars and buffs restyled in place.")
			Note(c, "Serene's own bags, bank and merchant.")
			Note(c, "The Peek key (Key Bindings, AddOns): everything in sight while held.")
		end },
	{ key = "preset", title = "How much Serene",
		text = "Start from one of these. The next pages are already set by it; change what you like there." },
	{ key = "fade", title = "Fading",
		text = "What you don't need goes away, and comes back under the mouse, in a fight, with a target or while casting.",
		build = function(c)
			Toggle(c, "Fade what you don't need", "fade")
			Toggle(c, "Everything fades when you are idle", "idle")
			Toggle(c, "Hide the quest tracker", "tracker", { note = "a key brings it back" })
		end },
	{ key = "top", title = "Compass and top bar",
		text = "The minimap as a compass, and a band at the top with the zone, your gold, your bags and the time.",
		build = function(c)
			Choice(c, "The compass shows", "compass", { { "hover", "Under the mouse" }, { "world", "Always, but in towns" } },
				{ depends = { "fade", "groups.minimap" } })
			Toggle(c, "The top bar", "top")
			Choice(c, "The top bar shows", "topShow",
				{ { "hover", "Under the mouse" }, { "calm", "Away in fights" }, { "always", "Always" } },
				{ depends = { "top", "fade" } })
		end },
	{ key = "frames", title = "Bars and frames",
		text = "The game's own action bars, unit frames and buffs made calm: their art away, flat bars on glass, round icons.",
		build = function(c)
			Toggle(c, "Serene's action bars", "actionBars", { note = "reload", reload = true })
			Choice(c, "Their buttons", "barStyle", { { "classic", "Classic" }, { "glass", "Glass" }, { "round", "Round" } },
				{ depends = { "actionBars", "barStyleSame" } })
			Toggle(c, "Fade what isn't ready", "barReady", { note = "cooldown, range, mana" })
			Toggle(c, "Glow on buttons worth using", "hints", { note = "food, a missing buff", after = Hints })
			Toggle(c, "Serene's unit frames", "units", { note = "reload", reload = true })
			Toggle(c, "Your cast bar made calm", "castBar", { note = "reload", reload = true })
			Toggle(c, "Serene's buffs and debuffs", "auras", { note = "reload", reload = true })
		end },
	{ key = "chat", title = "Chat and tooltips",
		text = "Each message on a soft glass of its own, fading after a while; fewer and shorter lines for loot and channels.",
		build = function(c)
			Toggle(c, "Chat in glass", "chat", { note = "reload", reload = true })
			Slider(c, "Messages stay", "lineTime", 5, 300, 5, kit.Seconds, { depends = { "chat" } })
			Toggle(c, "Short channel tags  [G] [1]", "tags", { depends = { "chat" } })
			Toggle(c, "Loot and rolls in few lines", "loot", { depends = { "chat" } })
			Toggle(c, "Public channels wait during fights", "calm", { depends = { "chat" } })
			Toggle(c, "Calm tooltips", "tooltip", { note = "glass, Shift for more" })
		end },
	{ key = "bags", title = "Bags and merchants",
		text = "Serene's own windows for the bags, the bank and the merchant; at every merchant, junk sold and gear repaired.",
		build = function(c)
			Toggle(c, "Serene's bags and bank", "bags", { note = "reload", reload = true })
			Toggle(c, "Serene's merchant window", "merchant")
			Toggle(c, "Sell the junk", "sellJunk", { note = "greys, the bags' Junk" })
			Toggle(c, "Repair everything", "autoRepair")
			Toggle(c, "Counts in item tooltips", "bagCounts", { note = "bank, alts", depends = { "bags" } })
		end },
	{ key = "done", title = "Ready",
		build = function(c)
			Note(c, "/serene: every setting, on pages of its own.")
			Note(c, "/serene setup: these pages again.")
		end },
}

local atLogin = {} -- the reload settings as the modules read them at login
local function NeedsReload()
	for _, key in ipairs(RELOAD) do
		if ns.db[key] ~= atLogin[key] then return true end
	end
	return false
end

-- The window ------------------------------------------------------------------------------------------------------

local window
local mode, index = "setup", 1
local setupPages, newsPage
local cards = {}
local dots = {}
local back, forward, skip
local finished = false
local since -- (the newest version seen before this login: news after it is new)

local function Label(parent, text, font, color)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	label:SetText(text or "")
	label:SetJustifyH("LEFT")
	if color then label:SetTextColor(color[1], color[2], color[3]) end
	return label
end

-- A soft pill with a word: gold for the way on, quiet for the rest.
local function Pill(parent, gold)
	local pill = CreateFrame("Button", nil, parent)
	pill.ground = pill:CreateTexture(nil, "BACKGROUND")
	pill.ground:SetTexture(MEDIA .. "Pill")
	pill.ground:SetAllPoints()
	pill.text = Label(pill, "", "GameFontHighlightSmall")
	pill.text:SetPoint("CENTER")
	local function Paint(over)
		if gold then
			pill.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], over and 1 or 0.85)
			pill.text:SetTextColor(INK[1], INK[2], INK[3])
		elseif over then
			pill.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
			pill.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			pill.ground:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.06)
			pill.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
		end
	end
	Paint(false)
	pill:SetScript("OnEnter", function() Paint(true) end)
	pill:SetScript("OnLeave", function() Paint(false) end)
	function pill:Say(text)
		self.text:SetText(text)
		local width = Clean(Safe(self.text.GetStringWidth, self.text)) or 60
		self:SetSize(math.floor(width + 28 + 0.5), 22)
	end
	return pill
end

-- A page: its title and words, a body under them for its rows.
local function Page(title, text)
	local p = {}
	p.frame = CreateFrame("Frame", nil, window)
	p.frame:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
	p.frame:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
	p.frame:SetHeight(10)
	p.frame:Hide()
	p.title = Label(p.frame, title, "GameFontNormalLarge", GOLD)
	p.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -PAD - 22)
	p.text = Label(p.frame, text, "GameFontHighlight", TEXT)
	p.text:SetWidth(WIDTH - PAD * 2)
	p.text:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -10)
	p.body = CreateFrame("Frame", nil, p.frame)
	p.body:SetPoint("TOPLEFT", p.text, "BOTTOMLEFT", 0, -18)
	p.body:SetSize(WIDTH - PAD * 2, 10)
	p.height = 0
	return p
end

-- The presets as three cards one under the other, as wide as the rows; the one the settings match now in gold.
local function PaintCards()
	for _, card in ipairs(cards) do
		local on = Matches(card.preset)
		local line = on and ns.LINE or { TEXT[1], TEXT[2], TEXT[3], card.over and 0.3 or 0.12 }
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			card.lines[side]:SetColorTexture(line[1], line[2], line[3], line[4])
		end
		if on then
			card.ground:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.07)
			card.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			card.ground:SetColorTexture(TEXT[1], TEXT[2], TEXT[3], card.over and 0.06 or 0.03)
			card.name:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
		end
	end
end

local function Pick(preset)
	for key in pairs(touched) do ns.db[key] = Wanted(preset, key) end
	Hints()
	if ns.SettingsApply then ns.SettingsApply() end
	PaintCards()
end

local function Cards(body)
	local y = -4
	for _, preset in ipairs(PRESETS) do
		local card = CreateFrame("Button", nil, body)
		card.preset = preset
		card.ground = card:CreateTexture(nil, "BACKGROUND")
		card.ground:SetAllPoints()
		card.name = Label(card, preset.name, "GameFontNormal")
		card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
		card.text = Label(card, preset.text, "GameFontHighlightSmall", MUTED)
		card.text:SetWidth(ROWS - 24)
		card.text:SetJustifyV("TOP")
		card.text:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
		local name = Clean(Safe(card.name.GetStringHeight, card.name)) or 14
		local words = Clean(Safe(card.text.GetStringHeight, card.text)) or 24
		local height = math.floor(10 + name + 5 + words + 10 + 0.5)
		card:SetSize(ROWS, height)
		card:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
		card.lines = ns.Hairline(card)
		y = y - height - CARD_GAP
		card:SetScript("OnClick", function() Pick(preset) end)
		card:SetScript("OnEnter", function(self) self.over = true PaintCards() end)
		card:SetScript("OnLeave", function(self) self.over = false PaintCards() end)
		cards[#cards + 1] = card
	end
	return -y
end

local function BuildSetup()
	setupPages = {}
	for _, def in ipairs(PAGES) do
		local p = Page(def.title, def.text)
		p.def = def
		if def.key == "preset" then
			p.height = Cards(p.body)
		elseif def.build then
			p.height = ns.SettingsRows(p.body, ROWS, def.build)
		end
		setupPages[#setupPages + 1] = p
	end
	for i = 1, #setupPages do
		local dot = window:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(MEDIA .. "Disc")
		dot:SetSize(6, 6)
		dot:SetPoint("BOTTOM", window, "BOTTOM", (i - (#setupPages + 1) / 2) * 12, 31)
		dots[i] = dot
	end
end

-- The news since the version seen before this login (or, nothing being new, the latest).
local function BuildNews()
	local fresh = {}
	for _, entry in ipairs(NEWS) do
		if Newer(entry[1], since) then fresh[#fresh + 1] = entry end
	end
	if #fresh == 0 then fresh[1] = NEWS[#NEWS] end
	local latest = fresh[#fresh][1]
	newsPage = Page("New in Serene " .. latest,
		"Since you last looked. Each switch is set as Serene would have it; change what you like, or later with /serene.")
	newsPage.height = ns.SettingsRows(newsPage.body, ROWS, function(c)
		for _, entry in ipairs(fresh) do
			Header(c, entry[2])
			entry[3](c)
		end
	end)
end

local function Paint()
	local last = mode == "news" or index == #setupPages
	for i, dot in ipairs(dots) do
		local on = mode == "setup" and i == index
		dot:SetVertexColor(on and GOLD[1] or TEXT[1], on and GOLD[2] or TEXT[2], on and GOLD[3] or TEXT[3], on and 0.9 or 0.25)
		dot:SetShown(mode == "setup")
	end
	if last then
		forward:Say(NeedsReload() and "Reload" or "Done")
	else
		forward:Say(index == 1 and "Set up" or "Next")
	end
	back:Say("Back")
	back:SetShown(mode == "setup" and index > 1)
	skip.text:SetText(index == 1 and "Keep the defaults" or "Skip to the end")
	skip:SetShown(mode == "setup" and not last)
	skip:SetWidth(Clean(Safe(skip.text.GetStringWidth, skip.text)) or 100)
end

local function Show(p)
	for _, other in ipairs(setupPages or {}) do other.frame:SetShown(other == p) end
	if newsPage then newsPage.frame:SetShown(newsPage == p) end
	-- (the last page's words follow the choices; set on every page, so the window is measured with them)
	for _, each in ipairs(setupPages or {}) do
		if each.def.key == "done" then
			each.text:SetText(NeedsReload()
				and "Some of what you chose is put in place by a reload: the interface reloads once, and Serene is ready."
				or "Serene is ready.")
		end
	end
	-- (as tall as the tallest of the setup's pages, so the buttons stay put from page to page)
	local height = 0
	for _, each in ipairs(mode == "setup" and setupPages or { p }) do
		local words = Clean(Safe(each.text.GetStringHeight, each.text)) or 40
		height = math.max(height, TOP + words + 18 + each.height + BOTTOM)
	end
	window:SetHeight(math.floor(height + 0.5))
	if ns.SettingsApply then ns.SettingsApply() end
	PaintCards()
	Paint()
end

local function Finish()
	finished = true
	window:Hide()
	if NeedsReload() then ReloadUI() end
end

local function Window()
	if window then return end
	window = CreateFrame("Frame", "SereneSetup", UIParent)
	window:SetSize(WIDTH, 400)
	window:SetPoint("CENTER")
	window:SetFrameStrata("FULLSCREEN_DIALOG") -- (over the game's Options, from where it can be opened)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:Hide()
	local ground = window:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.95)
	ns.Hairline(window)
	local heading = Label(window, "SERENE", "GameFontNormalSmall", GOLD)
	heading:SetAlpha(0.7)
	heading:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -PAD)
	tinsert(UISpecialFrames, "SereneSetup") -- (Escape closes it)

	forward = Pill(window, true)
	forward:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 24)
	forward:SetScript("OnClick", function()
		if mode == "news" or index == #setupPages then return Finish() end
		index = index + 1
		Show(setupPages[index])
	end)
	back = Pill(window, false)
	back:SetPoint("RIGHT", forward, "LEFT", -8, 0)
	back:SetScript("OnClick", function()
		index = math.max(1, index - 1)
		Show(setupPages[index])
	end)
	-- (on the welcome page: nothing changed, the window away; after it: straight to the last page)
	skip = CreateFrame("Button", nil, window)
	skip:SetHeight(22)
	skip:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 24)
	skip.text = Label(skip, "", "GameFontHighlightSmall", MUTED)
	skip.text:SetPoint("LEFT")
	skip:SetScript("OnEnter", function(self) self.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3]) end)
	skip:SetScript("OnLeave", function(self) self.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end)
	skip:SetScript("OnClick", function()
		if index == 1 then
			finished = true
			return window:Hide()
		end
		index = #setupPages
		Show(setupPages[index])
	end)

	-- (closed some other way with a reload still owed: a word in the chat)
	window:SetScript("OnHide", function()
		if not finished and NeedsReload() then ns.Print("some of what you chose comes with a /reload") end
	end)
end

-- (mode: "setup", its pages from the first; "news", what's new)
function ns.OpenSetup(which)
	if not (ns.db and ns.SettingsRows and Toggle) then return end
	Window()
	finished = false
	if which == "news" then
		mode = "news"
		if not newsPage then BuildNews() end
		Show(newsPage)
	else
		mode, index = "setup", 1
		if not setupPages then BuildSetup() end
		Show(setupPages[1])
	end
	window:Show()
end

local function Init()
	for _, key in ipairs(RELOAD) do atLogin[key] = ns.db[key] end
	since = ns.db.setupSeen
	local latest = NEWS[#NEWS][1]
	local open
	if ns.fresh then
		open = "setup"
	elseif Newer(latest, since) then
		open = "news"
	end
	ns.db.setupSeen = latest
	-- (a moment after login, once the interface has settled)
	if open then C_Timer.After(2, function() ns.OpenSetup(open) end) end
end

ns.Setup = { news = NEWS, presets = PRESETS, reload = RELOAD } -- (tests)

table.insert(ns.modules, { init = Init })
