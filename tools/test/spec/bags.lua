-- Bags.lua: the sections (ns.BagsSections) and Serene's bags opening and closing with the game's.

-- (the game's bag windows start closed, and its bag calls open and close them)
for _, name in ipairs({ "ContainerFrameCombinedBags" }) do _G[name]:Hide() end
for index = 1, NUM_CONTAINER_FRAMES do _G["ContainerFrame" .. index]:Hide() end
function OpenAllBags() ContainerFrameCombinedBags:Show() end
function CloseAllBags() ContainerFrameCombinedBags:Hide() end
function ToggleAllBags() ContainerFrameCombinedBags:SetShown(not ContainerFrameCombinedBags:IsShown()) end
function OpenBackpack() ContainerFrameCombinedBags:Show() end
function ToggleBackpack() ToggleAllBags() end

local ns = wow.load()

wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20, sell = 13, classID = 7, subclassID = 5 }
wow.items[2592] = { name = "Wool Cloth", quality = 1, stack = 20, sell = 33, classID = 7, subclassID = 5 }
wow.items[4865] = { name = "Ruined Pelt", quality = 0, stack = 10, sell = 5, classID = 15 }
wow.items[25] = { name = "Worn Shortsword", quality = 1, sell = 7, classID = 2, equipLoc = "INVTYPE_WEAPONMAINHAND" }
wow.items[15] = { name = "Shiny Blade", quality = 2, sell = 70, classID = 2, equipLoc = "INVTYPE_WEAPONMAINHAND" }
wow.items[159] = { name = "Refreshing Spring Water", quality = 1, stack = 20, sell = 1, classID = 0 }
wow.items[745] = { name = "Marshal McBride's Documents", quality = 1, classID = 12 }
wow.items[2512] = { name = "Rough Arrow", quality = 1, stack = 200, sell = 1, classID = 6 }

local function Entries()
	local list = {}
	for _, bag in ipairs(ns.Items.Bags()) do
		for slot = 1, ns.Items.NumSlots(bag) do
			local e = ns.Items.Slot(bag, slot)
			if e then list[#list + 1] = e end
		end
	end
	return list
end

local function Names(sections)
	local names = {}
	for _, s in ipairs(sections) do names[#names + 1] = s.name end
	return names
end

local function CellNames(section)
	local names = {}
	for _, cell in ipairs(section.cells) do names[#names + 1] = cell.first.name .. " x" .. cell.count end
	return names
end

local function Login()
	wow.login(nil)
	wow.advance(1)
end

test("Sections: in the bags' order, only those with something in them", function()
	wow.bags[0] = { size = 16, [1] = { id = 4865, count = 2 }, [2] = { id = 2589, count = 5 }, [3] = { id = 25 },
		[4] = { id = 745, quest = true }, [5] = { id = 159, count = 3 }, [6] = { id = 2512, count = 200 } }
	Login()
	local sections = ns.BagsSections(Entries())
	eq(Names(sections), { "Equipment", "Consumables", "Quest", "Trade goods", "Ammo", "Junk" })
	for _, s in ipairs(sections) do eq(s.custom, false, s.name .. " is the bags' own") end
	clean()
end)

test("Sections: nothing in the bags, no sections", function()
	Login()
	eq(ns.BagsSections({}), {})
end)

test("Sections: stacks of one item make one cell; gear never does", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 20 }, [2] = { id = 2589, count = 7 }, [3] = { id = 25 },
		[4] = { id = 25 } }
	Login()
	local sections = ns.BagsSections(Entries())
	eq(Names(sections), { "Equipment", "Trade goods" })
	eq(CellNames(sections[1]), { "Worn Shortsword x1", "Worn Shortsword x1" })
	eq(CellNames(sections[2]), { "Linen Cloth x27" })
	eq(#sections[2].cells[1].slots, 2, "the cell knows both slots")
end)

test("Sections: a cell grey only when every stack is locked; its button the first stack that isn't", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 20, locked = true }, [2] = { id = 2589, count = 7 } }
	Login()
	local cell = ns.BagsSections(Entries())[1].cells[1]
	eq(cell.locked, false)
	eq(cell.live.slot, 2)
	wow.bags[0][2].locked = true
	cell = ns.BagsSections(Entries())[1].cells[1]
	eq(cell.locked, true)
end)

test("Sections: in a section, better quality first, then by kind and name, the bigger stack first", function()
	wow.bags[0] = { size = 16, [1] = { id = 25 }, [2] = { id = 15 }, [3] = { id = 2592, count = 3 },
		[4] = { id = 2589, count = 5 } }
	Login()
	local sections = ns.BagsSections(Entries())
	eq(CellNames(sections[1]), { "Shiny Blade x1", "Worn Shortsword x1" })
	eq(CellNames(sections[2]), { "Linen Cloth x5", "Wool Cloth x3" })
end)

test("Sections: the player's own sections first, in their order", function()
	wow.bags[0] = { size = 16, [1] = { id = 159, count = 3 }, [2] = { id = 2589, count = 5 }, [3] = { id = 4865 },
		[4] = { id = 25 } }
	Login()
	ns.db.bagCats = { "Raid", "Fishing", "Empty one" }
	ns.db.bagPins = { [159] = "Fishing", [2589] = "Raid" }
	local sections = ns.BagsSections(Entries())
	eq(Names(sections), { "Raid", "Fishing", "Equipment", "Junk" }, "an empty custom section isn't listed")
	eq(sections[1].custom, true)
	eq(sections[3].custom, false)
end)

test("Sections: a grey pinned elsewhere leaves Junk", function()
	wow.bags[0] = { size = 16, [1] = { id = 4865, count = 2 } }
	Login()
	ns.db.bagPins = { [4865] = "Trade goods" }
	eq(Names(ns.BagsSections(Entries())), { "Trade goods" })
end)

test("the game's B opens Serene's bags; again closes them", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 5 }, [2] = { id = 4865 } }
	Login()
	ok(SereneBags, "SereneBags made")
	no(SereneBags:IsShown(), "closed at login")
	ToggleAllBags()
	wow.advance(0.2)
	ok(SereneBags:IsShown(), "open with the game's")
	ToggleAllBags()
	wow.advance(0.2)
	no(SereneBags:IsShown(), "closed with the game's")
	clean()
end)

test("OpenAllBags and CloseAllBags, then Serene's own close closes the game's", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 5 } }
	Login()
	OpenAllBags()
	wow.advance(0.2)
	ok(SereneBags:IsShown())
	SereneBags:Hide()
	wow.advance(0.2)
	no(ContainerFrameCombinedBags:IsShown(), "the game's closed too, so the next B opens them again")
	OpenBackpack()
	wow.advance(0.2)
	ok(SereneBags:IsShown())
	CloseAllBags()
	wow.advance(0.2)
	no(SereneBags:IsShown())
	clean()
end)

test("the bags open with a full bag, a bag update while open, and money", function()
	wow.bags[0] = { size = 2, [1] = { id = 2589, count = 5 }, [2] = { id = 4865 } }
	Login()
	OpenAllBags()
	wow.advance(0.2)
	wow.bags[0][2] = nil
	wow.fire("BAG_UPDATE_DELAYED")
	wow.fire("PLAYER_MONEY")
	wow.advance(0.5)
	ok(SereneBags:IsShown())
	clean()
end)

test("closed bags are still remembered for the other characters' counts", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 5 } }
	Login()
	wow.fire("BAG_UPDATE_DELAYED")
	wow.advance(0.5)
	local me = ns.db.inv[wow.player.realm][wow.player.name]
	ok(me and me.bags, "the bags remembered")
	eq(me.bags[1], { wow.link(2589), 5, 1 })
	eq(me.class, "WARRIOR")
	clean()
end)

test("an item's tooltip: how many another character has", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 5 } }
	Login()
	ns.db.inv[wow.player.realm]["Alt"] = { class = "MAGE", bags = { { wow.link(2589), 12, 1 } } }
	-- (the processor's item post-calls: Bags' among them)
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	GameTooltip:AddLine("Linen Cloth")
	GameTooltip:Show()
	for _, call in ipairs(wow.tooltipPostCalls or {}) do
		if call[1] == Enum.TooltipDataType.Item then call[2](GameTooltip, { id = 2589, type = Enum.TooltipDataType.Item }) end
	end
	local found
	for index = 1, GameTooltip:NumLines() do
		local right = _G["GameTooltipTextRight" .. index]
		local left = _G["GameTooltipTextLeft" .. index]
		if left and (left:GetText() or ""):find("Alt") then found = right:GetText() end
	end
	ok(found and found:find("bags 12"), "the alt's 12 in bags (got " .. tostring(found) .. ")")
	clean()
end)

-- The rows under the header (BagSlots.lua) ------------------------------------------------------------------------------

test("\"bags\": a row of your bag slots, each with its bag's icon and the room left in it", function()
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 5 } }
	wow.bags[1] = { size = 6, [1] = { id = 159, count = 3 } }
	wow.equipped = { [20] = { icon = 133622 } } -- (bag 1, in inventory slot 20)
	Login()
	OpenAllBags()
	wow.advance(0.2)
	no(SereneBags.slots[1] and SereneBags.slots[1]:IsShown(), "hidden at first")
	SereneBags.slotsWord:GetScript("OnClick")(SereneBags.slotsWord, "LeftButton")
	local first = SereneBags.slots[1]
	ok(first and first:IsShown(), "shown")
	eq(first.slot.bag, 1)
	eq(first.icon:GetTexture(), 133622, "its bag's icon")
	eq(first.free:GetText(), 5, "five of six free")
	ok(SereneBags.slots[2]:IsShown(), "an empty bag slot shown too")
	eq(SereneBags.slots[2].slot.has, nil, "nothing in it")
	SereneBags.slotsWord:GetScript("OnClick")(SereneBags.slotsWord, "LeftButton")
	no(first:IsShown(), "hidden again")
	clean()
end)

test("at a banker, \"tabs\": how full each tab is, and buying one more on the game's own bank page", function()
	C_Bank.FetchPurchasedBankTabData = function() return { { ID = 6, name = "Tab 1" } } end
	C_Bank.CanPurchaseBankTab = function() return true end
	C_Bank.FetchNextPurchasableBankTabData = function() return { tabCost = 100000 } end
	wow.bags[6] = { size = 10, [1] = { id = 2589, count = 5 }, [2] = { id = 2592, count = 2 } }
	Login()
	wow.fire("BANKFRAME_OPENED")
	wow.advance(0.2)
	ok(SereneBank:IsShown(), "the bank")
	SereneBank.tabsWord:GetScript("OnClick")(SereneBank.tabsWord, "LeftButton")
	ok(SereneBank.tabsText:IsShown(), "the tabs as words")
	eq(SereneBank.tabsText:GetText(), "Tab 1 2/10")
	ok(SereneBank.buyWord:IsShown(), "one more to buy")
	ok(SereneBank.buyWord.text:GetText():find("buy a tab"), "a tab")
	SereneBank.buyWord:GetScript("OnClick")(SereneBank.buyWord, "LeftButton")
	eq(BankFrame:GetParent(), UIParent, "the game's own bank page shown")
	no(SereneBank:IsShown(), "Serene's bank away meanwhile")
	wow.fire("BANKFRAME_CLOSED")
	ok(BankFrame:GetParent() ~= UIParent, "the game's bank out of sight again")
	clean()
end)

test("bags switched off: no bags made, the game's untouched", function()
	wow.login({ bags = false })
	wow.advance(1)
	eq(rawget(_G, "SereneBags"), nil)
	clean()
end)
