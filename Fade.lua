local _, ns = ...
local Safe, Clean, Over = ns.Safe, ns.Clean, ns.Over

-- The interface away when you don't need it.
-- Each group fades out when calm and comes back softly when it is needed; hovering any of its parts brings the
-- whole group back. Only opacities change (allowed in a fight too): nothing is moved, nothing hidden but the
-- minimap's map itself (below), a faded button still works. Edit Mode, or the key held (Key Bindings > AddOns >
-- Serene), shows everything.
--   bars     action bars: in a fight, with an enemy targeted, while casting, a spell or item on the cursor
--   bar4/5   Action Bars 4 and 5: under the mouse only, each on its own
--   unit     your portrait and your pet's: in a fight, hurt, healed or struck (a moment after), mana or energy
--            not full, rage, a target
--   minimap  the compass: under the mouse only (/serene compass world: always, except in cities and towns);
--            its band, its round buttons and its addons panel count as the compass under the mouse; the queue's
--            eye comes and goes with it (the top bar tells of the queue meanwhile)
--   buffs    buffs and debuffs: in a fight (and a moment after), a target, while a debuff is on you, under the mouse;
--            the buffs always while a Welcoming Campfire warms you
--   xp       experience and reputation bars: in a fight (and a moment after), experience gained, under the mouse
--   menu     micro menu and bags: under the mouse
--   top      Serene's top bar: always, away in fights, or under the mouse (/serene top always|calm|hover)
--   words    the menu's words under the top bar (MenuBar.lua): only under the mouse, the top bar's or theirs
-- A button glowing with a hint (Hints.lua) shows itself alone, its bar staying away (or, as set, its bar or every
-- bar comes back with it: hintReveal).

local CHECK_EVERY = 0.1
local FRAMES_EVERY = 3 -- seconds between two looks at which frames exist
local FADE_IN, FADE_OUT = 0.25, 0.9
-- The minimap's engine cannot draw it half-seen (no terrain, a crosshatch): shown or hidden at once, never between.
local AT_ONCE = { minimap = true }
-- (and what the engine draws whatever the opacity, the arrow of where you stand and the dots on the map: the map
-- itself hidden while the compass is away; its frame around stays, so the mouse still finds it)
local HIDE_AWAY = { minimap = { "Minimap" } }
local hiddenAway = {} -- frame -> true while Serene hides it

-- The compass comes and goes through dark glass: a disc over the map darkens, the map appears (or goes) under it
-- at once, then the glass clears; the ring and the band fade with it. Only the glass and the decorations change
-- opacity, never the map itself.
local COVER_IN, REVEAL = 0.1, 0.45  -- seconds: coming (glass up, then clearing over the map)
local COVER_OUT, CLEAR = 0.25, 0.35  -- going (glass over the map, then clearing over the world)
local GLASS = 1                      -- the glass at its darkest (the map's switch never seen)
local GLASS_SIZE = 1.16              -- the glass over the map's size: a solid middle, a soft edge beyond the map's
-- (the glass never lingers dark: it leaves its darkest at once and slows as it clears)
local function Ease(t) return t * t end
local compass = { shown = true, glass = 0 }
local SetAlphas -- (below)
local glass -- the disc's frame

local function Glass()
	if glass then return glass end
	local map = _G.Minimap
	if type(map) ~= "table" then return nil end
	glass = CreateFrame("Frame", nil, UIParent)
	glass:SetPoint("CENTER", map, "CENTER")
	glass:SetFrameStrata(map:GetFrameStrata() or "LOW")
	glass:SetFrameLevel((map:GetFrameLevel() or 1) + 20) -- (over everything the compass hangs on the map)
	glass:EnableMouse(false)
	glass.disc = glass:CreateTexture(nil, "OVERLAY")
	glass.disc:SetAllPoints()
	glass:Hide()
	return glass
end

local function ShowMap(show)
	for _, name in ipairs(HIDE_AWAY.minimap) do
		local frame = _G[name]
		if type(frame) == "table" and frame.Show then
			if not show and not hiddenAway[frame] and Safe(frame.IsShown, frame) then
				if pcall(frame.Hide, frame) then hiddenAway[frame] = true end
			elseif show and hiddenAway[frame] then
				if pcall(frame.Show, frame) then hiddenAway[frame] = nil end
			end
		end
	end
end

local function PaintGlass(amount)
	local g = Glass()
	if not g then return end
	if amount <= 0 then
		g:Hide()
	else
		local map = _G.Minimap
		local w = Clean(Safe(map.GetWidth, map)) or 140
		local h = Clean(Safe(map.GetHeight, map)) or w
		if g.edge ~= ns.db.edge or g.w ~= w or g.h ~= h then
			g.edge, g.w, g.h = ns.db.edge, w, h
			if g.edge == "square" then
				g.disc:SetColorTexture(1, 1, 1, 1)
				g:SetSize(w, h)
			else
				g.disc:SetTexture("Interface\\AddOns\\Serene\\Media\\DiscSoft")
				g:SetSize(w * GLASS_SIZE, h * GLASS_SIZE)
			end
			g.disc:SetVertexColor(0.035, 0.04, 0.05, 1)
		end
		g:SetAlpha(Ease(amount) * GLASS)
		g:Show()
	end
end

local function Compass(s, elapsed)
	local want = s.want >= 1
	local amount = compass.glass
	if want ~= compass.shown then
		-- (the glass up first; at its darkest, the map comes or goes beneath it)
		amount = math.min(1, amount + elapsed / (want and COVER_IN or COVER_OUT))
		if amount >= 1 then
			compass.shown = want
			SetAlphas(s.frames, want and 1 or 0)
			ShowMap(want)
		end
	else
		amount = math.max(0, amount - elapsed / (want and REVEAL or CLEAR))
	end
	compass.glass = amount
	s.alpha = compass.shown and 1 or 0
	-- (kept so: the queue's eye the game shows again, or found meanwhile)
	SetAlphas(s.frames, s.alpha)
	PaintGlass(amount)
	if ns.CompassDecor then ns.CompassDecor(compass.shown and (1 - Ease(amount)) or 0) end
end
local LINGER = 1.5     -- seconds a group stays after it was needed
local AFTER_FIGHT = 3  -- seconds the fighting groups stay after a fight
local AFTER_STRUCK = 3 -- seconds your portrait stays after a heal or a blow on you (one at full health too)

local GROUPS = {
	bars = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "MainMenuBarArtFrame",
		"MultiCastActionBarFrame" },
	bar4 = { "MultiBarRight" }, -- Action Bar 4: under the mouse only
	bar5 = { "MultiBarLeft" },  -- Action Bar 5: under the mouse only
	unit = { "PlayerFrame", "PetFrame" },
	minimap = { "MinimapCluster" },
	buffs = { "BuffFrame", "TemporaryEnchantFrame", "SereneAuras" }, -- (Serene's own buff frame: AuraFrame.lua)
	debuffs = { "DebuffFrame", "SereneDebuffs" },
	xp = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"MainMenuExpBar", "ReputationWatchBar" },
	menu = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar", "BagsBar" },
	top = { "SereneTopBar" }, -- Serene's top bar (TopBar.lua)
	words = { "SereneMenuBar" }, -- the menu's words under it (MenuBar.lua)
}
-- Groups whose frames stand on their own: in this game Action Bars 4 and 5 may sit inside the main bar, whose
-- opacity they would follow (shown with a target). Their parent's opacity is ignored, they are never left to it.
local OWN = { bar4 = true, bar5 = true }

-- (groups with no switch of their own: the group whose switch they follow)
local SWITCH = { debuffs = "buffs", xp = "menu", bar4 = "bars", bar5 = "bars" }
local ORDER = { "bars", "bar4", "bar5", "unit", "minimap", "buffs", "debuffs", "xp", "menu", "top", "words" }
-- Groups wholly away at rest, whatever the rest opacity is.
local GONE = { words = true }

local state = {} -- group -> { frames = { frame, ... }, alpha, last }
local groupOf = {} -- a faded frame -> its group
local touched = setmetatable({}, { __mode = "k" }) -- frame -> true once Serene set its opacity
local peeking = false
local fightEnded = -math.huge
local struck = -math.huge -- the last heal or blow on you
local inFight = false

-- Why each group is needed now, beside the mouse.
local function Casting()
	return Clean(Safe(UnitCastingInfo, "player")) ~= nil or Clean(Safe(UnitChannelInfo, "player")) ~= nil
end

local function Targeted()
	return Clean(Safe(UnitExists, "target")) and true or false
end

local function EnemyTargeted()
	if not Clean(Safe(UnitExists, "target")) then return false end
	local enemy = Safe(UnitCanAttack, "player", "target")
	-- (a secret answer counts as an enemy: bars shown for nothing cost less than bars missing in a fight)
	if ns.IsSecret(enemy) then return true end
	return enemy and not Clean(Safe(UnitIsDead, "target")) and true or false
end

-- (values the game hides from addons are unknown: never taken as hurt or tired; a fight shows it all anyway)
local function Hurt(unit)
	if not Clean(Safe(UnitExists, unit)) then return false end
	local health, most = Clean(Safe(UnitHealth, unit)), Clean(Safe(UnitHealthMax, unit))
	return type(health) == "number" and type(most) == "number" and most > 0 and health < most
end

local function PowerNotRested()
	local kind = Clean(Safe(UnitPowerType, "player"))
	local power, most = Clean(Safe(UnitPower, "player")), Clean(Safe(UnitPowerMax, "player"))
	if type(power) ~= "number" or type(most) ~= "number" or most <= 0 then return false end
	-- (rage and runic power rest at nothing; mana, energy and focus at full)
	if kind == 1 or kind == 6 then return power > 0 end
	return power < most
end

-- A debuff worth seeing: one that ends soon (a poison, a curse, a snare...). Long ones (Resurrection Sickness,
-- Deserter) and those that never end (the game's own lasting marks) don't bring the buffs back.
local SHORT = 120 -- seconds
local function Debuffs()
	local list = {}
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for index = 1, 40 do
		local name, duration
		if get then
			local aura = Safe(get, "player", index, "HARMFUL")
			if aura == nil then break end
			if type(aura) == "table" then name, duration = Clean(aura.name), Clean(aura.duration) end
		else
			local found, _, _, _, length = Safe(UnitDebuff, "player", index)
			if Clean(found) == nil then break end
			name, duration = Clean(found), Clean(length)
		end
		list[#list + 1] = { name = name or "?", duration = duration }
	end
	return list
end

local function DebuffOn()
	for _, debuff in ipairs(Debuffs()) do
		-- (unreadable: in a fight, where the buffs show anyway)
		if type(debuff.duration) ~= "number" then return false end
		if debuff.duration > 0 and debuff.duration <= SHORT then return true end
	end
	return false
end

-- Buffs that keep the buffs shown while they are on you (by name: the spell may have several ids).
local ALWAYS = { ["Welcoming Campfire"] = true }
local function AlwaysOn()
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for index = 1, 40 do
		local name
		if get then
			local aura = Safe(get, "player", index, "HELPFUL")
			if aura == nil then break end
			if type(aura) == "table" then name = Clean(aura.name) end
		else
			local found = Safe(UnitBuff, "player", index)
			if Clean(found) == nil then break end
			name = Clean(found)
		end
		-- (unreadable names, in a fight: the buffs show anyway)
		if name and ALWAYS[name] then return true end
	end
	return false
end

local NEEDED = {
	bars = function()
		return inFight or EnemyTargeted() or Casting() or Clean(Safe(GetCursorInfo)) ~= nil
	end,
	bar4 = function() return false end,
	bar5 = function() return false end,
	unit = function()
		return inFight or GetTime() - struck < AFTER_STRUCK or Hurt("player") or Hurt("pet") or PowerNotRested()
			or Clean(Safe(UnitExists, "target")) and true
	end,
	-- (the compass: always out in the world, dungeons included; in cities and towns, under the mouse only)
	minimap = function()
		if ns.db.compass == "world" then return not Clean(Safe(IsResting)) end
		return ns.CompassOpen ~= nil and ns.CompassOpen() or false
	end,
	buffs = function() return inFight or Targeted() or DebuffOn() or AlwaysOn() end,
	debuffs = function() return inFight or Targeted() or DebuffOn() end,
	xp = function() return inFight or (ns.XPGained ~= nil and ns.XPGained()) end,
	menu = function() return false end,
	-- (the top bar: always, away in fights, or under the mouse only; worn gear, full bags or a queue bring it back)
	top = function()
		return Over(_G.SereneMenuBar) or ns.TopNeeded ~= nil and ns.TopNeeded(inFight) or false
	end,
	-- (the words: with the top bar under the mouse)
	words = function() return Over(_G.SereneTopBar) end,
}

local function EditMode()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and manager.IsEditModeActive and Safe(manager.IsEditModeActive, manager) and true or false
end

local freed = {} -- frame -> true once its parent's opacity is ignored
local function Free(frames)
	for _, frame in ipairs(frames) do
		-- (the bars are protected frames: left alone in a fight, tried again at the next Collect)
		if not freed[frame] and frame.SetIgnoreParentAlpha and not InCombatLockdown() then
			if pcall(frame.SetIgnoreParentAlpha, frame, true) then freed[frame] = true end
		end
	end
end

-- Each group's candidates: its frames by name.
local function Candidates(group)
	local list = {}
	-- (the menu as words: the game's bars kept out of sight by MenuBar.lua, never brought back here)
	if group == "menu" and ns.On("menuBar") then return list end
	for _, name in ipairs(GROUPS[group]) do
		local frame = _G[name]
		if type(frame) == "table" and frame.SetAlpha then list[#list + 1] = frame end
	end
	return list
end

-- Which frames exist (looked at now and then): a frame whose parent is faded already is left to its parent.
local function Collect()
	wipe(groupOf)
	local all, candidates = {}, {}
	for _, group in ipairs(ORDER) do
		candidates[group] = Candidates(group)
		for _, frame in ipairs(candidates[group]) do
			if all[frame] == nil then all[frame] = group end
		end
	end
	for _, group in ipairs(ORDER) do
		local frames = {}
		for _, frame in ipairs(candidates[group]) do
			if all[frame] == group and OWN[group] then
				frames[#frames + 1] = frame
			elseif all[frame] == group then
				local parent, inside = frame.GetParent and frame:GetParent(), false
				for _ = 1, 4 do
					if type(parent) ~= "table" then break end
					if all[parent] then inside = true break end
					parent = parent.GetParent and parent:GetParent()
				end
				if not inside then frames[#frames + 1] = frame end
			end
		end
		-- (the queue's eye comes and goes with the compass, wherever the game hangs it)
		if group == "minimap" and ns.QueueFrames then
			local have = {}
			for _, frame in ipairs(frames) do have[frame] = true end
			for _, frame in ipairs(ns.QueueFrames()) do
				if not have[frame] then frames[#frames + 1] = frame end
			end
		end
		state[group] = state[group] or { alpha = 1, last = GetTime() }
		state[group].frames = frames
		for _, frame in ipairs(frames) do groupOf[frame] = group end
		if OWN[group] then Free(frames) end
	end
end

-- (the top band has its own switch; the words band follows menuBar alone, being only ever seen under the mouse)
local function Wanted(group)
	if group == "top" then return ns.On("fade") and ns.On("top") end
	if group == "words" then return ns.On("menuBar") end
	return ns.On("fade") and ns.db.groups[SWITCH[group] or group] and true or false
end

SetAlphas = function(frames, alpha)
	for _, frame in ipairs(frames) do
		local now = Safe(frame.GetAlpha, frame)
		-- (near enough already: not set again every frame)
		if type(now) ~= "number" or math.abs(now - alpha) > 0.004 then
			pcall(frame.SetAlpha, frame, alpha)
			touched[frame] = true
		end
	end
end

-- Ten times a second: what each group wants (full, or at rest).
local function Look()
	local now = GetTime()
	local all = peeking or EditMode()
	local rest = (ns.db.rest or 0) / 100
	for _, group in ipairs(ORDER) do
		local s = state[group]
		if s then
			if not Wanted(group) then
				s.want, s.off = 1, true
			else
				s.off = false
				local hovered = false
				for _, frame in ipairs(s.frames) do
					if Over(frame) then hovered = true break end
				end
				-- (the compass's parts outside its frame: its band, its round buttons, its addons panel)
				if not hovered and group == "minimap" and ns.CompassParts then
					for _, part in ipairs(ns.CompassParts()) do
						if Over(part) then hovered = true break end
					end
				end
				-- (debuffs come back with the buffs under the mouse, and the other way round)
				if not hovered and (group == "buffs" or group == "debuffs") then
					local other = state[group == "buffs" and "debuffs" or "buffs"]
					for _, frame in ipairs(other and other.frames or {}) do
						if Over(frame) then hovered = true break end
					end
				end
				local fighting = (group == "bars" or group == "unit" or group == "buffs" or group == "debuffs"
					or group == "xp") and now - fightEnded < AFTER_FIGHT
				local ok, needed = pcall(NEEDED[group])
				-- (a glow asking for every action bar)
				if (group == "bars" or group == "bar4" or group == "bar5") and ns.HintRevealBars and ns.HintRevealBars() then
					needed, ok = true, true
				end
				if all or hovered or fighting or (ok and needed) then s.last = now end
				s.want = (now - s.last < LINGER) and 1 or ((AT_ONCE[group] or GONE[group]) and 0 or rest)
			end
		end
	end
end

-- Every frame: each group toward what it wants.
local function Fade(elapsed)
	for _, group in ipairs(ORDER) do
		local s = state[group]
		if s and s.want then
			if s.off then
				-- (switched off: given back at full, once)
				if s.alpha ~= 1 then
					s.alpha = 1
					SetAlphas(s.frames, 1)
				end
				if group == "minimap" and (not compass.shown or compass.glass > 0) then
					ShowMap(true)
					compass.shown, compass.glass = true, 0
					PaintGlass(0)
					if ns.CompassDecor then ns.CompassDecor(1) end
				end
			elseif group == "minimap" then
				Compass(s, elapsed)
			else
				if AT_ONCE[group] then
					s.alpha = s.want
				else
					s.alpha = ns.Approach(s.alpha, s.want, elapsed, FADE_IN, FADE_OUT)
				end
				SetAlphas(s.frames, s.alpha)
			end
		end
	end
end

local function Step(elapsed)
	Look()
	Fade(elapsed or 0)
end

-- The key: the whole interface while it is held.
function Serene_Peek(keystate)
	peeking = keystate == "down"
end
function ns.IsPeeking() return peeking end
BINDING_HEADER_SERENE = "Serene"
BINDING_NAME_SERENE_PEEK = "Show the whole interface (hold)"

local function Init()
	Collect()
	local since, sinceFrames = 0, 0
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		sinceFrames = sinceFrames + elapsed
		if sinceFrames >= FRAMES_EVERY then
			sinceFrames = 0
			Collect()
		end
		-- (looked at ten times a second; the fades themselves move every frame)
		if since >= CHECK_EVERY then
			since = 0
			Look()
		end
		Fade(elapsed)
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- (a heal or a blow on you: healing over time at full health, a shield soaking a hit, a fall...)
	for _, event in ipairs({ "UNIT_COMBAT", "UNIT_HEALTH" }) do
		if not (events.RegisterUnitEvent and pcall(events.RegisterUnitEvent, events, event, "player")) then
			pcall(events.RegisterEvent, events, event)
		end
	end
	events:SetScript("OnEvent", function(_, event, unit, action)
		if event == "UNIT_COMBAT" or event == "UNIT_HEALTH" then
			if unit ~= "player" then return end
			-- (mana or energy given is not a heal; an unreadable action is taken as one)
			if event == "UNIT_COMBAT" and Clean(action) == "ENERGIZE" then return end
			struck = GetTime()
			if state.unit and state.unit.want ~= 1 then Look() end
			return
		end
		inFight = event == "PLAYER_REGEN_DISABLED"
		if not inFight then fightEnded = GetTime() end
		-- (a fight: the bars back at once, not at the next look)
		if inFight then Look() end
	end)
	inFight = InCombatLockdown() and true or false
end

-- /serene debug: each group's frames (their parent, their opacity), the names not found in this game.
local function NameOf(frame)
	local name = type(frame) == "table" and frame.GetName and Safe(frame.GetName, frame)
	return type(name) == "string" and name or tostring(frame)
end

function ns.FadeDebug()
	Collect()
	local list = {}
	for _, debuff in ipairs(Debuffs()) do
		list[#list + 1] = ("%s (%s)"):format(debuff.name, type(debuff.duration) == "number" and
			(debuff.duration > 0 and ("%ds"):format(debuff.duration) or "lasting") or "unreadable")
	end
	ns.Print("debuffs on you: " .. (#list > 0 and table.concat(list, ", ") or "none")
		.. "  -  buffs brought back by them: " .. tostring(DebuffOn()) .. "  -  campfire: " .. tostring(AlwaysOn()))
	for _, group in ipairs(ORDER) do
		local ok, needed = pcall(NEEDED[group])
		local s = state[group]
		ns.Print(("  %s: needed now %s, wanted %s, shown %.2f"):format(group, tostring(ok and needed),
			tostring(s and s.want), s and s.alpha or -1))
	end
	for _, group in ipairs(ORDER) do
		local s, shown, missing = state[group], {}, {}
		for _, frame in ipairs(s and s.frames or {}) do
			local parent = frame.GetParent and frame:GetParent()
			local alpha = Safe(frame.GetEffectiveAlpha, frame)
			shown[#shown + 1] = ("%s (in %s, seen %s)"):format(NameOf(frame), NameOf(parent),
				type(alpha) == "number" and ("%.2f"):format(alpha) or "?")
		end
		for _, name in ipairs(GROUPS[group]) do
			local frame = _G[name]
			if type(frame) ~= "table" then
				missing[#missing + 1] = name
			else
				local listed = false
				for _, each in ipairs(s and s.frames or {}) do listed = listed or each == frame end
				if not listed then missing[#missing + 1] = name .. " (inside another faded frame)" end
			end
		end
		ns.Print(("|cffffd100%s|r: %s"):format(group, #shown > 0 and table.concat(shown, ", ") or "nothing"))
		if #missing > 0 then ns.Print("   not used: " .. table.concat(missing, ", ")) end
	end
	-- (the game's experience bar, wherever it lives)
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "StatusTrackingBarManager", "MainMenuExpBar" }) do
		local frame = _G[name]
		if type(frame) == "table" then
			local chain, parent = {}, frame.GetParent and frame:GetParent()
			for _ = 1, 5 do
				if type(parent) ~= "table" then break end
				chain[#chain + 1] = NameOf(parent)
				parent = parent.GetParent and parent:GetParent()
			end
			ns.Print(("experience: %s shown %s, inside %s"):format(name, tostring(Safe(frame.IsShown, frame)),
				table.concat(chain, " > ")))
		end
	end
end

-- (/serene debug: the top bar's group as Fade sees it, the mouse over it or not)
function ns.FadeTopDebug()
	local s = state.top
	local names = {}
	for _, frame in ipairs(s and s.frames or {}) do names[#names + 1] = NameOf(frame) .. " over " .. tostring(Over(frame)) end
	local ok, needed = pcall(NEEDED.top)
	ns.Print(("  top group: switched on %s, frames %s, needed %s, wanted %s, shown %s, last needed %.1fs ago, fight %s, peek %s, edit mode %s"):format(
		tostring(Wanted("top")), #names > 0 and table.concat(names, ", ") or "none", tostring(ok and needed),
		tostring(s and s.want), tostring(s and s.alpha), s and s.last and (GetTime() - s.last) or -1,
		tostring(inFight), tostring(peeking), tostring(EditMode())))
end

table.insert(ns.modules, { init = Init, refresh = function() if state.bars then Step(0) end end })
ns.FadeStep = Step -- (tests)
ns.FadeCollect = Collect
