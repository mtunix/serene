-- CastBar.lua: your own cast bar restyled. Its art put away, its colour by what the cast is (as the game says it, or
-- as it colours an older bar), its size from the settings or Edit Mode's, the words in it or under it, the spark at
-- the fill's end while a cast goes on, the time in Serene's words, your lag at its end, a channel's ticks, the flash
-- as it ends, Serene's way in and out. (The target's and focus's cast bars: spec/units.lua.)

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
bar.unit = "player"
-- (the game's way of ending a cast: its methods, and its fade animations, a hold before the interrupted one's)
function bar:ApplyAlpha(alpha) self:SetAlpha(alpha) end
function bar:PlayFadeAnim() end
function bar:PlayInterruptAnims() self.InterruptShakeAnim:Play() end
local function Fade(group, from, to, duration)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(from)
	anim:SetToAlpha(to)
	anim:SetDuration(duration)
	return anim
end
bar.FadeOutAnim = bar:CreateAnimationGroup()
local fadeOut = Fade(bar.FadeOutAnim, 1, 0, 0.3)
bar.HoldFadeOutAnim = bar:CreateAnimationGroup()
local hold, holdOut = Fade(bar.HoldFadeOutAnim, 1, 1, 1), Fade(bar.HoldFadeOutAnim, 1, 0, 0.3)
bar.InterruptShakeAnim = bar:CreateAnimationGroup()

local ns = wow.load({ "Core.lua", "CastBar.lua" })

local CASTING, CHANNELING, LOCKED, FAILED = { 0.86, 0.7, 0.36 }, { 0.42, 0.68, 0.44 }, { 0.58, 0.58, 0.6 },
	{ 0.78, 0.33, 0.3 }

-- The colour Serene last gave the fill.
local function Colour()
	local calls = wow.calls(bar, "SetStatusBarColor")
	local last = calls[#calls]
	return last and { last[2], last[3], last[4] }
end

-- Serene's parts on the bar.
local function Parts() return ns.CastParts(bar) end
local function Spark() return Parts().spark end

-- A cast going on: this far through its whole (a channel counts down).
local function Cast(value, most, channel)
	bar:SetMinMaxValues(0, most)
	bar:SetValue(value)
	bar.casting, bar.channeling = not channel or nil, channel or nil
	wow.advance(0.1)
end

local function Near(a, b) return math.abs(a - b) < 0.01 end

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

-- The time, the lag, the ticks ---------------------------------------------------------------------------------------

test("the time in Serene's words: left, left and the whole, or none; the game's own put away", function()
	Login()
	eq(bar.CastTimeText:GetAlpha(), 0, "the game's")
	Cast(0.5, 2)
	eq(Parts().time:GetText(), "1.5", "left")
	ns.db.castTime = "both"
	ns.Refresh()
	Cast(0.8, 3, true)
	eq(Parts().time:GetText(), "0.8 / 3.0", "a channel: left and the whole")
	ns.db.castTime = "none"
	ns.Refresh()
	no(Parts().time:IsShown(), "none")
	clean()
end)

test("your lag at the cast's end: the game's latency, then as measured; at a channel's start", function()
	Login()
	local zone = Parts().lag
	Cast(0.2, 2)
	ok(zone:IsShown(), "shown")
	ok(Near(zone:GetWidth(), 195 * 0.04 / 2), "the game's latency, 40 ms")
	local point = zone:GetPoint(1)
	eq(point, "TOPRIGHT", "at the cast's end")
	wow.fire("UNIT_SPELLCAST_SENT", "player")
	wow.advance(0.2)
	wow.fire("UNIT_SPELLCAST_START", "player")
	Cast(0.2, 2)
	ok(Near(zone:GetWidth(), 195 * 0.2 / 2), "measured: sent to started")
	Cast(1, 2, true)
	point = zone:GetPoint(1)
	eq(point, "TOPLEFT", "a channel ends at the fill's start")
	ns.db.castLatency = false
	wow.advance(0.1)
	no(zone:IsShown(), "switched off")
	bar.channeling = nil
	clean()
end)

test("a channel's ticks where they land, for a channel Serene knows", function()
	wow.spells[689] = { name = "Drain Life" }
	Login()
	wow.player.channel = { "Drain Life" }
	Cast(4.5, 5, true)
	local shown = 0
	for _, tick in ipairs(Parts().ticks) do
		if tick:IsShown() then shown = shown + 1 end
	end
	eq(shown, 4, "one each second, the end not marked")
	local _, relative, relPoint, x = Parts().ticks[1]:GetPoint(1)
	eq({ relative, relPoint }, { bar, "LEFT" }, "from the fill's start")
	ok(Near(x, 195 * 4 / 5), "the first a second in")
	bar.channeling = nil
	wow.advance(0.1)
	no(Parts().ticks[1]:IsShown(), "gone when it ends")
	wow.player.channel = { "Mind Vision" }
	Cast(4.5, 5, true)
	no(Parts().ticks[1]:IsShown(), "a channel without ticks")
	wow.player.channel = nil
	bar.channeling = nil
	clean()
end)

-- The end ------------------------------------------------------------------------------------------------------------

test("a soft flash as it ends: light when it lands, red when interrupted, out with the next cast", function()
	Login()
	local flash = Parts().flash
	local function Colour() local c = wow.state(flash).color return { c[1], c[2], c[3] } end
	bar:PlayFadeAnim()
	ok(flash:GetAlpha() > 0.4, "lit")
	eq(Colour(), { 1, 0.95, 0.82 }, "light")
	wow.advance(0.5)
	eq(flash:GetAlpha(), 0, "faded")
	bar:PlayInterruptAnims()
	eq(Colour(), FAILED, "red")
	bar:ApplyAlpha(1)
	eq(flash:GetAlpha(), 0, "out with the next cast")
	ns.db.castFlash = false
	bar:PlayFadeAnim()
	eq(flash:GetAlpha(), 0, "switched off")
	clean()
end)

test("Serene's rhythm: in softly from away, at once while fading, away slowly, no shake", function()
	Login()
	eq(fadeOut:GetDuration(), 0.9, "away slowly")
	eq({ hold:GetDuration(), holdOut:GetDuration() }, { 1, 0.9 }, "the game's hold kept")
	bar:Hide()
	bar:ApplyAlpha(1)
	eq(bar:GetAlpha(), 0, "from nothing")
	bar:Show()
	wow.advance(0.06, 0.06)
	ok(bar:GetAlpha() > 0.3 and bar:GetAlpha() < 0.7, "coming in")
	wow.advance(0.1)
	eq(bar:GetAlpha(), 1, "in")
	bar:ApplyAlpha(1)
	eq(bar:GetAlpha(), 1, "shown already: at once")
	bar:PlayInterruptAnims()
	no(bar.InterruptShakeAnim:IsPlaying(), "no shake")
	ns.db.castFade = false
	ns.Refresh()
	eq(fadeOut:GetDuration(), 0.3, "the game's again")
	bar:Hide()
	bar:ApplyAlpha(1)
	eq(bar:GetAlpha(), 1, "the game's way in")
	bar:PlayInterruptAnims()
	ok(bar.InterruptShakeAnim:IsPlaying(), "the game's shake")
	clean()
end)

test("the bar's numbers secret: no time, lag or ticks worked out from them, and nothing breaks", function()
	wow.spells[689] = { name = "Drain Life" }
	Login()
	wow.player.channel = { wow.secret("Drain Life") }
	rawset(bar, "GetValue", function() return wow.secret(4.5) end)
	rawset(bar, "GetMinMaxValues", function() return wow.secret(0), wow.secret(5) end)
	bar.spellID = wow.secret(689)
	bar.channeling = wow.secret(true)
	wow.advance(0.1)
	bar.channeling = true
	wow.advance(0.1)
	no(Parts().lag:IsShown(), "no lag")
	eq(#Parts().ticks, 0, "no ticks")
	eq(Parts().time:GetText() or "", "", "no time")
	bar:ApplyAlpha(wow.secret(1))
	bar:PlayFadeAnim()
	rawset(bar, "GetValue", nil)
	rawset(bar, "GetMinMaxValues", nil)
	bar.spellID, bar.channeling, wow.player.channel = nil, nil, nil
	clean()
end)
