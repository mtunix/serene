local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The game's swing timer made calm. Nothing new is added beside it: its frames stay where the game's Edit Mode put
-- them (it has one for each hand), shown when the game shows them (Options: the swing timer); only their art is put
-- away (bars, borders, the time) and drawn again in Serene's way on the main hand's frame: a thin line of glass for
-- each weapon, filling up to the next swing, a soft spark at its edge, the weapon's own icon at its start (framed
-- by a hairline of gold) so main hand, off hand and Auto Shot are told apart at a glance. Main hand in warm white,
-- off hand a little fainter, Auto Shot or a wand in gold (the last half second, where a hunter must stand still,
-- tinted on the track). The swings come from the game itself (PLAYER_SWING: each swing and its length), a change
-- of speed mid-swing (haste) keeps the part already done.
-- /serene swing on|off (off: the game's own look back), /serene shots on|off

-- (at size 100%; the setting "swingSize" makes them thicker or thinner, the width stays Edit Mode's)
local HEIGHTS = { main = 4, off = 3, ranged = 4 }
local ICON = 12              -- the weapon's icon at the start of each line
local ICON_GAP = 5           -- between the icon and its line
local ROW_GAP = 3            -- between two lines
local LEAST_WIDTH = 120
local LINGER = 1.5           -- seconds the lines stay after the last swing (while the game's frame is still shown)
local FADE_IN, FADE_OUT = 0.15, 0.6
local CAST = 0.5             -- Auto Shot's own cast at the end of each turn
local RETRY = 5              -- seconds between two looks for the game's frames while they aren't all found
local GOLD = { 1, 0.82, 0.35 }
local SOFT = ns.SOFT_RGB
local INK = ns.INK
local COLOURS = { main = { SOFT[1], SOFT[2], SOFT[3], 0.9 }, off = { SOFT[1], SOFT[2], SOFT[3], 0.6 },
	ranged = { GOLD[1], GOLD[2], GOLD[3], 0.95 } }
local FRAMES = { main = ns.LINE, off = { ns.LINE[1], ns.LINE[2], ns.LINE[3], 0.3 },
	ranged = { GOLD[1], GOLD[2], GOLD[3], 0.8 } } -- the icons' hairlines
local ORDER = { "main", "off", "ranged" }
-- (where each hand's weapon is worn: the ranged slot, else the main hand where a bow is held there)
local SLOTS = { main = { INVSLOT_MAINHAND or 16 }, off = { INVSLOT_OFFHAND or 17 },
	ranged = { INVSLOT_RANGED or 18, INVSLOT_MAINHAND or 16 } }
local FALLBACK_ICONS = { main = "Interface\\Icons\\INV_Sword_04", off = "Interface\\Icons\\INV_Sword_04",
	ranged = "Interface\\Icons\\INV_Weapon_Bow_02" }
local SWING_TYPES = Enum and Enum.PlayerSwingType or {}
local HAND_OF = { [SWING_TYPES.MainHand or 0] = "main", [SWING_TYPES.OffHand or 1] = "off",
	[SWING_TYPES.Ranged or 2] = "ranged" }

local games = {}    -- the game's swing timer frames, the main hand's first
local game          -- the one Serene's lines sit on
local anchoredTo    -- (the frame the lines were last placed on)
local foundBy       -- (/serene debug: how they were found)
local lines         -- Serene's drawing
local rows = {}
local timers = {}   -- hand -> { start, speed }
local melee, ranged = false, false
local wantedAt = -math.huge
local alpha = 0
local hiddenArt = {} -- the game's own regions and frames put away -> their opacity before
local lookedAt = -math.huge
local iconsStale = true
local size          -- the size the rows are drawn at now (1 = 100%)
local dims = {}     -- their measures at that size: icon, gap, pitch, and each hand's height

local function Now() return GetTime() end

-- The game's frames ---------------------------------------------------------------------------------------------------
-- Their names aren't written anywhere an addon can read: they are asked of Edit Mode (the frames holding the swing
-- timer's system, one for each of its indices: MainHand, OffHand), else looked for among the named frames.

local function IsFrame(value)
	return type(value) == "table" and type(value.GetObjectType) == "function"
		and Safe(value.IsObjectType, value, "Frame") == true
end

local function FromEditMode()
	local manager = _G.EditModeManagerFrame
	local system = Enum and Enum.EditModeSystem and Enum.EditModeSystem.SwingTimer
	if type(manager) ~= "table" or system == nil then return nil end
	local frames = manager.registeredSystemFrames
	if type(frames) ~= "table" then return nil end
	local found = {}
	for _, frame in pairs(frames) do
		if type(frame) == "table" and frame.system == system and IsFrame(frame) then found[#found + 1] = frame end
	end
	local indices = Enum.EditModeSwingTimerSystemIndices
	local mainIndex = indices and indices.MainHand
	local function Rank(frame)
		local index = Clean(frame.systemIndex)
		if mainIndex ~= nil and index == mainIndex then return -1 end
		return tonumber(index) or 99
	end
	table.sort(found, function(a, b) return Rank(a) < Rank(b) end)
	return found
end

local function FromNames()
	local outer, any = {}, {}
	for name, value in pairs(_G) do
		if type(name) == "string" and name:find("SwingTimer") and not name:find("^Serene") and IsFrame(value) then
			-- (the outermost ones: frames of the game's own, held by the screen)
			if Safe(value.GetParent, value) == UIParent then outer[#outer + 1] = { value, name } end
			any[#any + 1] = { value, name }
		end
	end
	local list = #outer > 0 and outer or any
	table.sort(list, function(a, b) return #a[2] < #b[2] or (#a[2] == #b[2] and a[2] < b[2]) end)
	if #outer == 0 then list = { list[1] } end
	local frames = {}
	for _, entry in ipairs(list) do frames[#frames + 1] = entry[1] end
	return frames, list[1] and list[1][2]
end

local function Find()
	if game and (foundBy ~= "Edit Mode" or #games >= 2) then return game end
	local now = Now()
	if now - lookedAt < RETRY then return game end
	lookedAt = now
	local found = FromEditMode()
	if found and #found > 0 then
		games, game, foundBy = found, found[1], "Edit Mode"
		return game
	end
	if game then return game end
	local name
	found, name = FromNames()
	if #found > 0 then games, game, foundBy = found, found[1], name end
	return game
end

-- The game's art away (its Edit Mode outlines kept), back when Serene's look is switched off.

local function Keep(object)
	if object == lines then return true end
	for _, frame in ipairs(games) do
		if object == frame.Selection then return true end
	end
	return false
end

local function PutAway(object)
	if hiddenArt[object] == nil then hiddenArt[object] = Clean(Safe(object.GetAlpha, object)) or 1 end
	local now = Clean(Safe(object.GetAlpha, object))
	if now ~= 0 then pcall(object.SetAlpha, object, 0) end
end

local function Ignores(object)
	return Clean(Safe(object.IsIgnoringParentAlpha, object)) == true
end

-- (its own parts away; deeper down only what wouldn't fade with them, ignoring its parent's opacity)
local function HideIn(frame, top)
	for _, region in ipairs({ frame:GetRegions() }) do
		if top or Ignores(region) then PutAway(region) end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not Keep(child) then
			if top or Ignores(child) then PutAway(child) end
			HideIn(child, false)
		end
	end
end

local function HideArt()
	for _, frame in ipairs(games) do HideIn(frame, true) end
end

local function ShowArt()
	for object, before in pairs(hiddenArt) do pcall(object.SetAlpha, object, before) end
	wipe(hiddenArt)
end

local function Shown()
	for _, frame in ipairs(games) do
		if Clean(Safe(frame.IsVisible, frame)) then return true end
	end
	return false
end

-- The swings ------------------------------------------------------------------------------------------------------------

local function Speeds()
	local main, off = Safe(UnitAttackSpeed, "player")
	main, off = Clean(main), Clean(off)
	if type(main) ~= "number" or main <= 0 then main = nil end
	if type(off) ~= "number" or off <= 0 then off = nil end
	return main, off
end

local function RangedSpeed()
	local speed = Clean(Safe(UnitRangedDamage, "player"))
	if type(speed) == "number" and speed > 0 then return speed end
end

local function SpeedOf(hand)
	if hand == "ranged" then return RangedSpeed() end
	local main, off = Speeds()
	if hand == "main" then return main end
	return off
end

local function Swing(hand, length)
	length = Clean(length)
	if type(length) ~= "number" or length <= 0 then length = SpeedOf(hand) end
	if not length then return end
	-- (base: the weapon's speed as the swing began, for a change of speed mid-swing)
	timers[hand] = { start = Now(), speed = length, base = SpeedOf(hand) or length }
	wantedAt = Now()
end

-- (the weapon faster or slower mid-swing: the part already done stays done)
local function Rescale(hand)
	local timer = timers[hand]
	local speed = SpeedOf(hand)
	if not timer or not speed then return end
	local base = timer.base
	if math.abs(speed - base) < 0.001 then return end
	local now = Now()
	local done = math.min(1, (now - timer.start) / timer.speed)
	local length = timer.speed * speed / base
	timer.start, timer.speed, timer.base = now - done * length, length, speed
end

local function Running(hand)
	local timer = timers[hand]
	return timer and Now() < timer.start + timer.speed
end

-- Serene's lines ------------------------------------------------------------------------------------------------------

local function MakeRow(hand)
	local row = CreateFrame("Frame", nil, lines)
	-- the weapon's icon, a hairline of gold around it
	row.badge = CreateFrame("Frame", nil, row)
	row.badge:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon = row.badge:CreateTexture(nil, "ARTWORK")
	row.icon:SetAllPoints(row.badge)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.badge.lines = ns.Hairline(row.badge, FRAMES[hand], "OVERLAY")
	-- the line itself
	local bar = CreateFrame("Frame", nil, row)
	bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.bar = bar
	row.track = bar:CreateTexture(nil, "BACKGROUND")
	row.track:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	row.track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	row.track:SetColorTexture(INK[1], INK[2], INK[3], 0.65)
	if hand == "ranged" then
		row.zone = bar:CreateTexture(nil, "BORDER")
		row.zone:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
		row.zone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
		row.zone:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
	end
	local c = COLOURS[hand]
	row.fill = bar:CreateTexture(nil, "ARTWORK")
	row.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	row.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	row.fill:SetColorTexture(c[1], c[2], c[3], 1)
	row.fill:SetAlpha(c[4])
	row.spark = bar:CreateTexture(nil, "OVERLAY")
	row.spark:SetColorTexture(1, 0.97, 0.88, 1)
	row.spark:SetBlendMode("ADD")
	row:Hide()
	rows[hand] = row
end

-- The rows at the size chosen (Settings: the swing timer's size, in percent).
local function Resize(wanted)
	size = wanted
	local function Scaled(value) return math.max(1, math.floor(value * wanted + 0.5)) end
	dims.icon, dims.gap = Scaled(ICON), Scaled(ICON_GAP)
	dims.pitch = dims.icon + Scaled(ROW_GAP)
	for _, hand in ipairs(ORDER) do
		local row, height = rows[hand], Scaled(HEIGHTS[hand])
		dims[hand] = height
		row:SetHeight(dims.icon)
		row.badge:SetSize(dims.icon, dims.icon)
		row.bar:ClearAllPoints()
		row.bar:SetPoint("LEFT", row.badge, "RIGHT", dims.gap, 0)
		row.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.bar:SetHeight(height)
		row.spark:SetSize(math.max(2, Scaled(2)), height + Scaled(4))
	end
	iconsStale = true -- (the hairlines fitted again)
end

local function WantedSize()
	local percent = tonumber(ns.db and ns.db.swingSize) or 100
	return math.max(0.5, math.min(3, percent / 100))
end

-- Each line's icon: the weapon worn for it.
local function Icons()
	iconsStale = false
	for _, hand in ipairs(ORDER) do
		local texture
		for _, slot in ipairs(SLOTS[hand]) do
			texture = texture or Clean(Safe(GetInventoryItemTexture, "player", slot))
		end
		rows[hand].icon:SetTexture(texture or FALLBACK_ICONS[hand])
		rows[hand].badge.lines:Fit()
	end
end

local function EditMode()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and manager.IsEditModeActive and Safe(manager.IsEditModeActive, manager) and true or false
end

-- How far each line is, nil when it isn't shown; `ready` while the swing waits (out of reach, say).
local function Progress(hand, demo)
	if hand == "ranged" and not ns.On("swingRanged") then return nil end
	if hand == "off" and not timers.off and not select(2, Speeds()) then return nil end
	local timer = timers[hand]
	local active = hand == "ranged" and ranged or hand ~= "ranged" and melee
	if timer and (active or Running(hand)) then
		local p = (Now() - timer.start) / timer.speed
		return math.min(1, math.max(0, p)), p >= 1
	end
	if active then return 1, true end
	if demo then
		if hand == "ranged" and not RangedSpeed() then return nil end
		return hand == "off" and 0.4 or 0.65, false
	end
end

-- (the lines on the main hand's frame, at its scale and above it)
local function Place()
	if anchoredTo == game then return end
	anchoredTo = game
	lines:ClearAllPoints()
	lines:SetPoint("CENTER", game, "CENTER", 0, 0)
	local strata = Clean(Safe(game.GetFrameStrata, game))
	if strata then lines:SetFrameStrata(strata) end
	lines:SetFrameLevel((Clean(Safe(game.GetFrameLevel, game)) or 1) + 5)
end

local function Paint(elapsed)
	Find()
	if not game then
		lines:SetAlpha(0)
		return
	end
	Place()
	HideArt() -- (the game may bring a part of it back: it goes again at once)
	local wanted = WantedSize()
	if wanted ~= size then Resize(wanted) end
	local gameScale = Clean(Safe(game.GetEffectiveScale, game))
	local ownParent = Clean(Safe(UIParent.GetEffectiveScale, UIParent))
	if gameScale and ownParent and ownParent > 0 and math.abs(lines:GetScale() - gameScale / ownParent) > 0.001 then
		lines:SetScale(gameScale / ownParent)
		iconsStale = true -- (the hairlines kept at one pixel)
	end
	if iconsStale then Icons() end
	local demo = EditMode()
	local width = math.max(LEAST_WIDTH, Clean(Safe(game.GetWidth, game)) or 0)
	local barWidth = width - dims.icon - dims.gap
	local any = false
	local y = 0
	for _, hand in ipairs(ORDER) do
		local row = rows[hand]
		local p, ready = Progress(hand, demo)
		if p then
			any = true
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", lines, "TOPLEFT", 0, y)
			row:SetWidth(width)
			y = y - dims.pitch
			local filled = math.max(0.01, barWidth * p)
			row.fill:SetWidth(filled)
			row.fill:SetAlpha(COLOURS[hand][4] * (ready and 0.45 or 1))
			row.badge:SetAlpha(ready and 0.5 or 1)
			row.spark:SetShown(not ready and p > 0.01)
			row.spark:ClearAllPoints()
			row.spark:SetPoint("CENTER", row.bar, "LEFT", filled, 0)
			if row.zone then
				local speed = timers.ranged and timers.ranged.speed or RangedSpeed() or 2
				row.zone:SetWidth(barWidth * math.min(1, CAST / speed))
			end
			row:Show()
		else
			row:Hide()
		end
	end
	local now = Now()
	if any and (melee or ranged or Running("main") or Running("off") or Running("ranged")) then wantedAt = now end
	local target = (demo and any or now - wantedAt < LINGER) and 1 or 0
	alpha = ns.Approach(alpha, target, elapsed, FADE_IN, FADE_OUT)
	-- (shown only while the game shows its swing timer, and as faded as its frame)
	local shown = demo or Shown()
	local gameAlpha = Clean(Safe(game.GetEffectiveAlpha, game)) or 1
	lines:SetAlpha(shown and alpha * gameAlpha or 0)
	lines:SetSize(width, math.max(1, -y - (dims.pitch - dims.icon)))
end

-- Serene's look on the game's frames, or the game's own look back.
local function Apply()
	if not ns.On("swing") then
		if lines then lines:Hide() end
		ShowArt()
		return
	end
	Find()
	if not lines then
		lines = CreateFrame("Frame", nil, UIParent)
		lines:SetSize(LEAST_WIDTH, 10)
		lines:SetAlpha(0)
		for _, hand in ipairs(ORDER) do MakeRow(hand) end
		Resize(WantedSize())
		lines:SetScript("OnUpdate", function(_, elapsed) Paint(elapsed or 0) end)
	end
	iconsStale = true
	lines:Show()
	if game then
		Place()
		HideArt()
	end
end

-- Events ---------------------------------------------------------------------------------------------------------------

local function OnEvent(_, event, a, b)
	if event == "PLAYER_SWING" then
		local hand = HAND_OF[Clean(b)]
		if hand then Swing(hand, a) end
	elseif event == "PLAYER_ENTER_COMBAT" then
		melee = true
		wantedAt = Now()
	elseif event == "PLAYER_LEAVE_COMBAT" then
		melee = false
	elseif event == "START_AUTOREPEAT_SPELL" then
		ranged = true
		wantedAt = Now()
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		ranged = false
	elseif event == "UNIT_ATTACK_SPEED" then
		Rescale("main")
		Rescale("off")
	elseif event == "UNIT_RANGEDDAMAGE" then
		Rescale("ranged")
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		iconsStale = true
	end
end

local function Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_SWING", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL",
		"STOP_AUTOREPEAT_SPELL", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE" }) do
		if not (events.RegisterUnitEvent and pcall(events.RegisterUnitEvent, events, event, "player")) then
			pcall(events.RegisterEvent, events, event)
		end
	end
	events:SetScript("OnEvent", OnEvent)
	-- (already attacking after a /reload)
	melee = Clean(Safe(IsCurrentSpell, 6603)) and true or false
	ranged = Clean(Safe(IsAutoRepeatSpell, 75)) and true or false
	Apply()
end

function ns.SwingDebug()
	lookedAt = -math.huge
	Find()
	local found = {}
	for i, frame in ipairs(games) do
		found[#found + 1] = ("%d: %s index %s%s"):format(i, tostring(Safe(frame.GetName, frame) or "unnamed"),
			tostring(Clean(frame.systemIndex)), Clean(Safe(frame.IsVisible, frame)) and " shown" or "")
	end
	local main, off = Speeds()
	ns.Print(("swing: %s, shots %s, the game's swing timers %s, its option %s, attacking %s, shooting %s, speeds %s / %s / %s"):format(
		tostring(ns.On("swing")), tostring(ns.On("swingRanged")),
		game and ("found by " .. tostring(foundBy) .. " (" .. table.concat(found, "; ") .. ")") or "|cffff8080not found|r",
		tostring(Clean(Safe(GetCVar, "showSwingTimer"))), tostring(melee), tostring(ranged),
		main and ("%.2f"):format(main) or "-", off and ("%.2f"):format(off) or "-",
		RangedSpeed() and ("%.2f"):format(RangedSpeed()) or "-"))
end

table.insert(ns.modules, { init = Init, refresh = Apply })
