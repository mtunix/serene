-- Vendor.lua and Merchant.lua: the junk sold and the repair at every merchant, Serene's merchant window, a full
-- stack bought with Alt-click.

local ns = wow.load()

wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20, sell = 13, classID = 7, subclassID = 5 }
wow.items[4865] = { name = "Ruined Pelt", quality = 0, stack = 10, sell = 5, classID = 15 }
wow.items[4757] = { name = "Cracked Egg Shells", quality = 0, stack = 10, sell = 3, classID = 15 }
wow.items[2934] = { name = "Ruined Leather Scraps", quality = 0, stack = 10, sell = 0, classID = 15 }
wow.items[5373] = { name = "Lucky Charm", quality = 0, sell = 2, classID = 15 }
wow.items[745] = { name = "Marshal McBride's Documents", quality = 0, sell = 4, classID = 12 }
wow.items[159] = { name = "Refreshing Spring Water", quality = 1, stack = 20, sell = 1, classID = 0 }
wow.items[2512] = { name = "Rough Arrow", quality = 1, stack = 200, sell = 1, classID = 6 }
wow.items[2488] = { name = "Gladius", quality = 1, sell = 100, classID = 2, equipLoc = "INVTYPE_WEAPONMAINHAND" }
wow.items[5578] = { name = "Recipe: Rage Potion", quality = 1, sell = 100, classID = 9 }

-- (the game's guild repair: allowed, no limit; what it repaired leaves nothing to pay)
local guildBank = false
CanGuildBankRepair = function() return guildBank end
GetGuildBankWithdrawMoney = function() return -1 end
RepairAllItems = function(guild)
	wow.repaired = guild and "guild" or "gold"
	wow.merchant.repairCost = 0
end

local function Junk()
	wow.bags[0] = { size = 16, [1] = { id = 4865, count = 3 }, [2] = { id = 2589, count = 5 }, [3] = { id = 4757 },
		[4] = { id = 2934, count = 2 }, [5] = { id = 745, quest = true } }
	wow.bags[1] = { size = 4, [2] = { id = 5373 } }
end

local function Login(saved)
	wow.login(saved)
	wow.advance(0.5)
end

local function Visit()
	wow.merchant.open = true
	wow.fire("MERCHANT_SHOW")
	wow.advance(3)
end

local function Sold()
	local list = {}
	for _, used in ipairs(wow.used or {}) do list[#list + 1] = used[1] .. ":" .. used[2] end
	return list
end

local function Said(pattern)
	for _, line in ipairs(wow.printed) do
		if type(line) == "string" and line:find(pattern) then return line end
	end
end

test("FindJunk: greys worth something, in bag order, and their worth", function()
	Junk()
	Login()
	local found, worth = ns.MerchantFindJunk()
	eq(found, { { bag = 0, slot = 1, id = 4865 }, { bag = 0, slot = 3, id = 4757 }, { bag = 1, slot = 2, id = 5373 } })
	eq(worth, 3 * 5 + 3 + 2)
end)

test("FindJunk: not a grey that sells for nothing, a quest's grey, a locked one", function()
	wow.bags[0] = { size = 8, [1] = { id = 2934, count = 2 }, [2] = { id = 745, quest = true },
		[3] = { id = 4865, locked = true } }
	Login()
	local found, worth = ns.MerchantFindJunk()
	eq(found, {})
	eq(worth, 0)
end)

test("FindJunk: exactly the bags' Junk section (pins count both ways)", function()
	Junk()
	Login()
	ns.db.bagPins = { [4865] = "Other", [159] = "Junk", [2589] = "Junk" }
	local found = ns.MerchantFindJunk()
	local ids = {}
	for _, item in ipairs(found) do ids[#ids + 1] = item.id end
	eq(ids, { 2589, 4757, 5373 }, "the pinned grey kept, the cloth pinned to Junk sold")
	for _, bag in ipairs(ns.Items.Bags()) do
		for slot = 1, ns.Items.NumSlots(bag) do
			local e = ns.Items.Slot(bag, slot)
			if e and not e.noValue and not e.locked and ns.Items.IsJunk(e) and ns.Items.SellPrice(e.link) > 0 then
				local listed = false
				for _, item in ipairs(found) do if item.bag == bag and item.slot == slot then listed = true end end
				ok(listed, "junk at " .. bag .. ":" .. slot .. " is sold")
			end
		end
	end
end)

test("at a merchant: the junk sold one by one, then a line says for how much", function()
	Junk()
	Login()
	Visit()
	eq(Sold(), { "0:1", "0:3", "1:2" })
	ok(Said("sold 5 junk for"), "a line: sold 5 junk")
	ok(Said("sold 5 junk for 20c"), "worth 20c")
	clean()
end)

test("at a merchant: then everything repaired with your gold", function()
	Junk()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	Login()
	Visit()
	eq(wow.repaired, "gold")
	ok(Said("repaired for 12s 34c"))
	clean()
end)

test("at a merchant: the guild's money first, when chosen and allowed", function()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	guildBank = true
	Login({ repairGuild = true })
	Visit()
	wow.advance(2)
	eq(wow.repaired, "guild")
	ok(Said("repaired for 12s 34c %(the guild's money%)"))
	clean()
end)

test("at a merchant: the guild's money not chosen, your gold", function()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	guildBank = true
	Login()
	Visit()
	eq(wow.repaired, "gold")
end)

test("at a merchant: not enough money to repair, said and nothing done", function()
	wow.merchant.repair, wow.merchant.repairCost = true, 50000
	wow.money = 100
	Login()
	Visit()
	eq(wow.repaired, nil)
	ok(Said("not enough money to repair"))
	clean()
end)

test("a merchant who can't repair: nothing tried", function()
	wow.merchant.repair, wow.merchant.repairCost = false, 1234
	Login()
	Visit()
	eq(wow.repaired, nil)
end)

test("junk and repairs switched off: nothing done", function()
	Junk()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	Login({ sellJunk = false, autoRepair = false })
	Visit()
	eq(Sold(), {})
	eq(wow.repaired, nil)
	clean()
end)

test("only the junk off: still repaired", function()
	Junk()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	Login({ sellJunk = false })
	Visit()
	eq(Sold(), {})
	eq(wow.repaired, "gold")
end)

test("Shift held while the merchant opens: nothing done by itself", function()
	Junk()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	Login()
	wow.shift = true
	Visit()
	eq(Sold(), {})
	eq(wow.repaired, nil)
end)

test("in a fight: nothing sold (the repair still done)", function()
	Junk()
	wow.merchant.repair, wow.merchant.repairCost = true, 1234
	Login()
	wow.combat = true
	Visit()
	eq(Sold(), {})
	eq(wow.repaired, "gold")
	clean()
end)

test("the merchant gone in the middle: the selling stops", function()
	Junk()
	Login()
	wow.fire("MERCHANT_SHOW")
	wow.advance(0.2) -- (the first sold)
	wow.fire("MERCHANT_CLOSED")
	wow.advance(3)
	ok(#Sold() < 3, "not all sold after the merchant left (" .. #Sold() .. ")")
	clean()
end)

test("a slot changed while selling: what is there now isn't sold", function()
	Junk()
	Login()
	wow.fire("MERCHANT_SHOW")
	wow.advance(0.05)
	wow.bags[1][2] = { id = 2589, count = 5 } -- (the grey moved away, cloth put there)
	wow.advance(3)
	eq(Sold(), { "0:1", "0:3" })
	clean()
end)

-- Serene's merchant window -------------------------------------------------------------------------------------------

local function Texts()
	local list = {}
	for _, f in ipairs(wow.frames) do
		if f:GetObjectType() == "FontString" and f:IsVisible() then
			local text = f:GetText()
			if type(text) == "string" and text ~= "" then list[#list + 1] = text end
		end
	end
	return list
end

local function Shows(pattern)
	for _, text in ipairs(Texts()) do if text:find(pattern) then return text end end
end

local function Goods()
	wow.merchant.items = {
		{ id = 159, price = 25, stack = 1, numAvailable = -1 },
		{ id = 2512, price = 10, stack = 200, numAvailable = -1 },
		{ id = 2488, price = 2000, stack = 1, numAvailable = 2 },
	}
end

test("the merchant's goods in Serene's window, the game's out of sight", function()
	Goods()
	Login()
	Visit()
	ok(SereneMerchant and SereneMerchant:IsShown(), "Serene's window open")
	eq(MerchantFrame:GetAlpha(), 0, "the game's window unseen")
	ok(Shows("Refreshing Spring Water"), "water listed")
	ok(Shows("Rough Arrow"), "arrows listed")
	ok(Shows("Gladius"), "the sword listed")
	ok(Shows("2 left"), "how many he has left")
	clean()
end)

test("the window closes with the visit, the game's back in its place", function()
	Goods()
	Login()
	MerchantFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	Visit()
	wow.fire("MERCHANT_CLOSED")
	wow.advance(0.5)
	no(SereneMerchant:IsShown())
	-- (Serene leaves it out of sight until the next OnShow decides; asking the window back gives the old place)
	ns.db.merchant = false
	ns.Refresh()
	local point, _, _, x, y = MerchantFrame:GetPoint(1)
	eq({ point, x, y }, { "TOPLEFT", 16, -116 })
	eq(MerchantFrame:GetAlpha(), 1)
	clean()
end)

test("merchant window off: the game's window stays, the junk still sold", function()
	Goods()
	Junk()
	Login({ merchant = false })
	Visit()
	ok(not rawget(_G, "SereneMerchant") or not SereneMerchant:IsShown())
	eq(MerchantFrame:GetAlpha(), 1)
	eq(#Sold(), 3)
	clean()
end)

test("why you can't use it, in a few words (the tooltip's red line)", function()
	wow.merchant.items = { { id = 2488, price = 2000, stack = 1, usable = false } }
	wow.tooltipData["merchant:1"] = { lines = {
		{ leftText = "Gladius" },
		{ leftText = "Requires Level 40", leftColor = { r = 1, g = 0.13, b = 0.13 } } } }
	Login()
	Visit()
	ok(Shows("level 40"), "the reason shortened to 'level 40'")
	clean()
end)

local REASONS = {
	{ "Requires Level 40", "level 40" },
	{ "Requires Tailoring (150)", "Tailoring 150" },
	{ "Requires Stormwind - Honored", "Stormwind honored" },
	{ "Classes: Mage, Priest", "Mage, Priest" },
	{ "Requires Blacksmithing", "Blacksmithing" },
	{ "Some other red line", "Some other red line" },
}
test("each kind of 'Requires...' line shortened", function()
	for _, case in ipairs(REASONS) do
		wow.merchant.items = { { id = 2488, price = 2000, stack = 1, usable = false } }
		wow.tooltipData["merchant:1"] = { lines = { { leftText = "Gladius" },
			{ leftText = case[1], leftColor = { r = 1, g = 0.13, b = 0.13 } } } }
		Login()
		Visit()
		ok(Shows(case[2]:gsub("[%-%(%)]", "%%%0")), case[1] .. " -> " .. case[2])
		wow.fire("MERCHANT_CLOSED")
		wow.advance(0.5)
		wow.loggedIn = false
	end
end)

test("a recipe you know: 'known'", function()
	wow.merchant.items = { { id = 5578, price = 400, stack = 1 } }
	wow.tooltipData["merchant:1"] = { lines = { { leftText = "Recipe: Rage Potion" }, { leftText = "Already known" } } }
	Login()
	Visit()
	ok(Shows("known"))
	clean()
end)

test("usable only: what you can't use hidden", function()
	wow.merchant.items = { { id = 2488, price = 2000, stack = 1, usable = false }, { id = 159, price = 25, stack = 1 } }
	wow.tooltipData["merchant:1"] = { lines = { { leftText = "Gladius" },
		{ leftText = "Requires Level 40", leftColor = { r = 1, g = 0.13, b = 0.13 } } } }
	Login({ merchantUsable = true })
	Visit()
	no(Shows("Gladius"), "the sword hidden")
	ok(Shows("Refreshing Spring Water"))
	clean()
end)

-- A full stack (Merchant.lua) ----------------------------------------------------------------------------------------

local function Bought()
	local list = {}
	for _, b in ipairs(wow.bought or {}) do list[#list + 1] = b[2] or 1 end
	return list
end

test("Alt-click: one full stack bought", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), { 20 })
end)

test("Alt-click: fewer when you can't pay for a stack, said so", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	wow.money = 110
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), { 4 })
	ok(Said("4 bought %(all you can pay for%)"))
end)

test("Alt-click: fewer when he has fewer", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1, numAvailable = 3 } }
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), { 3 })
	ok(Said("all the merchant has"))
end)

test("Alt-click: sold in lots of 5: whole lots only", function()
	wow.items[1179] = { name = "Ice Cold Milk", quality = 1, stack = 20, sell = 1, classID = 0 }
	wow.merchant.items = { { id = 1179, price = 100, stack = 5 } }
	wow.money = 250 -- (100 a lot of 5: 12 milk paid for, two whole lots)
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), { 10 })
end)

test("Alt-click: bought in parts when he sells fewer at once", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	GetMerchantItemMaxStack = function() return 5 end
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), { 5, 5, 5, 5 })
end)

test("Alt-click: an expensive stack asked first", function()
	wow.merchant.items = { { id = 159, price = 100000, stack = 1 } }
	wow.money = 100000000
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), {})
	eq(wow.popup and wow.popup.which, "SERENE_MERCHANT_STACK")
	StaticPopupDialogs.SERENE_MERCHANT_STACK.OnAccept(nil, wow.popup.data)
	eq(Bought(), { 20 })
end)

test("Alt-click: nothing for gear (stacks of one) or with no money", function()
	wow.merchant.items = { { id = 2488, price = 2000, stack = 1 }, { id = 159, price = 25, stack = 1 } }
	wow.money = 10
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	ns.MerchantBuyStack(2)
	eq(Bought(), {})
	ok(Said("not enough money for one more"))
end)

test("Alt-click: the vendor switch off, nothing bought", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	Login({ vendor = false })
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), {})
end)

test("Alt-click on the game's merchant buttons: a stack on the buy tab, nothing on buyback", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	Login()
	Visit()
	local button = MerchantItem1ItemButton
	button:SetID(1)
	wow.alt = true
	button:_Fire("OnClick", "LeftButton")
	eq(Bought(), { 20 }, "the buy tab")
	MerchantFrame.selectedTab = 2
	button:_Fire("OnClick", "LeftButton")
	eq(Bought(), { 20 }, "buyback: the button buys back, nothing more here")
	wow.alt = nil
end)

test("paid with tokens or items: no stack, the game's own buying stays", function()
	wow.merchant.items = { { id = 159, price = 0, stack = 1, extended = true } }
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	eq(Bought(), {})
end)

test("an expensive stack, the merchant's goods changed before the answer: nothing bought", function()
	wow.merchant.items = { { id = 159, price = 100000, stack = 1 } }
	wow.money = 100000000
	Login()
	Visit()
	ns.MerchantBuyStack(1)
	wow.merchant.items = { { id = 2512, price = 100000, stack = 1 } }
	StaticPopupDialogs.SERENE_MERCHANT_STACK.OnAccept(nil, wow.popup.data)
	eq(Bought(), {})
end)

test("the how-many popup: a Stack button for a merchant's item, buying a stack; none for the bags' split", function()
	wow.merchant.items = { { id = 159, price = 25, stack = 1 } }
	Login()
	Visit()
	MerchantItem1ItemButton:SetID(1)
	StackSplitFrame:Hide()
	StackSplitFrame.owner = MerchantItem1ItemButton
	StackSplitFrame:Show()
	ok(SereneStackSplitStackButton:IsShown(), "a merchant's item")
	SereneStackSplitStackButton:GetScript("OnClick")(SereneStackSplitStackButton)
	eq(Bought(), { 20 }, "a stack bought")
	no(StackSplitFrame:IsShown(), "the popup closed")
	-- (a bag's item button: its ID is its slot, which a merchant's index could be mistaken for)
	local bagItem = CreateFrame("Button", "ContainerFrame1Item1", UIParent)
	bagItem:SetID(1)
	StackSplitFrame.owner = bagItem
	StackSplitFrame:Show()
	no(SereneStackSplitStackButton:IsShown(), "the bags' split")
	clean()
end)
