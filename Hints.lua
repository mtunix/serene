local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Hints: a soft gold glow around an action button worth pressing now. What else comes back with it (the settings,
-- "When something glows"):
--   none     nothing: the glow is seen only when its bar is (under the mouse, in a fight...)
--   button   the button itself, alone
--   bar      the bar holding it, all its buttons
--   bars     every action bar (Fade.lua asks ns.HintRevealBars)
-- Each rule says, out of a fight, which of your action buttons make sense to use:
--   food     you are not Well Fed (and not eating): the food on your bars that makes you Well Fed
--   buffs    something your class keeps up is missing (a buff, a weapon's poison or imbue): what gives it, on your
--            bars (CLASS_BUFFS below); not while mounted, and a spell only when it can be cast (learned, the mana)
-- Running out (a setting, on by default): a class buff or a weapon's poison or imbue with less than a while left
-- (2 minutes by default) gives what renews it a fainter, still glow: worth renewing before a fight, not yet missing.
-- Only buffs that last longer than that while (an aura or a blessing at 5 minutes is not "running out" at 10).
-- More rules are one function each (RULES below). /serene hints on|off

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local GOLD = { 1, 0.8, 0.3 }
local GLOW_SCALE = 1.6   -- the glow's texture over the button's size (its ring sits on the button's edge)
local FAINT = 0.4        -- the glow for something running out: still, this strong
local CHECK_EVERY = 0.5

local Actions = ns.Actions
local Slot, ActionOn, Buttons = Actions.Slot, Actions.Cast, Actions.Buttons

local lit = {}      -- button -> true while it glows
local faint = {}    -- button -> true while it glows faintly (a class buff running out)
local litList = {}  -- (the same, as a list, for Fade.lua)
local glows = {}    -- button -> its glow frame
local dirty = true

-- What is on a button ---------------------------------------------------------------------------------------------

local function Count(item)
	local count = C_Item and C_Item.GetItemCount and Safe(C_Item.GetItemCount, item) or Safe(GetItemCount, item)
	return Clean(count) or 0
end

local function ItemOn(slot)
	local kind, id = ActionOn(slot)
	if kind == "item" then return id end
end

-- What you have on you ---------------------------------------------------------------------------------------------

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return Clean(Safe(C_Spell.GetSpellName, id)) end
	return Clean((Safe(GetSpellInfo, id)))
end

-- Your buffs' names, or nil when the game does not let them be read. (In a fight this game answers nothing at all
-- when asked for your buffs one by one: that is "can't be read", never "no buffs".) Second: name -> { left, duration }
-- in seconds for the buffs that run out (the longest of one name).
local function BuffNames()
	local names, ends = {}, {}
	local now = GetTime()
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	local fighting = InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player"))
	for index = 1, 40 do
		local name
		if get then
			local aura = Safe(get, "player", index, "HELPFUL")
			if aura == nil and index == 1 and fighting then return nil end
			if aura == nil then break end
			name = type(aura) == "table" and Clean(aura.name)
			local expires = type(aura) == "table" and Clean(aura.expirationTime)
			local duration = type(aura) == "table" and Clean(aura.duration)
			if name and type(expires) == "number" and type(duration) == "number" then
				local key = name:lower()
				local left = duration > 0 and expires > 0 and expires - now or math.huge
				if not ends[key] or ends[key].left < left then ends[key] = { left = left, duration = duration } end
			end
		else
			name = Clean((Safe(UnitBuff, "player", index)))
			if name == nil then break end
		end
		if name == nil then return nil end
		names[name:lower()] = true
	end
	return names, ends
end

-- The food rule -----------------------------------------------------------------------------------------------------

local WELL_FED, EATING
local fedFood = {} -- item -> true / false (does it make you Well Fed), once its tooltip could be read

local function Lower(text) return type(text) == "string" and text:lower() or nil end

-- An item's tooltip, as lines of text (nil while the game has not loaded the item yet).
local scanner
local function TooltipLines(item)
	local lines = {}
	local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and Safe(C_TooltipInfo.GetItemByID, item)
	if type(data) == "table" then
		if TooltipUtil and TooltipUtil.SurfaceArgs then Safe(TooltipUtil.SurfaceArgs, data) end
		for _, line in ipairs(type(data.lines) == "table" and data.lines or {}) do
			if TooltipUtil and TooltipUtil.SurfaceArgs and line.leftText == nil then Safe(TooltipUtil.SurfaceArgs, line) end
			local text = Clean(line.leftText)
			if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
		end
	end
	if #lines > 1 then return lines, "tooltip info" end
	-- (else the old way: a hidden tooltip of our own, read line by line)
	if not scanner then
		scanner = CreateFrame("GameTooltip", "SereneScanTooltip", nil, "GameTooltipTemplate")
	end
	lines = {}
	Safe(scanner.SetOwner, scanner, WorldFrame, "ANCHOR_NONE")
	Safe(scanner.ClearLines, scanner)
	if scanner.SetItemByID then Safe(scanner.SetItemByID, scanner, item)
	else Safe(scanner.SetHyperlink, scanner, "item:" .. item) end
	for index = 1, Clean(Safe(scanner.NumLines, scanner)) or 0 do
		local region = _G["SereneScanTooltipTextLeft" .. index]
		local text = region and Clean(Safe(region.GetText, region))
		if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
	end
	Safe(scanner.Hide, scanner)
	if #lines > 1 then return lines, "scanned" end
end

local function MakesWellFed(item)
	if fedFood[item] ~= nil then return fedFood[item] end
	local lines = TooltipLines(item)
	if not lines then return false end -- (not loaded yet: asked again later)
	local found = false
	for _, line in ipairs(lines) do
		local text = Lower(line)
		if text and (text:find("well fed", 1, true) or (WELL_FED and text:find(WELL_FED, 1, true))) then
			found = true
			break
		end
	end
	fedFood[item] = found
	return found
end

-- The class buffs rule -----------------------------------------------------------------------------------------------

-- Per class, what you keep up, one line each:
--   spells   the spells that give it (any rank: matched by name). One of them glows: the one you used last, or else
--            the first on your bars (a choice like your armor or your blessing is kept, not argued with)
--   have     the buffs that mean it is on already (by default those spells' own)
--   weapon   instead of a buff: a weapon of yours without its temporary enchant ("main", or "both" hands)
--   items    instead of spells: the items that give it (poisons, stones: all of them on your bars glow)
local ASPECTS = { 13165, 13163, 5118, 13159, 13161, 20043 } -- Hawk, Monkey, Cheetah, Pack, Beast, Wild
local POISONS = {
	6947, 6949, 6950, 8926, 8927, 8928, -- Instant
	2892, 2893, 8984, 8985, 20844,      -- Deadly
	3775, 3776,                         -- Crippling
	5237, 6951, 9186,                   -- Mind-numbing
	10918, 10920, 10921, 10922,         -- Wound
}
local STONES = {
	2862, 2863, 2871, 7964, 12404, 18262, -- sharpening stones
	3239, 3240, 3241, 7965, 12643,        -- weightstones
}
local CLASS_BUFFS = {
	HUNTER = {
		-- Aspect of the Hawk (Monkey if that is yours), unless an aspect is on already (Cheetah on the road...)
		{ spells = { 13165, 13163 }, have = ASPECTS },
		{ spells = { 19506 } }, -- Trueshot Aura (when talented: an unlearned one can't be cast, so it doesn't glow)
	},
	MAGE = {
		{ spells = { 1459 }, have = { 1459, 23028 } }, -- Arcane Intellect (or Brilliance)
		{ spells = { 7302, 6117, 168 } },               -- Ice Armor, Mage Armor, Frost Armor
	},
	PRIEST = {
		{ spells = { 1243 }, have = { 1243, 21562 } },   -- Power Word: Fortitude (or Prayer of)
		{ spells = { 588 } },                             -- Inner Fire
		{ spells = { 14752 }, have = { 14752, 27681 } }, -- Divine Spirit (or Prayer of Spirit), when talented
	},
	DRUID = {
		{ spells = { 1126 }, have = { 1126, 21849 } }, -- Mark of the Wild (or Gift of the Wild)
		{ spells = { 467 } },                           -- Thorns
		{ spells = { 16864 } },                         -- Omen of Clarity, when talented
	},
	WARLOCK = {
		{ spells = { 706, 687 } }, -- Demon Armor, Demon Skin
	},
	PALADIN = {
		-- an aura: Devotion, Retribution, Concentration, Sanctity, Shadow / Frost / Fire Resistance
		{ spells = { 465, 7294, 19746, 20218, 19876, 19888, 19891 } },
		-- a blessing: Might, Wisdom, Kings, Salvation, Light, Sanctuary (a Greater one counts)
		{ spells = { 19740, 19742, 20217, 1038, 19977, 20911 },
			have = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 } },
	},
	SHAMAN = {
		{ spells = { 324 } }, -- Lightning Shield
		-- a weapon imbue: Windfury, Flametongue, Frostbrand, Rockbiter
		{ spells = { 8232, 8024, 8033, 8017 }, weapon = "main" },
	},
	ROGUE = {
		{ items = POISONS, weapon = "both" },
	},
	WARRIOR = {
		{ items = STONES, weapon = "both" },
	},
}

local classBuffs -- (your class's, with the names in your language, once they could all be read)
local function ClassBuffs()
	if classBuffs then return classBuffs end
	local _, class = Safe(UnitClass, "player")
	local list = CLASS_BUFFS[Clean(class) or ""]
	if not list then return nil end
	local named = {}
	for _, def in ipairs(list) do
		local entry = { weapon = def.weapon, spells = {}, have = {}, ids = {} }
		if def.items then
			entry.key = "items"
			entry.items = {}
			for _, item in ipairs(def.items) do entry.items[item] = true end
		else
			entry.key = tostring(def.spells[1])
			for _, spell in ipairs(def.spells) do
				local name = Lower(SpellName(spell))
				if not name then return nil end -- (asked again later)
				entry.spells[#entry.spells + 1] = name
				entry.ids[name] = spell
			end
			for _, spell in ipairs(def.have or def.spells) do
				local name = Lower(SpellName(spell))
				if name then entry.have[#entry.have + 1] = name end
			end
		end
		named[#named + 1] = entry
	end
	classBuffs = named
	return named
end

-- The spell of a group you used last (kept per character, across sessions).
local function Memory()
	if type(ns.db.hintLast) ~= "table" then ns.db.hintLast = {} end
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	ns.db.hintLast[who] = type(ns.db.hintLast[who]) == "table" and ns.db.hintLast[who] or {}
	return ns.db.hintLast[who]
end

local function Remember(name)
	local list = ClassBuffs()
	if not list or not name then return end
	for _, def in ipairs(list) do
		if #def.spells > 1 then
			for _, spell in ipairs(def.spells) do
				if spell == name then Memory()[def.key] = name end
			end
		end
	end
end

local function Mounted() return Clean(Safe(IsMounted)) == true end

local function Castable(slot)
	return Actions.Usable(slot) == true
end

local function ItemClass(item)
	local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	local _, _, _, _, _, class, subclass = Safe(get, item)
	return Clean(class), Clean(subclass)
end

-- A weapon (not a fishing pole) in that hand, without a temporary enchant.
local function Bare(slot, enchanted)
	local item = Clean(Safe(GetInventoryItemID, "player", slot))
	if type(item) ~= "number" then return false end
	local class, subclass = ItemClass(item)
	return class == 2 and subclass ~= 20 and not enchanted
end

local function Missing(def, buffs)
	if def.weapon then
		local main, _, _, _, off = Safe(GetWeaponEnchantInfo)
		main, off = Clean(main), Clean(off)
		return Bare(16, main) or (def.weapon == "both" and Bare(17, off))
	end
	for _, name in ipairs(def.have) do
		if buffs[name] then return false end
	end
	return true
end

-- On, but running out: less than the setting's while left, of a buff (or an enchant) that lasts longer than that.
local function RunningOut(def, buffs, ends)
	local at = tonumber(ns.db.hintBuffSoonAt) or 120
	if def.weapon then
		local main, mainLeft, _, _, off, offLeft = Safe(GetWeaponEnchantInfo)
		main, mainLeft, off, offLeft = Clean(main), Clean(mainLeft), Clean(off), Clean(offLeft)
		local function Low(slot, on, left)
			return on and type(left) == "number" and left / 1000 < at and Bare(slot, false)
		end
		return Low(16, main, mainLeft) or (def.weapon == "both" and Low(17, off, offLeft)) or false
	end
	local found = false
	for _, name in ipairs(def.have) do
		if buffs[name] then
			local e = ends and ends[name]
			-- (one that doesn't run out, or not yet near its end: nothing to renew)
			if not e or e.left >= at or e.duration <= at then return false end
			found = true
		end
	end
	return found
end

-- What is on your bars: spell name -> castable now (false: there, not castable); item -> true (one you carry).
local function OnBars()
	local spells, items = {}, {}
	for _, button in ipairs(Buttons()) do
		local slot = Slot(button)
		local kind, id
		if slot then kind, id = ActionOn(slot) end
		if kind == "spell" then
			local name = Lower(SpellName(id))
			if name then spells[name] = spells[name] or Castable(slot) end
		elseif kind == "item" and Count(id) > 0 then
			items[id] = true
		end
	end
	return { spells = spells, items = items }
end

-- Which spell of a group glows: the one you used last if it is on your bars, else the first that can be cast.
local function Pick(def, bars)
	local last = Memory()[def.key]
	if last and bars.spells[last] ~= nil then return last, bars.spells[last] end
	for _, name in ipairs(def.spells) do
		if bars.spells[name] then return name, true end
	end
end

-- What glows for your class now: spell names, items (and, for /serene debug, a line on each). Second: what glows
-- faintly (running out), the same way.
local function Plan(buffs, notes, ends)
	local glow = { spells = {}, items = {} }
	local soon = { spells = {}, items = {} }
	local list = ClassBuffs()
	if not list then return glow, soon end
	local bars
	for _, def in ipairs(list) do
		-- (what you wear now is your choice)
		if #def.spells > 1 then
			for _, name in ipairs(def.spells) do
				if buffs[name] then Memory()[def.key] = name end
			end
		end
		local missing = Missing(def, buffs)
		local low = not missing and ns.db.hintBuffSoon ~= false and RunningOut(def, buffs, ends)
		local what
		if missing or low then
			local into = missing and glow or soon
			bars = bars or OnBars()
			if def.items then
				local found = 0
				for item in pairs(def.items) do
					if bars.items[item] then into.items[item], found = true, found + 1 end
				end
				what = ("%d of them on your bars"):format(found)
			else
				local pick, castable = Pick(def, bars)
				if pick and castable then into.spells[pick] = true end
				what = pick and ("%s, castable: %s"):format(pick, tostring(castable)) or "none on your bars"
			end
		end
		if notes then
			notes[#notes + 1] = ("%s: missing: %s, running out: %s%s%s"):format(def.items and "weapon items" or def.spells[1],
				tostring(missing), tostring(low), Memory()[def.key] and (", last used: " .. Memory()[def.key]) or "",
				what and ((missing and ", glows: " or ", faint: ") .. what) or "")
		end
	end
	return glow, soon
end

-- For the buff frame (AuraFrame.lua) --------------------------------------------------------------------------------

-- A spell you know (any rank): its name as the game writes it, and its icon.
local function Known(id)
	local name = C_Spell and C_Spell.GetSpellName and Clean(Safe(C_Spell.GetSpellName, id)) or Clean((Safe(GetSpellInfo, id)))
	if not name then return nil end
	local known = Clean(Safe(IsPlayerSpell, id)) or Clean(Safe(IsSpellKnown, id))
	if not known and C_Spell and C_Spell.GetSpellInfo then
		-- (by name: any rank of it in your spellbook)
		known = type(Clean(Safe(C_Spell.GetSpellInfo, name))) == "table"
	end
	if not known then return nil end
	local icon = C_Spell and C_Spell.GetSpellTexture and Clean(Safe(C_Spell.GetSpellTexture, id))
		or Clean(select(3, Safe(GetSpellInfo, id)))
	return name, icon
end

local function WeaponGhost(out, slot)
	local item = Clean(Safe(GetInventoryItemID, "player", slot))
	local name = item and C_Item and C_Item.GetItemNameByID and Clean(Safe(C_Item.GetItemNameByID, item))
	out[#out + 1] = { weapon = slot, name = name or (slot == 16 and "Main hand" or "Off hand"),
		icon = Clean(Safe(GetInventoryItemTexture, "player", slot)) }
end

-- What your class keeps up and is missing now: { name, icon, spell (to cast it), weapon (its slot) } each; nil when
-- your buffs can't be read (in a fight: what was missing before stays). Not while mounted, dead or flying.
function ns.MissingClassBuffs()
	if Mounted() or Clean(Safe(UnitIsDeadOrGhost, "player")) or Clean(Safe(UnitOnTaxi, "player")) then return {} end
	if Clean(Safe(UnitInVehicle, "player")) then return {} end
	local buffs = BuffNames()
	if not buffs then return nil end
	local list = ClassBuffs()
	if not list then return {} end
	local out = {}
	for _, def in ipairs(list) do
		if Missing(def, buffs) then
			if def.items then
				local main, _, _, _, off = Safe(GetWeaponEnchantInfo)
				main, off = Clean(main), Clean(off)
				if Bare(16, main) then WeaponGhost(out, 16) end
				if def.weapon == "both" and Bare(17, off) then WeaponGhost(out, 17) end
			else
				-- (the one you used last, else the first you know)
				local order, last = {}, Memory()[def.key]
				if last then order[1] = last end
				for _, name in ipairs(def.spells) do order[#order + 1] = name end
				for _, lower in ipairs(order) do
					local id = def.ids[lower]
					-- (both of Known's answers: "id and Known(id)" would keep only the first, the name)
					local name, icon
					if id then name, icon = Known(id) end
					if name then
						out[#out + 1] = { name = name, icon = icon, spell = name }
						break
					end
				end
			end
		end
	end
	return out
end

local RULES = {
	-- not Well Fed, not eating: the food that makes you Well Fed
	food = function(buffs)
		if ns.db.hintFood == false then return nil end
		if buffs["well fed"] or (WELL_FED and buffs[WELL_FED]) then return nil end
		if buffs["food"] or (EATING and buffs[EATING]) then return nil end
		return function(kind, id) return kind == "item" and MakesWellFed(id) end
	end,
	-- something your class keeps up missing: what gives it
	buffs = function(buffs)
		if ns.db.hintBuffs == false or Mounted() then return nil end
		local glow = Plan(buffs)
		if not next(glow.spells) and not next(glow.items) then return nil end
		return function(kind, id)
			if kind == "spell" then return glow.spells[Lower(SpellName(id)) or ""] == true end
			return kind == "item" and glow.items[id] == true
		end
	end,
}

-- Looking -------------------------------------------------------------------------------------------------------------

local function Quiet()
	if not ns.On("hints") then return true end
	if InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player")) then return true end
	if Clean(Safe(UnitIsDeadOrGhost, "player")) or Clean(Safe(UnitOnTaxi, "player")) then return true end
	-- (the whole interface resting: no glow either)
	if ns.ModeNow and ns.ModeNow() then return true end
	return false
end

-- The buttons renewing a class buff that is running out (glowing faintly).
local function SoonButtons(buffs, ends)
	local soon = {}
	if ns.db.hintBuffs == false or ns.db.hintBuffSoon == false or Mounted() then return soon end
	local _, plan = Plan(buffs, nil, ends)
	if not next(plan.spells) and not next(plan.items) then return soon end
	for _, button in ipairs(Buttons()) do
		local slot = Slot(button)
		local kind, id
		if slot then kind, id = ActionOn(slot) end
		if kind == "spell" and plan.spells[Lower(SpellName(id)) or ""] then soon[button] = true end
		if kind == "item" and plan.items[id] and Count(id) > 0 then soon[button] = true end
	end
	return soon
end

local function Look()
	local want, soon = {}, {}
	if not Quiet() then
		local buffs, ends = BuffNames()
		if buffs then
			local ok, found = pcall(SoonButtons, buffs, ends)
			if ok then soon = found end
			local tests = {}
			for _, rule in pairs(RULES) do
				local ok, test = pcall(rule, buffs)
				if ok and test then tests[#tests + 1] = test end
			end
			if #tests > 0 then
				for _, button in ipairs(Buttons()) do
					local slot = Slot(button)
					local kind, id
					if slot then kind, id = ActionOn(slot) end
					if kind == "item" and Count(id) <= 0 then kind = nil end
					if kind then
						for _, test in ipairs(tests) do
							local ok, yes = pcall(test, kind, id, slot)
							if ok and yes then want[button] = true break end
						end
					end
				end
			end
		end
	end
	return want, soon
end

-- The glow -----------------------------------------------------------------------------------------------------------

local function Glow(button)
	local glow = glows[button]
	if glow then return glow end
	glow = CreateFrame("Frame", nil, button)
	glow:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
	glow:SetPoint("CENTER", button, "CENTER")
	local size = Clean(Safe(button.GetWidth, button)) or 36
	glow:SetSize(size * GLOW_SCALE, size * GLOW_SCALE)
	glow.texture = glow:CreateTexture(nil, "OVERLAY")
	glow.texture:SetAllPoints()
	glow.texture:SetTexture(MEDIA .. "Glow")
	pcall(glow.texture.SetBlendMode, glow.texture, "ADD")
	glow.texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	-- (a slow breath: brighter, softer)
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(1.1)
	if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
	glow.pulse = pulse
	glow:Hide()
	glows[button] = glow
	return glow
end

local revealed = {} -- button -> true while it shows itself whatever its bar's opacity

local function Reveal()
	local mode = ns.db.hintReveal or "button"
	local show = {}
	for button in pairs(lit) do
		if mode == "button" then
			show[button] = true
		elseif mode == "bar" then
			for _, other in ipairs(Actions.BarButtons(button)) do show[other] = true end
		end
	end
	for button in pairs(revealed) do
		if not show[button] then
			revealed[button] = nil
			pcall(button.SetIgnoreParentAlpha, button, false)
		end
	end
	for button in pairs(show) do
		if not revealed[button] and pcall(button.SetIgnoreParentAlpha, button, true) then revealed[button] = true end
	end
end

local function Apply(want, soon)
	soon = soon or {}
	-- (lit and running out at once: the full glow)
	for button in pairs(want) do soon[button] = nil end
	for button in pairs(lit) do
		if not want[button] then
			lit[button] = nil
			local glow = glows[button]
			if glow then
				glow.pulse:Stop()
				glow:Hide()
			end
		end
	end
	for button in pairs(faint) do
		if not soon[button] then
			faint[button] = nil
			local glow = glows[button]
			if glow and not want[button] then glow:Hide() end
		end
	end
	for button in pairs(want) do
		if not lit[button] then
			lit[button] = true
			local glow = Glow(button)
			-- (Glass and Round light their own in its place, ActionBars.lua)
			glow.texture:SetAlpha(ns.BarsOwnGlow and ns.BarsOwnGlow(button) and 0 or 1)
			glow:SetAlpha(1)
			glow:Show()
			glow.pulse:Play()
		end
	end
	for button in pairs(soon) do
		if not faint[button] then
			faint[button] = true
			local glow = Glow(button)
			glow.pulse:Stop()
			glow.texture:SetAlpha(ns.BarsOwnGlow and ns.BarsOwnGlow(button) and 0 or 1)
			glow:SetAlpha(FAINT)
			glow:Show()
		end
	end
	Reveal()
	wipe(litList)
	for button in pairs(lit) do litList[#litList + 1] = button end
end

-- The buttons glowing now (Fade.lua brings their bars back).
function ns.HintButtons() return litList end
-- A button's glow (ActionBars.lua: Glass and Round light their own in its place, this one's texture put away).
function ns.HintGlow(button) return glows[button] end
-- A button glowing faintly: a class buff it gives running out (ActionBars.lua lights its own the same way).
function ns.HintSoon(button) return faint[button] == true end
-- Every action bar back while something glows ("All bars").
function ns.HintRevealBars() return #litList > 0 and ns.db.hintReveal == "bars" end
function ns.HintsDirty() dirty = true end

-- Start ---------------------------------------------------------------------------------------------------------------

local function Init()
	WELL_FED = Lower(SpellName(19705))
	EATING = Lower(SpellName(433))
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"GET_ITEM_INFO_RECEIVED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED",
		"ACTIONBAR_UPDATE_USABLE", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_INVENTORY_CHANGED", "player")
	events:SetScript("OnEvent", function(_, event, _, _, spell)
		if event == "PLAYER_REGEN_DISABLED" then
			Apply({}) -- (a fight: no hints, at once)
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- (the armor, blessing, imbue... you cast is the one you'll want again)
			local id = Clean(spell)
			if type(id) == "number" then Remember(Lower(SpellName(id))) end
		end
		dirty = true
	end)
	local since = 0
	events:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		-- (looked at when something changed, and now and then for what no event tells)
		if since >= CHECK_EVERY and (dirty or since >= 5) then
			since, dirty = 0, false
			Apply(Look())
		end
	end)
end

-- /serene debug: why a button glows or not.
function ns.HintDebug()
	local say = ns.Print
	say(("hints: %s, quiet now: %s (in a fight %s, dead %s, flying %s)"):format(tostring(ns.On("hints")),
		tostring(Quiet()), tostring(InCombatLockdown()), tostring(Clean(Safe(UnitIsDeadOrGhost, "player"))),
		tostring(Clean(Safe(UnitOnTaxi, "player")))))
	local buffs = BuffNames()
	if not buffs then
		say("hints: your buffs can't be read right now")
	else
		local names = {}
		for name in pairs(buffs) do names[#names + 1] = name end
		say("hints: your buffs: " .. (#names > 0 and table.concat(names, ", ") or "none")
			.. ("  (well fed is called '%s', eating '%s')"):format(tostring(WELL_FED), tostring(EATING)))
	end
	local buttons, shown = Buttons(), 0
	say(("hints: %d action buttons found"):format(#buttons))
	for _, button in ipairs(buttons) do
		local slot = Slot(button)
		local item = slot and ItemOn(slot)
		if item and shown < 12 then
			shown = shown + 1
			fedFood[item] = nil
			local lines, how = TooltipLines(item)
			local fed = MakesWellFed(item)
			say(("  %s slot %s: item %d x%d, tooltip %s (%s lines), well fed: %s, glowing: %s"):format(
				button:GetName() or "?", tostring(slot), item, Count(item), tostring(how), tostring(lines and #lines),
				tostring(fed), tostring(lit[button] == true)))
		end
	end
	if shown == 0 then say("hints: no items found on the action buttons") end
	local notes = {}
	local _, ends = BuffNames()
	if buffs then Plan(buffs, notes, ends) end
	say(("hints: class buffs: %s, mounted: %s"):format(ClassBuffs() and #notes .. " for your class" or "none for your class",
		tostring(Mounted())))
	for _, note in ipairs(notes) do say("  " .. note) end
end

ns.HintLook = function() Apply(Look()) return litList end -- (tests)
ns.MakesWellFed = function(item) return MakesWellFed(item) end -- (BarSupplies.lua: food kept for its buff left out)
table.insert(ns.modules, { init = Init, refresh = function() dirty = true end })
