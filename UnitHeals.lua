local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The game's heal prediction on the unit frames' health bars, made as calm as the bars (Units.lua dresses the cards;
-- this, what a health bar shows of the heals and absorbs coming):
--   - flat and as tall as the bar, the game's colours kept, its gradient art and slanted masks gone;
--   - growing from the fill's end whichever way the bar fills: the target's, filling toward its portrait on the right,
--     mirrored, glows and shadows too;
--   - a bright hairline at the bar's full end, fading in from it, while a heal of yours is coming and the heals coming
--     would overflow the bar (an overheal). In a fight the game may keep that a secret: never read, only handed on.
--   ns.UnitHeals.Dress(d)            a card's health bar taken in (d: Units.lua's record of the card); d:Segments()
--                                    lays it out again once the bar's direction changes
--   ns.UnitHeals.Overheal(d, unit)   the overheal mark shown or not, now

local FLAT = "Interface\\Buttons\\WHITE8X8"
local OVERHEAL = { 0.62, 0.95, 0.66 } -- (if the game's heal colour can't be read)
local OVERHEAL_FADE = 22               -- the overheal mark's soft fade in from the bar's end
local IsRegion, IsTexture = ns.IsRegion, ns.IsTexture

-- Mirrored with the bar ------------------------------------------------------------------------------------------------
-- The game's heal prediction and absorbs on a health bar: segments of colour, each hung from the right edge of the
-- fill (or of the segment before it), and two glows at the bar's ends. Once the bar fills toward the portrait (the
-- target's, on the right), that edge is the bar's own end: the segments would fall past it, cut away by the game's
-- mask, unseen. While the bar is mirrored they are too: hung from the fill's other edge, growing the other way, the
-- glows and shadows at the other ends. The game still decides what shows and how much.

local SEGMENTS = { "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar" }
local SWAP = { LEFT = "RIGHT", RIGHT = "LEFT", TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
	BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT" }

-- A region with fixed anchors (a glow, a shadow) mirrored, or put back as the game had it.
local function Mirror(region, on, kept)
	if on then
		if kept[region] then return end
		local points = {}
		for index = 1, Clean(Safe(region.GetNumPoints, region)) or 0 do
			local point, relative, relPoint, x, y = Safe(region.GetPoint, region, index)
			point, relPoint, x, y = Clean(point), Clean(relPoint), Clean(x), Clean(y)
			if type(point) ~= "string" then return end
			points[#points + 1] = { point, relative, relPoint or point, x or 0, y or 0 }
		end
		if #points == 0 then return end
		local coords = { Safe(region.GetTexCoord, region) }
		kept[region] = { points = points, coords = #coords == 8 and coords or nil }
		pcall(region.ClearAllPoints, region)
		for _, p in ipairs(points) do
			pcall(region.SetPoint, region, SWAP[p[1]] or p[1], p[2], SWAP[p[3]] or p[3], -p[4], p[5])
		end
		local c = kept[region].coords
		if c then pcall(region.SetTexCoord, region, c[5], c[6], c[7], c[8], c[1], c[2], c[3], c[4]) end
	else
		local was = kept[region]
		if not was then return end
		kept[region] = nil
		pcall(region.ClearAllPoints, region)
		for _, p in ipairs(was.points) do pcall(region.SetPoint, region, unpack(p)) end
		if was.coords then pcall(region.SetTexCoord, region, unpack(was.coords)) end
	end
end

local function Segments(d)
	local health = d.health
	local from = {}     -- segment -> { the texture it hangs from, its offset (a share of the bar's width) }
	local mirrored = {} -- segment -> true while hung the other way
	local kept = {}     -- glow or shadow -> its own anchors, while mirrored
	local fixed = {}    -- the glows and shadows
	-- (a segment hung as the game would, or mirrored: from the fill's left edge, growing left)
	local function Hang(segment)
		local at, mask = from[segment], rawget(segment, "FillMask")
		if not at or not IsRegion(mask) or not IsRegion(at[1]) then return end
		if not d.reversed and not mirrored[segment] then return end -- (the game's own placing: left alone)
		local bar = rawget(segment, "statusBar") or health
		local width = Clean(Safe(bar.GetWidth, bar))
		-- (the width secret in a fight: hung with no offset)
		local x = (type(width) == "number" and type(at[2]) == "number") and width * at[2] or 0
		pcall(mask.ClearAllPoints, mask)
		if d.reversed then
			pcall(mask.SetPoint, mask, "TOPRIGHT", at[1], "TOPLEFT", -x, 0)
			pcall(mask.SetPoint, mask, "BOTTOMRIGHT", at[1], "BOTTOMLEFT", -x, 0)
			mirrored[segment] = true
		else
			pcall(mask.SetPoint, mask, "TOPLEFT", at[1], "TOPRIGHT", x, 0)
			pcall(mask.SetPoint, mask, "BOTTOMLEFT", at[1], "BOTTOMRIGHT", x, 0)
			mirrored[segment] = nil
		end
	end
	local seen = {}
	for _, key in ipairs(SEGMENTS) do
		local segment = rawget(health, key)
		if type(segment) == "table" and not seen[segment] and type(segment.UpdateFillPosition) == "function"
			and IsRegion(rawget(segment, "FillMask")) then
			seen[segment] = true
			hooksecurefunc(segment, "UpdateFillPosition", function(self, previous, _, percent)
				from[self] = { previous, Clean(percent) }
				pcall(Hang, self)
			end)
			for _, shadow in ipairs({ rawget(segment, "LeftShadow") or false, rawget(segment, "RightShadow") or false }) do
				if IsRegion(shadow) then fixed[#fixed + 1] = shadow end
			end
			-- (flat, as the bars are: the game's colour kept, its gradient art not)
			local fill = rawget(segment, "Fill")
			if IsTexture(fill) then pcall(fill.SetTexture, fill, FLAT) end
			-- (the game's slanted bar mask off it, as off the fill: it still sits where the game's bar was, and cut
			-- the segment shorter than the bar. Only its own mask kept, the one showing how much.)
			local own = rawget(segment, "FillMask")
			for _, key in ipairs({ "Fill", "TiledFillOverlay", "LeftShadow", "RightShadow" }) do
				local texture = rawget(segment, key)
				if IsTexture(texture) and texture.GetNumMaskTextures then
					for index = Clean(Safe(texture.GetNumMaskTextures, texture)) or 0, 1, -1 do
						local mask = Safe(texture.GetMaskTexture, texture, index)
						if mask and mask ~= own then pcall(texture.RemoveMaskTexture, texture, mask) end
					end
				end
			end
		end
	end
	for _, key in ipairs({ "OverAbsorbGlow", "OverHealAbsorbGlow" }) do
		local glow = rawget(health, key)
		if IsRegion(glow) then fixed[#fixed + 1] = glow end
	end
	-- The overheal mark: a bright hairline at the bar's full end (the right; the left once mirrored) and a short soft
	-- fade in from it, there while the heals coming would fill the bar and more. Above the segments.
	local mark = CreateFrame("Frame", nil, health)
	mark:SetAllPoints(health)
	mark:EnableMouse(false)
	mark.line = mark:CreateTexture(nil, "OVERLAY", nil, 2)
	mark.line:SetTexture(FLAT)
	mark.fade = mark:CreateTexture(nil, "OVERLAY", nil, 1)
	mark.fade:SetTexture(FLAT)
	local c = OVERHEAL
	local game = _G.HEALTHBAR_MY_HEAL_PREDICTION_COLOR
	if type(game) == "table" and game.GetRGB then
		local r, g, b = Safe(game.GetRGB, game)
		r, g, b = Clean(r), Clean(g), Clean(b)
		-- (the game's own heal colour, lifted toward white: the same heal, brimming)
		if r and g and b then c = { r + (1 - r) * 0.6, g + (1 - g) * 0.6, b + (1 - b) * 0.6 } end
	end
	mark.line:SetVertexColor(c[1], c[2], c[3], 1)
	mark.color = c
	mark.parts = { mark.line, mark.fade }
	-- (shown or not as a whole, by the holder's alpha: the parts' own colours and gradient never bring it back)
	mark:SetAlpha(0)
	d.overheal = mark
	local function PlaceMark()
		local px = ns.Pixel(health)
		pcall(mark.SetFrameLevel, mark, (Clean(Safe(health.GetFrameLevel, health)) or 2) + 3)
		local near, far = "RIGHT", "LEFT" -- (the full end, and the way in from it)
		if d.reversed then near, far = "LEFT", "RIGHT" end
		mark.line:ClearAllPoints()
		mark.line:SetPoint("TOP" .. near, health, "TOP" .. near, 0, 0)
		mark.line:SetPoint("BOTTOM" .. near, health, "BOTTOM" .. near, 0, 0)
		mark.line:SetWidth(3 * px)
		mark.fade:ClearAllPoints()
		mark.fade:SetPoint("TOP" .. near, mark.line, "TOP" .. far, 0, 0)
		mark.fade:SetPoint("BOTTOM" .. near, mark.line, "BOTTOM" .. far, 0, 0)
		mark.fade:SetWidth(OVERHEAL_FADE)
		if mark.reversed == (d.reversed and true or false) then return end -- (its gradient already this way)
		mark.reversed = d.reversed and true or false
		local clear, full = { c[1], c[2], c[3], 0 }, { c[1], c[2], c[3], 0.7 }
		local left, right = clear, full
		if d.reversed then left, right = full, clear end
		if not (CreateColor and pcall(mark.fade.SetGradient, mark.fade, "HORIZONTAL",
			CreateColor(unpack(left)), CreateColor(unpack(right)))) then
			mark.fade:SetVertexColor(c[1], c[2], c[3], 0.2)
		end
	end
	function d:Segments()
		for _, region in ipairs(fixed) do pcall(Mirror, region, self.reversed, kept) end
		for segment in pairs(from) do pcall(Hang, segment) end
		pcall(PlaceMark)
	end
	d:Segments()
end

-- One calculator for all (asked and read at once): incoming heals capped at the health missing, so it says when they
-- would overflow. The answer may be a secret in a fight: never read, only handed to the mark's alpha.
local calculator
local function Calculator()
	if calculator == nil then
		calculator = false -- (tried once: false where this client has none)
		if type(CreateUnitHealPredictionCalculator) == "function" then
			local made = Safe(CreateUnitHealPredictionCalculator)
			if made and pcall(function()
				local modes = Enum and Enum.UnitIncomingHealClampMode
				made:SetIncomingHealClampMode(modes and modes.MissingHealth or 0)
				made:SetIncomingHealOverflowPercent(1) -- (1: nothing past the bar's end)
			end) then
				calculator = made
			end
		end
	end
	return calculator or nil
end

-- You casting (or channelling) a spell now.
local function Casting()
	for _, info in ipairs({ UnitCastingInfo or false, UnitChannelInfo or false }) do
		if info then
			local name = Safe(info, "player")
			-- (a secret name is still a cast: asked whether it is secret before it is tested)
			if ns.IsSecret(name) or name then return true end
		end
	end
	return false
end

-- Only for your own heal: the mark shows while a heal of yours is coming to this unit (one of yours, read from the
-- calculator; in a fight, if that amount is a secret, while you are casting) and the heals coming would overflow it.
local function Overheal(d, unit)
	local mark = d.overheal
	if not mark then return end
	local calc = Calculator()
	local over = false
	if unit and calc and type(UnitGetDetailedHealPrediction) == "function"
		and pcall(UnitGetDetailedHealPrediction, unit, "player", calc) then
		-- (all heals coming, yours, others', and whether they were clamped at the health missing)
		local ok, _, mine, _, clamped = pcall(calc.GetIncomingHeals, calc)
		if ok then
			local yours
			if ns.IsSecret(mine) then
				yours = Casting()
			else
				yours = type(mine) == "number" and mine > 0
			end
			-- (clamped: nil or a secret alike, only handed on, never tested here)
			if yours then over = clamped end
		end
	end
	-- (the holder shown or not; were that not possible, each part, as before)
	if mark.SetAlphaFromBoolean and pcall(mark.SetAlphaFromBoolean, mark, over, 1, 0) then return end
	if not ns.IsSecret(over) then
		for _, part in ipairs(mark.parts) do part:SetAlpha(1) end
		mark:SetAlpha(over and 1 or 0)
		return
	end
	mark:SetAlpha(1)
	for _, part in ipairs(mark.parts) do
		if not (part.SetAlphaFromBoolean and pcall(part.SetAlphaFromBoolean, part, over, 1, 0)) then part:SetAlpha(0) end
	end
end

ns.UnitHeals = { Dress = Segments, Overheal = Overheal }
