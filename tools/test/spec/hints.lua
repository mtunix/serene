-- Hints.lua: a gold glow on an action button worth pressing now (out of a fight): food when not Well Fed, what gives
-- a class buff that is missing; a faint one for a class buff running out.
-- The player here: a mage with food, Arcane Intellect and two armors on Action Bar 1.

local ns = wow.load({ "Core.lua", "Actions.lua", "Fade.lua", "Modes.lua", "Hints.lua" })

local FOOD, PLAIN_FOOD = 4599, 117
wow.player.class, wow.player.classFile = "Mage", "MAGE"
for id, name in pairs({ [1459] = "Arcane Intellect", [23028] = "Arcane Brilliance", [7302] = "Ice Armor",
	[6117] = "Mage Armor", [168] = "Frost Armor" }) do
	wow.spells[id] = { name = name, known = true }
end
wow.items[FOOD] = { name = "Cured Ham Steak", quality = 1, stack = 20, classID = 0 }
wow.items[PLAIN_FOOD] = { name = "Tough Jerky", quality = 1, stack = 20, classID = 0 }
wow.bags[0] = { size = 16, [1] = { id = FOOD, count = 5 }, [2] = { id = PLAIN_FOOD, count = 5 } }
wow.tooltipData["item:" .. FOOD] = { lines = { { leftText = "Cured Ham Steak" }, { leftText = "Use: Restores 1392 health "
	.. "over 30 sec. If you spend at least 10 seconds eating you will become well fed and gain 14 Stamina and Spirit." } } }
wow.tooltipData["item:" .. PLAIN_FOOD] = { lines = { { leftText = "Tough Jerky" },
	{ leftText = "Use: Restores 61 health over 18 sec." } } }
wow.actions = {
	[1] = { kind = "item", id = FOOD },
	[2] = { kind = "spell", id = 1459 },
	[3] = { kind = "spell", id = 7302 },
	[4] = { kind = "spell", id = 6117 },
	[5] = { kind = "item", id = PLAIN_FOOD },
}
-- (every mage spell can be cast)
IsUsableAction = function(slot) return wow.actions[slot] ~= nil, false end

local WHO = "Testrealm-Tester"

local function Lit()
	local set = {}
	for _, button in ipairs(ns.HintLook()) do set[button:GetName()] = true end
	return set
end

local function Buff(name, duration, left)
	return { name = name, duration = duration or 0, expirationTime = duration and duration > 0 and (wow.now + left) or 0 }
end

test("not Well Fed, an Arcane Intellect and an armor missing: the food, the intellect and the first armor glow", function()
	wow.login({})
	eq(Lit(), { ActionButton1 = true, ActionButton2 = true, ActionButton3 = true })
end)

test("Well Fed, or eating: no food glows", function()
	wow.login({})
	wow.player.buffs = { Buff("Well Fed", 900, 800) }
	eq(Lit().ActionButton1, nil)
	wow.player.buffs = { Buff("Food", 30, 20) }
	eq(Lit().ActionButton1, nil)
end)

test("food that doesn't make you Well Fed never glows", function()
	wow.login({})
	ok(Lit().ActionButton1)
	eq(Lit().ActionButton5, nil)
	eq(ns.MakesWellFed(PLAIN_FOOD), false)
	eq(ns.MakesWellFed(FOOD), true)
end)

test("an item whose tooltip isn't loaded yet: asked again later, not taken as plain", function()
	wow.login({})
	local saved = wow.tooltipData["item:" .. FOOD]
	wow.tooltipData["item:" .. FOOD] = nil
	eq(Lit().ActionButton1, nil, "not loaded: no glow")
	wow.tooltipData["item:" .. FOOD] = saved
	eq(Lit().ActionButton1, true, "loaded: it glows")
end)

test("food on the bar but none in the bags: no glow", function()
	wow.bags[0][1] = nil
	wow.login({})
	eq(Lit().ActionButton1, nil)
end)

test("the class buff on (or its bigger form): nothing glows for it", function()
	wow.login({})
	wow.player.buffs = { Buff("Arcane Intellect", 1800, 1700) }
	eq(Lit().ActionButton2, nil)
	wow.player.buffs = { Buff("Arcane Brilliance", 3600, 3000) }
	eq(Lit().ActionButton2, nil)
end)

test("an armor worn: none of them glows, and it is remembered for this character", function()
	wow.login({})
	wow.player.buffs = { Buff("Mage Armor", 1800, 1700) }
	local lit = Lit()
	eq(lit.ActionButton3, nil)
	eq(lit.ActionButton4, nil)
	eq(ns.db.hintLast[WHO], { ["7302"] = "mage armor" })
end)

test("the armor used last glows, not the first", function()
	wow.login({ hintLast = { [WHO] = { ["7302"] = "mage armor" } } })
	local lit = Lit()
	eq(lit.ActionButton3, nil)
	eq(lit.ActionButton4, true)
end)

test("another character's memory is its own", function()
	wow.login({ hintLast = { ["Testrealm-Other"] = { ["7302"] = "mage armor" } } })
	eq(Lit().ActionButton3, true)
end)

test("an armor cast is remembered (UNIT_SPELLCAST_SUCCEEDED)", function()
	wow.login({})
	wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 6117)
	eq(ns.db.hintLast[WHO]["7302"], "mage armor")
	wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 1459)
	eq(ns.db.hintLast[WHO]["1459"], nil, "a one-spell group needs no memory")
	wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", wow.secret(7302))
	eq(ns.db.hintLast[WHO]["7302"], "mage armor", "a secret spell id is ignored")
end)

test("a spell that can't be cast now doesn't glow", function()
	IsUsableAction = function(slot) return slot ~= 2, false end
	wow.login({})
	eq(Lit().ActionButton2, nil)
end)

test("a class buff running out (under 2 min of a long one): a faint glow, not the full one", function()
	wow.login({})
	wow.player.buffs = { Buff("Arcane Intellect", 1800, 60), Buff("Ice Armor", 1800, 1700) }
	eq(Lit().ActionButton2, nil)
	eq(ns.HintSoon(ActionButton2), true)
	wow.player.buffs = { Buff("Arcane Intellect", 1800, 200), Buff("Ice Armor", 1800, 1700) }
	Lit()
	eq(ns.HintSoon(ActionButton2), false, "200 s left: not yet")
end)

test("a buff no longer than the warning is never 'running out'", function()
	wow.login({})
	wow.player.buffs = { Buff("Arcane Intellect", 100, 10), Buff("Ice Armor", 1800, 1700) }
	Lit()
	eq(ns.HintSoon(ActionButton2), false)
end)

test("running out: its own threshold and switch", function()
	wow.login({ hintBuffSoonAt = 300 })
	wow.player.buffs = { Buff("Arcane Intellect", 1800, 200), Buff("Ice Armor", 1800, 1700) }
	Lit()
	eq(ns.HintSoon(ActionButton2), true)
	ns.db.hintBuffSoon = false
	Lit()
	eq(ns.HintSoon(ActionButton2), false)
end)

test("quiet: in a fight, dead, on a taxi, resting, or switched off", function()
	local cases = {
		{ function() wow.combat = true end, "in a fight" },
		{ function() wow.player.dead = true end, "dead" },
		{ function() wow.taxi = true end, "on a taxi" },
		{ function() ns.ModeNow = function() return "rest" end end, "rest mode" },
		{ function() ns.db.hints = false end, "hints off" },
	}
	for _, c in ipairs(cases) do
		wow.login({})
		c[1]()
		eq(Lit(), {}, c[2])
		wow.combat, wow.player.dead, wow.taxi = false, nil, nil
		ns.ModeNow = function() return nil end
		ns.db.hints = true
	end
end)

test("a fight puts out every glow at once", function()
	wow.login({})
	ok(next(Lit()))
	wow.fight(true)
	eq(ns.HintButtons(), {})
end)

test("mounted: no class buff glows, the food still does", function()
	wow.login({})
	wow.mounted = true
	eq(Lit(), { ActionButton1 = true })
end)

test("each rule has its switch", function()
	wow.login({ hintFood = false })
	eq(Lit(), { ActionButton2 = true, ActionButton3 = true })
	ns.db.hintFood, ns.db.hintBuffs = true, false
	eq(Lit(), { ActionButton1 = true })
end)

test("a class with no buffs to keep: only food", function()
	wow.player.class, wow.player.classFile = "Death Knight", "DEATHKNIGHT"
	wow.login({})
	eq(Lit(), { ActionButton1 = true })
end)

test("a class buff's spell names not all readable yet: no class glow until they are", function()
	wow.spells[168] = nil
	wow.login({})
	eq(Lit(), { ActionButton1 = true })
	wow.spells[168] = { name = "Frost Armor", known = true }
	eq(Lit(), { ActionButton1 = true, ActionButton2 = true, ActionButton3 = true })
end)

test("a rogue: the poisons on the bars glow while a weapon is bare", function()
	wow.player.class, wow.player.classFile = "Rogue", "ROGUE"
	wow.items[2207] = { name = "Jambiya", classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPON" }
	wow.items[6947] = { name = "Instant Poison", classID = 0, stack = 20 }
	wow.equipped = { [16] = { id = 2207 }, [17] = { id = 2207 } }
	wow.bags[0][3] = { id = 6947, count = 10 }
	wow.actions = { [6] = { kind = "item", id = 6947 } }
	wow.login({})
	eq(Lit(), { ActionButton6 = true })
	GetWeaponEnchantInfo = function() return true, 1800000, 1, 0, false end
	eq(Lit(), { ActionButton6 = true }, "the off hand still bare")
	GetWeaponEnchantInfo = function() return true, 1800000, 1, 0, true, 1800000, 1, 0 end
	eq(Lit(), {}, "both coated")
	GetWeaponEnchantInfo = function() return true, 60000, 1, 0, true, 1800000, 1, 0 end
	Lit()
	eq(ns.HintSoon(ActionButton6), true, "a minute of poison left: faint")
end)

test("a fishing pole is not a bare weapon", function()
	wow.player.class, wow.player.classFile = "Rogue", "ROGUE"
	wow.items[6256] = { name = "Fishing Pole", classID = 2, subclassID = 20 }
	wow.items[6947] = { name = "Instant Poison", classID = 0, stack = 20 }
	wow.equipped = { [16] = { id = 6256 } }
	wow.bags[0][3] = { id = 6947, count = 10 }
	wow.actions = { [6] = { kind = "item", id = 6947 } }
	wow.login({})
	eq(Lit(), {})
end)

-- What comes back with a glow (hintReveal) --------------------------------------------------------------------------

test("hintReveal 'button': the lit button alone shows through its bar's fade", function()
	wow.login({ hintReveal = "button" })
	Lit()
	eq(wow.state(ActionButton1).ignoreParentAlpha, true)
	eq(wow.state(ActionButton7).ignoreParentAlpha, nil)
	no(ns.HintRevealBars())
end)

test("hintReveal 'bar': its whole bar", function()
	wow.login({ hintReveal = "bar" })
	Lit()
	eq(wow.state(ActionButton12).ignoreParentAlpha, true)
	eq(wow.state(MultiBarLeftButton1).ignoreParentAlpha, nil)
end)

test("hintReveal 'bars': every bar (through Fade); 'none': nothing", function()
	wow.login({ hintReveal = "bars" })
	Lit()
	ok(ns.HintRevealBars())
	eq(wow.state(ActionButton1).ignoreParentAlpha, nil)
	ns.db.hintReveal = "none"
	no(ns.HintRevealBars())
end)

test("a button no longer lit is given back to its bar", function()
	wow.login({ hintReveal = "button" })
	Lit()
	wow.player.buffs = { Buff("Well Fed", 900, 800) }
	Lit()
	eq(wow.state(ActionButton1).ignoreParentAlpha, false)
end)

-- For the buff frame ---------------------------------------------------------------------------------------------------

test("MissingClassBuffs: what is missing, with the spell to cast it", function()
	wow.login({})
	local missing = ns.MissingClassBuffs()
	eq(#missing, 2)
	eq(missing[1].name, "Arcane Intellect")
	eq(missing[1].spell, "Arcane Intellect")
	eq(missing[2].name, "Ice Armor", "the first armor known")
	ns.db.hintLast[WHO] = { ["7302"] = "frost armor" }
	eq(ns.MissingClassBuffs()[2].name, "Frost Armor", "the one used last")
end)

test("MissingClassBuffs: nothing while mounted or dead; unknown (nil) when your buffs can't be read", function()
	wow.login({})
	wow.mounted = true
	eq(ns.MissingClassBuffs(), {})
	wow.mounted = false
	wow.player.dead = true
	eq(ns.MissingClassBuffs(), {})
	wow.player.dead = nil
	wow.secretFight(true)
	eq(ns.MissingClassBuffs(), nil, "in a fight the game answers nothing: that is not 'no buffs'")
	wow.secretFight(false)
	clean()
end)

test("/serene debug's lines for Hints run", function()
	wow.login({})
	ns.HintDebug()
	clean()
end)
