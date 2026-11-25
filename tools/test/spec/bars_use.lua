-- BarKeys.lua (keys that teach: bright while you still click, away once known) and BarUse.lua (presses counted per
-- slot in hours of play: unused buttons, easier keys).

dofile(wow.root .. "/tools/test/spec/lib/actions_world.lua")
function TryUseActionButton(button, down) end -- (the game's key bindings press a button through this)
local ns = wow.load({ "Core.lua", "Actions.lua", "ActionBars.lua", "BarKeys.lua", "BarSets.lua", "BarUse.lua" })

local WHO = "Testrealm-Tester"
for id, name in pairs({ [133] = "Fireball", [116] = "Frostbolt", [2136] = "Fire Blast", [122] = "Frost Nova" }) do
	wow.spells[id] = { name = name, known = true }
end
wow.put(1, "spell", 133)
wow.put(2, "spell", 116)
wow.put(37, "spell", 2136) -- (Action Bar 5, button 1: MultiBarLeftButton1)

local function Key(button, down) TryUseActionButton(button, down ~= false) end
local function Click(button)
	button:Click("LeftButton")
	wow.now = wow.now + 0.5 -- (one click heard once: the next one a moment later)
end

local function Start(saved)
	wow.login(saved or {})
	ActionButton1.HotKey:SetText("1")
	wow.advance(4) -- (BarKeys hooks the buttons a second in; BarUse settles 3 s in)
end

-- BarKeys --------------------------------------------------------------------------------------------------------------

test("a key clicked with the mouse comes up bright", function()
	Start()
	eq(ns.KeyLook(ActionButton1), nil)
	Click(ActionButton1)
	eq(ns.KeyLook(ActionButton1), "bright")
	eq(ns.db.keyLearn[WHO].ActionButton1.key, "1", "kept per character, by the button's name")
end)

test("pressed by its key again and again: known after 20 presses, the label away", function()
	Start()
	for _ = 1, 19 do Key(ActionButton1) end
	eq(ns.KeyLook(ActionButton1), nil)
	Key(ActionButton1)
	eq(ns.KeyLook(ActionButton1), "hidden")
end)

test("a click halves what was learnt", function()
	Start()
	for _ = 1, 25 do Key(ActionButton1) end
	eq(ns.KeyLook(ActionButton1), "hidden")
	Click(ActionButton1)
	eq(ns.KeyLook(ActionButton1), nil, "not known any more, not yet bright")
	Click(ActionButton1)
	eq(ns.KeyLook(ActionButton1), "bright")
end)

test("bright until the key has been pressed enough again", function()
	Start()
	Click(ActionButton1)
	Key(ActionButton1)
	eq(ns.KeyLook(ActionButton1), "bright")
	for _ = 1, 3 do Key(ActionButton1) end
	eq(ns.KeyLook(ActionButton1), nil)
end)

test("the key's way up is not a second press", function()
	Start()
	for _ = 1, 20 do Key(ActionButton1, true) Key(ActionButton1, false) end
	eq(ns.KeyLook(ActionButton1), "hidden")
	ns.db.keyLearn[WHO].ActionButton1.score = 0.4
	for _ = 1, 10 do Key(ActionButton1, false) end
	eq(ns.db.keyLearn[WHO].ActionButton1.score, 0.4)
end)

test("a double click is one click; a right click counts, other buttons don't", function()
	Start()
	ActionButton1:Click("LeftButton")
	ActionButton1:Click("LeftButton")
	eq(ns.db.keyLearn[WHO].ActionButton1.score, 0.2)
	wow.now = wow.now + 1
	ActionButton1:Click("MiddleButton")
	eq(ns.db.keyLearn[WHO].ActionButton1.score, 0.2)
	ActionButton1:Click("RightButton")
	eq(ns.db.keyLearn[WHO].ActionButton1.score, 0.1)
end)

test("a new key on the button starts over", function()
	Start()
	for _ = 1, 25 do Key(ActionButton1) end
	ActionButton1.HotKey:SetText("Q")
	eq(ns.KeyLook(ActionButton1), nil)
	Key(ActionButton1)
	eq(ns.db.keyLearn[WHO].ActionButton1.key, "Q")
	ok(ns.db.keyLearn[WHO].ActionButton1.score < 0.5)
end)

test("under the mouse a known key shows again", function()
	Start()
	for _ = 1, 25 do Key(ActionButton1) end
	wow.hover(ActionButton1)
	eq(ns.KeyLook(ActionButton1), nil)
	wow.hover(nil)
	eq(ns.KeyLook(ActionButton1), "hidden")
end)

test("no key (or the range dot) on the button: nothing to learn", function()
	Start()
	Click(ActionButton2)
	eq(ns.db.keyLearn[WHO].ActionButton2, nil)
	RANGE_INDICATOR = "●"
	ActionButton2.HotKey:SetText("●")
	Click(ActionButton2)
	eq(ns.db.keyLearn[WHO].ActionButton2, nil)
end)

test("learning switched off: keys as always", function()
	Start({ barKeysLearn = false })
	Click(ActionButton1)
	eq(ns.KeyLook(ActionButton1), nil)
end)

-- BarUse ---------------------------------------------------------------------------------------------------------------

test("regression: the per-character store lives in barUseBy, barUse stays the on/off switch", function()
	Start()
	eq(ns.db.barUse, true)
	eq(type(ns.db.barUseBy[WHO]), "table")
	clean()
end)

test("regression: saved settings from before (barUse = true) log in cleanly", function()
	Start({ barUse = true, barUseHours = 10 })
	eq(ns.db.barUse, true)
	ok(ns.db.barUseBy[WHO].slots)
	clean()
end)

test("each press counted on its slot, by key and by mouse", function()
	Start()
	local store = ns.db.barUseBy[WHO]
	store.played = 500
	Key(ActionButton1)
	Click(ActionButton1)
	eq(store.slots[1].n, 2)
	eq(store.slots[1].last, 500)
	eq(store.slots[1].what, "spell:133")
end)

test("presses not counted while switched off", function()
	Start({ barUse = false })
	Key(ActionButton1)
	eq(ns.db.barUseBy[WHO].slots[1].n, 0)
end)

test("hours of play: 10 s at a time, not while away", function()
	Start()
	local store = ns.db.barUseBy[WHO]
	local before = store.played
	wow.advance(30, 1)
	eq(store.played - before, 30)
	wow.player.afk = true
	wow.advance(30, 1)
	eq(store.played - before, 30)
end)

test("a new action in a slot starts counting over", function()
	Start()
	local store = ns.db.barUseBy[WHO]
	Key(ActionButton1)
	store.played = 1000
	wow.put(1, "spell", 122)
	wow.fire("ACTIONBAR_SLOT_CHANGED", 1)
	eq(store.slots[1], { what = "spell:122", since = 1000, n = 0 })
end)

test("unused: not pressed for barUseHours of play; one quiet line about a minute in", function()
	Start({ barUseHours = 1 })
	local store = ns.db.barUseBy[WHO]
	store.played = 4000
	Key(ActionButton2)
	Key(MultiBarLeftButton1)
	wow.advance(60, 1)
	local line = wow.printed[#wow.printed]
	eq(line, "|cff9ad0c2Serene|r: 1 button on your bars not pressed in 1 h of play  -  /serene review")
	eq(store.told, "spell:133")
end)

test("the same unused buttons are not said twice", function()
	Start({ barUseHours = 1, barUseBy = { [WHO] = { played = 4000, told = "spell:133",
		slots = { [1] = { what = "spell:133", since = 0, n = 0 } } } } })
	local store = ns.db.barUseBy[WHO]
	Key(ActionButton2)
	Key(MultiBarLeftButton1)
	local printed = #wow.printed
	wow.advance(60, 1)
	eq(#wow.printed, printed)
end)

test("kept buttons are never unused; faded ones are faint for Ready", function()
	Start({ barUseHours = 1 })
	local store = ns.db.barUseBy[WHO]
	store.played = 4000
	store.faded["spell:116"] = true
	ok(ns.BarUseFaded(2))
	no(ns.BarUseFaded(1))
	ns.db.barUse = false
	no(ns.BarUseFaded(2), "switched off: nothing faded")
	ns.db.barUse = true
	store.keep["spell:133"] = true
	store.keep["spell:116"] = true
	store.keep["spell:2136"] = true
	ns.BarUseDebug()
	ok(wow.printed[#wow.printed]:find("0 unused now", 1, true), wow.printed[#wow.printed])
end)

test("the review: unused buttons cleared from it", function()
	Start({ barUseHours = 1 })
	local store = ns.db.barUseBy[WHO]
	store.played = 4000
	Key(ActionButton2)
	Key(MultiBarLeftButton1)
	ns.BarReview()
	ok(SereneBarReview:IsShown())
	local clear
	for _, f in ipairs(wow.frames) do
		if f.text and f:IsVisible() and f.text:GetText() == "Clear" then clear = f end
	end
	ok(clear, "a Clear chip")
	clear:Click()
	eq(wow.actions[1], nil, "the slot emptied")
	eq(store.slots[1], nil)
	eq(wow.held, nil, "nothing left on the cursor")
end)

test("easier keys: a busy action on no key traded with a quiet one on an easy key", function()
	wow.bindings = { ACTIONBUTTON1 = "1" }
	Start()
	local store = ns.db.barUseBy[WHO]
	store.played = 2 * 3600
	store.slots[1] = { what = "spell:133", since = 0, n = 1 }
	store.slots[37] = { what = "spell:2136", since = 0, n = 200 }
	ns.BarReview()
	local swap
	for _, f in ipairs(wow.frames) do
		if f.text and f:IsVisible() and f.text:GetText() == "Swap" then swap = f end
	end
	ok(swap, "a swap suggested")
	swap:Click()
	wow.advance(0.1)
	eq(wow.actions[1].id, 2136, "the busy one on the easy key")
	eq(wow.actions[37].id, 133)
	eq(store.slots[1].n, 200, "its count went with it")
	eq(store.slots[37].n, 1)
	eq(wow.held, nil)
end)

test("no swap when the busy action isn't much busier", function()
	wow.bindings = { ACTIONBUTTON1 = "1" }
	Start()
	local store = ns.db.barUseBy[WHO]
	store.played = 2 * 3600
	store.slots[1] = { what = "spell:133", since = 0, n = 10 }
	store.slots[37] = { what = "spell:2136", since = 0, n = 20 }
	ns.BarUseDebug()
	ok(wow.printed[#wow.printed]:find("0 swaps suggested", 1, true), wow.printed[#wow.printed])
end)

test("Serene's action bars off: BarUse doesn't start", function()
	Start({ actionBars = false })
	eq(ns.db.barUseBy, nil)
	ns.BarUseDebug()
	eq(wow.printed[#wow.printed], "|cff9ad0c2Serene|r: bar use: not started (Serene's action bars off)")
end)
