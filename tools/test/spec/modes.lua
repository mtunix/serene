-- Modes.lua: rest mode. Away, or nothing done for a while: the whole interface (UIParent) fades away; anything done
-- brings it back at once. Never in a fight, in Edit Mode or while peeking.

local ns = wow.load({ "Core.lua", "Fade.lua", "Modes.lua" })
local loaded = wow.now -- (Modes counts "still" from when its file loaded)

local function near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 0.03 then
		error((what and (what .. ": ") or "") .. "expected about " .. expected .. ", got " .. tostring(actual), 2)
	end
end

test("still for idleAfter seconds (120 by default): rest", function()
	wow.login({})
	eq(ns.ModesMode(loaded + 119), nil)
	eq(ns.ModesMode(loaded + 120), "rest")
	ns.db.idleAfter = 300
	eq(ns.ModesMode(loaded + 299), nil)
	eq(ns.ModesMode(loaded + 300), "rest")
end)

test("away (the game's AFK): rest after 8 s still", function()
	wow.login({})
	wow.player.afk = true
	eq(ns.ModesMode(loaded + 7.9), nil)
	eq(ns.ModesMode(loaded + 8), "rest")
end)

test("a secret AFK answer is not taken as away", function()
	wow.login({})
	UnitIsAFK = function() return wow.secret(true) end
	eq(ns.ModesMode(loaded + 10), nil)
end)

test("idle switched off: never rest", function()
	wow.login({ idle = false })
	wow.player.afk = true
	eq(ns.ModesMode(loaded + 10000), nil)
end)

test("never in Edit Mode or while the peek key is held", function()
	wow.login({})
	EditModeManagerFrame.IsEditModeActive = function() return true end
	eq(ns.ModesMode(loaded + 1000), nil)
	EditModeManagerFrame.IsEditModeActive = nil
	Serene_Peek("down")
	eq(ns.ModesMode(loaded + 1000), nil)
	Serene_Peek("up")
	eq(ns.ModesMode(loaded + 1000), "rest")
end)

test("never in a fight; the fight's end counts as being awake", function()
	wow.login({})
	wow.fight(true)
	eq(ns.ModesMode(loaded + 1000), nil)
	wow.now = loaded + 1000
	wow.fight(false)
	eq(ns.ModesMode(wow.now + 119), nil, "counted again from the fight's end")
	eq(ns.ModesMode(wow.now + 120), "rest")
end)

test("the interface fades out (1.2 s) after idleAfter, and is back at once (0.25 s) when the mouse moves", function()
	wow.login({ idleAfter = 30 })
	wow.advance(29.5)
	eq(ns.ModeNow(), nil)
	eq(UIParent:GetAlpha(), 1)
	wow.advance(0.5)
	eq(ns.ModeNow(), "rest", "30 s still")
	wow.advance(0.5)
	near(UIParent:GetAlpha(), 0.5, "halfway out after 0.6 s")
	wow.advance(0.7)
	eq(UIParent:GetAlpha(), 0)
	wow.cursorX = 600
	wow.advance(0.1)
	eq(ns.ModeNow(), nil, "the mouse moved: awake")
	wow.advance(0.3)
	eq(UIParent:GetAlpha(), 1)
end)

test("a mouse moved by 2 pixels or less is not you", function()
	wow.login({ idleAfter = 30 })
	for _ = 1, 40 do
		wow.cursorX = (wow.cursorX or 500) == 500 and 502 or 500
		wow.advance(1)
	end
	eq(ns.ModeNow(), "rest")
end)

test("walking, casting, or typing in the chat keeps you awake", function()
	local cases = {
		function() GetUnitSpeed = function() return 7 end end,
		function() wow.player.casting = { "Fireball" } end,
		function() wow.player.channel = { "Drink" } end,
		function() wow.activeEditBox = { HasFocus = function() return true end } end,
	}
	for index, setup in ipairs(cases) do
		wow.login({ idleAfter = 30 })
		setup()
		wow.advance(60)
		eq(ns.ModeNow(), nil, "case " .. index)
	end
end)

test("a chat box open but not typed in is not activity", function()
	wow.login({ idleAfter = 30 })
	wow.activeEditBox = { HasFocus = function() return false end }
	wow.advance(31)
	eq(ns.ModeNow(), "rest")
end)

test("a fight while resting: everything back at once", function()
	wow.login({ idleAfter = 30 })
	wow.advance(33)
	eq(UIParent:GetAlpha(), 0)
	wow.fight(true)
	eq(ns.ModeNow(), nil)
	wow.advance(0.3)
	eq(UIParent:GetAlpha(), 1)
end)

test("the hints are told when the mode changes", function()
	wow.login({ idleAfter = 30 })
	local told = 0
	ns.HintsDirty = function() told = told + 1 end
	wow.advance(31)
	eq(told, 1)
	wow.cursorX = 900
	wow.advance(0.2)
	eq(told, 2)
end)

test("Serene never touches UIParent's opacity while you are active", function()
	wow.login({ idleAfter = 30 })
	UIParent:SetAlpha(0.7) -- (another addon's choice)
	for _ = 1, 20 do
		wow.cursorX = (wow.cursorX or 500) + 10
		wow.advance(1)
	end
	near(UIParent:GetAlpha(), 0.7)
end)
