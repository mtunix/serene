local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The five-second rule, seen. Mana spent on a spell stops your spirit's regeneration for five seconds: a thin line of
-- the game's gold under your mana bar grows from left to right over them, brightening toward its moving end. It starts
-- at your portrait's rim and is marked off in seconds: a small notch at each, faint ahead of the line, bright once it
-- has passed. At its end full regeneration starts again, and the line fades away. Shown only while your bar shows
-- mana (a druid in bear or cat form: away) and the mana isn't full.
-- What counts as spent: a cast of yours and your mana dropping, heard together (either may come first; a drain by
-- someone else, or a spell made free by Clearcasting, doesn't count). Where the game hides the numbers in a fight,
-- the spell's own cost tells instead.
-- /serene regen on|off

local WAIT = 5          -- seconds without regeneration after mana is spent
local PAIR = 0.5        -- seconds between a cast and the mana it took
local FADE_IN, FADE_OUT = 0.15, 0.6
local TRAIL = 0.55      -- the line's opacity behind its glow
local TIP = 14           -- the bright end of the line, fading back into it
local BRIGHT = { 1, 0.93, 0.7 }
local GOLD = { 1, 0.82, 0.35 }
local TICK_AHEAD, TICK_PASSED = 0.35, 0.9 -- (a second's notch, still to come and gone by)
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local line          -- Serene's drawing, under the player's mana bar
local bar           -- that bar
local startedAt     -- the last spend (nil: regenerating)
local held = 0      -- how far the line is drawn (kept while it fades)
local alpha = 0
local castAt, dropAt = -math.huge, -math.huge
local lastMana

local function Now() return GetTime() end

local function Mana()
	return Clean(Safe(UnitPower, "player", MANA)), Clean(Safe(UnitPowerMax, "player", MANA))
end

local function ShowsMana()
	local kind = Clean(Safe(UnitPowerType, "player"))
	return kind == nil or kind == MANA
end

-- (the spell's own cost, where the mana itself can't be read)
local function CostsMana(spell)
	spell = Clean(spell)
	if not spell then return false end
	local get = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
	local costs = get and Safe(get, spell)
	if type(costs) ~= "table" then return false end
	for _, cost in ipairs(costs) do
		if type(cost) == "table" then
			local kind, amount = Clean(cost.type), Clean(cost.cost)
			if kind == MANA and type(amount) == "number" and amount > 0 then return true end
		end
	end
	return false
end

-- Serene's line --------------------------------------------------------------------------------------------------------

local function Build()
	line = CreateFrame("Frame", nil, bar)
	line:EnableMouse(false)
	line.fill = line:CreateTexture(nil, "ARTWORK")
	line.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	line.fill:SetAlpha(TRAIL)
	-- (the tip: as thin as the line, see-through behind, bright at the end)
	line.tip = line:CreateTexture(nil, "OVERLAY")
	line.tip:SetTexture("Interface\\Buttons\\WHITE8X8")
	pcall(line.tip.SetBlendMode, line.tip, "ADD")
	local from, to = { BRIGHT[1], BRIGHT[2], BRIGHT[3], 0 }, { BRIGHT[1], BRIGHT[2], BRIGHT[3], 1 }
	if not (CreateColor and pcall(line.tip.SetGradient, line.tip, "HORIZONTAL", CreateColor(unpack(from)),
		CreateColor(unpack(to)))) then
		pcall(line.tip.SetGradientAlpha, line.tip, "HORIZONTAL", from[1], from[2], from[3], from[4], to[1], to[2], to[3],
			to[4])
	end
	line.tip:SetPoint("TOPRIGHT", line.fill, "TOPRIGHT", 0, 0)
	line.tip:SetPoint("BOTTOMRIGHT", line.fill, "BOTTOMRIGHT", 0, 0)
	-- (a notch at each whole second between its ends)
	line.ticks = {}
	for i = 1, WAIT - 1 do
		local tick = line:CreateTexture(nil, "OVERLAY", nil, 1)
		tick:SetColorTexture(BRIGHT[1], BRIGHT[2], BRIGHT[3], 1)
		line.ticks[i] = tick
	end
	line:SetAlpha(0)
	line:Hide()
end

-- How far left of the bar the line begins: at the rim of your round portrait, where the line's height meets it (the
-- portrait's ring a pixel outside it). 0 with no portrait, or none beside the line.
local function Reach(px)
	local portrait = ns.PlayerPortrait and ns.PlayerPortrait()
	if not portrait then return 0 end
	local cx, cy = Safe(portrait.GetCenter, portrait)
	cx, cy = Clean(cx), Clean(cy)
	local size = Clean(Safe(portrait.GetWidth, portrait))
	local left, bottom = Clean(Safe(bar.GetLeft, bar)), Clean(Safe(bar.GetBottom, bar))
	local ps = Clean(Safe(portrait.GetEffectiveScale, portrait)) or 1
	local bs = Clean(Safe(bar.GetEffectiveScale, bar)) or 1
	if not (cx and cy and size and left and bottom) or bs <= 0 then return 0 end
	local k = ps / bs -- (the portrait's numbers in the bar's)
	cx, cy = cx * k, cy * k
	local r = size * k / 2 + px
	local dy = (bottom - px) - cy -- (the line's middle)
	if math.abs(dy) >= r then return 0 end
	return math.max(0, left - (cx + math.sqrt(r * r - dy * dy)))
end

-- (right under the bar, from the portrait's rim to the bar's end; the trail a hairline of two pixels at its top, the
-- seconds' notches hanging two pixels under it)
local function Place()
	local px = ns.Pixel(bar)
	local reach = Reach(px)
	local width = (Clean(Safe(bar.GetWidth, bar)) or 0) + reach
	if line.px == px and line.reach and math.abs(line.reach - reach) < 0.25 and line.total == width then return width end
	line.px, line.reach, line.total = px, reach, width
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -reach, 0)
	line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	line:SetHeight(2 * px)
	line.fill:ClearAllPoints()
	line.fill:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
	line.fill:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 0)
	for i, tick in ipairs(line.ticks) do
		tick:ClearAllPoints()
		tick:SetSize(px, 4 * px)
		tick:SetPoint("TOPLEFT", line, "TOPLEFT", math.floor(width * i / WAIT / px + 0.5) * px, 0)
	end
	line:SetFrameLevel((Clean(Safe(bar.GetFrameLevel, bar)) or 1) + 2)
	return width
end

local function Paint(elapsed)
	local now = Now()
	local target = 0
	if startedAt then
		local p = (now - startedAt) / WAIT
		local mana, most = Mana()
		if p >= 1 then
			startedAt, held = nil, 1 -- (drawn to its end, then away)
		elseif mana and most and most > 0 and mana >= most then
			startedAt = nil -- (full anyway: nothing to wait for)
		elseif ShowsMana() then
			held, target = math.max(0, p), 1
		end
	end
	alpha = ns.Approach(alpha, target, elapsed, FADE_IN, FADE_OUT)
	if alpha <= 0 and not startedAt then
		line:SetAlpha(0)
		line:Hide()
		return
	end
	local width = Place()
	local filled = math.max(0.01, width * held)
	line.fill:SetWidth(filled)
	line.tip:SetWidth(math.max(0.01, math.min(TIP, filled)))
	line.tip:SetShown(held < 1 and held > 0.005)
	for i, tick in ipairs(line.ticks) do
		tick:SetAlpha(held >= i / WAIT and TICK_PASSED or TICK_AHEAD)
	end
	line:SetAlpha(alpha)
end

local function Spent()
	startedAt = Now()
	castAt, dropAt = -math.huge, -math.huge
	if line and ns.On("manaRegen") then line:Show() end
end

-- Events ---------------------------------------------------------------------------------------------------------------

local function OnEvent(_, event, unit, a, b)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if Clean(unit) ~= "player" then return end
		local now = Now()
		if lastMana ~= nil and Mana() ~= nil then
			-- (the mana readable: the drop it took tells)
			castAt = now
			if now - dropAt <= PAIR then Spent() end
		elseif CostsMana(b) then
			Spent()
		end
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
		if Clean(unit) ~= "player" or Clean(a) ~= "MANA" then return end
		local mana = Mana()
		if mana and lastMana and mana < lastMana then
			dropAt = Now()
			if dropAt - castAt <= PAIR then Spent() end
		end
		lastMana = mana
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMana = Mana()
		if not bar then ns.RegenFind() end
	end
end

function ns.RegenFind()
	if bar then return end
	bar = ns.PlayerPowerBar and ns.PlayerPowerBar()
	if type(bar) ~= "table" or not bar.CreateTexture then
		bar = nil
		return
	end
	Build()
	line:SetScript("OnUpdate", function(_, elapsed) Paint(elapsed or 0) end)
end

local function Apply()
	if not line then return end
	if ns.On("manaRegen") then
		if startedAt then line:Show() end
	else
		alpha = 0
		line:SetAlpha(0)
		line:Hide()
	end
end

local function Init()
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
	for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }) do
		if not (events.RegisterUnitEvent and pcall(events.RegisterUnitEvent, events, event, "player")) then
			pcall(events.RegisterEvent, events, event)
		end
	end
	events:SetScript("OnEvent", OnEvent)
	lastMana = Mana()
	ns.RegenFind()
	Apply()
end

table.insert(ns.modules, { init = Init, refresh = Apply })
