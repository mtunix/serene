local ADDON, ns = ...

-- Serene: a calm interface.
--
-- What Serene is: a marriage of the original World of Warcraft interface and a modern, minimalist, calm spin on it.
-- It should still feel like WoW, but Serene leads: WoW is in the accents, never at full weight. The game's own frames
-- are kept and restyled, never replaced by something generic; its character comes through quietly: a hairline of
-- its gold (1 pixel, soft) framing Serene's glass the way its old frames framed everything, its round portraits,
-- its gold for what matters. Its ornate borders and rings at their own thickness are too loud (tried on the unit
-- frames: "too much WoW, too little Serene"); its glossy gradients too (bars are flat). Serene's own parts carry
-- the rest: dark glass, flat colour, quiet text, fading away when not needed, space around things, parts flowing
-- into each other rather than boxes side by side. The shared pieces for it are below (ns.LINE, ns.Pixel,
-- ns.Hairline).
--
--   Chat.lua     the chat in glass: a soft dark backdrop behind each message only, fading with it; no window, no
--                buttons until the mouse comes; the game's own lines ("[1. General] [Name]: text").
--   Minimap.lua  the compass: the minimap in a thin ring with degree ticks and N/E/S/W, the zone, where you
--                stand and the time under it; its buttons under the mouse. Under the mouse, or always outside
--                cities and towns.
--   Fade.lua     the interface away when you don't need it: action bars, your portrait, the minimap, buffs, the
--                menu, bags and experience; back on hover, in a fight, with a target, while casting...
--   TopBar.lua   the top bar: zone, experience, money, bags, gear, latency, the time... in one glass band.
--   Tracker.lua  the quest tracker (the game's and Questie's) hidden, a key to bring it back.
--   Bags.lua     bags and bank in glass: quiet sections, one cell per item, remembered (alts too), counts in
--                item tooltips; the game's own item buttons, its bag windows kept out of sight.
--   Vendor.lua   the merchant in glass: his goods in one list (search, usable only, how many you have), buyback;
--                at every merchant the junk sold and everything repaired. The game's window kept out of sight.
--   ActionBars.lua  the action bars made calm: the game's own buttons and frames, the key small and quiet in a
--                corner (soft red out of range), macro names and the bars' art away, empty slots see-through.
--   Ready.lua    readiness: an action button as present as it is ready; on cooldown, short of mana, unusable or
--                out of range it steps back to a faint shade, and comes back the moment it can be pressed.
--   BarCooldowns.lua  the buttons' cooldowns in their look (a sweep, a gold line, the round icon's ring), their
--                numbers, and one global cooldown line under Action Bar 1 instead of it on every button.
--   BarKeys.lua  keys that teach: bright while you still click the button, away once you press its key.
--   BarPages.lua Action Bar 1's icons coming in softly when its page or form changes; the page's number.
--   Ranks.lua    a spell's new rank onto the bars (by itself, or a mark and a button).
--   Reagents.lua reagents running low: the count in amber, a word at merchants who sell them.
--   BarPing.lua  a long cooldown coming back: one soft ring of gold out from its button (seen on faded bars too).
--   BarSets.lua  your bars kept: what leaves them by itself (a talent reset) put back, named sets put on.
--   BarSupplies.lua  supply buttons: macros holding the best food, water, potions, bandage you carry.
--   BarUse.lua   how you use your bars: unused buttons pointed out (keep, fade, clear), easier keys suggested.
--   MenuBar.lua  the micro menu and the bags as words: a second band of glass right under
--                the top bar, shown with it under the mouse; the open one gold. The game's buttons do the opening.
--   Swing.lua    the game's swing timer made calm: its frames (one for each hand) and place kept, their art
--                away, drawn again as a thin line of glass for each weapon (and Auto Shot) filling to the next
--                swing, the weapon's icon at its start.
--   Units.lua    the unit frames made calm: the game's own frames (you, pet, target, focus), their ornate art away,
--                flat bars on glass coloured by class or by how a creature feels about you, portraits round or away.
--   CastBar.lua  your cast bar made calm: the game's own bar, its art away, a slim line on glass coloured by what
--                it is, the spell's icon at its start, its name and time quiet in it, your lag at its end, a
--                channel's ticks, a soft flash as it ends, in and out in Serene's rhythm.
--   Auras.lua    buffs and debuffs made calm: the game's own aura buttons (yours, your target's and focus's), the
--                icons round, a hairline ring around each (gold for a buff, a quieter shade of the game's colour for a
--                debuff's kind), the time left small and muted under it.
--   AuraFrame.lua  Serene's own frame for your buffs and debuffs, built on the game's aura containers (filled by the
--                game, in a fight too): short buffs full size, the long and steady in a small row, each icon
--                darkening with the time, missing class buffs as faint rings, debuffs you can remove in colour,
--                world buffs on a shelf.
--   UnitAuras.lua  the target's and focus's auras drawn by Serene, round, above the card (the game draws its own in
--                frames addons can't reach); the game's shown again whenever the auras can't be read.
--   Regen.lua    the five-second rule: a line of gold growing under your mana bar after mana is spent, until
--                full regeneration starts again.
--   Experience.lua  experience gained: the game's bar back for a moment, the part just earned lit in gold.
--   Toasts.lua   the game's toasts made calm: recipes learned and achievements earned on a slim card of glass, the
--                icon round at its end;
--                where the toasts appear, placed by dragging a sample (/serene toasts move).
--   Tooltip.lua  tooltips in glass: no frame, a soft fade, quiet colours, how-to lines on Shift; in a fight
--                the world's and the action bars' wait for Shift.
--   Setup.lua    the setup: on the first login a few pages and three presets (all of Serene, always in view, a
--                light touch); after an update, only what is new, with its switches.
-- /serene for the switches.

ns.DEFAULTS = {
	chat = true,     -- the chat in glass (Chat.lua; a reload to switch)
	minimap = true,  -- the compass (Minimap.lua; a reload to switch)
	fade = true,     -- what isn't needed fades away (Fade.lua)
	tracker = true,  -- the quest tracker hidden, a key brings it back (Tracker.lua)
	loot = true,     -- loot and rolls in few lines (ChatLoot.lua)
	quiet = true,    -- friends and guild coming online / going offline: quiet and short
	gains = true,    -- money, experience and reputation: one quiet line per fight
	tags = true,     -- short channel tags: [1] [G] [P]...
	group = false,   -- one speaker's lines in a row: the name once (off: names on every line read clearer)
	hints = true,    -- a gold glow on action buttons worth pressing now (food when not Well Fed, a missing class buff)
	hintReveal = "button", -- what a glow brings back: "none", "button", "bar" or "bars" (all of them)
	hintFood = true,  -- the food rule: food that makes you Well Fed, when you are not
	hintBuffs = true, -- what your class keeps up (armors, auras, poisons...), when missing
	hintLast = {},   -- per character: the spell of a group (armor, blessing, aspect...) used last
	actionBars = true, -- the action bars made calm (ActionBars.lua)
	barKeys = true,    -- the keys on the buttons
	barNames = false,  -- macro names on the buttons
	barReady = true,   -- readiness: a button as present as it is ready, the rest faint (Ready.lua)
	barReadyWhen = "always", -- when: "always" or only in a "fight"
	barReadyDim = 30,  -- a button not ready stays at this opacity, in percent
	barReadyCooldown = true, -- on its cooldown (the global one never counts)
	barReadyPower = true,    -- short of mana, rage or energy
	barReadyUnusable = true, -- unusable now (wrong form, no reagent, a condition not met...)
	barReadyTarget = true,   -- an attack with no enemy targeted (you, a friend, a corpse, nobody)
	barReadyRange = true,    -- out of range of the target
	barReadyHover = true,    -- the bar under the mouse all at full
	barStyle = "classic",    -- the buttons' look: "classic" (the game's frame), "glass" or "round" (ActionBars.lua)
	barStyleSame = true,     -- one look for every bar (off: each bar its own, barStyles)
	barStyles = { main = "classic", bar2 = "classic", bar3 = "classic", bar4 = "classic", bar5 = "classic",
		bar6 = "classic", bar7 = "classic", bar8 = "classic", pet = "classic", stance = "classic" },
	barCooldown = "style",   -- cooldowns: "style" (the look's own), "sweep", "line" or "none" (BarCooldowns.lua)
	barCooldownText = "game",-- their numbers: "game" (the game's option), "soon" (last seconds), "always", "never"
	barGcd = true,           -- the global cooldown off the buttons, one gold line under Action Bar 1 instead
	barKeysLearn = true,     -- keys bright while being learnt, away once known (BarKeys.lua)
	barPages = true,         -- Action Bar 1's icons come in softly when its page changes; the page's number (BarPages.lua)
	barRanks = true,         -- a spell's new rank onto the buttons holding its old highest (Ranks.lua)
	barRanksAuto = true,     -- by itself (off: a mark on them and a button to do it)
	barReagents = true,      -- reagents: the count warm amber when low, a word at merchants (Reagents.lua)
	barReagentLow = 5,       -- low from this many casts left
	barPing = true,          -- a long cooldown coming back: one soft ring (BarPing.lua)
	barPingMin = 30,         -- long: at least this many seconds
	barSets = true,          -- a copy of your bars kept: what leaves by itself put back (BarSets.lua)
	barSupplies = true,      -- Serene's supply macros kept on the best you carry (BarSupplies.lua)
	barUse = true,           -- unused buttons pointed out, easier keys suggested (BarUse.lua)
	barUseHours = 10,        -- unused: not pressed in this many hours of play
	hintBuffSoon = true,     -- a class buff running out: what renews it glows faintly (Hints.lua)
	hintBuffSoonAt = 120,    -- running out: less than this many seconds left
	xpGain = true,     -- experience gained: its bar shown, the new part lit (Experience.lua)
	toast = true,      -- the game's recipe and achievement toasts in Serene's look (Toasts.lua; a reload to switch)
	-- toastAt: where the toasts appear, { x from the screen's middle, y from its bottom } (unset: the game's place)
	swing = true,      -- the game's swing timer in Serene's look (Swing.lua; off: the game's own look)
	swingRanged = true,-- its Auto Shot and wand line
	swingSize = 100,   -- its lines and icons, in percent (thicker or thinner; the width is Edit Mode's)
	units = true,      -- the game's unit frames made calm (Units.lua; a reload to switch)
	unitPortraits = true, -- their portraits (round)
	unitElite = true,  -- the game's dragon around an elite's or a rare's portrait
	castBar = true,   -- your cast bar made calm: a slim line on glass, the spell's icon at its start (CastBar.lua; a reload to switch)
	castHeight = 11,  -- its height
	castWidth = 0,    -- its width (0: Edit Mode's)
	castIcon = true,  -- the spell's icon at its start
	castText = "in",  -- the spell's name: "in" the bar, "under" it, or "none"
	castFont = 0,     -- the words' size (0: worked out from the height)
	castTime = "left", -- the time: "left" (1.4), "both" (left and the whole: 1.4 / 2.5) or "none"
	castLatency = true, -- your lag at the cast's end: a muted strip, where the next spell can already be pressed
	castTicks = true, -- a channel's ticks marked where they land
	castFlash = true, -- a soft flash as a cast ends: light when it lands, red when it is interrupted
	castFade = true,  -- in softly and away slowly, as the rest of Serene fades; no shake on an interrupt
	auras = true,      -- buffs and debuffs made calm: round icons in a hairline ring, the time muted (Auras.lua; a reload to switch)
	auraUnits = true,  -- the target's and focus's auras too (a reload to switch)
	auraPlates = true, -- nameplates' auras too: your debuffs on an enemy (a reload to switch)
	auraTime = "outline", -- their time left: "outline" (thinly outlined), "plate" (on a pill of dark glass) or "none"
	auraTimeAt = "under", -- where: "under" the icon (the game's place) or "on" its lower edge
	auraTimeSize = 0,     -- its size (0: the game's, a little smaller)
	auraShape = "round",  -- the icons "round" (like the portraits) or "square"
	auraRing = "all",     -- the line around them: "all" (gold for buffs, the kind's colour for debuffs), "debuffs" or "none"
	auraRingSize = 1,     -- its thickness in pixels (1-3)
	auraColors = "quiet", -- a debuff's colour: "quiet" (Serene's shades) or "game" (the game's own)
	auraArrow = true,     -- the arrow folding your buffs away only under the mouse (the game's frame)
	-- Serene's own buff frame (AuraFrame.lua)
	auraFrame = "serene", -- your buffs in "serene"'s frame or the "game"'s, restyled (a reload to switch)
	auraSize = 30,        -- its icons
	auraPerRow = 12,      -- icons in a row
	auraDrain = true,     -- others' auras (target, nameplates): a ring drains around each as it runs out
	auraEdge = true,      -- a dark hairline outside the ring (it stands out on bright ground)
	auraDim = true,       -- the elapsed part of each icon and its ring darkened, a swirl over it
	auraTimeWhen = "soon",-- the time: "always", "soon" (in the last stretch) or "never"
	auraTiers = true,     -- long, steady buffs step back into a quiet row
	auraSmall = 16,       -- its rings
	auraShort = 180,      -- a buff shorter than this (seconds) always shown full
	auraSoon = 60,        -- the last stretch (seconds): the time shows
	auraGhosts = true,    -- your class's missing buffs as faint rings (click: cast)
	auraWorld = true,     -- world buffs on a shelf of their own
	auraDebuffSize = 34,  -- debuffs' icons
	auraDebuffAt = "buffs", -- where: "buffs" (under them), "portrait" (by yours) or "free" (where you put them)
	auraDispel = true,    -- a debuff you can remove in its colour, the others grey
	-- auraAt, auraDebuffFree: where they were put (unset: the game's place); auraShortSpells: buffs seen to be short
	manaRegen = true,  -- the five-second rule: a line of gold under your mana bar until regeneration starts (Regen.lua)
	unitBorder = "line", -- "line": a hairline of the game's gold around the card and the portrait; "none": glass only
	menuBar = true,    -- the micro menu and the bag bar made calm (MenuBar.lua; a reload to switch)
	barEmpty = false,  -- empty slots shown too (off: see-through, shown faintly while dragging)
	vendor = true,   -- merchants: a "Stack" button and Alt-click to buy a full stack (Merchant.lua)
	card = true,     -- a player's card on hover over their name in the chat
	chatArrows = true, -- the line to write in: arrow keys move in it (Ctrl: by word), Up/Down bring back what you sent
	chatRoom = true,   -- the line to write in's room used by the messages while nobody writes; they glide up as you write
	chatReveal = true, -- while you write, every message in the window seen (the faded ones come back)
	tooltip = true,  -- tooltips in glass: no frame, a soft fade, quiet colours, how-to lines on Shift (Tooltip.lua)
	tipcalm = true,  -- in a fight, the world's and the action bars' tooltips wait (Shift or the key shows them; enemies show)
	tipmore = true,  -- what addons add under an item waits for Shift
	tipcard = true,  -- a player's tooltip as a card: race and class icons, name and level, guild
	tipvendor = true, -- item tooltips: what a merchant pays for it
	calm = true,     -- in a fight, the public channels wait until it is over
	idle = true,     -- away or nothing done for a while: the whole interface rests
	idleAfter = 120, -- seconds before it rests
	rest = 0,        -- opacity of a faded part, in percent
	lineTime = 30,   -- seconds a chat message stays before fading
	compass = "hover", -- the compass: "hover" (only under the mouse) or "world" (always, except in towns)
	edge = "round",  -- the minimap's edge: "round" (the game's own) or "square"
	top = true,      -- the top bar (TopBar.lua)
	topShow = "hover", -- when it shows: "hover" (under the mouse only, like the menu), "calm" (away in fights) or "always"
	topItems = { queue = true, zone = true, coords = true, xp = true, gold = true, bags = true, repair = true, loot = true,
		perf = true, volume = false, clock = true },
	groups = { bars = true, unit = true, minimap = true, buffs = true, menu = true },
	bags = true,       -- Serene's bags and bank (Bags.lua)
	bagColumns = 10,   -- cells in a row
	bagCounts = true,  -- item tooltips: how many in the bank and on your other characters
	bankAt = "bags",   -- where the bank opens: "bags" (beside Serene's bags, as a merchant's window) or "free" (where you put it)
	bagPins = {},      -- itemID -> the section it was given (Alt-right-click)
	bagCats = {},      -- sections of your own, in order
	bagKeep = {},      -- itemID -> true: never suggested by "make room" (its "keep", or Alt-right-click)
	inv = {},          -- remembered bags and banks: realm -> name -> { class, money, bags, bank, ... }
	merchant = true,       -- Serene's merchant window (Vendor.lua)
	merchantAt = "bags",   -- where it opens: "bags" (beside Serene's bags) or "game" (where the game's window opens)
	merchantCounts = true, -- each item: how many you have (bags, bank)
	merchantSearch = true, -- a search and "usable only" over the list
	merchantUsable = false,-- only what you can use (known recipes, too high a level... hidden)
	sellJunk = true,       -- at a merchant: the junk sold (greys, and what is in the bags' Junk section)
	autoRepair = true,     -- at a merchant: everything repaired
	repairGuild = false,   -- with the guild's money first, when it allows
}

-- Saved, but not settings: what the files keep in SereneDB themselves (so no default). Anything saved that is neither
-- this nor a setting is let go at login (a setting or a dump no file reads any more), so a new one goes here, on
-- purpose; spec/settings.lua fails on a read that is neither.
ns.STATE = {
	ungrouped = true, topHover = true,                 -- migration flags (Core.lua)
	toastAt = true,                                   -- where the toasts appear (Toasts.lua)
	auraAt = true, auraDebuffFree = true, auraShortSpells = true, -- AuraFrame.lua
	topPos = true, gold = true,                       -- TopBar.lua (gold: money per character)
	settingsPage = true,                              -- the settings panel's page last open
	setupSeen = true,                                 -- the newest version whose news the setup showed (Setup.lua)
	supplies = true,                                  -- BarSupplies.lua
	ranks = true,                                     -- Ranks.lua
	keyLearn = true,                                  -- BarKeys.lua
	barUseBy = true,                                  -- BarUse.lua, per character
	barSetsBy = true,                                 -- BarSets.lua, per character
	namesSaved = true, namesKeyGiven = true,          -- Names.lua
	tipCompare = true, tipCompareDone = true,         -- Tooltip.lua
	merchantNoted = true, bagsNoted = true,           -- one-time notes said
	bankPos = true, bagsPos = true,                   -- Bags.lua windows placed by hand
	unitsDump = true, probeMouse = true, probeGlow = true, -- debug dumps (Units, Auras, ActionBars)
	capture = true, capturing = true,                 -- Capture.lua
}

-- Serene's colours, one palette for every file -------------------------------------------------------------------

ns.MUTED = "|cff8f8f8f"         -- what is said quietly (a time, a hint, a detail)
ns.SOFT = "|cffe8e4da"          -- the words themselves: a warm white
ns.GOLD_TEXT = "|cffffd100"     -- the game's own gold, for what matters
ns.MUTED_RGB = { 0.56, 0.56, 0.56 }
ns.SOFT_RGB = { 0.91, 0.894, 0.855 }
ns.INK = { 0.035, 0.04, 0.05 }  -- the glass

-- WoW's character, quietly: a hairline of its gold ---------------------------------------------------------------
ns.LINE = { 1, 0.82, 0.35, 0.45 } -- the game's gold, soft

-- One pixel of the screen in a region's own units (so a hairline stays one pixel at any UI scale).
function ns.Pixel(region)
	local _, height = GetPhysicalScreenSize()
	local scale = region and ns.Clean(ns.Safe(region.GetEffectiveScale, region)) or 1
	if type(height) ~= "number" or height <= 0 or type(scale) ~= "number" or scale <= 0 then return 1 end
	return 768 / height / scale -- (the interface is 768 units high at scale 1)
end

-- A hairline just inside a frame's edges: four textures, one pixel each. Returns them (to colour or show again).
function ns.Hairline(frame, color, layer)
	color = color or ns.LINE
	local lines = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local line = frame:CreateTexture(nil, layer or "BORDER")
		line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		lines[side] = line
	end
	function lines:Fit()
		local px = ns.Pixel(frame)
		self.top:ClearAllPoints()
		self.top:SetPoint("TOPLEFT", frame, "TOPLEFT")
		self.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		self.top:SetHeight(px)
		self.bottom:ClearAllPoints()
		self.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
		self.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
		self.bottom:SetHeight(px)
		self.left:ClearAllPoints()
		self.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -px)
		self.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, px)
		self.left:SetWidth(px)
		self.right:ClearAllPoints()
		self.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -px)
		self.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, px)
		self.right:SetWidth(px)
	end
	lines:Fit()
	return lines
end

-- Safe reading ----------------------------------------------------------------------------------------------------
-- In a fight the game hides some values from addons (secret values): never compared, never used as numbers.

ns.IsSecret = issecretvalue or function() return false end

local function Results(ok, ...)
	if ok then return ... end
end

function ns.Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Results(pcall(fn, ...))
end

function ns.Clean(value)
	if value == nil or ns.IsSecret(value) then return nil end
	return value
end

-- One of the game's regions (a texture, a text...), and of which kind: for parts found by searching a frame's keys.
function ns.IsRegion(value)
	return type(value) == "table" and type(value.GetObjectType) == "function" and type(value.SetAlpha) == "function"
end

function ns.IsTexture(region)
	return ns.IsRegion(region) and ns.Safe(region.IsObjectType, region, "Texture") == true
end

function ns.IsFontString(region)
	return ns.IsRegion(region) and ns.Safe(region.IsObjectType, region, "FontString") == true
end

-- A frame of the game's made unseen, and too small to catch the mouse, again whenever the game sets it back: for one
-- that must stay shown and keep working (the game's aura containers, which Edit Mode places and the game fills).
local silenced = {}
function ns.Silence(frame)
	if silenced[frame] then return end
	silenced[frame] = true
	local holding = false
	local function Again()
		if holding then return end
		holding = true
		pcall(frame.SetAlpha, frame, 0)
		pcall(frame.SetScale, frame, 0.01)
		holding = false
	end
	Again()
	hooksecurefunc(frame, "SetAlpha", Again)
	hooksecurefunc(frame, "SetScale", Again)
end

-- The mouse over a frame (extended by top, bottom, left, right like the game's own method).
function ns.Over(frame, top, bottom, left, right)
	if type(frame) ~= "table" or not frame.IsMouseOver then return false end
	local visible = ns.Safe(frame.IsVisible, frame)
	if visible == false then return false end
	local ok, over = pcall(frame.IsMouseOver, frame, top or 0, bottom or 0, left or 0, right or 0)
	return ok and ns.Clean(over) and true or false
end

-- One step of a fade toward a target: seconds for a full fade in, and out.
function ns.Approach(current, target, elapsed, fadeIn, fadeOut)
	if current == target then return current end
	if target > current then
		return math.min(target, current + (elapsed or 0) / (fadeIn > 0 and fadeIn or 0.001))
	end
	return math.max(target, current - (elapsed or 0) / (fadeOut > 0 and fadeOut or 0.001))
end

-- A switch: on or off (the default until the saved settings are loaded).
function ns.On(key)
	local db = ns.db
	if not db then return ns.DEFAULTS[key] end
	return db[key] and true or false
end

-- Whether a frame is anchored to another (windows beside each other: never both ways round).
function ns.AnchoredTo(frame, other)
	if not (frame and other) then return false end
	for index = 1, frame:GetNumPoints() do
		if select(2, frame:GetPoint(index)) == other then return true end
	end
	return false
end

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff9ad0c2Serene|r: " .. text)
end

-- Saved settings, missing keys filled from the defaults (into nested tables too).
local function Fill(into, from)
	for key, value in pairs(from) do
		if type(value) == "table" then
			into[key] = type(into[key]) == "table" and into[key] or {}
			Fill(into[key], value)
		elseif into[key] == nil then
			into[key] = value
		end
	end
end

ns.modules = {} -- { init = fn, refresh = fn } in load order

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then return end
		-- (nothing saved yet: Serene's first login on this account, and the setup opens)
		ns.fresh = type(SereneDB) ~= "table"
		SereneDB = type(SereneDB) == "table" and SereneDB or {}
		-- (what no file reads any more only takes room)
		for key in pairs(SereneDB) do
			if ns.DEFAULTS[key] == nil and not ns.STATE[key] then SereneDB[key] = nil end
		end
		Fill(SereneDB, ns.DEFAULTS)
		-- ("glow" isn't one of hintReveal's choices: the nearest is "none")
		if SereneDB.hintReveal == "glow" then SereneDB.hintReveal = "none" end
		-- (once: a name on every line reads clearer)
		if not SereneDB.ungrouped then SereneDB.group, SereneDB.ungrouped = false, true end
		-- (the top bar now rests like the rest of the interface: under the mouse only)
		if not SereneDB.topHover then SereneDB.topShow, SereneDB.topHover = "hover", true end
		if SereneDB.auraTime ~= "outline" and SereneDB.auraTime ~= "plate" and SereneDB.auraTime ~= "none" then SereneDB.auraTime = "outline" end
		if SereneDB.unitBorder ~= "line" and SereneDB.unitBorder ~= "none" then SereneDB.unitBorder = "line" end
		ns.db = SereneDB
		return
	end
	-- (PLAYER_LOGIN: every module's init once, in TOC order; one failing doesn't stop the rest)
	self:UnregisterAllEvents()
	for _, module in ipairs(ns.modules) do
		if module.init then
			local ok, problem = pcall(module.init)
			if not ok then ns.Print("|cffff6060" .. tostring(problem) .. "|r") end
		end
	end
end)

local function Refresh()
	for _, module in ipairs(ns.modules) do
		if module.refresh then pcall(module.refresh) end
	end
end
ns.Refresh = Refresh

-- Slash command ---------------------------------------------------------------------------------------------------

local SWITCHES = {
	chat = "chat in glass (/reload to switch)",
	minimap = "the compass (/reload to switch)",
	fade = "interface fades when calm",
	tracker = "quest tracker hidden",
	loot = "loot and rolls in few lines",
	quiet = "quiet online / offline lines",
	gains = "money, experience and reputation in one line",
	tags = "short channel tags [1] [G] [P]",
	group = "one speaker's lines together",
	card = "player card on hover over a name",
	tooltip = "calm tooltips: glass, a soft fade, quiet colours, how-to lines on Shift",
	tipcalm = "tooltips of the world and the action bars wait during fights (enemies show; Shift shows the rest)",
	tipmore = "addons' lines under items only with Shift",
	tipcard = "players' tooltips as a card (race and class icons, name, level, guild)",
	tipvendor = "item tooltips: what a merchant pays for it (the whole stack)",
	hints = "gold glow on buttons worth using (and their bar shown)",
	bars = "calm action bars (/reload to switch)",
	keys = "keys on the action buttons",
	macros = "macro names on the action buttons",
	empty = "empty action slots shown (off: see-through)",
	ready = "readiness: action buttons not ready (cooldown, mana, range...) faint until they are",
	menu = "the micro menu and bags as quiet words on a band of glass (/reload to switch)",
	xpgain = "experience bar shown when experience is gained, the new part lit",
	toasts = "the recipe and achievement toasts in glass (/reload to switch)",
	swing = "the game's swing timer made calm: thin lines of glass",
	shots = "the swing timer's line for Auto Shot and wands",
	units = "calm unit frames: flat bars on glass, the frames' art away (/reload to switch)",
	portraits = "portraits on the unit frames",
	elite = "the game's dragon around an elite's or a rare's portrait",
	castbar = "your cast bar made calm: a slim line on glass, the spell's icon at its start (/reload to switch)",
	auras = "buffs and debuffs made calm: round icons in a hairline ring, the time muted (/reload to switch)",
	auraunits = "the target's and focus's auras made calm too (/reload to switch)",
	regen = "the five-second rule: a line of gold under your mana bar until regeneration starts",
	calm = "public channels wait during fights",
	idle = "rest mode: everything away when you are away or idle",
	top = "the top bar: zone, experience, money, bags, gear, latency, time",
	bags = "bags and bank in glass (/reload to switch)",
	bagcounts = "item tooltips: how many in the bank and on your other characters",
	merchant = "the merchant in glass: one list, search, buyback",
	junk = "junk sold at merchants (greys, and the bags' Junk section)",
	repair = "everything repaired at merchants",
}
local GROUPS = {
	bars = "action bars", unit = "your portrait and pet", minimap = "the compass",
	buffs = "buffs and debuffs", menu = "menu, bags, experience",
}
local ORDER = { "chat", "tags", "group", "card", "loot", "gains", "quiet", "calm", "minimap", "fade", "bars", "keys", "macros", "empty", "ready", "menu", "swing", "shots", "units", "portraits", "elite", "castbar", "auras", "auraunits", "regen", "xpgain", "toasts", "hints", "tooltip", "tipcalm", "tipmore", "tipcard", "tipvendor", "tracker", "top", "bags", "bagcounts", "merchant", "junk", "repair", "idle" }
local KEYS = { bagcounts = "bagCounts", junk = "sellJunk", repair = "autoRepair", bars = "actionBars",
	keys = "barKeys", macros = "barNames", empty = "barEmpty", ready = "barReady", xpgain = "xpGain", toasts = "toast", shots = "swingRanged", portraits = "unitPortraits", elite = "unitElite", regen = "manaRegen", castbar = "castBar", menu = "menuBar", auraunits = "auraUnits" } -- (a switch's word -> its setting, where they differ)
local GROUP_ORDER = { "bars", "unit", "minimap", "buffs", "menu" }

local function OnOff(value) return value and "|cff80ff80on|r" or "|cffff8080off|r" end

local function Help()
	for _, key in ipairs(ORDER) do
		ns.Print(("/serene %s on|off  -  %s (%s)"):format(key, SWITCHES[key], OnOff(ns.db[KEYS[key] or key])))
	end
	for _, key in ipairs(GROUP_ORDER) do
		ns.Print(("/serene fade %s on|off  -  fade the %s (%s)"):format(key, GROUPS[key], OnOff(ns.db.groups[key])))
	end
	ns.Print(("/serene rest 0-100  -  how visible a faded part stays (%d%%)"):format(ns.db.rest))
	ns.Print(("/serene lines 5-600  -  seconds a chat message stays (%d)"):format(ns.db.lineTime))
	ns.Print(("/serene idle 30-1800  -  seconds idle before rest mode (%d)"):format(ns.db.idleAfter))
	ns.Print(("/serene compass hover|world  -  the compass only under the mouse, or always out in the world (%s)"):format(ns.db.compass))
	ns.Print(("/serene top always|calm|hover  -  the top bar always, away in fights, or under the mouse only (%s)"):format(ns.db.topShow))
	ns.Print("/serene setup  -  the setup again: how much of Serene, fading, bars, chat, bags")
	ns.Print("/serene news  -  what the latest version brought, with its switches")
	ns.Print("/serene names  -  hide or show the names over heads (key: ` by default)")
	ns.Print("/serene copy  -  the chat's whole history to copy from (or Shift+Alt+click the chat)")
	ns.Print(("/serene border line|none  -  the unit frames in a hairline of gold, or glass only (%s)"):format(ns.db.unitBorder))
	ns.Print(("/serene edge round|square  -  the minimap's edge (%s)"):format(ns.db.edge))
	ns.Print(("/serene barstyle classic|glass|round  -  every action bar's look (%s)"):format(ns.db.barStyle))
	ns.Print("/serene sets [save|load|delete <name>]  -  your bars saved under a name, put on again; sets back: what left them")
	ns.Print("/serene supply food|water|health|mana|bandage  -  a supply button onto the cursor, for a bar")
	ns.Print("/serene review  -  unused buttons and easier keys")
	ns.Print("/serene capture on|off|clear  -  keep real chat lines and item tooltips for Serene's tests (tools/test)")
	ns.Print("/serene ping  -  a sample of the ready ping on Action Bar 1")
	ns.Print(("/serene swingsize 50-300  -  the swing timer's lines and icons, in percent (%d%%)"):format(ns.db.swingSize))
	ns.Print("/serene toasts move|reset|test  -  drag where the toasts appear, or back to the game's place; a sample toast")
	ns.Print("/serene aurasmove  -  drag your buffs and debuffs where you want them (again to finish)")
	ns.Print(("/serene auratime outline|plate|none  -  the buffs' time left outlined, on a pill of glass, or not shown (%s)"):format(ns.db.auraTime))
	ns.Print(("/serene castheight 4-24  -  your cast bar's height (%d)"):format(ns.db.castHeight))
	ns.Print(("/serene castwidth 0|80-400  -  your cast bar's width, 0: Edit Mode's (%d)"):format(ns.db.castWidth))
	ns.Print(("/serene columns 6-16  -  cells in a row in the bags and bank (%d)"):format(ns.db.bagColumns))
end

SLASH_SERENE1 = "/serene"
SlashCmdList.SERENE = function(msg)
	local words = {}
	for word in strtrim(msg or ""):lower():gmatch("%S+") do words[#words + 1] = word end
	local a, b, c = words[1], words[2], words[3]
	if (a == nil or a == "config" or a == "settings" or a == "options") and ns.OpenSettings then
		return ns.OpenSettings()
	elseif a == "help" then
		return Help()
	elseif (a == "setup" or a == "news") and ns.OpenSetup then
		return ns.OpenSetup(a)
	elseif a == "copy" and ns.CopyHistory then
		return ns.CopyHistory()
	elseif a == "names" and Serene_ToggleNames then
		return Serene_ToggleNames()
	elseif a == "toasts" and (b == "move" or b == "reset" or b == "test") then
		local act = b == "move" and ns.ToastMove or b == "reset" and ns.ToastReset or ns.ToastTest
		if act then act() end
		return
	elseif SWITCHES[a] and (b == "on" or b == "off") then
		ns.db[KEYS[a] or a] = b == "on"
		ns.Print(SWITCHES[a] .. ": " .. OnOff(ns.db[KEYS[a] or a]))
	elseif a == "fade" and GROUPS[b] and (c == "on" or c == "off") then
		ns.db.groups[b] = c == "on"
		ns.Print("fade the " .. GROUPS[b] .. ": " .. OnOff(ns.db.groups[b]))
	elseif a == "rest" and tonumber(b) then
		ns.db.rest = math.max(0, math.min(100, math.floor(tonumber(b))))
		ns.Print(("a faded part stays at %d%%"):format(ns.db.rest))
	elseif a == "debug" and b == "menu" and ns.MenuDebug then
		return ns.MenuDebug()
	elseif a == "debug" and b == "mouse" and ns.AuraMouseDump then
		return ns.AuraMouseDump()
	elseif a == "debug" and b == "auras" and ns.AuraProbe then
		return ns.AuraProbe()
	elseif a == "sets" then
		if b == "save" and c then return ns.BarSetSave(c) end
		if b == "load" and c then return ns.BarSetLoad(c) end
		if b == "delete" and c then return ns.BarSetDelete(c) end
		if b == "back" and ns.BarSetsRestore then return ns.BarSetsRestore() end
		return ns.BarSetList and ns.BarSetList()
	elseif a == "capture" and ns.Capture then
		return ns.Capture(b)
	elseif a == "supply" and ns.SupplyPickup then
		return ns.SupplyPickup(b)
	elseif a == "review" and ns.BarReview then
		return ns.BarReview()
	elseif a == "ping" and ns.PingTest then
		return ns.PingTest()
	elseif a == "debug" and b == "glow" and ns.BarsGlowDump then
		return ns.BarsGlowDump()
	elseif a == "debug" and b == "units" and ns.UnitsDump then
		return ns.UnitsDump(c)
	elseif a == "debug" then
		if ns.FadeDebug then ns.FadeDebug() end
		if ns.MinimapDebug then ns.MinimapDebug() end
		if ns.ChatDebug then ns.ChatDebug() end
		if ns.HintDebug then ns.HintDebug() end
		if ns.BarsDebug then ns.BarsDebug() end
		if ns.ReadyDebug then ns.ReadyDebug() end
		if ns.CooldownsDebug then ns.CooldownsDebug() end
		if ns.KeysDebug then ns.KeysDebug() end
		if ns.RanksDebug then ns.RanksDebug() end
		if ns.ReagentsDebug then ns.ReagentsDebug() end
		if ns.PingDebug then ns.PingDebug() end
		if ns.BarSetsDebug then ns.BarSetsDebug() end
		if ns.SuppliesDebug then ns.SuppliesDebug() end
		if ns.BarUseDebug then ns.BarUseDebug() end
		if ns.XPDebug then ns.XPDebug() end
		if ns.SwingDebug then ns.SwingDebug() end
		if ns.UnitsDebug then ns.UnitsDebug() end
		if ns.CastDebug then ns.CastDebug() end
		if ns.AurasDebug then ns.AurasDebug() end
		if ns.AuraFrameDebug then ns.AuraFrameDebug() end
		if ns.UnitAurasDebug then ns.UnitAurasDebug() end
		if ns.BagsDebug then ns.BagsDebug() end
		if ns.MenuDebug then ns.MenuDebug() end
		if ns.TopDebug then ns.TopDebug() end
		if ns.ToastsDebug then ns.ToastsDebug() end
		return
	elseif a == "compass" and (b == "hover" or b == "world") then
		ns.db.compass = b
		ns.Print(b == "hover" and "the compass: only under the mouse"
			or "the compass: always out in the world, under the mouse in cities and towns")
	elseif a == "top" and (b == "always" or b == "calm" or b == "hover") then
		ns.db.topShow = b
		ns.Print("the top bar: " .. (b == "always" and "always" or b == "calm" and "away in fights" or "under the mouse only"))
	elseif a == "border" and (b == "line" or b == "none") then
		ns.db.unitBorder = b
		ns.Print("unit frames: " .. (b == "none" and "glass only" or "a hairline of gold"))
	elseif a == "edge" and (b == "round" or b == "square") then
		ns.db.edge = b
		if ns.MinimapEdge then ns.MinimapEdge() end
		ns.Print("minimap edge: " .. b)
	elseif a == "idle" and tonumber(b) then
		ns.db.idleAfter = math.max(30, math.min(1800, math.floor(tonumber(b))))
		ns.Print(("rest mode after %d seconds idle"):format(ns.db.idleAfter))
	elseif a == "barstyle" and (b == "classic" or b == "glass" or b == "round") then
		ns.db.barStyle = b
		ns.db.barStyleSame = true -- (the word is every bar's look)
		ns.Print("action bars: " .. b .. (InCombatLockdown() and " (after the fight)" or ""))
	elseif a == "swingsize" and tonumber(b) then
		ns.db.swingSize = math.max(50, math.min(300, math.floor(tonumber(b) / 10 + 0.5) * 10)) -- (in tens, as the slider)
		ns.Print(("swing timer: %d%%"):format(ns.db.swingSize))
	elseif a == "aurasmove" and ns.AuraMove then
		return ns.AuraMove()
	elseif a == "auratime" and (b == "outline" or b == "plate" or b == "none") then
		ns.db.auraTime = b
		ns.Print("buffs' time left: " .. (b == "plate" and "on a pill of glass" or b == "none" and "not shown" or "outlined"))
	elseif a == "castheight" and tonumber(b) then
		ns.db.castHeight = math.max(4, math.min(24, math.floor(tonumber(b))))
		ns.Print(("cast bar: %d high"):format(ns.db.castHeight))
	elseif a == "castwidth" and tonumber(b) then
		local width = math.floor(tonumber(b))
		ns.db.castWidth = width < 80 and 0 or math.min(400, width)
		ns.Print(ns.db.castWidth == 0 and "cast bar: as wide as Edit Mode makes it"
			or ("cast bar: %d wide"):format(ns.db.castWidth))
	elseif a == "columns" and tonumber(b) then
		ns.db.bagColumns = math.max(6, math.min(16, math.floor(tonumber(b))))
		ns.Print(("bags: %d cells in a row"):format(ns.db.bagColumns))
	elseif a == "lines" and tonumber(b) then
		ns.db.lineTime = math.max(5, math.min(600, math.floor(tonumber(b))))
		ns.Print(("chat messages stay %d seconds"):format(ns.db.lineTime))
	else
		return Help()
	end
	Refresh()
end
