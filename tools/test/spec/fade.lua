-- Fade.lua: each group of the interface fades away when calm and comes back when needed. Time is moved by hand and
-- ns.FadeStep run as the game's frames would (Look, then Fade), so the numbers are exact.
-- Groups (in the stub): bars = MainMenuBar, MultiBarBottomLeft/Right, MainMenuBarArtFrame; bar4 = MultiBarRight;
-- bar5 = MultiBarLeft; unit = PlayerFrame, PetFrame; buffs = BuffFrame; debuffs = DebuffFrame; minimap = MinimapCluster.

local ns = wow.load({ "Core.lua", "Fade.lua" })

-- (a quiet player: rage at nothing, full health, nothing targeted)
wow.player.power, wow.player.powerType = 0, 1

local function Run(seconds)
	local steps = math.floor(seconds / 0.05 + 0.5)
	for _ = 1, steps do
		wow.now = wow.now + 0.05
		ns.FadeStep(0.05)
	end
end

local function near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 0.03 then
		error((what and (what .. ": ") or "") .. "expected about " .. expected .. ", got " .. tostring(actual), 2)
	end
end

local function Login(saved)
	wow.login(saved or {})
	ns.FadeStep(0)
end

-- Faded away: logged in, then left alone for a while.
local function Calm(saved)
	Login(saved)
	Run(3)
end

-- One step of a fade --------------------------------------------------------------------------------------------------

test("ns.Approach: one step of a fade, never past its target", function()
	local cases = {
		-- current, target, elapsed, in, out -> result
		{ 0, 1, 0.125, 0.25, 0.9, 0.5 },
		{ 1, 0, 0.45, 0.25, 0.9, 0.5 },
		{ 0.9, 1, 1, 0.25, 0.9, 1 },   -- (never past the target, coming)
		{ 0.1, 0, 1, 0.25, 0.9, 0 },   -- (nor going)
		{ 0.3, 0.3, 1, 0.25, 0.9, 0.3 },
		{ 0, 1, 0.0001, 0, 0, 0.1 },   -- (a zero length: a thousandth of a second)
		{ 1, 0.4, 0.45, 0.25, 0.9, 0.5 },
		{ 0.2, 0.4, 0.05, 0.25, 0.9, 0.4 },
		{ 0.5, 1, nil, 0.25, 0.9, 0.5 }, -- (no elapsed time: no step)
	}
	for _, c in ipairs(cases) do
		near(ns.Approach(c[1], c[2], c[3], c[4], c[5]), c[6], table.concat({ c[1], c[2], tostring(c[3]) }, " "))
	end
end)

-- At rest ------------------------------------------------------------------------------------------------------------

test("the bars stay 1.5 s after login, then fade out over 0.9 s", function()
	Login()
	Run(1.4)
	eq(MainMenuBar:GetAlpha(), 1, "lingering")
	Run(0.55)
	near(MainMenuBar:GetAlpha(), 0.5, "halfway out")
	Run(0.5)
	eq(MainMenuBar:GetAlpha(), 0)
	eq(MultiBarBottomLeft:GetAlpha(), 0, "the whole group")
	eq(PlayerFrame:GetAlpha(), 0)
	eq(BuffFrame:GetAlpha(), 0)
end)

test("the rest setting: a faded part stays this visible", function()
	Calm({ rest = 40 })
	near(MainMenuBar:GetAlpha(), 0.4)
	near(PlayerFrame:GetAlpha(), 0.4)
end)

test("frames inside another faded frame are left to it (never faded twice)", function()
	local inner = CreateFrame("Frame", "MultiBar5", MainMenuBar)
	Calm()
	eq(inner:GetAlpha(), 1, "its parent's opacity does it")
	eq(MainMenuBar:GetAlpha(), 0)
end)

-- What brings them back ---------------------------------------------------------------------------------------------

test("a fight brings back bars, portrait, buffs, debuffs at once, and they stay 3 s + 1.5 s after", function()
	Calm()
	wow.fight(true)
	ns.FadeStep(0)
	Run(0.15)
	near(MainMenuBar:GetAlpha(), 0.6, "coming in over 0.25 s")
	Run(0.15)
	for _, f in ipairs({ MainMenuBar, PlayerFrame, BuffFrame, DebuffFrame }) do eq(f:GetAlpha(), 1, f:GetName()) end
	eq(MultiBarRight:GetAlpha(), 0, "Action Bar 4 only under the mouse")
	wow.fight(false)
	Run(4.4)
	eq(MainMenuBar:GetAlpha(), 1, "still there 4.4 s after")
	Run(1.2)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("an enemy targeted: the bars, the portrait and the buffs", function()
	Calm()
	wow.units.target = { name = "Thug", enemy = true }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(PlayerFrame:GetAlpha(), 1)
	eq(BuffFrame:GetAlpha(), 1)
	eq(DebuffFrame:GetAlpha(), 1)
	eq(MultiBarRight:GetAlpha(), 0)
end)

test("a friend targeted: the portrait and the buffs, not the bars", function()
	Calm()
	wow.units.target = { name = "Friend" }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 0)
	eq(PlayerFrame:GetAlpha(), 1)
	eq(BuffFrame:GetAlpha(), 1)
end)

test("a dead enemy targeted: not the bars", function()
	Calm()
	wow.units.target = { name = "Corpse", enemy = true, dead = true }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("an enemy whose 'can attack' is secret counts as an enemy", function()
	Calm()
	wow.units.target = { name = "Thug" }
	UnitCanAttack = function() return wow.secret(false) end
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
end)

test("casting, channelling, or something on the cursor: the bars", function()
	Calm()
	wow.player.casting = { "Fireball" }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	wow.player.casting = nil
	Run(3)
	eq(MainMenuBar:GetAlpha(), 0)
	wow.player.channel = { "Drink" }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	wow.player.channel = nil
	Run(3)
	wow.cursor = { "spell", 133 }
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
end)

test("the mouse over any part of a group brings the whole group back", function()
	Calm()
	wow.hover(MultiBarBottomLeft)
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(MultiBarBottomLeft:GetAlpha(), 1)
	eq(PlayerFrame:GetAlpha(), 0, "other groups stay away")
	wow.hover(nil)
	Run(1.4)
	eq(MainMenuBar:GetAlpha(), 1, "lingers 1.5 s")
	Run(1.2)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("the mouse over a hidden frame is not over it", function()
	Calm()
	MultiBarBottomLeft:Hide()
	wow.hover(MultiBarBottomLeft)
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("Action Bars 4 and 5: only under the mouse, each on its own, free of their parent's opacity", function()
	Calm()
	eq(wow.state(MultiBarRight).ignoreParentAlpha, true)
	eq(wow.state(MultiBarLeft).ignoreParentAlpha, true)
	wow.hover(MultiBarRight)
	Run(0.3)
	eq(MultiBarRight:GetAlpha(), 1)
	eq(MultiBarLeft:GetAlpha(), 0)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("buffs and debuffs come back together under the mouse", function()
	Calm()
	wow.hover(DebuffFrame)
	Run(0.3)
	eq(BuffFrame:GetAlpha(), 1)
	eq(DebuffFrame:GetAlpha(), 1)
end)

test("your portrait: hurt, your pet hurt, mana not full, rage held", function()
	local cases = {
		{ function() wow.player.health = 60 end, "hurt" },
		{ function() wow.units.pet = { name = "Wolf", health = 10 } end, "the pet hurt" },
		{ function() wow.player.powerType, wow.player.power = 0, 50 end, "mana not full" },
		{ function() wow.player.powerType, wow.player.power = 3, 80 end, "energy not full" },
		{ function() wow.player.power = 10 end, "rage held" },
	}
	for _, c in ipairs(cases) do
		Calm()
		eq(PlayerFrame:GetAlpha(), 0)
		c[1]()
		Run(0.3)
		eq(PlayerFrame:GetAlpha(), 1, c[2])
		wow.player.health, wow.player.power, wow.player.powerType, wow.units.pet = 100, 0, 1, nil
		Run(3)
	end
end)

test("your portrait at rest: full mana, no rage", function()
	wow.player.powerType, wow.player.power = 0, 100
	Calm()
	eq(PlayerFrame:GetAlpha(), 0)
end)

test("secret health or power is never taken as hurt or tired", function()
	Calm()
	UnitHealth = function() return wow.secret(10) end
	UnitPower = function() return wow.secret(10) end
	Run(0.3)
	eq(PlayerFrame:GetAlpha(), 0)
	clean()
end)

test("a heal or a blow on you shows your portrait for 3 s; mana given does not", function()
	Calm()
	wow.fire("UNIT_COMBAT", "player", "ENERGIZE", "", 10, 0)
	Run(0.3)
	eq(PlayerFrame:GetAlpha(), 0, "energize is not a heal")
	wow.fire("UNIT_COMBAT", "target", "WOUND", "", 10, 0)
	Run(0.3)
	eq(PlayerFrame:GetAlpha(), 0, "a blow on someone else")
	wow.fire("UNIT_COMBAT", "player", "HEAL", "", 10, 0)
	Run(0.3)
	eq(PlayerFrame:GetAlpha(), 1)
	Run(4)
	eq(PlayerFrame:GetAlpha(), 1, "3 s + lingering 1.5 s")
	Run(1.2)
	eq(PlayerFrame:GetAlpha(), 0)
end)

test("a short debuff on you brings the buffs; long or lasting ones don't", function()
	local cases = { { 30, 1 }, { 120, 1 }, { 600, 0 }, { 0, 0 } }
	for _, c in ipairs(cases) do
		wow.player.debuffs = nil
		Calm()
		wow.player.debuffs = { { name = "Poison", duration = c[1], expirationTime = wow.now + c[1] } }
		Run(0.3)
		eq(BuffFrame:GetAlpha(), c[2], "a debuff of " .. c[1] .. " s: buffs")
		eq(DebuffFrame:GetAlpha(), c[2], "a debuff of " .. c[1] .. " s: debuffs")
	end
end)

test("the Welcoming Campfire keeps the buffs (not the debuffs)", function()
	Calm()
	wow.player.buffs = { { name = "Welcoming Campfire", duration = 0 } }
	Run(0.3)
	eq(BuffFrame:GetAlpha(), 1)
	eq(DebuffFrame:GetAlpha(), 0)
end)

-- Everything at once ----------------------------------------------------------------------------------------------------

test("the peek key: everything while it is held", function()
	Calm()
	Serene_Peek("down")
	ok(ns.IsPeeking())
	Run(0.3)
	for _, f in ipairs({ MainMenuBar, MultiBarRight, MultiBarLeft, PlayerFrame, BuffFrame, DebuffFrame }) do
		eq(f:GetAlpha(), 1, f:GetName())
	end
	Serene_Peek("up")
	no(ns.IsPeeking())
	Run(3)
	eq(MainMenuBar:GetAlpha(), 0)
end)

test("Edit Mode open: everything", function()
	Calm()
	EditModeManagerFrame.IsEditModeActive = function() return true end
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(MultiBarLeft:GetAlpha(), 1)
	eq(PlayerFrame:GetAlpha(), 1)
end)

test("a hint asking for every bar brings Action Bars 4 and 5 too", function()
	Calm()
	ns.HintRevealBars = function() return true end
	Run(0.3)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(MultiBarRight:GetAlpha(), 1)
	eq(PlayerFrame:GetAlpha(), 0)
end)

-- Switched off ---------------------------------------------------------------------------------------------------------

test("a group switched off is given back at full at once; Action Bars 4/5 follow the bars' switch", function()
	Calm()
	ns.db.groups.bars = false
	ns.FadeStep(0)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(MultiBarRight:GetAlpha(), 1)
	eq(PlayerFrame:GetAlpha(), 0)
	Run(5)
	eq(MainMenuBar:GetAlpha(), 1, "and stays")
end)

test("debuffs follow the buffs' switch", function()
	Calm({ groups = { buffs = false } })
	eq(BuffFrame:GetAlpha(), 1)
	eq(DebuffFrame:GetAlpha(), 1)
end)

test("fading off: everything at full", function()
	Calm()
	ns.db.fade = false
	ns.FadeStep(0)
	for _, f in ipairs({ MainMenuBar, MultiBarRight, PlayerFrame, BuffFrame, DebuffFrame, MinimapCluster }) do
		eq(f:GetAlpha(), 1, f:GetName())
	end
end)

test("the menu: left alone while Serene's menu words are on", function()
	Calm()
	eq(MicroMenu:GetAlpha(), 1, "menuBar on: MenuBar.lua keeps the game's menu out of sight, not Fade")
end)

test("the menu with Serene's words off: under the mouse only", function()
	Calm({ menuBar = false })
	eq(MicroMenu:GetAlpha(), 0)
	wow.hover(MicroMenu)
	Run(0.3)
	eq(MicroMenu:GetAlpha(), 1)
end)

-- The compass -----------------------------------------------------------------------------------------------------------

test("the compass is never half seen: its frame shown or away, the map hidden while away", function()
	Login()
	local seen = {}
	for _ = 1, 80 do
		Run(0.05)
		seen[MinimapCluster:GetAlpha()] = true
	end
	eq(seen, { [0] = true, [1] = true }, "only 0 and 1 along the way")
	eq(MinimapCluster:GetAlpha(), 0)
	eq(Minimap:IsShown(), false, "the map hidden (the engine draws its dots whatever the opacity)")
	ns.db.fade = false
	ns.FadeStep(0)
	eq(MinimapCluster:GetAlpha(), 1)
	eq(Minimap:IsShown(), true, "given back when switched off")
end)

test("the compass 'world': always out in the world, under the mouse only when resting", function()
	Calm({ compass = "world" })
	eq(MinimapCluster:GetAlpha(), 1)
	wow.resting = true
	Run(3)
	eq(MinimapCluster:GetAlpha(), 0)
	wow.hover(MinimapCluster)
	Run(1)
	eq(MinimapCluster:GetAlpha(), 1)
	eq(Minimap:IsShown(), true)
end)

test("the compass comes back when the minimap says it is open", function()
	Calm()
	ns.CompassOpen = function() return true end
	Run(1)
	eq(MinimapCluster:GetAlpha(), 1)
end)

test("fading in a fight with secret values: no errors, the fighting groups shown", function()
	Calm()
	wow.units.target = { name = "Thug", enemy = true, health = 50 }
	wow.player.debuffs = { { name = "Rend", duration = 15, expirationTime = wow.now + 10 } }
	wow.secretFight(true)
	Run(1)
	eq(MainMenuBar:GetAlpha(), 1)
	eq(BuffFrame:GetAlpha(), 1)
	wow.secretFight(false)
	clean()
end)

test("/serene debug's lines for Fade run", function()
	Calm()
	ns.FadeDebug()
	ns.FadeTopDebug()
	clean()
	ok(#wow.printed > 5)
end)
