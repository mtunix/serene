-- Ready.lua: an action button as present as it is ready. Not ready (cooldown, short of mana, unusable, an attack with
-- no enemy, out of range): faint (barReadyDim, 30% by default). Unknown is never a fact: what can't be read never dims.

dofile(wow.root .. "/tools/test/spec/lib/actions_world.lua")
local ns = wow.load({ "Core.lua", "Actions.lua", "Ready.lua" })

wow.spells[133] = { name = "Fireball", known = true }
wow.spells[78] = { name = "Heroic Strike", known = true }
wow.put(1, "spell", 133)
wow.put(2, "spell", 78)

local state = {} -- slot -> what the game says of it: usable, noMana, range, cooldown, harmful, current
local function S(slot) state[slot] = state[slot] or {} return state[slot] end
IsUsableAction = function(slot)
	local s = state[slot] or {}
	if s.usable == nil then return HasAction(slot), false end
	return s.usable, s.noMana
end
IsActionInRange = function(slot) return (state[slot] or {}).range end
GetActionCooldown = function(slot) local s = state[slot] or {} return s.cooldown and wow.now or 0, s.cooldown or 0, 1 end
IsHarmfulAction = function(slot) return (state[slot] or {}).harmful or false end
IsCurrentAction = function(slot) return (state[slot] or {}).current or false end

local function near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 0.02 then
		error((what and (what .. ": ") or "") .. "expected about " .. expected .. ", got " .. tostring(actual), 2)
	end
end

local function Settle()
	wow.fire("ACTIONBAR_UPDATE_USABLE")
	wow.advance(1)
end

test("ready: at full", function()
	wow.login({})
	Settle()
	eq(ActionButton1:GetAlpha(), 1)
	eq(ActionButton2:GetAlpha(), 1)
end)

test("each reason dims, each with its own switch", function()
	local cases = {
		{ function() S(1).cooldown = 30 end, "barReadyCooldown", "on its cooldown" },
		{ function() S(1).usable, S(1).noMana = false, true end, "barReadyPower", "short of mana" },
		{ function() S(1).usable, S(1).noMana = false, false end, "barReadyUnusable", "unusable" },
		{ function() S(1).harmful = true end, "barReadyTarget", "an attack, nobody targeted" },
		{ function() S(1).range = 0 end, "barReadyRange", "out of range" },
	}
	for _, c in ipairs(cases) do
		wow.login({})
		state = {}
		c[1]()
		Settle()
		near(ActionButton1:GetAlpha(), 0.3, c[3])
		eq(ActionButton2:GetAlpha(), 1, c[3] .. ": the others stay")
		ns.db[c[2]] = false
		Settle()
		eq(ActionButton1:GetAlpha(), 1, c[3] .. " switched off")
		ns.db[c[2]] = true
	end
end)

test("the global cooldown never dims", function()
	wow.login({})
	S(1).cooldown = 1.5
	Settle()
	eq(ActionButton1:GetAlpha(), 1)
end)

test("an attack: faint with nobody, a friend or a corpse targeted; full with an enemy", function()
	wow.login({})
	S(2).harmful = true
	local cases = {
		{ nil, 0.3, "nobody" },
		{ { name = "Friend" }, 0.3, "a friend" },
		{ { name = "Corpse", enemy = true, dead = true }, 0.3, "a corpse" },
		{ { name = "Thug", enemy = true }, 1, "an enemy" },
	}
	for _, c in ipairs(cases) do
		wow.units.target = c[1]
		Settle()
		near(ActionButton2:GetAlpha(), c[2], c[3])
	end
end)

test("a secret answer on the target counts as an enemy", function()
	wow.login({})
	S(2).harmful = true
	wow.units.target = { name = "Thug" }
	UnitCanAttack = function() return wow.secret(false) end
	Settle()
	eq(ActionButton2:GetAlpha(), 1)
end)

test("in a fight with secrets nothing dims (cooldown, usable, range all unknown)", function()
	wow.login({})
	S(1).cooldown, S(1).usable, S(1).noMana, S(1).range = 30, false, true, 0
	wow.secretFight(true)
	Settle()
	eq(ActionButton1:GetAlpha(), 1)
	wow.secretFight(false)
	clean()
end)

test("barReadyDim: how faint, kept between 0 and 100", function()
	for _, c in ipairs({ { 50, 0.5 }, { 0, 0 }, { 150, 1 }, { -20, 0 }, { "x", 0.3 } }) do
		wow.login({ barReadyDim = c[1] })
		state = {}
		S(1).cooldown = 30
		ns.db.barReadyDim = c[1]
		Settle()
		near(ActionButton1:GetAlpha(), c[2], "dim " .. tostring(c[1]))
	end
end)

test("fading takes 0.35 s out and 0.12 s back in", function()
	wow.login({})
	Settle()
	S(1).cooldown = 30
	wow.fire("ACTIONBAR_UPDATE_COOLDOWN")
	wow.advance(0.1, 0.05)
	local mid = ActionButton1:GetAlpha()
	ok(mid < 1 and mid > 0.3, "on its way out (" .. mid .. ")")
	wow.advance(0.5, 0.05)
	near(ActionButton1:GetAlpha(), 0.3)
	S(1).cooldown = nil
	wow.fire("ACTIONBAR_UPDATE_COOLDOWN")
	wow.advance(0.2, 0.05)
	eq(ActionButton1:GetAlpha(), 1)
end)

test("a cooldown's end with no event is caught by the safety look (within 0.5 s)", function()
	wow.login({})
	S(1).cooldown = 30
	Settle()
	near(ActionButton1:GetAlpha(), 0.3)
	S(1).cooldown = nil
	wow.advance(0.8)
	eq(ActionButton1:GetAlpha(), 1)
end)

test("always at full: in use, a proc, lit by a hint, something on the cursor, Edit Mode, peeking", function()
	local cases = {
		{ function() S(1).current = true end, "in use" },
		{ function() ActionButton1.overlay = CreateFrame("Frame", nil, ActionButton1) end, "a proc" },
		{ function() ns.HintButtons = function() return { ActionButton1 } end end, "a hint" },
		{ function() wow.held = { kind = "spell", id = 78 } end, "the cursor" },
		{ function() EditModeManagerFrame.IsEditModeActive = function() return true end end, "Edit Mode" },
		{ function() ns.IsPeeking = function() return true end end, "peeking" },
	}
	for _, c in ipairs(cases) do
		wow.login({})
		state, wow.held, ActionButton1.overlay = {}, nil, nil
		ns.HintButtons, ns.IsPeeking, EditModeManagerFrame.IsEditModeActive = nil, nil, nil
		S(1).cooldown = 30
		c[1]()
		Settle()
		eq(ActionButton1:GetAlpha(), 1, c[2])
	end
end)

test("the bar under the mouse: all at full (barReadyHover)", function()
	wow.login({})
	S(1).cooldown = 30
	Settle()
	near(ActionButton1:GetAlpha(), 0.3)
	wow.hover(MainMenuBar)
	wow.advance(0.5)
	eq(ActionButton1:GetAlpha(), 1)
	wow.hover(nil)
	wow.advance(0.8)
	near(ActionButton1:GetAlpha(), 0.3)
	ns.db.barReadyHover = false
	wow.hover(MainMenuBar)
	wow.advance(0.8)
	near(ActionButton1:GetAlpha(), 0.3, "switched off")
end)

test("only in a fight (barReadyWhen = fight)", function()
	wow.login({ barReadyWhen = "fight" })
	S(1).cooldown = 30
	Settle()
	eq(ActionButton1:GetAlpha(), 1)
	wow.fight(true)
	Settle()
	near(ActionButton1:GetAlpha(), 0.3)
end)

test("switched off: every button given back at full", function()
	wow.login({})
	S(1).cooldown = 30
	Settle()
	near(ActionButton1:GetAlpha(), 0.3)
	ns.db.barReady = false
	wow.advance(0.2)
	eq(ActionButton1:GetAlpha(), 1)
end)

test("an empty slot is never dimmed", function()
	wow.login({})
	S(5).cooldown, S(5).usable = 30, false
	Settle()
	eq(ActionButton5:GetAlpha(), 1)
end)

test("a button faded on purpose (BarUse: unused) is faint for that reason", function()
	wow.login({})
	ns.BarUseFaded = function(slot) return slot == 2 end
	Settle()
	near(ActionButton2:GetAlpha(), 0.3)
	ns.ReadyDebug()
	ok(wow.printed[#wow.printed]:find("unused 1", 1, true), wow.printed[#wow.printed])
end)
