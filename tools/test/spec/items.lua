-- Items.lua: a bag slot read, what an item is, the bags' section it goes in, the one rule for junk, prices.

local ns = wow.load({ "Items.lua" })
local Items = ns.Items
ns.db = { bagPins = {}, bagCats = {} }

wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20, sell = 13, classID = 7, subclassID = 5 }
wow.items[4865] = { name = "Ruined Pelt", quality = 0, stack = 10, sell = 5, classID = 15 }
wow.items[25] = { name = "Worn Shortsword", quality = 1, sell = 7, classID = 2, equipLoc = "INVTYPE_WEAPONMAINHAND" }
wow.items[2575] = { name = "Red Linen Shirt", quality = 1, sell = 2, classID = 4, equipLoc = "INVTYPE_BODY" }
wow.items[159] = { name = "Refreshing Spring Water", quality = 1, stack = 20, sell = 1, classID = 0 }
wow.items[2512] = { name = "Rough Arrow", quality = 1, stack = 200, sell = 1, classID = 6 }
wow.items[5571] = { name = "Small Black Pouch", quality = 1, sell = 1, classID = 1, equipLoc = "INVTYPE_BAG" }
wow.items[745] = { name = "Marshal McBride's Documents", quality = 1, classID = 12 }
wow.items[6948] = { name = "Hearthstone", quality = 1, classID = 15 }
wow.items[5396] = { name = "Key to Searing Gorge", quality = 1, classID = 13 }
wow.items[2934] = { name = "Ruined Leather Scraps", quality = 0, stack = 10, sell = 0, classID = 15 }
wow.items[1179] = { name = "Ice Cold Milk", quality = 1, stack = 20, sell = 1, classID = 0 }
wow.items[3371] = { name = "Empty Vial", quality = 1, stack = 20, sell = 1, classID = 7, subclassID = 11 }
wow.items[5373] = { name = "Lucky Charm", quality = 0, sell = 2, classID = 15 } -- (a grey with no stack)
wow.items[4757] = { name = "Cracked Egg Shells", quality = 0, stack = 1, sell = 3, classID = 15 }

local function Entry(id, extra)
	local e = { id = id, link = wow.link(id), count = 1, quality = wow.items[id].quality }
	for key, value in pairs(extra or {}) do e[key] = value end
	return e
end

test("IdOf reads the id from a link, nothing else", function()
	eq(Items.IdOf(wow.link(2589)), 2589)
	eq(Items.IdOf("|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r"), 6948)
	eq(Items.IdOf("item:25"), 25)
	eq(Items.IdOf("no link"), nil)
	eq(Items.IdOf(2589), nil, "a number is not a link")
	eq(Items.IdOf(nil), nil)
end)

test("Bags: the backpack, four bags and the reagent bag (no keyring on this stub)", function()
	eq(Items.Bags(), { 0, 1, 2, 3, 4, 5 })
end)

test("Bags: the keyring last, where the game has one", function()
	Items.KEYRING = -2
	eq(Items.Bags(), { 0, 1, 2, 3, 4, 5, -2 })
	Items.KEYRING = nil
end)

test("NumSlots: a bag's size; 0 for a bag that isn't there", function()
	wow.bags[0] = { size = 16 }
	wow.bags[2] = { size = 10 }
	eq(Items.NumSlots(0), 16)
	eq(Items.NumSlots(2), 10)
	eq(Items.NumSlots(3), 0)
end)

test("NumSlots: a secret size reads as 0", function()
	C_Container.GetContainerNumSlots = function() return wow.secret(16) end
	eq(Items.NumSlots(0), 0)
end)

test("Slot: what is in a slot", function()
	wow.bags[0] = { size = 4, [1] = { id = 2589, count = 7 }, [3] = { id = 4865, count = 2, locked = true } }
	local e = Items.Slot(0, 1)
	eq(e.bag, 0) eq(e.slot, 1)
	eq(e.id, 2589)
	eq(e.link, wow.link(2589))
	eq(e.count, 7)
	eq(e.quality, 1)
	eq(e.locked, false)
	eq(e.quest, false)
	eq(e.noValue, false)
	local grey = Items.Slot(0, 3)
	eq(grey.locked, true)
	eq(grey.quality, 0)
end)

test("Slot: nil for an empty slot, a slot past the end, a bag that isn't there", function()
	wow.bags[0] = { size = 4, [1] = { id = 2589 } }
	eq(Items.Slot(0, 2), nil)
	eq(Items.Slot(0, 9), nil)
	eq(Items.Slot(3, 1), nil)
end)

test("Slot: a quest item, and one a merchant won't buy", function()
	wow.bags[0] = { size = 4, [1] = { id = 745, quest = true }, [2] = { id = 2934, count = 3 } }
	eq(Items.Slot(0, 1).quest, true)
	eq(Items.Slot(0, 2).noValue, true, "no sell price: no value")
end)

test("Slot: one count when the game says none", function()
	C_Container.GetContainerItemInfo = function()
		return { hyperlink = wow.link(6948), itemID = 6948, quality = 1 }
	end
	local e = Items.Slot(0, 1)
	eq(e.count, 1)
	eq(e.locked, false)
end)

test("Slot: the id from the link when the game gives none", function()
	C_Container.GetContainerItemInfo = function()
		return { hyperlink = wow.link(159), stackCount = 4, quality = 1 }
	end
	eq(Items.Slot(0, 1).id, 159)
end)

test("Slot: a secret link reads as nothing in the slot", function()
	C_Container.GetContainerItemInfo = function()
		return { hyperlink = wow.secret(wow.link(159)), stackCount = 4, itemID = 159 }
	end
	eq(Items.Slot(0, 1), nil)
end)

test("Describe: class, equip slot, name, whether its stacks merge", function()
	local cloth = Items.Describe(Entry(2589))
	eq(cloth.classID, 7) eq(cloth.subclassID, 5)
	eq(cloth.equipLoc, "")
	eq(cloth.name, "Linen Cloth")
	eq(cloth.merge, true)
	eq(cloth.equips, false)
end)

-- (gear never merges: each piece its own cell, even two of the same)
local MERGE = {
	{ 2589, true, "a stack of cloth" },
	{ 159, true, "water" },
	{ 2512, true, "arrows" },
	{ 25, false, "a weapon" },
	{ 2575, false, "a shirt" },
	{ 5571, false, "a bag (equips in a bag slot)" },
	{ 6948, true, "a Hearthstone (stack 1, not gear: its copies would be one cell)" },
	{ 745, true, "a quest item" },
}
test("Describe: what merges and what doesn't", function()
	for _, case in ipairs(MERGE) do
		eq(Items.Describe(Entry(case[1])).merge, case[2], case[3])
	end
end)

test("Describe: an item the game doesn't know yet is 'miscellaneous', common", function()
	local e = Items.Describe({ link = "|cffffffff|Hitem:99999::::::::60:::::|h[Mystery]|h|r", id = 99999, count = 1 })
	eq(e.classID, 15)
	eq(e.subclassID, 0)
	eq(e.equipLoc, "")
	eq(e.name, "Mystery")
	eq(e.quality, 1, "an unknown quality reads as common")
end)

test("Describe: a remembered entry (another character's) gets its quality from the game", function()
	local e = Items.Describe({ link = wow.link(4865), id = 4865, count = 2 })
	eq(e.quality, 0)
end)

-- The bags' own sections, by what an item is.
local AUTO = {
	{ 2589, "Trade goods", "cloth" },
	{ 3371, "Trade goods", "a vial" },
	{ 159, "Consumables", "water" },
	{ 2512, "Ammo", "arrows" },
	{ 25, "Equipment", "a weapon" },
	{ 2575, "Equipment", "a shirt" },
	{ 5571, "Other", "a bag" },
	{ 745, "Quest", "a quest item by class" },
	{ 5396, "Keys", "a key" },
	{ 6948, "Other", "miscellaneous" },
	{ 4865, "Junk", "a grey" },
}
test("Section: each kind of item in its own section", function()
	for _, case in ipairs(AUTO) do
		eq(Items.Section(Entry(case[1])), case[2], case[3])
	end
end)

test("Section: quest beats junk", function()
	eq(Items.Section(Entry(4865, { quest = true })), "Quest")
end)

test("Section: a grey bag or quiver is junk before it is 'Other'", function()
	wow.items[1000] = { name = "Old Quiver", quality = 0, sell = 1, classID = 11, equipLoc = "INVTYPE_BAG" }
	eq(Items.Section(Entry(1000)), "Junk")
end)

test("Section: a pin to one of the bags' own sections wins", function()
	ns.db.bagPins[4865] = "Trade goods"
	eq(Items.Section(Entry(4865)), "Trade goods", "a grey pinned elsewhere")
	ns.db.bagPins[2589] = "Junk"
	eq(Items.Section(Entry(2589)), "Junk", "cloth pinned to Junk")
end)

test("Section: a pin to a custom section, while it exists", function()
	ns.db.bagCats = { "Raid", "Fishing" }
	ns.db.bagPins[159] = "Raid"
	eq(Items.Section(Entry(159)), "Raid")
	ns.db.bagCats = { "Fishing" }
	eq(Items.Section(Entry(159)), "Consumables", "the custom section deleted: back by what it is")
end)

test("Section: a pin to a name that is no section falls back", function()
	ns.db.bagPins[2589] = "Nonsense"
	eq(Items.Section(Entry(2589)), "Trade goods")
end)

test("Section: without settings yet (before login) still by what it is", function()
	ns.db = nil
	eq(Items.Section(Entry(4865)), "Junk")
	eq(Items.IsCustom("Raid"), false)
end)

test("IsJunk: exactly what Section calls Junk", function()
	ns.db.bagPins = { [5373] = "Other", [159] = "Junk" }
	eq(Items.IsJunk(Entry(4865)), true, "a grey")
	eq(Items.IsJunk(Entry(5373)), false, "a grey pinned to Other")
	eq(Items.IsJunk(Entry(159)), true, "water pinned to Junk")
	eq(Items.IsJunk(Entry(2589)), false, "cloth")
	eq(Items.IsJunk(Entry(4865, { quest = true })), false, "a grey quest item")
end)

test("IsCustom: only the player's own sections", function()
	ns.db.bagCats = { "Raid" }
	eq(Items.IsCustom("Raid"), true)
	eq(Items.IsCustom("Junk"), false)
	ns.db.bagCats = "broken"
	eq(Items.IsCustom("Raid"), false, "a broken saved value is no section")
end)

test("SellPrice: what a merchant pays for one, by link or id", function()
	eq(Items.SellPrice(wow.link(2589)), 13)
	eq(Items.SellPrice(4865), 5)
	eq(Items.SellPrice(745), 0, "no price")
	eq(Items.SellPrice(99999), 0, "an unknown item")
	eq(Items.SellPrice(nil), 0)
end)

test("SellPrice: a secret price reads as 0", function()
	GetItemInfo = function() return wow.secret(1) end
	C_Item.GetItemInfo = function(...)
		local out = { "x", "y", 1, 1, 1, "", "", 1, "", 1, wow.secret(13) }
		return unpack(out, 1, 11)
	end
	-- (Items.lua keeps the call it found when it loaded: loaded again to take this one)
	local ns2 = wow.load({ "Items.lua" })
	eq(ns2.Items.SellPrice(2589), 0)
end)

test("Coins: copper as the game's coin text, red when you can't pay", function()
	eq(Items.Coins(10203), "1g 2s 3c")
	eq(Items.Coins(0), "0c")
	eq(Items.Coins(500, true), "|cffdb6b615s|r")
	eq(Items.Coins(nil), "")
	eq(Items.Coins("12"), "")
end)
