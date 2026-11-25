local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Serene's own frame for your buffs and debuffs (the game's put away; Auras.lua dresses the others' auras).
-- Built on the game's aura containers (patch 12.1): Serene makes each icon (round, a ring, a dark edge, the time, the
-- count) and hands its parts to the container; the game itself fills them, in a fight too, where addons may read
-- nothing of your auras. So every icon, time and count is the game's own, always right; Serene never has to guess.
--   - What matters now, full size: what is short (a proc, a shield, a heal over time). What is long and steady (an
--     hour of Fortitude, an aura, Well Fed) in a row of small rings under them.
--     (The containers can't keep an aura out of one group because another took it: so the small row leaves out the
--     buffs Serene has seen to be short, out of a fight. One never seen before may show in both rows, once.)
--   - Time as a shape: the icon and its ring darken as the time runs out (the game's own swipe). The number in the
--     last stretch (or always, or never), soft white in the last seconds.
--   - World buffs (Songflower, Rallying Cry, Darkmoon Faire, Dire Maul...) on a shelf of their own, a fuller gold
--     ring, their time always shown.
--   - Debuffs by what you can do: those you can remove (your class's cleanse, learned) first, in their kind's colour;
--     the rest after them, a quiet grey ring.
--   - What is missing: your class's buffs that have dropped (Hints.lua knows them) as faint grey icons beside the
--     row; a click casts it (out of a fight).
-- Under the mouse the game's tooltip; right click cancels (the game's own button does it, in a fight too).
-- Fade.lua fades it with the buffs. Everything on Serene's page ("Buffs"); /serene aurasmove to place them.

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local DISC = MEDIA .. "AuraDisc" -- (one soft-edged circle: the icon's mask, its ring, its edge, its swirl)
local FLAT = "Interface\\Buttons\\WHITE8X8"
local DIM = 0.55                 -- how dark the elapsed part turns
local GOLD = { 1, 0.82, 0.35 }
local SOFT, MUTED, LINE = ns.SOFT_RGB, ns.MUTED_RGB, ns.LINE
local GREY = { 0.52, 0.52, 0.55 }
local EDGE = { 0, 0, 0, 0.85 }   -- a dark hairline outside the ring: it stands out on bright ground
local TRIM = 0.08                -- the icon's baked-in edge trimmed away, on each side
local GAP = 5                    -- between two icons
local ROW_GAP = 5                -- between two rows
local SMALL_GAP = 4
local TIME_GAP = 2               -- between an icon and its time under it
local ON_EDGE = 1                -- the time on the icon: this far above its lower edge
local LOW = 10                   -- the last seconds: the time in soft white
local GHOST_DIM = 0.8            -- (a missing buff: its own icon in grayscale, a little dimmed)
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- World buffs (by spell): kept on their own shelf.
local WORLD = {
	[22888] = true, -- Rallying Cry of the Dragonslayer
	[16609] = true, -- Warchief's Blessing
	[24425] = true, -- Spirit of Zandalar
	[15366] = true, -- Songflower Serenade
	[22817] = true, [22818] = true, [22820] = true, -- Fengus' Ferocity, Mol'dar's Moxie, Slip'kik's Savvy
	[23735] = true, [23736] = true, [23737] = true, [23738] = true, -- Sayge's Dark Fortunes
	[23766] = true, [23767] = true, [23768] = true, [23769] = true,
	[349981] = true, -- Supercharged Chronoboon Displacer
}
-- What your class can remove, by the spell that does it (any rank; a pet's for the warlock's felhunter).
local DISPELS = {
	PRIEST = { { 527, "Magic" }, { 988, "Magic" }, { 528, "Disease" }, { 552, "Disease" } },
	PALADIN = { { 1152, "Poison", "Disease" }, { 4987, "Magic", "Poison", "Disease" } },
	DRUID = { { 2782, "Curse" }, { 8946, "Poison" }, { 2893, "Poison" } },
	SHAMAN = { { 526, "Poison" }, { 2870, "Disease" } },
	MAGE = { { 475, "Curse" } },
	WARLOCK = { { 19505, "Magic", pet = true }, { 19731, "Magic", pet = true }, { 19734, "Magic", pet = true },
		{ 19736, "Magic", pet = true } },
}

local active = false
local problem               -- why Serene's frame couldn't be made, or a part of it (then the game's stays)
local buffs, debuffs        -- the two containers (global names, for Fade.lua: SereneAuras, SereneDebuffs)
local ghostRow
local made = setmetatable({}, { __mode = "k" }) -- each icon the containers made -> its parts
local canRemove = {}
local ghosts, ghostIcons = {}, {}
local movers
local pending = false       -- something to apply once out of the fight

local function S(key, fallback)
	local value = ns.db and ns.db[key]
	if value == nil then return fallback end
	return value
end

local function Num(key, fallback, low, high)
	local value = tonumber(S(key, fallback)) or fallback
	return math.max(low, math.min(high, math.floor(value + 0.5)))
end

local function Style()
	return ns.AuraStyle and ns.AuraStyle.Look() or { round = true, ring = "all", width = 1, quiet = true,
		time = "outline", on = false, font = 0, edge = true, dim = true }
end

-- (in a fight by either sign: your auras can't be read then, and secure frames can't be touched)
local function Fighting()
	return InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player")) and true or false
end

-- What the game names its pieces ---------------------------------------------------------------------------------------

local SORT_BY = _G.AuraContainerSortMethod and _G.AuraContainerSortMethod.Expiration or nil
local SORT_WAY = _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal or nil
local FLOW = AnchorUtil and AnchorUtil.FlowDirection
local AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local DISPEL_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
local REMAINING = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration or 0
local ENCHANT_SLOT = _G.AuraContainerItemEnchantmentSlot
local ENCHANT_PLACE = _G.CustomAuraContainerItemEnchantmentPlacement

-- Sizes ----------------------------------------------------------------------------------------------------------------

local function Debuff(kind) return kind == "removable" or kind == "other" end

-- Each kind of icon: how large its picture, how thick its ring (pixels), whether its time shows.
local function Measure(kind, look)
	local size, width, timed = Num("auraSize", 30, 16, 64), look.width, true
	if kind == "small" then
		size, width, timed = Num("auraSmall", 16, 8, 32), 1, false
	elseif kind == "world" then
		width = look.width + 1
	elseif Debuff(kind) then
		size = Num("auraDebuffSize", 34, 16, 64)
	end
	local ringed = look.ring == "all" or kind == "world" or (Debuff(kind) and look.ring == "debuffs")
	if not ringed then width = 0 end
	return size, width, timed and look.time ~= "none" and S("auraTimeWhen", "soon") ~= "never"
end

-- How much room the time under an icon takes.
local function Under(look, timed)
	if not timed or look.on then return 0 end
	local font = look.font > (ns.AURA_FONT_AUTO or 6) and look.font or 9
	return font + TIME_GAP + 2
end

-- Colours --------------------------------------------------------------------------------------------------------------

-- The time's colour by how long is left (the game samples it, the time itself stays secret): soft white in the last
-- seconds, muted after; shown in its last stretch only, unless always.
local curves = {}
local function TimeCurve(always)
	local key = (always and "always" or S("auraTimeWhen", "soon")) .. ":" .. Num("auraSoon", 60, 5, 1800)
	if curves[key] then return curves[key] end
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
	if not ok or not curve then return nil end
	if Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(curve.SetType, curve, Enum.LuaCurveType.Step) end
	pcall(curve.AddPoint, curve, 0, CreateColor(SOFT[1], SOFT[2], SOFT[3], 1))
	pcall(curve.AddPoint, curve, LOW, CreateColor(MUTED[1], MUTED[2], MUTED[3], 1))
	if not always and S("auraTimeWhen", "soon") == "soon" then
		pcall(curve.AddPoint, curve, Num("auraSoon", 60, 5, 1800), CreateColor(MUTED[1], MUTED[2], MUTED[3], 0))
	end
	curves[key] = curve
	return curve
end

-- A debuff's ring in its kind's colour (the game colours it: the kind may be secret).
local function KindColors(look)
	local map = {}
	local kinds = ns.AuraStyle and ns.AuraStyle.KINDS or {}
	for _, kind in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage", "None" }) do
		local c
		if look.quiet then
			c = kinds[kind:lower()] or (ns.AuraStyle and ns.AuraStyle.DEBUFF) or { 0.82, 0.34, 0.3 }
		else
			local game = _G.DebuffTypeColor and (_G.DebuffTypeColor[kind] or _G.DebuffTypeColor.none)
			c = game and { game.r, game.g, game.b } or { 0.8, 0.3, 0.3 }
		end
		map[kind] = CreateColor(c[1], c[2], c[3], 0.9)
	end
	return map
end
ns.AuraKindColors = KindColors -- (the target's and focus's debuffs too, UnitAuras.lua)

-- (a debuff's ring coloured by its kind: one you can remove; any, when they aren't told apart)
local function ByKind(kind)
	return kind == "removable" or (kind == "other" and not (S("auraDispel", true) and next(canRemove)))
end

local function RingColor(kind)
	if kind == "world" then return GOLD[1], GOLD[2], GOLD[3], 1 end
	if kind == "enchant" then
		local c = ns.AuraStyle and ns.AuraStyle.ENCHANT or { 0.7, 0.5, 0.92 }
		return c[1], c[2], c[3], 0.9
	end
	if kind == "other" then return GREY[1], GREY[2], GREY[3], 0.9 end
	return GOLD[1], GOLD[2], GOLD[3], LINE[4] or 0.8
end

-- Each icon --------------------------------------------------------------------------------------------------------------

local function TimeFont(text, look)
	local font = Clean(select(1, Safe(GameFontNormalSmall.GetFont, GameFontNormalSmall))) or STANDARD_TEXT_FONT
	local size = look.font > (ns.AURA_FONT_AUTO or 6) and look.font or 9
	pcall(text.SetFont, text, font, size, "OUTLINE")
	pcall(text.SetShadowColor, text, 0, 0, 0, 0.4)
	pcall(text.SetShadowOffset, text, 1, -1)
end

-- An icon laid out for the look chosen (when made, and again when the look changes, out of a fight).
local function Dress(button, p)
	local look = Style()
	local size, width, timed = Measure(p.kind, look)
	local px = ns.Pixel(button)
	local ring = width * px
	button:SetSize(size + 2 * ring, size + 2 * ring)
	local shape = look.round and DISC or FLAT
	-- the picture, round (or square), inside the ring
	p.icon:ClearAllPoints()
	p.icon:SetPoint("TOPLEFT", button, "TOPLEFT", ring, -ring)
	p.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ring, ring)
	p.icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
	if look.round and not p.masked then
		p.masked = pcall(p.icon.AddMaskTexture, p.icon, p.mask)
	elseif not look.round and p.masked then
		pcall(p.icon.RemoveMaskTexture, p.icon, p.mask)
		p.masked = false
	end
	-- the ring (a disc behind the picture: what shows of it around), the dark edge beyond
	p.ring:SetTexture(shape)
	p.ring:SetAllPoints(button)
	p.ring:SetVertexColor(RingColor(p.kind))
	p.ring:SetShown(width > 0)
	p.edge:SetTexture(shape)
	p.edge:ClearAllPoints()
	p.edge:SetPoint("TOPLEFT", button, "TOPLEFT", -px, px)
	p.edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", px, -px)
	p.edge:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	p.edge:SetShown(look.edge ~= false)
	-- a debuff's ring in its kind's colour (the game's to set)
	if Debuff(p.kind) and DISPEL_STYLE and button.AddDispelTypeTexture then
		pcall(button.ClearDispelTypeTextures, button)
		if width > 0 and ByKind(p.kind) then
			pcall(button.AddDispelTypeTexture, button, p.ring, { style = DISPEL_STYLE.PreserveAsset,
				showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
				customDispelColorMap = KindColors(look) })
		end
	end
	-- the swirl: over picture and ring, the part of the time gone darkened
	p.swirl:ClearAllPoints()
	p.swirl:SetAllPoints(button)
	pcall(p.swirl.SetSwipeTexture, p.swirl, shape)
	pcall(p.swirl.SetUseCircularEdge, p.swirl, look.round)
	pcall(p.swirl.SetSwipeColor, p.swirl, 0, 0, 0, DIM)
	pcall(p.swirl.SetReverse, p.swirl, true)
	pcall(p.swirl.SetDrawEdge, p.swirl, false)
	pcall(p.swirl.SetDrawBling, p.swirl, false)
	pcall(p.swirl.SetHideCountdownNumbers, p.swirl, true)
	if look.dim ~= false and p.kind ~= "small" then
		pcall(button.SetDurationCooldown, button, p.swirl)
		pcall(p.swirl.SetDrawSwipe, p.swirl, true)
	else
		pcall(button.ClearDurationCooldown, button)
		pcall(p.swirl.SetDrawSwipe, p.swirl, false)
	end
	-- the words above all that
	p.words:SetAllPoints(button)
	p.words:SetFrameLevel(p.swirl:GetFrameLevel() + 2)
	p.count:ClearAllPoints()
	p.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
	p.count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	p.count:SetShown(p.kind ~= "small")
	TimeFont(p.time, look)
	p.time:ClearAllPoints()
	if look.on then
		p.time:SetPoint("BOTTOM", button, "BOTTOM", 0, ON_EDGE)
	else
		p.time:SetPoint("TOP", button, "BOTTOM", 0, -TIME_GAP)
	end
	if timed then
		local curve = TimeCurve(p.kind == "world")
		local options = curve and { textColor = { curve = curve, property = REMAINING } } or nil
		pcall(button.SetDurationText, button, p.time, options)
		p.time:Show()
	else
		pcall(button.ClearDurationText, button)
		p.time:SetText("")
		p.time:Hide()
	end
end

-- An icon the container just made: Serene's parts on it, handed to the game.
local function Maker(kind)
	return function(button)
		local p = { kind = kind }
		made[button] = p
		p.edge = button:CreateTexture(nil, "BACKGROUND", nil, -2)
		p.ring = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		p.icon = button:CreateTexture(nil, "ARTWORK")
		p.mask = button:CreateMaskTexture()
		if not pcall(p.mask.SetTexture, p.mask, DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
			p.mask:SetTexture(DISC)
		end
		p.mask:SetAllPoints(p.icon)
		p.swirl = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		p.words = CreateFrame("Frame", nil, button)
		p.count = p.words:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		p.time = p.words:CreateFontString(nil, "OVERLAY")
		pcall(button.SetIcon, button, p.icon)
		pcall(button.SetApplicationCount, button, p.count)
		pcall(button.SetCancelAuraButtons, button, "RightButtonUp")
		pcall(button.SetTooltipAnchorPoint, button, "ANCHOR_BOTTOMLEFT")
		local ok, why = pcall(Dress, button, p)
		if not ok then problem = problem or ("an icon: " .. tostring(why)) end
	end
end

-- The containers ------------------------------------------------------------------------------------------------------

local function Container(name)
	local ok, c = pcall(CreateFrame, "AuraContainer", name, UIParent,
		"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
	if not ok or not c then return nil, tostring(c) end
	c:SetFrameStrata("LOW")
	pcall(c.SetUnit, c, "player")
	if c.SetEnabled then pcall(c.SetEnabled, c, true) end
	c:Show()
	return c
end

local function Flow(c, anchor, horizontal)
	if not (FLOW and AXIS) then return end
	pcall(c.SetFlowLayoutAnchorPoint, c, anchor)
	pcall(c.SetFlowLayoutGrowthDirection, c, horizontal, FLOW.Down)
	pcall(c.SetFlowLayoutAxis, c, AXIS.Horizontal)
	pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
end

local function Element(kind)
	local size, width = Measure(kind, Style())
	return size + 2 * width * ns.Pixel(UIParent)
end

local function Layout(kind, order, newLine)
	local look = Style()
	local _, _, timed = Measure(kind, look)
	local element = Element(kind)
	-- (each cell is tall enough for the time hanging under its icon, so the next row starts below it)
	return { elementWidth = element, elementHeight = element + Under(look, timed),
		elementSpacing = kind == "small" and SMALL_GAP or GAP,
		lineSpacing = ROW_GAP, groupSpacing = GAP, groupLineSpacing = ROW_GAP,
		forceNewLine = newLine and true or false, layoutIndex = order }
end

local function EnchantLayout()
	local look = Style()
	local _, _, timed = Measure("enchant", look)
	local element = Element("enchant")
	return { placement = ENCHANT_PLACE and ENCHANT_PLACE.BeforeAuraGroups or nil, elementWidth = element,
		elementHeight = element + Under(look, timed), elementSpacing = GAP }
end

-- What each group shows (filters the game applies: by spell, by how long an aura lasts, by its kind).
local function ShortSpells()
	ns.db.auraShortSpells = ns.db.auraShortSpells or {}
	return ns.db.auraShortSpells
end

local function Filters(kind)
	local world = S("auraWorld", true)
	if kind == "world" then
		return { includeSpellIDs = WORLD }
	elseif kind == "full" then
		local f = {}
		if world then f.excludeSpellIDs = WORLD end
		if S("auraTiers", true) then f.maxDuration = Num("auraShort", 180, 10, 3600) end
		return f
	elseif kind == "small" then
		local out = {}
		if world then for id in pairs(WORLD) do out[id] = true end end
		for id in pairs(ShortSpells()) do out[id] = true end
		return next(out) and { excludeSpellIDs = out } or {}
	elseif kind == "removable" then
		return { includeDispelTypes = canRemove }
	elseif kind == "other" then
		return (S("auraDispel", true) and next(canRemove)) and { excludeDispelTypes = canRemove } or {}
	end
	return {}
end

local function Enabled(kind)
	if kind == "world" then return S("auraWorld", true) and true or false end
	if kind == "small" then return S("auraTiers", true) and true or false end
	if kind == "removable" then return (S("auraDispel", true) and next(canRemove)) and true or false end
	return true
end

local BUFF_GROUPS = { { "world", 1 }, { "full", 2 }, { "small", 3 } }
local DEBUFF_GROUPS = { { "removable", 1 }, { "other", 2 } }

local function AddGroups(c, filter, list)
	for index, g in ipairs(list) do
		local kind, order = g[1], g[2]
		local ok, why = pcall(c.AddAuraGroup, c, kind, filter, {
			initializeFrame = Maker(kind),
			candidateFilters = Filters(kind),
			sortMethod = SORT_BY, sortDirection = SORT_WAY,
			layout = Layout(kind, order, index > 1), -- (TopRowWidth counts on this)
		})
		if not ok then
			problem = problem or (kind .. ": " .. tostring(why))
		-- (every group added, the unwanted ones switched off: a setting can bring one back without a reload)
		elseif not Enabled(kind) then
			pcall(c.SetAuraGroupEnabled, c, kind, false)
		end
	end
end

local function UpdateGroups(c, list)
	for index, g in ipairs(list) do
		local kind, order = g[1], g[2]
		pcall(c.SetAuraGroupCandidateFilters, c, kind, Filters(kind))
		pcall(c.SetAuraGroupLayout, c, kind, Layout(kind, order, index > 1))
		pcall(c.SetAuraGroupEnabled, c, kind, Enabled(kind))
	end
end

-- Placing them ---------------------------------------------------------------------------------------------------------

local function PlaceHolders()
	local perRow = Num("auraPerRow", 12, 3, 30)
	buffs:ClearAllPoints()
	local at = S("auraAt", nil)
	if type(at) == "table" and at[1] then
		buffs:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", at[1], at[2])
	elseif _G.BuffFrame then
		buffs:SetPoint("TOPRIGHT", _G.BuffFrame, "TOPRIGHT", 0, 0)
	else
		buffs:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -13) -- (about where the game's buff frame sits)
	end
	Flow(buffs, "TOPRIGHT", FLOW and FLOW.Left)
	pcall(buffs.SetFlowLayoutMaximumLineSize, buffs, perRow * (Element("full") + GAP))
	debuffs:ClearAllPoints()
	local where = S("auraDebuffAt", "buffs")
	local player = _G.PlayerFrame
	if where == "portrait" and player then
		debuffs:SetPoint("TOPLEFT", player, "BOTTOMLEFT", 8, -6)
		Flow(debuffs, "TOPLEFT", FLOW and FLOW.Right)
	elseif where == "free" then
		local pos = S("auraDebuffFree", nil)
		local x = type(pos) == "table" and pos[1] or UIParent:GetWidth() / 2
		local y = type(pos) == "table" and pos[2] or -300
		debuffs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
		Flow(debuffs, "TOPLEFT", FLOW and FLOW.Right)
	else
		debuffs:SetPoint("TOPRIGHT", buffs, "BOTTOMRIGHT", 0, -ROW_GAP)
		Flow(debuffs, "TOPRIGHT", FLOW and FLOW.Left)
	end
	pcall(debuffs.SetFlowLayoutMaximumLineSize, debuffs, perRow * (Element("removable") + GAP))
end

-- How many icons of each kind show now (out of a fight; nil: unreadable). The game's own frame count also holds its
-- spare icons, made in batches.
local function Shown()
	local counts = {}
	for button, p in pairs(made) do
		local shown = Clean(Safe(button.IsShown, button))
		if shown == nil then return nil end
		if shown then counts[p.kind] = (counts[p.kind] or 0) + 1 end
	end
	return counts
end

-- The same counts from your buffs themselves (out of a fight they can be read), as the groups' filters sort them: for
-- when the icons' being shown is kept secret (the game does, for some effects). nil: unreadable.
local function Counted()
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get or Fighting() then return nil end
	local counts = {}
	local world, tiers, limit = S("auraWorld", true), S("auraTiers", true), Num("auraShort", 180, 10, 3600)
	local short = ShortSpells()
	for index = 1, 40 do
		local data = Safe(get, "player", index, "HELPFUL")
		if data == nil then break end
		local id = Clean(Safe(function() return data.spellId end))
		local duration = Clean(Safe(function() return data.duration end))
		if type(id) ~= "number" or type(duration) ~= "number" then return nil end
		if world and WORLD[id] then
			counts.world = (counts.world or 0) + 1
		else
			if not tiers or (duration > 0 and duration <= limit) then counts.full = (counts.full or 0) + 1 end
			if not short[id] then counts.small = (counts.small or 0) + 1 end
		end
	end
	local main, _, _, _, off = Safe(GetWeaponEnchantInfo)
	main, off = Clean(main), Clean(off)
	counts.enchant = (main and 1 or 0) + (off and 1 or 0)
	return counts
end

-- How wide the top row of buffs is (out of a fight, when the counts can be read): the layout's own steps, its first
-- line only. nil: unknown.
local function TopRowWidth()
	local counts = Shown() or Counted()
	if not counts then return nil end
	local steps = { { counts.enchant or 0, Element("enchant"), GAP, 0, false } }
	for index, g in ipairs(BUFF_GROUPS) do
		local n = Enabled(g[1]) and (counts[g[1]] or 0) or 0
		-- (a new line for every group after the first, as Layout tells the game: the game starts one whenever
		-- anything, the enchants too, was placed before it)
		steps[#steps + 1] = { n, Element(g[1]), g[1] == "small" and SMALL_GAP or GAP, GAP, index > 1 }
	end
	local most = Num("auraPerRow", 12, 3, 30) * (Element("full") + GAP)
	local line, placed, spacing = 0, false, 0
	for _, step in ipairs(steps) do
		local n, width, between, before, newLine = step[1], step[2], step[3], step[4], step[5]
		if n > 0 then
			if placed then
				if newLine then break end
				if before > 0 then
					if line > 0 and line + before > most then break end
					line = line + before
				end
			end
			for _ = 1, n do
				local next_ = line > 0 and line + width or width
				if line > 0 and next_ > most then return line - spacing end
				line, spacing, placed = next_ + between, between, true
			end
		end
	end
	return placed and (line - spacing) or 0
end

-- (the missing ones just left of the top row: the container's own width is its widest row, and secret)
local function PlaceGhostRow()
	if not (ghostRow and buffs) or InCombatLockdown() then return end
	ghostRow:ClearAllPoints()
	local width = TopRowWidth()
	if width then
		ghostRow:SetPoint("TOPRIGHT", buffs, "TOPRIGHT", -(width + (width > 0 and GAP or 0)), 0)
	else
		ghostRow:SetPoint("TOPRIGHT", buffs, "TOPLEFT", -GAP, 0)
	end
end

-- What you can remove; which buffs are short (learned out of a fight) ----------------------------------------------------

local function LearnDispels()
	local before = {}
	for kind in pairs(canRemove) do before[#before + 1] = kind end
	canRemove = {}
	local _, class = Safe(UnitClass, "player")
	for _, def in ipairs(DISPELS[Clean(class) or ""] or {}) do
		local id = def[1]
		local known = def.pet and Clean(Safe(IsSpellKnown, id, true)) -- (true: the pet's spellbook)
			or Clean(Safe(IsPlayerSpell, id)) or Clean(Safe(IsSpellKnown, id))
		-- (by name: known at any rank, whatever that rank's id)
		if not known and not def.pet and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellInfo then
			local name = Clean(Safe(C_Spell.GetSpellName, id))
			known = name and type(Clean(Safe(C_Spell.GetSpellInfo, name))) == "table"
		end
		if known then
			for index = 2, #def do canRemove[def[index]] = true end
		end
	end
	local after = {}
	for kind in pairs(canRemove) do after[#after + 1] = kind end
	table.sort(before)
	table.sort(after)
	return table.concat(before, ",") ~= table.concat(after, ",")
end

-- (out of a fight your buffs can be read: each short one's spell remembered, so the small row leaves it out)
local function LearnShort()
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get or Fighting() then return false end
	local short, limit, changed = ShortSpells(), Num("auraShort", 180, 10, 3600), false
	for index = 1, 40 do
		local data = Safe(get, "player", index, "HELPFUL")
		if type(data) ~= "table" then break end
		local id = Clean(Safe(function() return data.spellId end))
		local duration = Clean(Safe(function() return data.duration end))
		if type(id) == "number" and type(duration) == "number" then
			local isShort = duration > 0 and duration <= limit
			if isShort and not short[id] then
				short[id], changed = true, true
			elseif not isShort and short[id] then
				short[id], changed = nil, true
			end
		end
	end
	return changed
end

-- Missing class buffs: Serene's own icons beside the row (out of a fight) ------------------------------------------------

-- (each missing one is a secure button of its own, so a click casts it: the row sits beside the game's container,
-- whose size is secret, so where an icon is can't be read to lay a button over it)
local function Tip(icon)
	local g = icon.ghost
	if not g then return end
	GameTooltip:SetOwner(icon, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText(tostring(g.name), GOLD[1], GOLD[2], GOLD[3])
	GameTooltip:AddLine(g.spell and "Missing. Click to cast it." or "Nothing on this weapon.", MUTED[1], MUTED[2],
		MUTED[3])
	GameTooltip:Show()
end

local function GhostIcon(index)
	local b = ghostIcons[index]
	if b then return b end
	b = CreateFrame("Button", "SereneAuraGhost" .. index, ghostRow, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown") -- (both: it acts on whichever the game's key-down setting says)
	b.ring = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.ring:SetAllPoints()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.mask = b:CreateMaskTexture()
	pcall(b.mask.SetTexture, b.mask, DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	b.mask:SetAllPoints(b.icon)
	b:SetScript("OnEnter", Tip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ghostIcons[index] = b
	return b
end

local function Ghosts()
	if not ghostRow or InCombatLockdown() then return end
	local list = {}
	if S("auraGhosts", true) and ns.MissingClassBuffs and not Fighting() then
		list = ns.MissingClassBuffs()
		if list == nil then return end -- (unreadable: kept)
	end
	ghosts = list
	local look = Style()
	local size = Num("auraSize", 30, 16, 64)
	local px = ns.Pixel(ghostRow)
	local ring = (look.ring == "all" and look.width or 0) * px
	local element = size + 2 * ring
	for index, g in ipairs(list) do
		local b = GhostIcon(index)
		b.ghost = g
		b:SetAttribute("type1", g.spell and "spell" or nil)
		b:SetAttribute("spell", g.spell)
		b:SetSize(element, element)
		b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", ghostRow, "TOPRIGHT", -(index - 1) * (element + GAP), 0)
		b.icon:ClearAllPoints()
		b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", ring, -ring)
		b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -ring, ring)
		b.icon:SetTexture(g.icon or QUESTION)
		b.icon:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
		b.icon:SetDesaturated(true)
		b.icon:SetVertexColor(GHOST_DIM, GHOST_DIM, GHOST_DIM)
		if look.round and not b.masked then
			b.masked = pcall(b.icon.AddMaskTexture, b.icon, b.mask)
		elseif not look.round and b.masked then
			pcall(b.icon.RemoveMaskTexture, b.icon, b.mask)
			b.masked = false
		end
		b.ring:SetTexture(look.round and DISC or FLAT)
		b.ring:SetVertexColor(LINE[1], LINE[2], LINE[3], 0.5)
		b.ring:SetShown(ring > 0)
		b:Show()
	end
	for index = #list + 1, #ghostIcons do ghostIcons[index]:Hide() end
	ghostRow:SetSize(math.max(1, #list * (element + GAP)), element)
	PlaceGhostRow()
	ghostRow:SetShown(#list > 0)
end

-- Moving them --------------------------------------------------------------------------------------------------------------

-- (the containers' sizes are the game's and may be secret: the movers are a fixed size, at the containers' corners)
local function Mover(label, corner, save)
	local m = CreateFrame("Frame", nil, UIParent)
	m:SetFrameStrata("DIALOG")
	m:SetSize(160, 40)
	m:EnableMouse(true)
	m:SetMovable(true)
	m:SetClampedToScreen(true)
	m:RegisterForDrag("LeftButton")
	m.ground = m:CreateTexture(nil, "BACKGROUND")
	m.ground:SetAllPoints()
	m.ground:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	m.lines = ns.Hairline(m, { GOLD[1], GOLD[2], GOLD[3], 0.8 })
	m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.text:SetPoint("CENTER")
	m.text:SetText(label)
	m.corner = corner
	m:SetScript("OnDragStart", function(self) self:StartMoving() end)
	m:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		pcall(self.SetUserPlaced, self, false) -- (not kept by the game's own layout: Serene saves the place)
		save(self)
		PlaceHolders()
	end)
	m:Hide()
	return m
end

local function FitMovers()
	if not movers or not movers[1]:IsShown() then return end
	for _, m in ipairs(movers) do m.lines:Fit() end
end

local function Movers()
	if movers then return movers end
	movers = {
		Mover("Your buffs", "TOPRIGHT", function(m)
			ns.db.auraAt = { (m:GetRight() or 0) - UIParent:GetRight(), (m:GetTop() or 0) - UIParent:GetTop() }
		end),
		Mover("Your debuffs", "TOPLEFT", function(m)
			ns.db.auraDebuffFree = { m:GetLeft() or 0, (m:GetTop() or 0) - UIParent:GetTop() }
			ns.db.auraDebuffAt = "free"
		end),
	}
	movers[1].target, movers[2].target = buffs, debuffs
	return movers
end

function ns.AuraMove()
	if not active then return ns.Print("buffs: Serene's frame is off (the game's is in use)") end
	if InCombatLockdown() then return ns.Print("buffs: after the fight") end
	local list = Movers()
	local on = not list[1]:IsShown()
	if on then
		-- (each mover at its container's corner, then free to move on its own)
		list[2].corner = (S("auraDebuffAt", "buffs") == "buffs") and "TOPRIGHT" or "TOPLEFT"
		for _, m in ipairs(list) do
			m:ClearAllPoints()
			m:SetPoint(m.corner, m.target, m.corner, 0, 0)
			local left, top = m:GetLeft(), m:GetTop()
			if left and top then
				m:ClearAllPoints()
				m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			end
			m.lines:Fit()
		end
		-- (the debuffs' mover is saved by its top left: the debuffs are placed freely from there)
		list[2].corner = "TOPLEFT"
	end
	for _, m in ipairs(list) do m:SetShown(on) end
	ns.Print(on and "drag your buffs and debuffs where you want them; again to finish" or "buffs placed")
end

function ns.AuraReset()
	if not active then return end
	if InCombatLockdown() then return ns.Print("buffs: after the fight") end
	ns.db.auraAt, ns.db.auraDebuffFree = nil, nil
	if ns.db.auraDebuffAt == "free" then ns.db.auraDebuffAt = "buffs" end
	PlaceHolders()
	if movers and movers[1]:IsShown() then ns.AuraMove() end
end

-- The game's own frames put out of sight -----------------------------------------------------------------------------------

local hidden
local Silence = ns.Silence

-- (the frames stay where Edit Mode put them, so Serene's can sit there; what they show is made unseen)
local function PutGameAway()
	hidden = hidden or CreateFrame("Frame", nil, UIParent)
	hidden:Hide()
	for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
		local frame = _G[name]
		local inner = type(frame) == "table" and rawget(frame, "AuraContainer")
		if type(inner) == "table" and inner.SetScale then
			pcall(Silence, inner)
			local arrow = rawget(frame, "CollapseAndExpandButton")
			if type(arrow) == "table" then
				pcall(arrow.SetAlpha, arrow, 0)
				pcall(arrow.EnableMouse, arrow, false)
			end
		elseif type(frame) == "table" and frame.SetParent then
			pcall(frame.SetParent, frame, hidden)
		end
	end
end

-- Starting, and the look changed -------------------------------------------------------------------------------------------

local function Apply()
	if not active then return end
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	wipe(curves) -- (curves for settings no longer in use let go)
	PlaceHolders()
	UpdateGroups(buffs, BUFF_GROUPS)
	UpdateGroups(debuffs, DEBUFF_GROUPS)
	if ENCHANT_SLOT then pcall(buffs.SetItemEnchantmentLayout, buffs, EnchantLayout()) end
	for button, p in pairs(made) do pcall(Dress, button, p) end
	Ghosts()
	FitMovers()
end

local function Init()
	if not (ns.SereneAuraFrame and ns.SereneAuraFrame()) then return end
	local why
	buffs, why = Container("SereneAuras")
	if not buffs then
		problem = "the game's aura containers aren't there (" .. tostring(why) .. "): its own buff frame stays"
		return
	end
	debuffs, why = Container("SereneDebuffs")
	if not debuffs then
		problem = "no aura container for debuffs (" .. tostring(why) .. "): the game's buff frame stays"
		buffs:Hide()
		return
	end
	active = true
	LearnDispels()
	LearnShort()
	ghostRow = CreateFrame("Frame", "SereneAuraGhosts", UIParent, "DisableUntrustedLayoutScriptsTemplate")
	ghostRow:SetSize(1, 1)
	ghostRow:SetFrameStrata("LOW")
	PlaceHolders()
	AddGroups(buffs, "HELPFUL", BUFF_GROUPS)
	AddGroups(debuffs, "HARMFUL", DEBUFF_GROUPS)
	-- (your weapons' enchants: before the buffs, as the game has them)
	if ENCHANT_SLOT then
		for _, slot in ipairs({ ENCHANT_SLOT.MainHand, ENCHANT_SLOT.OffHand }) do
			local ok, problemHere = pcall(buffs.AddItemEnchantment, buffs, slot, { initializeFrame = Maker("enchant") })
			if not ok then problem = problem or ("enchants: " .. tostring(problemHere)) end
		end
		pcall(buffs.SetItemEnchantmentLayout, buffs, EnchantLayout())
	end
	PutGameAway()
	Ghosts()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED",
		"LEARNED_SPELL_IN_TAB", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_PET", "player")
	local waiting = false
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			-- (the missing ones put away before the fight locks them)
			if ghostRow and not InCombatLockdown() then ghostRow:Hide() end
			return
		end
		if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "UNIT_PET" then
			if LearnDispels() then pending = true end
		elseif event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "PLAYER_ENTERING_WORLD" or event == "UI_SCALE_CHANGED" then
			PutGameAway()
			pending = true
		end
		if Fighting() or waiting then return end
		-- (out of a fight, once a moment later: what is short learned, what is missing looked at)
		waiting = true
		C_Timer.After(0.3, function()
			waiting = false
			if Fighting() then return end
			if LearnShort() then pending = true end
			if pending then Apply() else Ghosts() end
		end)
	end)
end

local function Refresh()
	if not active then return end
	Apply()
end

-- /serene debug: how Serene's frame stands.
function ns.AuraFrameDebug()
	if not active then
		return ns.Print("buff frame: the game's" .. (problem and (" — " .. problem) or " (Serene's is off)"))
	end
	local counts = {}
	local shown, from = not Fighting() and Shown(), "shown"
	if not shown and not Fighting() then shown, from = Counted(), "from your buffs (icons secret)" end
	if shown then
		counts[#counts + 1] = from
		for _, g in ipairs(BUFF_GROUPS) do counts[#counts + 1] = g[1] .. " " .. (shown[g[1]] or 0) end
		for _, g in ipairs(DEBUFF_GROUPS) do counts[#counts + 1] = g[1] .. " " .. (shown[g[1]] or 0) end
		counts[#counts + 1] = "enchants " .. (shown.enchant or 0)
	end
	local kinds, short = {}, 0
	for kind in pairs(canRemove) do kinds[#kinds + 1] = kind end
	for _ in pairs(ShortSpells()) do short = short + 1 end
	ns.Print(("buff frame: the game's containers; %s; %d missing; %d short buffs known; you remove: %s%s"):format(
		#counts > 0 and table.concat(counts, ", ") or "counts secret in a fight", #ghosts, short,
		#kinds > 0 and table.concat(kinds, ", ") or "none", problem and (" — problem: " .. problem) or ""))
end
ns.AuraProbe = ns.AuraFrameDebug -- (/serene debug auras)

table.insert(ns.modules, { init = Init, refresh = Refresh })
