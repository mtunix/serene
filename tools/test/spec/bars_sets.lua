-- BarSets.lua: a copy of your bars kept. Three or more actions gone at once by themselves (a talent reset), or a
-- spell unlearnt: a button to put them back, the unlearnt ones as you learn them again. Named sets saved and put on.

dofile(wow.root .. "/tools/test/spec/lib/actions_world.lua")
local ns = wow.load({ "Core.lua", "Actions.lua", "BarSets.lua" })

local WHO = "Testrealm-Tester"
for id, name in pairs({ [133] = "Fireball", [116] = "Frostbolt", [2136] = "Fire Blast", [122] = "Frost Nova",
	[11366] = "Pyroblast" }) do
	wow.spells[id] = { name = name, known = true }
end
wow.items[159] = { name = "Refreshing Spring Water", stack = 20 }
wow.macroList = { [1] = "Burst" }
wow.put(1, "spell", 133)
wow.put(2, "spell", 116)
wow.put(3, "spell", 2136)
wow.put(4, "spell", 122)
wow.put(5, "item", 159)
wow.put(6, "macro", 1, "Burst")
wow.put(7, "spell", 11366)

local function Start(saved)
	wow.login(saved or {})
	wow.advance(4) -- (the bars read whole 3 s in)
end

local function Remove(...)
	for _, slot in ipairs({ ... }) do
		wow.actions[slot] = nil
		wow.fire("ACTIONBAR_SLOT_CHANGED", slot)
	end
	wow.advance(1.5)
end

local function Pill() return SereneBarSetsButton end
local function Last() return wow.printed[#wow.printed] end
local function Ids()
	local out = {}
	for slot = 1, 8 do out[slot] = wow.actions[slot] and wow.actions[slot].id or false end
	return out
end

test("the copy: every slot read 3 s after entering the world", function()
	Start()
	local store = ns.db.barSetsBy[WHO]
	eq(store.copy[1], { kind = "spell", id = 133 })
	eq(store.copy[5], { kind = "item", id = 159 })
	eq(store.copy[6], { kind = "macro", id = 1, name = "Burst" }, "a macro by its name")
end)

test("three gone at once by themselves: a button to put them back", function()
	Start()
	Remove(1, 2, 3)
	eq(ns.BarSetsLost(), 3)
	ok(Pill():IsShown())
	eq(Pill().text:GetText(), "3 actions left your bars: put them back")
end)

test("two gone by your hand (still known): yours, nothing kept", function()
	Start()
	Remove(1, 2)
	eq(ns.BarSetsLost(), 0)
	no(Pill():IsShown())
	eq(ns.db.barSetsBy[WHO].copy[1], nil, "the copy follows")
end)

test("one gone whose spell was unlearnt: kept for later", function()
	Start()
	wow.spells[11366].known = false
	Remove(7)
	eq(ns.BarSetsLost(), 1)
	eq(Pill().text:GetText(), "An action left your bars: put it back")
end)

test("a click puts back what can be put back, into its own slot", function()
	Start()
	Remove(1, 2, 3)
	Pill():Click("LeftButton")
	wow.advance(2)
	eq(Ids(), { 133, 116, 2136, 122, 159, 1, 11366, false })
	eq(Last(), "|cff9ad0c2Serene|r: bars: 3 back in their place")
	eq(ns.BarSetsLost(), 0)
	no(Pill():IsShown())
end)

test("a slot you used since is yours: never replaced", function()
	Start()
	Remove(1, 2, 3)
	wow.put(1, "spell", 122)
	Pill():Click("LeftButton")
	wow.advance(2)
	eq(wow.actions[1].id, 122)
	eq(wow.actions[2].id, 116)
end)

test("spells not learnt again yet wait, and come back by themselves as they are learnt", function()
	Start()
	wow.spells[133].known, wow.spells[116].known = false, false
	Remove(1, 2, 3)
	Pill():Click("LeftButton")
	wow.advance(2)
	eq(Ids()[3], 2136, "Fire Blast back now")
	eq(Ids()[1], false)
	eq(Pill().text:GetText(), "2 actions wait for their spells")
	wow.spells[133].known = true
	wow.fire("LEARNED_SPELL_IN_TAB", 133, 1)
	wow.advance(3)
	eq(Ids()[1], 133)
	eq(Last(), "|cff9ad0c2Serene|r: bars: 1 back in their place (learnt again)")
	eq(Pill().text:GetText(), "1 action waits for its spell")
end)

test("right-click: forget them", function()
	Start()
	Remove(1, 2, 3)
	Pill():Click("RightButton")
	eq(ns.BarSetsLost(), 0)
	no(Pill():IsShown())
end)

test("not in a fight: put back after it", function()
	Start()
	Remove(1, 2, 3)
	wow.fight(true)
	no(Pill():IsShown(), "hidden in a fight")
	ns.BarSetsRestore()
	eq(wow.actions[1], nil)
	wow.fight(false)
	ok(Pill():IsShown())
end)

test("switched off for a while: the bars then are the copy, nothing taken as lost", function()
	Start()
	ns.db.barSets = false
	ns.modules[#ns.modules].refresh() -- (BarSets: the last module loaded here)
	Remove(1, 2, 3)
	ns.db.barSets = true
	ns.modules[#ns.modules].refresh()
	wow.advance(2)
	eq(ns.BarSetsLost(), 0)
	eq(ns.db.barSetsBy[WHO].copy[1], nil)
end)

test("an empty read (bars not loaded yet) is not a wipe", function()
	Start()
	local saved = wow.actions
	wow.actions = {}
	wow.fire("ACTIONBAR_SLOT_CHANGED", 1)
	wow.advance(1.5)
	eq(ns.BarSetsLost(), 0)
	eq(ns.db.barSetsBy[WHO].copy[1], { kind = "spell", id = 133 })
	wow.actions = saved
end)

test("Serene's own changes (BarUse's clear) are not taken as actions leaving", function()
	Start()
	ns.BarSetsMine(function()
		PickupAction(1) ClearCursor()
		PickupAction(2) ClearCursor()
		PickupAction(3) ClearCursor()
	end)
	wow.advance(3)
	eq(ns.BarSetsLost(), 0)
	eq(ns.db.barSetsBy[WHO].copy[1], nil, "the copy taken once done")
end)

-- Sets -----------------------------------------------------------------------------------------------------------------

test("a set saved, the bars changed, the set put on: exactly as saved", function()
	Start()
	wow.slash("/serene sets save solo")
	eq(Last(), "|cff9ad0c2Serene|r: bars saved as \"solo\" (7 actions)")
	ok(ns.BarSetHas("solo"))
	wow.actions[1] = nil
	wow.put(2, "spell", 133)
	wow.put(8, "spell", 122)
	wow.slash("/serene sets load solo")
	wow.advance(2)
	eq(Ids(), { 133, 116, 2136, 122, 159, 1, 11366, false })
	eq(Last(), "|cff9ad0c2Serene|r: bars: \"solo\" put on")
	ok(ns.BarSetHas("undo"), "the bars before saved as undo")
	eq(ns.db.barSetsBy[WHO].sets.undo[8], { kind = "spell", id = 122 })
end)

test("putting on a set: what can't be placed is said", function()
	Start()
	ns.BarSetSave("raid")
	wow.actions = {}
	wow.spells[11366].known = false
	wow.macroList = {}
	ns.BarSetLoad("raid")
	ok(Last():find("not placed: ", 1, true), Last())
	ok(Last():find("Pyroblast", 1, true))
	ok(Last():find("Burst", 1, true))
	eq(wow.actions[1].id, 133)
end)

test("not in a fight, not with something held, not a set that doesn't exist", function()
	Start()
	ns.BarSetSave("a")
	ns.BarSetLoad("nope")
	eq(Last(), "|cff9ad0c2Serene|r: no set called \"nope\" (/serene sets)")
	wow.held = { kind = "item", id = 159 }
	ns.BarSetLoad("a")
	eq(Last(), "|cff9ad0c2Serene|r: bars: put down what you hold first")
	wow.held = nil
	wow.combat = true
	ns.BarSetLoad("a")
	eq(Last(), "|cff9ad0c2Serene|r: bars: not in a fight")
end)

test("sets listed and deleted", function()
	Start()
	ns.BarSetSave("solo")
	ns.BarSetSave("raid")
	ns.BarSetList()
	eq(Last(), "|cff9ad0c2Serene|r: sets: raid (7), solo (7)  -  /serene sets save|load|delete <name>")
	wow.slash("/serene sets delete solo")
	no(ns.BarSetHas("solo"))
	ns.BarSetDelete("solo")
	eq(Last(), "|cff9ad0c2Serene|r: no set called \"solo\"")
end)

test("each character its own sets", function()
	Start({ barSetsBy = { ["Testrealm-Alt"] = { copy = {}, sets = { alt = {} } } } })
	no(ns.BarSetHas("alt"))
end)

test("putting on a set with fewer actions: the ones it clears are not taken as leaving by themselves", function()
	wow.actions = {}
	wow.put(1, "spell", 133)
	wow.put(2, "spell", 116)
	wow.put(3, "spell", 2136)
	wow.put(4, "spell", 122)
	Start()
	ns.db.barSetsBy[WHO].sets.small = { [1] = { kind = "spell", id = 133 } }
	ns.BarSetLoad("small")
	wow.advance(3)
	eq(Ids(), { 133, false, false, false, false, false, false, false })
	eq(ns.BarSetsLost(), 0, "Serene cleared them: nothing to put back")
	no(Pill():IsShown())
end)
