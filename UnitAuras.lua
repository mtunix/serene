local _, ns = ...

-- The target's and focus's auras, drawn by Serene above the card, round like your own buffs.
-- Built on the game's aura containers (patch 12.1), as your buff frame is (AuraFrame.lua): Serene makes each icon (round,
-- a hairline ring, the dark edge, the count) and hands its parts to a container set to the unit; the game itself fills
-- them, in a fight too, where addons may read nothing of a unit's auras. So every icon, time and count is the game's.
--   - Your own debuffs on it first, a little larger; then the others' debuffs; then its buffs.
--   - A debuff's ring in its kind's colour (the game colours it: the kind may be secret); a buff's in soft gold.
--   - The elapsed part of each darkened (the game's own swipe).
-- The game's own square icons are put out of sight. Under the mouse the game's tooltip.
--   (on Serene's page: Buffs, "Target and focus"; a reload to switch)

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local DISC = MEDIA .. "AuraDisc" -- (one soft-edged circle: the icon's mask, its ring, its edge, its swirl)
local FLAT = "Interface\\Buttons\\WHITE8X8"
local DIM = 0.55                 -- how dark the elapsed part turns
local GOLD = { 1, 0.82, 0.35 }
local SOFT, LINE = ns.SOFT_RGB, ns.LINE
local EDGE = { 0, 0, 0, 0.85 }
local TRIM = 0.08                -- the icon's baked-in edge trimmed away, on each side
local SMALL, LARGE = 18, 23      -- others' auras, and your own debuffs
local GAP = 4
local PER_ROW = 8                -- (about as wide as the card)
local LIFT = 7                   -- above the card's name
local MOST_DEBUFFS, MOST_BUFFS = 16, 32 -- (as many as the game shows)
local TINY = 0.01                -- the game's holder shrunk to this (too small to catch the mouse)

local UNITS = { target = "TargetFrame", focus = "FocusFrame" }
local NAMES = { target = "SereneTargetAuras", focus = "SereneFocusAuras" }

local active = false
local problem                    -- why a part couldn't be made (then the game's icons stay for that unit)
local containers = {}            -- unit -> Serene's container
local made = setmetatable({}, { __mode = "k" }) -- each icon the containers made -> its parts
local pending = false            -- a look to apply once out of the fight

local SORT_BY = _G.AuraContainerSortMethod and _G.AuraContainerSortMethod.Expiration or nil
local SORT_WAY = _G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal or nil
local FLOW = AnchorUtil and AnchorUtil.FlowDirection
local AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local DISPEL_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle

-- The groups: what each shows (the game's filters), in order.
--   (the game's own debuff filter includes nameplate-only debuffs: so does Serene's)
local GROUPS = {
	{ key = "mine", filter = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", most = MOST_DEBUFFS },
	{ key = "debuffs", filter = "HARMFUL|!PLAYER|INCLUDE_NAME_PLATE_ONLY", most = MOST_DEBUFFS },
	{ key = "buffs", filter = "HELPFUL", most = MOST_BUFFS },
}

local function Style()
	return ns.AuraStyle and ns.AuraStyle.Look() or { round = true, ring = "all", width = 1, quiet = true, edge = true,
		dim = true }
end

local function Harmful(kind) return kind ~= "buffs" end

-- Each kind of icon: how large its picture, how thick its ring (pixels).
local function Measure(kind, look)
	local width = (look.ring == "all" or (look.ring == "debuffs" and Harmful(kind))) and (look.width or 1) or 0
	return kind == "mine" and LARGE or SMALL, width
end

local function Element(kind)
	local size, width = Measure(kind, Style())
	return size + 2 * width * ns.Pixel(UIParent)
end

-- A debuff's ring in its kind's colour (as your own debuffs': AuraFrame.lua's colours), the game's to set.
local function KindColors(look)
	if ns.AuraKindColors then return ns.AuraKindColors(look) end
	local map = {}
	local kinds = ns.AuraStyle and ns.AuraStyle.KINDS or {}
	for _, kind in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage", "None" }) do
		local c = kinds[kind:lower()] or (ns.AuraStyle and ns.AuraStyle.DEBUFF) or { 0.82, 0.34, 0.3 }
		map[kind] = CreateColor(c[1], c[2], c[3], 0.9)
	end
	return map
end

-- Each icon --------------------------------------------------------------------------------------------------------------

-- An icon laid out for the look chosen (when made, and again when the look changes, out of a fight).
local function Dress(button, p)
	local look = Style()
	local size, width = Measure(p.kind, look)
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
	p.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], LINE[4] or 0.8)
	p.ring:SetShown(width > 0)
	p.edge:SetTexture(shape)
	p.edge:ClearAllPoints()
	p.edge:SetPoint("TOPLEFT", button, "TOPLEFT", -px, px)
	p.edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", px, -px)
	p.edge:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	p.edge:SetShown(look.edge ~= false)
	-- a debuff's ring in its kind's colour
	if Harmful(p.kind) and DISPEL_STYLE and button.AddDispelTypeTexture then
		pcall(button.ClearDispelTypeTextures, button)
		if width > 0 then
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
	if look.dim ~= false then
		pcall(button.SetDurationCooldown, button, p.swirl)
		pcall(p.swirl.SetDrawSwipe, p.swirl, true)
	else
		pcall(button.ClearDurationCooldown, button)
		pcall(p.swirl.SetDrawSwipe, p.swirl, false)
	end
	-- the count above all that
	p.words:SetAllPoints(button)
	p.words:SetFrameLevel(p.swirl:GetFrameLevel() + 2)
	p.count:ClearAllPoints()
	p.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -2)
	p.count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
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
		pcall(button.SetIcon, button, p.icon)
		pcall(button.SetApplicationCount, button, p.count)
		pcall(button.SetTooltipAnchorPoint, button, "ANCHOR_BOTTOMRIGHT")
		local ok, why = pcall(Dress, button, p)
		if not ok then problem = problem or ("an icon: " .. tostring(why)) end
	end
end

-- The containers ------------------------------------------------------------------------------------------------------

local function Layout(kind, order)
	local element = Element(kind)
	return { elementWidth = element, elementHeight = element, elementSpacing = GAP, lineSpacing = GAP,
		groupSpacing = GAP, groupLineSpacing = GAP, forceNewLine = false, layoutIndex = order }
end

-- (above the card's name, growing right and up: rows stack upward, away from the card)
local function Place(c, frame)
	c:ClearAllPoints()
	local name = rawget(frame, "name")
	if type(name) == "table" and name.GetTop then
		c:SetPoint("BOTTOMLEFT", name, "TOPLEFT", -2, LIFT)
	else
		c:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
	end
	if FLOW and AXIS then
		pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT")
		pcall(c.SetFlowLayoutGrowthDirection, c, FLOW.Right, FLOW.Up)
		pcall(c.SetFlowLayoutAxis, c, AXIS.Horizontal)
		pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
	end
	-- (eight of the small icons: a row of your larger ones holds fewer)
	pcall(c.SetFlowLayoutMaximumLineSize, c, PER_ROW * (Element("debuffs") + GAP))
end

local function AddGroups(c)
	for order, g in ipairs(GROUPS) do
		local options = {
			initializeFrame = Maker(g.key),
			maxFrameCount = g.most,
			sortMethod = SORT_BY, sortDirection = SORT_WAY,
			layout = Layout(g.key, order),
		}
		local ok, why = pcall(c.AddAuraGroup, c, g.key, g.filter, options)
		if not ok and g.key == "debuffs" then
			-- (a game that can't leave out your own: all debuffs here, yours then twice)
			ok, why = pcall(c.AddAuraGroup, c, g.key, "HARMFUL|INCLUDE_NAME_PLATE_ONLY", options)
		end
		if not ok then return false, g.key .. ": " .. tostring(why) end
	end
	return true
end

local function Container(unit)
	local frame = _G[UNITS[unit]]
	if type(frame) ~= "table" then return nil, "no " .. UNITS[unit] end
	local ok, c = pcall(CreateFrame, "AuraContainer", NAMES[unit], frame,
		"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
	if not ok or not c then return nil, tostring(c) end
	c.sereneOwn = true -- (Auras.lua leaves it alone: Serene's own icons)
	pcall(c.SetFrameLevel, c, (frame:GetFrameLevel() or 0) + 8) -- (above the card's own layers)
	Place(c, frame)
	local added, why = AddGroups(c)
	if not added then
		c:Hide()
		return nil, why
	end
	pcall(c.SetUnit, c, unit)
	if c.SetEnabled then pcall(c.SetEnabled, c, true) end
	c:Show()
	return c
end

-- The game's own icons put out of sight -----------------------------------------------------------------------------------

-- (unseen, and too small to catch the mouse; again whenever the game sets them back)
local silenced = {}
local function Silence(holder)
	if silenced[holder] then return end
	silenced[holder] = true
	local holding = false
	local function Again()
		if holding then return end
		holding = true
		pcall(holder.SetAlpha, holder, 0)
		pcall(holder.SetScale, holder, TINY)
		holding = false
	end
	Again()
	hooksecurefunc(holder, "SetAlpha", Again)
	hooksecurefunc(holder, "SetScale", Again)
end

-- (the game's own aura holder under the card: its known path first, else the first holder found, never Serene's)
local function GameHolder(frame)
	local content = rawget(frame, "TargetFrameContent")
	local contextual = type(content) == "table" and rawget(content, "TargetFrameContentContextual")
	local holder = type(contextual) == "table" and rawget(contextual, "Auras")
	if type(holder) == "table" and holder.SetScale then return holder end
	holder = ns.AuraContainers and ns.AuraContainers(frame)[1]
	if type(holder) == "table" and holder.SetScale and not rawget(holder, "sereneOwn") then return holder end
end

-- Starting, and the look changed -------------------------------------------------------------------------------------------

local function Apply()
	if not active then return end
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	for unit, c in pairs(containers) do
		Place(c, _G[UNITS[unit]])
		for order, g in ipairs(GROUPS) do pcall(c.SetAuraGroupLayout, c, g.key, Layout(g.key, order)) end
	end
	for button, p in pairs(made) do pcall(Dress, button, p) end
end

local function Init()
	if not (ns.On("auras") and ns.On("auraUnits")) then return end
	for unit in pairs(UNITS) do
		local c, why = Container(unit)
		if c then
			containers[unit] = c
			local holder = GameHolder(_G[UNITS[unit]])
			if holder then pcall(Silence, holder) end
		else
			problem = problem or (unit .. ": " .. tostring(why))
		end
	end
	if not next(containers) then return end
	active = true
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED",
		"UI_SCALE_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		-- (a new unit: the containers hear only its aura changes, so they're asked to start over)
		if event == "PLAYER_TARGET_CHANGED" and containers.target then
			pcall(containers.target.UpdateAllAuras, containers.target)
		elseif event == "PLAYER_FOCUS_CHANGED" and containers.focus then
			pcall(containers.focus.UpdateAllAuras, containers.focus)
		elseif event == "UI_SCALE_CHANGED" then
			Apply()
		elseif event == "PLAYER_REGEN_ENABLED" and pending then
			Apply()
		end
	end)
end

local function Refresh()
	if active then Apply() end
end

-- /serene debug: how the target's and focus's auras stand.
function ns.UnitAurasDebug()
	if not active then
		return ns.Print("target auras: the game's" .. (problem and (" — " .. problem) or " (Serene's are off)"))
	end
	local units, icons = {}, 0
	for unit in pairs(containers) do units[#units + 1] = unit end
	table.sort(units)
	for _ in pairs(made) do icons = icons + 1 end
	ns.Print(("target auras: the game's containers for %s; %d icons made%s"):format(table.concat(units, ", "), icons,
		problem and (" — problem: " .. problem) or ""))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
