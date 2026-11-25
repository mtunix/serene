-- Ranks.lua: a spell's new rank onto the buttons holding the rank that was the highest; Reagents.lua: casts left of a
-- reagent spell, amber when low, a word at a merchant who sells the reagent.

dofile(wow.root .. "/tools/test/spec/lib/actions_world.lua")
local ns = wow.load({ "Core.lua", "Actions.lua", "Ranks.lua", "Reagents.lua" })

local WHO = "Testrealm-Tester"

-- Fireball rank 1 (133), rank 2 (143), rank 3 (145); Frostbolt (116).
local function Book(fireball)
	wow.book = { { id = fireball, name = "Fireball" }, { id = 116, name = "Frostbolt" } }
	for _, id in ipairs({ 133, 143, 145, 116 }) do wow.spells[id] = { name = id == 116 and "Frostbolt" or "Fireball", known = true } end
end

local function Learn(fireball)
	Book(fireball)
	wow.fire("LEARNED_SPELL_IN_TAB", fireball, 1)
	wow.advance(1)
end

-- Ranks ------------------------------------------------------------------------------------------------------------------

test("the first look only learns your highest ranks; nothing moves", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.login({})
	wow.advance(4)
	eq(ns.db.ranks[WHO].seen, { Fireball = 133, Frostbolt = 116 })
	eq(wow.actions[1].id, 133)
end)

test("a new rank goes onto every button holding the old highest, by itself", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.put(13, "spell", 133) -- (another page)
	wow.put(2, "spell", 116)
	wow.login({})
	wow.advance(4)
	Learn(143)
	eq(wow.actions[1].id, 143)
	eq(wow.actions[13].id, 143)
	eq(wow.actions[2].id, 116, "other spells left alone")
	eq(wow.printed[#wow.printed], "|cff9ad0c2Serene|r: new rank on your bars: Fireball")
	eq(ns.db.ranks[WHO].pending, {})
	clean()
end)

test("a lower rank kept on purpose is never touched", function()
	Book(143)
	wow.put(1, "spell", 143)
	wow.put(2, "spell", 133) -- (rank 1, kept for its mana)
	wow.login({})
	wow.advance(4)
	Learn(145)
	eq(wow.actions[1].id, 145)
	eq(wow.actions[2].id, 133)
end)

test("ranks learnt while Serene was off are seen at the next login", function()
	Book(143)
	wow.put(1, "spell", 133)
	wow.login({ ranks = { [WHO] = { seen = { Fireball = 133, Frostbolt = 116 }, pending = {} } } })
	wow.advance(4)
	eq(wow.actions[1].id, 143)
end)

test("not by itself: a mark on the button and a quiet button to do it", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.login({ barRanksAuto = false })
	wow.advance(4)
	Learn(143)
	eq(wow.actions[1].id, 133, "not changed")
	local pill = SereneRankButton
	ok(pill and pill:IsShown(), "the button shown")
	eq(pill.text:GetText(), "A new rank: put it on your bars")
	pill:Click()
	eq(wow.actions[1].id, 143)
	no(pill:IsShown())
end)

test("several spells: the button says how many", function()
	Book(133)
	wow.book[2].id = 116
	wow.spells[205] = { name = "Frostbolt", known = true }
	wow.put(1, "spell", 133)
	wow.put(2, "spell", 116)
	wow.login({ barRanksAuto = false })
	wow.advance(4)
	Book(143)
	wow.book[2].id = 205
	wow.fire("SPELLS_CHANGED")
	wow.advance(1)
	eq(SereneRankButton.text:GetText(), "New ranks for 2 spells: put them on your bars")
end)

test("in a fight: after it", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.login({})
	wow.advance(4)
	wow.fight(true)
	Learn(143)
	eq(wow.actions[1].id, 133, "not in a fight")
	wow.fight(false)
	wow.advance(1)
	eq(wow.actions[1].id, 143)
end)

test("something held on the cursor is left alone, tried again later", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.login({})
	wow.advance(4)
	Book(143)
	wow.held = { kind = "item", id = 159 }
	wow.fire("SPELLS_CHANGED")
	wow.advance(1)
	eq(wow.actions[1].id, 133)
	eq(wow.held.id, 159, "yours, still held")
	wow.held = nil
	wow.advance(3)
	eq(wow.actions[1].id, 143)
end)

test("switched off: nothing waits, nothing moves", function()
	Book(133)
	wow.put(1, "spell", 133)
	wow.login({ barRanks = false })
	wow.advance(4)
	Learn(143)
	eq(wow.actions[1].id, 133)
end)

test("a low rank the spellbook marks as such, or a passive, is never a 'highest'", function()
	wow.book = { { id = 133, name = "Fireball", lowRank = true }, { id = 999, name = "Passive Thing", passive = true } }
	wow.login({})
	wow.advance(4)
	eq(ns.db.ranks[WHO].seen, {})
end)

-- Reagents ---------------------------------------------------------------------------------------------------------------

local function Teleport(casts)
	wow.spells[3561] = { name = "Teleport: Stormwind", known = true }
	wow.put(1, "spell", 3561)
	C_Spell.IsConsumableSpell = function(id) return id == 3561 end
	GetActionCount = function(slot) return slot == 1 and casts or 0 end
	wow.tooltipData["action:1"] = { lines = { { leftText = "Teleport: Stormwind" },
		{ leftText = "Reagents: |cffffffffRune of Teleportation|r" } } }
end

local function Color(button)
	local r, g, b = button.Count:GetTextColor()
	return { math.floor(r * 100 + 0.5) / 100, math.floor(g * 100 + 0.5) / 100, math.floor(b * 100 + 0.5) / 100 }
end

test("casts left at the warning or fewer: amber; none left: soft red; more: as the game draws it", function()
	local cases = { { 5, { 0.98, 0.62, 0.3 } }, { 1, { 0.98, 0.62, 0.3 } }, { 0, { 0.95, 0.42, 0.38 } } }
	for _, c in ipairs(cases) do
		Teleport(c[1])
		wow.login({})
		wow.advance(1)
		eq(Color(ActionButton1), c[2], c[1] .. " casts left")
	end
end)

test("more than the warning: the count never coloured", function()
	Teleport(6)
	wow.login({})
	wow.advance(1)
	eq(wow.state(ActionButton1.Count).textColor, nil)
	eq(ns.ReagentLow("Rune of Teleportation"), nil)
end)

test("no longer low: given back its soft white", function()
	Teleport(2)
	wow.login({})
	wow.advance(1)
	Teleport(20)
	wow.fire("BAG_UPDATE_DELAYED")
	wow.advance(1)
	eq(Color(ActionButton1), { 0.91, 0.89, 0.86 })
end)

test("the warning's threshold is a setting", function()
	Teleport(8)
	wow.login({ barReagentLow = 10 })
	wow.advance(1)
	eq(ns.ReagentLow("Rune of Teleportation"), 8)
end)

test("the reagent's name read from the tooltip, for the merchant", function()
	Teleport(3)
	wow.login({})
	wow.advance(1)
	eq(ns.ReagentLow("Rune of Teleportation"), 3)
	eq(ns.ReagentLow("Something Else"), nil)
	ns.db.barReagents = false
	eq(ns.ReagentLow("Rune of Teleportation"), nil, "switched off")
end)

test("at a merchant who sells it: one quiet line", function()
	Teleport(3)
	wow.items[17031] = { name = "Rune of Teleportation", stack = 20 }
	wow.merchant.items = { { id = 17031, price = 1000 } }
	wow.login({})
	wow.advance(1)
	wow.fire("MERCHANT_SHOW")
	eq(wow.printed[#wow.printed], "|cff9ad0c2Serene|r: running low, sold here: Rune of Teleportation (3 left)")
end)

test("not a reagent spell: nothing", function()
	wow.spells[133] = { name = "Fireball", known = true }
	wow.put(1, "spell", 133)
	GetActionCount = function() return 0 end
	wow.login({})
	wow.advance(1)
	eq(wow.state(ActionButton1.Count).textColor, nil)
end)

test("in a fight counts aren't read; the last known stays", function()
	Teleport(3)
	wow.login({})
	wow.advance(1)
	wow.fight(true)
	GetActionCount = function() return wow.secret(9) end
	wow.fire("SPELL_UPDATE_USES")
	wow.advance(1)
	eq(ns.ReagentLow("Rune of Teleportation"), 3)
	clean()
end)
