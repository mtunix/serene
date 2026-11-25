-- The target's card, as Units.lua dresses it, and the two parts other files draw on it: the target's cast bar under
-- the card (CastBar.lua, placed from Units.lua) and the overheal mark on its health bar (UnitHeals.lua).
-- The stub draws nothing: what is read is where each part was put, its colour, and what was handed to the game.

-- (the target's frame as this client builds it, reduced to what is read here: a health bar, a cast bar with its icon,
-- words and art, and the target's target, a small frame of its own)
local function Card(name, unit)
	local frame = _G[name]
	frame.unit = unit
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

wow.units.target = { name = "Defias Thug", level = 12, exists = true, reaction = 2 }
wow.units.targettarget = { name = "Tester", exists = true, player = true }

local CHANNELING = { 0.42, 0.68, 0.44 }

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
