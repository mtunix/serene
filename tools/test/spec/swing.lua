-- Swing.lua: the game's swing timer frames, found through Edit Mode, their art put away and given back; Serene's lines
-- on them filling with each swing the game announces (PLAYER_SWING), kept in step through a change of speed, shown
-- only while the game shows its own and fading after the last swing.
-- The lines are read where the player sees them: each row's fill, as wide as the part of the swing already done.

local ns = wow.load({ "Core.lua", "Swing.lua" })

-- (this client's swing timer: an Edit Mode system with a frame for each hand; the stub has none of its own)
Enum.EditModeSystem = Enum.EditModeSystem or { SwingTimer = 22 }
local WIDTH = 220
local BAR = WIDTH - 12 - 5 -- (the line beside the weapon's icon and its gap, at 100%)

local function GameFrame(index)
	local f = CreateFrame("Frame", nil, UIParent)
	f.system, f.systemIndex = Enum.EditModeSystem.SwingTimer, index
	f:SetSize(WIDTH, 20)
	f.Bar = f:CreateTexture(nil, "ARTWORK")
	f.Selection = CreateFrame("Frame", nil, f) -- (Edit Mode's outline: never put away)
	return f
end
local mainFrame, offFrame = GameFrame(1), GameFrame(2)
EditModeManagerFrame.registeredSystemFrames = { offFrame, mainFrame }

local function near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 1 then
		error((what and (what .. ": ") or "") .. "expected about " .. expected .. ", got " .. tostring(actual), 2)
	end
end

-- Serene's lines: the frame placed on the main hand's, and its rows (main, off, ranged).
local function Lines()
	for _, f in ipairs(wow.frames) do
		local _, relative = f:GetPoint(1)
		if relative == mainFrame then return f end
	end
end

local function Row(hand)
	local main, off, ranged = Lines():GetChildren()
	return ({ main = main, off = off, ranged = ranged })[hand]
end

local function Filled(hand)
	local row = Row(hand)
	return row:IsShown() and row.fill:GetWidth() or nil
end

local function Login(saved)
	wow.login(saved or {})
	wow.advance(0.1)
end

local MAIN, OFF, RANGED = Enum.PlayerSwingType.MainHand, Enum.PlayerSwingType.OffHand, Enum.PlayerSwingType.Ranged

-- The swings -----------------------------------------------------------------------------------------------------------

test("a swing fills its line over its length; while you attack, the line then waits full and dim", function()
	Login()
	wow.fire("PLAYER_ENTER_COMBAT")
	wow.fire("PLAYER_SWING", 2.0, MAIN)
	wow.advance(1.0)
	near(Filled("main"), BAR / 2, "half way")
	ok(Row("main").spark:IsShown(), "the spark at its edge")
	wow.advance(1.5)
	near(Filled("main"), BAR, "the swing done")
	near(Row("main").fill:GetAlpha(), 0.9 * 0.45, "dim, waiting")
	no(Row("main").spark:IsShown(), "no spark while it waits")
	clean()
end)

test("a swing whose length can't be read lasts the weapon's speed", function()
	wow.speed = 2.6
	Login()
	wow.fire("PLAYER_SWING", wow.secret(1.0), MAIN)
	wow.advance(1.3)
	near(Filled("main"), BAR / 2)
	clean()
end)

test("faster mid-swing: the part already done stays done, the rest goes quicker", function()
	wow.speed = 2.6
	Login()
	wow.fire("PLAYER_ENTER_COMBAT")
	wow.fire("PLAYER_SWING", 2.6, MAIN)
	wow.advance(1.3)
	near(Filled("main"), BAR / 2, "half, before")
	wow.speed = 1.3
	wow.fire("UNIT_ATTACK_SPEED", "player")
	wow.advance(0.1)
	near(Filled("main"), BAR * (0.65 + 0.1) / 1.3, "half and a little more, after")
	wow.advance(0.55)
	near(Filled("main"), BAR, "done at the new speed")
	clean()
end)

test("a swing of a hand the game can't name is let be", function()
	Login()
	wow.fire("PLAYER_SWING", 2.0, wow.secret(MAIN))
	wow.advance(0.5)
	eq(Filled("main"), nil)
	clean()
end)

-- The rows -------------------------------------------------------------------------------------------------------------

test("the off hand's line only with a weapon there", function()
	wow.offSpeed = nil
	Login()
	wow.fire("PLAYER_ENTER_COMBAT")
	wow.advance(0.1)
	ok(Filled("main"), "main hand")
	eq(Filled("off"), nil, "one weapon: no off hand")
	wow.offSpeed = 1.8
	wow.fire("PLAYER_SWING", 1.8, OFF)
	wow.advance(0.9)
	near(Filled("off"), BAR / 2, "dual wielding")
	clean()
end)

test("Auto Shot's line while shooting, full before the first shot; none with shots off", function()
	wow.rangedSpeed = 3.0
	Login()
	wow.fire("START_AUTOREPEAT_SPELL")
	wow.advance(0.1)
	near(Filled("ranged"), BAR, "shooting, no shot heard yet")
	near(Row("ranged").zone:GetWidth(), BAR * 0.5 / 3.0, "the last half second marked")
	wow.fire("PLAYER_SWING", 3.0, RANGED)
	wow.advance(1.5)
	near(Filled("ranged"), BAR / 2, "half a shot")
	ns.db.swingRanged = false
	wow.advance(0.1)
	eq(Filled("ranged"), nil, "shots off")
	clean()
end)

test("in Edit Mode each line shows a sample, to place the frames by", function()
	wow.rangedSpeed = 3.0
	Login()
	EditModeManagerFrame.IsEditModeActive = function() return true end
	wow.advance(0.5)
	near(Filled("main"), BAR * 0.65, "main hand")
	near(Filled("ranged"), BAR * 0.65, "Auto Shot")
	ok(Lines():GetAlpha() > 0, "shown without a swing")
	clean()
end)

-- Shown, faded, put away -----------------------------------------------------------------------------------------------

test("the lines stay a moment after the last swing, then fade away", function()
	Login()
	wow.fire("PLAYER_SWING", 1.0, MAIN)
	wow.advance(1.0)
	near(Lines():GetAlpha() * 100, 100, "shown during the swing")
	wow.advance(1.2)
	ok(Lines():GetAlpha() > 0.9, "still there, just after")
	wow.advance(1.5)
	eq(Lines():GetAlpha(), 0, "gone")
	clean()
end)

test("the lines show only while the game shows its own swing timer", function()
	Login()
	mainFrame:Hide()
	offFrame:Hide()
	wow.fire("PLAYER_ENTER_COMBAT")
	wow.fire("PLAYER_SWING", 2.0, MAIN)
	wow.advance(0.5)
	eq(Lines():GetAlpha(), 0)
	clean()
end)

test("the game's art is put away, its Edit Mode outline kept; switched off, all of it comes back", function()
	mainFrame.Bar:SetAlpha(0.8)
	Login()
	eq(mainFrame.Bar:GetAlpha(), 0, "the game's bar")
	eq(offFrame.Bar:GetAlpha(), 0, "the off hand's")
	eq(mainFrame.Selection:GetAlpha(), 1, "Edit Mode's outline")
	wow.slash("/serene swing off")
	eq(mainFrame.Bar:GetAlpha(), 0.8, "the game's bar, as it was")
	no(Lines():IsShown(), "Serene's lines")
	clean()
end)
