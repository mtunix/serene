-- CastBar.lua: your own cast bar restyled. Its art put away, its colour by what the cast is (as the game says it, or
-- as it colours an older bar), its size from the settings or Edit Mode's, the words in it or under it, the spark at
-- the fill's end while a cast goes on. (The target's and focus's cast bars: spec/units.lua.)

-- (the game's own cast bar, as this client builds it: a status bar with an icon, the spell's name, the time, its art,
-- a frame of glow, and Edit Mode's outline)
local bar = CreateFrame("StatusBar", "PlayerCastingBarFrame", UIParent)
bar:SetSize(195, 13)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar.Icon = bar:CreateTexture()
bar.Icon:SetTexture(136243)
bar.Text = bar:CreateFontString()
bar.Border = bar:CreateTexture()
bar.CastTimeText = bar:CreateFontString()
bar.Flash = CreateFrame("Frame", nil, bar)
bar.Selection = CreateFrame("Frame", nil, bar)

local ns = wow.load({ "Core.lua", "CastBar.lua" })

local CASTING, CHANNELING, LOCKED, FAILED = { 0.86, 0.7, 0.36 }, { 0.42, 0.68, 0.44 }, { 0.58, 0.58, 0.6 },
	{ 0.78, 0.33, 0.3 }

-- The colour Serene last gave the fill.
local function Colour()
	local calls = wow.calls(bar, "SetStatusBarColor")
	local last = calls[#calls]
	return last and { last[2], last[3], last[4] }
end

-- (the spark: the last texture Serene made on the bar)
local function Spark()
	local found
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "Texture" then found = region end
	end
	return found
end

local function Login(saved)
	wow.login(saved or {})
	wow.advance(0.1)
end

-- The look --------------------------------------------------------------------------------------------------------------

test("the art put away, out of sight; the fill, the icon, the words and Edit Mode's outline stay", function()
	Login()
	no(bar.Border:IsVisible(), "the art")
	eq(bar.Flash:GetAlpha(), 0, "a glow frame")
	eq(bar.Selection:GetAlpha(), 1, "Edit Mode's outline")
	ok(bar:GetStatusBarTexture():IsVisible(), "the fill")
	ok(bar.Icon:IsVisible(), "the icon")
	ok(bar.Text:IsVisible(), "the spell's name")
	clean()
end)

test("the fill coloured by what the cast is: the game's word for it, or the colour it gave an older bar", function()
	Login()
	eq(Colour(), CASTING, "a cast")
	bar.barType = "channel"
	bar:SetStatusBarColor(0, 1, 0)
	eq(Colour(), CHANNELING, "a channel, by its word")
	bar.barType = nil
	bar:SetStatusBarColor(1, 0, 0)
	eq(Colour(), FAILED, "failed: the game's red")
	bar:SetStatusBarColor(0.5, 0.5, 0.5)
	eq(Colour(), LOCKED, "can't be interrupted: the game's grey")
	bar:SetStatusBarColor(1, 0.7, 0)
	bar.notInterruptible = true
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	eq(Colour(), LOCKED, "the game's flag for it")
	clean()
end)

test("its size: the height chosen, Edit Mode's width (kept as the game changes it), or a width chosen", function()
	Login()
	eq({ bar:GetSize() }, { 195, 11 }, "at first")
	bar:SetSize(250, 20)
	eq({ bar:GetSize() }, { 250, 11 }, "Edit Mode's new width, Serene's height")
	ns.db.castWidth, ns.db.castHeight = 200, 16
	ns.Refresh()
	eq({ bar:GetSize() }, { 200, 16 }, "chosen")
	ns.db.castWidth = 0
	ns.Refresh()
	eq(bar:GetWidth(), 250, "Edit Mode's again")
	clean()
end)

test("the words in the bar, under it when it is too low for them (or chosen so), or none", function()
	Login()
	local _, relative, relPoint = bar.Text:GetPoint(1)
	eq({ relative, relPoint }, { bar, "LEFT" }, "in the bar")
	ns.db.castHeight = 6
	ns.Refresh()
	_, relative, relPoint = bar.Text:GetPoint(1)
	eq({ relative, relPoint }, { bar, "BOTTOMLEFT" }, "under a bar too low")
	ns.db.castHeight, ns.db.castText = 14, "under"
	ns.Refresh()
	_, relative, relPoint = bar.Text:GetPoint(1)
	eq(relPoint, "BOTTOMLEFT", "under, chosen")
	ns.db.castText = "none"
	ns.Refresh()
	eq(bar.Text:GetAlpha(), 0, "none")
	clean()
end)

test("the icon: shown with a spell's, hidden when switched off", function()
	Login()
	ok(bar.Icon:IsShown(), "shown")
	ns.db.castIcon = false
	ns.Refresh()
	no(bar.Icon:IsShown(), "switched off")
	clean()
end)

test("the spark at the fill's end while a cast goes on, gone when it ends", function()
	Login()
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.5)
	bar.casting = true
	wow.advance(0.1)
	ok(Spark():IsShown(), "casting")
	local _, relative, relPoint = Spark():GetPoint(1)
	eq({ relative, relPoint }, { bar:GetStatusBarTexture(), "RIGHT" }, "at the fill's end")
	bar.casting = nil
	wow.advance(0.1)
	no(Spark():IsShown(), "ended")
	clean()
end)

test("with castBar off, the game's own bar is left alone", function()
	Login({ castBar = false })
	ok(bar.Border:IsVisible(), "its art")
	eq(#wow.calls(bar, "SetStatusBarColor"), 0, "its colour")
	clean()
end)
