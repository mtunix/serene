-- BarPing.lua: a long cooldown (30 s or more, measured from when it is first seen) coming back: one ring of gold
-- from its button, once. With the button faint, the spell's icon shows with it.

dofile(wow.root .. "/tools/test/spec/lib/actions_world.lua")
local ns = wow.load({ "Core.lua", "Actions.lua", "ActionBars.lua", "BarPing.lua" })

wow.spells[133] = { name = "Fireball", known = true }
wow.spells[122] = { name = "Frost Nova", known = true }
wow.put(1, "spell", 122)

local ends = {} -- slot -> when its cooldown ends
GetActionCooldown = function(slot)
	local at = ends[slot]
	if at and at > wow.now then return wow.now, at - wow.now, 1 end
	return 0, 0, 1
end

local function Pings()
	ns.PingDebug()
	return tonumber(wow.printed[#wow.printed]:match("(%d+) pings so far"))
end

local function Ping(button)
	for _, child in ipairs({ button:GetChildren() }) do
		if child.ring and child.group then return child end
	end
end

local function Start(saved)
	wow.login(saved or {})
	wow.advance(1)
end

test("a 35 s cooldown ending: one ping", function()
	Start()
	ends[1] = wow.now + 35
	wow.advance(36)
	eq(Pings(), 1)
	local f = Ping(ActionButton1)
	ok(f and f:IsShown(), "the ring on its button")
	wow.advance(5)
	eq(Pings(), 1, "never repeated")
end)

test("a short cooldown: no ping", function()
	Start()
	ends[1] = wow.now + 20
	wow.advance(22)
	eq(Pings(), 0)
end)

test("the global cooldown is never one", function()
	Start()
	for _ = 1, 30 do
		ends[1] = wow.now + 1.5
		wow.advance(1.6)
	end
	eq(Pings(), 0)
end)

test("barPingMin: how long counts as long", function()
	Start({ barPingMin = 10 })
	ends[1] = wow.now + 12
	wow.advance(13)
	eq(Pings(), 1)
end)

test("measured from when it was first seen (a cooldown already running at a reload may stay quiet)", function()
	ends[1] = wow.now + 40
	wow.advance(15) -- (running before Serene looked)
	Start()
	wow.advance(30)
	eq(Pings(), 0, "only seen for 26 s")
end)

test("another action put in the slot: its old cooldown forgotten", function()
	Start()
	ends[1] = wow.now + 35
	wow.advance(20)
	wow.put(1, "spell", 133)
	wow.fire("ACTIONBAR_SLOT_CHANGED", 1)
	wow.advance(20)
	eq(Pings(), 0)
end)

test("a cooldown not seen on its button at the end (the page turned away): no ping", function()
	Start()
	ends[1] = wow.now + 35
	wow.advance(20)
	MainMenuBar:Hide()
	wow.advance(16)
	MainMenuBar:Show()
	wow.advance(1)
	eq(Pings(), 0)
end)

test("switched off: nothing followed, nothing played", function()
	Start({ barPing = false })
	ends[1] = wow.now + 35
	wow.advance(36)
	eq(Pings(), 0)
end)

test("the button faint (its bar faded): the spell's icon shows with the ring", function()
	Start()
	ActionButton1.icon:SetTexture(135848)
	ends[1] = wow.now + 35
	wow.advance(30)
	MainMenuBar:SetAlpha(0.2)
	wow.advance(6)
	local f = Ping(ActionButton1)
	ok(f.icon:IsShown())
	eq(f.icon:GetTexture(), 135848)
end)

test("at full: the ring alone", function()
	Start()
	ends[1] = wow.now + 35
	wow.advance(36)
	no(Ping(ActionButton1).icon:IsShown())
end)

test("secret cooldowns in a fight: nothing made up, no error", function()
	Start()
	ends[1] = wow.now + 35
	wow.secretFight(true)
	wow.advance(36)
	wow.secretFight(false)
	eq(Pings(), 0)
	clean()
end)

test("/serene ping plays one on Action Bar 1 even while switched off", function()
	Start({ barPing = false })
	wow.slash("/serene ping")
	eq(Pings(), 1)
	eq(ns.db.barPing, false, "the setting as it was")
end)
