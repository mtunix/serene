-- The target's card, as Units.lua dresses it, and the two parts other files draw on it: the target's cast bar under
-- the card (CastBar.lua, placed from Units.lua) and the overheal mark on its health bar (UnitHeals.lua).
-- The stub draws nothing: what is read is where each part was put, its colour, and what was handed to the game.

-- (the target's frame as this client builds it, reduced to what is read here: a health bar, a cast bar with its icon,
-- words and art, and the target's target, a small frame of its own)
local function Card(name, unit)
	local frame = _G[name]
	frame.unit = unit
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 250, -4)
	frame:SetSize(200, 80)
	frame.healthbar = CreateFrame("StatusBar", nil, frame)
	frame.healthbar:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -30)
	frame.healthbar:SetSize(120, 12)
	return frame
end
Card("TargetFrame", "target")
Card("TargetFrameToT", "targettarget")
local cast = CreateFrame("StatusBar", "TargetFrameSpellBar", TargetFrame)
cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
cast.Icon = cast:CreateTexture()
cast.Icon:SetTexture(136243)
cast.Text = cast:CreateFontString()
cast.Border = cast:CreateTexture()
TargetFrame.spellbar = cast

-- (the game's heal prediction calculator: what is coming, as a test sets it)
local incoming = { mine = 0, clamped = false }
function CreateUnitHealPredictionCalculator()
	return { SetIncomingHealClampMode = function() end, SetIncomingHealOverflowPercent = function() end,
		GetIncomingHeals = function() return 0, incoming.mine, 0, incoming.clamped end }
end
function UnitGetDetailedHealPrediction() return true end

local ns = wow.load()

wow.units.target = { name = "Defias Thug", level = 12, exists = true, enemy = true, powerToken = "MANA" }
wow.units.targettarget = { name = "Tester", exists = true, player = true }

local CHANNELING = { 0.42, 0.68, 0.44 }
local HOSTILE, NEUTRAL, FRIENDLY, GREY = { 0.78, 0.33, 0.3 }, { 0.86, 0.7, 0.36 }, { 0.42, 0.68, 0.44 },
	{ 0.45, 0.45, 0.45 }

local function Login(saved)
	wow.login(saved or {})
	wow.advance(0.5)
end

-- The target's cast bar ------------------------------------------------------------------------------------------------

-- (its first two points: from the card's lowest bar, its left end and its right end)
local function CastRow()
	local _, below, _, left, y = cast:GetPoint(1)
	local _, _, _, right = cast:GetPoint(2)
	return below, left, right, y
end

test("the target's cast bar: a slim line under the card, its art away, coloured by what the cast is", function()
	Login()
	local below, _, right, y = CastRow()
	eq(below, TargetFrame.healthbar, "hung from the card's health bar")
	ok(y < 0, "under it")
	eq(right, -11, "the icon's room at its outer end")
	eq(cast:GetHeight(), 10, "slim")
	no(cast.Border:IsVisible(), "the game's art away")
	cast.barType = "channel"
	cast:SetStatusBarColor(0, 1, 0)
	local calls = wow.calls(cast, "SetStatusBarColor")
	local last = calls[#calls]
	eq({ last[2], last[3], last[4] }, CHANNELING, "a channel")
	clean()
end)

test("beside the target's target while that one is shown, the whole width when it's gone", function()
	Login()
	local _, left = CastRow()
	ok(left > 0, "room left for the target's target (got " .. tostring(left) .. ")")
	TargetFrameToT:Hide()
	_, left = CastRow()
	eq(left, 0, "the whole width")
	TargetFrameToT:Show()
	_, left = CastRow()
	ok(left > 0, "beside it again")
	clean()
end)

test("the game moving it: put back in its row at once", function()
	Login()
	local _, _, _, y = CastRow()
	cast:ClearAllPoints()
	cast:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	local below, _, _, again = CastRow()
	eq({ below, again }, { TargetFrame.healthbar, y })
	clean()
end)

test("with the unit frames off, the target's cast bar is the game's", function()
	Login({ units = false })
	ok(cast.Border:IsVisible(), "its art")
	eq(#wow.calls(cast, "SetStatusBarColor"), 0, "its colour")
	clean()
end)

-- The overheal mark ------------------------------------------------------------------------------------------------------

-- (UnitHeals' mark: a frame on the health bar holding a line and a fade)
local function Mark()
	for _, child in ipairs({ TargetFrame.healthbar:GetChildren() }) do
		if rawget(child, "line") and rawget(child, "fade") then return child end
	end
end

-- Whether the mark shows: its holder's opacity (the game sets it from the answer, secret or not: the stub's
-- SetAlphaFromBoolean reveals a secret as the game would).
local function Shows() return Mark():GetAlpha() == 1 end

test("a heal of yours coming that would overflow the bar: the mark shown; none of yours: not", function()
	Login()
	ok(Mark(), "the mark made")
	incoming.mine, incoming.clamped = 1200, true
	wow.advance(0.3)
	ok(Shows(), "yours, overflowing")
	incoming.clamped = false
	wow.advance(0.3)
	no(Shows(), "yours, fitting")
	incoming.mine, incoming.clamped = 0, true
	wow.advance(0.3)
	no(Shows(), "only others'")
	clean()
end)

test("in a fight, your heal's amount secret: while you cast, the game's answer is handed on unread", function()
	Login()
	incoming.mine, incoming.clamped = wow.secret(1200), wow.secret(true)
	wow.player.casting = { "Flash of Light" }
	wow.advance(0.3)
	ok(Shows(), "casting, overflowing: the secret answer handed on")
	incoming.clamped = wow.secret(false)
	wow.advance(0.3)
	no(Shows(), "casting, fitting")
	incoming.clamped = wow.secret(true)
	wow.player.casting = nil
	wow.advance(0.3)
	no(Shows(), "not casting: none of yours")
	clean()
end)

-- The card ---------------------------------------------------------------------------------------------------------------

-- The colour Serene last gave a bar.
local function Colour(bar)
	local calls = wow.calls(bar, "SetStatusBarColor")
	local last = calls[#calls]
	return last and { last[2], last[3], last[4] }
end

-- (the target's portrait, where the game draws it: beyond the bars' right end)
local function Portrait()
	local portrait = TargetFrame:CreateTexture()
	portrait:SetPoint("TOPLEFT", TargetFrame, "TOPLEFT", 150, -10)
	portrait:SetSize(64, 64)
	TargetFrame.portrait = portrait
	return portrait
end

test("the health bar coloured by how the unit feels about you: hostile, neutral, friendly; grey once tapped or dead", function()
	Login()
	local health = TargetFrame.healthbar
	eq(Colour(health), HOSTILE, "an enemy")
	wow.units.target.enemy, wow.units.target.reaction = false, 4
	wow.advance(0.3)
	eq(Colour(health), NEUTRAL, "neutral")
	wow.units.target.reaction = 6
	wow.advance(0.3)
	eq(Colour(health), FRIENDLY, "friendly")
	wow.units.target.tapped = true
	wow.units.target.reaction = 2
	wow.advance(0.3)
	eq(Colour(health), GREY, "tapped by someone else")
	clean()
end)

test("a player's bar in their class's colour, a little quieter than the game's", function()
	wow.units.target = { name = "Ally", exists = true, player = true, class = "Mage", classFile = "MAGE" }
	Login()
	local c = RAID_CLASS_COLORS.MAGE
	local got = Colour(TargetFrame.healthbar)
	for index, part in ipairs({ c.r, c.g, c.b }) do
		ok(math.abs(got[index] - (part * 0.82 + 0.06)) < 0.001, "quieter")
	end
	clean()
end)

test("the power bar by its kind; the game's own colour and texture put back at once", function()
	TargetFrame.manabar = CreateFrame("StatusBar", nil, TargetFrame)
	TargetFrame.manabar:SetPoint("TOPLEFT", TargetFrame.healthbar, "BOTTOMLEFT", 0, -1)
	TargetFrame.manabar:SetSize(120, 8)
	Login()
	eq(Colour(TargetFrame.manabar), { 0.33, 0.52, 0.86 }, "mana")
	local health = TargetFrame.healthbar
	health:SetStatusBarColor(0, 1, 0)
	eq(Colour(health), HOSTILE, "the game's green painted over")
	ok(TargetFrame.manabar:GetPoint(1), "the power bar placed under the health bar")
	local _, relative = TargetFrame.manabar:GetPoint(1)
	eq(relative, health)
	clean()
end)

test("the game's art put away, and kept away when the game shows it again", function()
	local art = TargetFrame:CreateTexture()
	TargetFrame.FrameTexture = art
	Login()
	eq(art:GetAlpha(), 0, "away")
	art:SetAlpha(1)
	eq(art:GetAlpha(), 0, "shown again by the game: away again")
	art:Show()
	eq(art:GetAlpha(), 0, "and again")
	clean()
end)

test("the portrait on the right: round, an even size, and the bars fill toward it; portraits off: as the game fills", function()
	local portrait = Portrait()
	Login()
	local health = TargetFrame.healthbar
	local calls = wow.calls(health, "SetReverseFill")
	eq(calls[#calls] and calls[#calls][2], true, "reversed")
	local w, h = portrait:GetSize()
	eq(w, h, "square")
	eq(w % 2, 0, "even")
	eq(portrait:GetNumMaskTextures(), 1, "Serene's round mask")
	ns.db.unitPortraits = false
	ns.Refresh()
	wow.advance(0.3)
	calls = wow.calls(health, "SetReverseFill")
	eq(calls[#calls][2], false, "portraits off: filling the game's way")
	clean()
end)

test("the PvP crest pinned to the portrait's rim", function()
	local portrait = Portrait()
	local crest = TargetFrame:CreateTexture()
	crest:SetPoint("TOPLEFT", TargetFrame, "TOPLEFT", 200, 0)
	TargetFrame.PvpIcon = crest
	Login()
	local point, relative, relPoint, x, y = crest:GetPoint(1)
	eq({ point, relative, relPoint }, { "CENTER", portrait, "CENTER" })
	ok(x > 0 and y > 0 and math.abs(x - y) < 0.001, "up on its outer side, 45 degrees")
	clean()
end)

test("heal prediction mirrored with a bar filling toward the portrait: hung from the fill's other edge", function()
	Portrait()
	local health = TargetFrame.healthbar
	local segment = CreateFrame("Frame", nil, health)
	segment.FillMask = segment:CreateMaskTexture()
	segment.Fill = segment:CreateTexture()
	function segment:UpdateFillPosition() end
	health.MyHealPredictionBar = segment
	Login()
	local fill = health:GetStatusBarTexture()
	segment:UpdateFillPosition(fill, nil, 0.25)
	local point, relative, relPoint, x = segment.FillMask:GetPoint(1)
	eq({ point, relative, relPoint }, { "TOPRIGHT", fill, "TOPLEFT" }, "from the fill's left edge")
	eq(x, -120 * 0.25, "a quarter of the bar further left")
	eq(segment.Fill:GetTexture(), "Interface\\Buttons\\WHITE8X8", "flat")
	clean()
end)

test("the target's target moves only out of a fight: in one, placed once it is over", function()
	wow.combat = true
	Login()
	local _, relative = TargetFrameToT:GetPoint(1)
	no(relative == TargetFrame, "not moved in the fight")
	wow.fight(false)
	wow.advance(0.5)
	_, relative = TargetFrameToT:GetPoint(1)
	eq(relative, TargetFrame, "placed from the target's frame once it is over")
	clean()
end)

test("heal prediction handed a secret part in a fight: never looked into", function()
	Portrait()
	local health = TargetFrame.healthbar
	local segment = CreateFrame("Frame", nil, health)
	segment.FillMask = segment:CreateMaskTexture()
	segment.Fill = segment:CreateTexture()
	function segment:UpdateFillPosition() end
	health.MyHealPredictionBar = segment
	Login()
	local before = { segment.FillMask:GetPoint(1) }
	no(ns.IsRegion(wow.secret(health:GetStatusBarTexture())), "a secret is no region")
	segment:UpdateFillPosition(wow.secret(health:GetStatusBarTexture()), nil, wow.secret(0.25))
	eq({ segment.FillMask:GetPoint(1) }, before, "left where it was")
	clean()
end)

test("the target's target's bars, protected in a fight: left where the game puts them, laid out once it is over", function()
	local bar = TargetFrameToT.healthbar
	function bar:IsProtected() return wow.combat, false end
	Login()
	local placed = { bar:GetPoint(1) }
	eq(bar:GetWidth() ~= 120, true, "laid out out of a fight")
	wow.fight(true)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", TargetFrameToT, "TOPLEFT", 5, -5)
	bar:SetWidth(120)
	wow.advance(0.5)
	eq({ bar:GetPoint(1) }, { "TOPLEFT", TargetFrameToT, "TOPLEFT", 5, -5 }, "not moved in the fight")
	eq(bar:GetWidth(), 120, "not sized in the fight")
	wow.fight(false)
	wow.advance(0.5)
	eq({ bar:GetPoint(1) }, placed, "placed again once it is over")
	clean()
end)
