local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Items in your bags, read and sorted in one place for Bags.lua (the windows, "make room"), Vendor.lua (the junk
-- sold, the merchant's window), Merchant.lua and Tooltip.lua (prices). Only reading: nothing here moves an item.
--   ns.Items.Bags(), NumSlots(bag)    your bags' ids (with the reagent bag and the keyring, where the game has them)
--   Slot(bag, slot)                   what is in a slot: { bag, slot, link, id, icon, count, quality, locked,
--                                     quest, noValue }, or nil
--   Describe(entry)                   its class, equip slot, name, whether its stacks merge
--   Section(entry)                    the bags' section it is shown in ("Junk", "Quest", one of your own...)
--   IsJunk(entry)                     shown in Junk: what the merchant's window sells as junk. One rule for both,
--                                     so what you see under Junk is what is sold, and only that.
--   IdOf(link), SellPrice(item), Coins(copper, red)

local Items = {}
ns.Items = Items

-- The bags' own sections, in their order.
Items.SECTIONS = { "Equipment", "Consumables", "Quest", "Trade goods", "Ammo", "Keys", "Other", "Junk" }
local IS_SECTION = {}
for _, name in ipairs(Items.SECTIONS) do IS_SECTION[name] = true end
-- (the game's item classes: 0 consumable, 1 container, 2 weapon, 3 gem, 4 armour, 5 reagent, 6 projectile,
-- 7 trade goods, 9 recipe, 11 quiver, 12 quest, 13 key, 15 miscellaneous)
local BY_CLASS = { [0] = "Consumables", [2] = "Equipment", [3] = "Trade goods", [4] = "Equipment", [5] = "Trade goods",
	[6] = "Ammo", [7] = "Trade goods", [9] = "Trade goods", [12] = "Quest", [13] = "Keys" }
local RED_TEXT = "|cffdb6b61" -- what you can't pay: a quiet red

local Container = C_Container or {}
local Instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local ItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

Items.KEYRING = rawget(_G, "KEYRING_CONTAINER")
Items.REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag

function Items.IdOf(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The bags ------------------------------------------------------------------------------------------------------------

function Items.Bags()
	local list = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
	if Items.REAGENT_BAG then list[#list + 1] = Items.REAGENT_BAG end
	if Items.KEYRING then list[#list + 1] = Items.KEYRING end
	return list
end

function Items.NumSlots(bag)
	return Clean(Safe(Container.GetContainerNumSlots or _G.GetContainerNumSlots, bag)) or 0
end

function Items.Slot(bag, slot)
	local entry
	if Container.GetContainerItemInfo then
		local info = Safe(Container.GetContainerItemInfo, bag, slot)
		if type(info) ~= "table" then return nil end
		entry = { link = Clean(info.hyperlink), icon = Clean(info.iconFileID), count = Clean(info.stackCount),
			quality = Clean(info.quality), locked = Clean(info.isLocked), id = Clean(info.itemID),
			noValue = Clean(info.hasNoValue) }
	elseif _G.GetContainerItemInfo then
		local icon, count, locked, quality, _, _, link, _, noValue, id = Safe(_G.GetContainerItemInfo, bag, slot)
		entry = { link = Clean(link), icon = Clean(icon), count = Clean(count), quality = Clean(quality),
			locked = Clean(locked), id = Clean(id), noValue = Clean(noValue) }
	end
	if not entry or type(entry.link) ~= "string" then return nil end
	entry.bag, entry.slot = bag, slot
	entry.count = type(entry.count) == "number" and entry.count or 1
	entry.id = type(entry.id) == "number" and entry.id or Items.IdOf(entry.link)
	entry.locked = entry.locked and true or false
	entry.noValue = entry.noValue and true or false
	local quest = Container.GetContainerItemQuestInfo and Safe(Container.GetContainerItemQuestInfo, bag, slot)
	entry.quest = type(quest) == "table" and (Clean(quest.isQuestItem) or Clean(quest.questID)) and true or false
	return entry
end

-- What an item is ------------------------------------------------------------------------------------------------------

-- Its class, equip slot and name filled in; whether its stacks make one cell (never gear: each piece is its own).
-- An entry from the saved bags of another character has only link, count, quality and id: that is enough.
function Items.Describe(entry)
	local _, _, _, equipLoc, icon, classID, subclassID = Safe(Instant, entry.id or entry.link)
	entry.classID, entry.subclassID = Clean(classID) or 15, Clean(subclassID) or 0
	entry.equipLoc = Clean(equipLoc) or ""
	entry.icon = entry.icon or Clean(icon)
	entry.name = type(entry.link) == "string" and entry.link:match("%[(.-)%]") or ""
	if type(entry.quality) ~= "number" then
		local get = (C_Item and C_Item.GetItemQualityByID)
		entry.quality = get and Clean(Safe(get, entry.link)) or 1
	end
	local equips = entry.equipLoc ~= "" and not entry.equipLoc:find("NON_EQUIP")
	local stack = C_Item and C_Item.GetItemMaxStackSizeByID and entry.id and Clean(Safe(C_Item.GetItemMaxStackSizeByID, entry.id))
	entry.merge = (type(stack) == "number" and stack > 1) or not (equips or entry.classID == 2 or entry.classID == 4)
	entry.equips = equips
	return entry
end

local function AutoSection(entry)
	if entry.quest or entry.classID == 12 then return "Quest" end
	if entry.quality == 0 then return "Junk" end
	if entry.classID == 1 or entry.classID == 11 then return "Other" end
	if entry.equips then return "Equipment" end
	return BY_CLASS[entry.classID] or "Other"
end

-- One of your own sections (made with Alt-right-click in the bags)?
function Items.IsCustom(name)
	local cats = ns.db and ns.db.bagCats
	for _, custom in ipairs(type(cats) == "table" and cats or {}) do
		if custom == name then return true end
	end
	return false
end

-- The section an item is shown in: the one you gave it (while that section still exists), else by what it is.
function Items.Section(entry)
	if entry.classID == nil then Items.Describe(entry) end
	local pins = ns.db and ns.db.bagPins
	local pin = entry.id and type(pins) == "table" and pins[entry.id]
	if pin and (IS_SECTION[pin] or Items.IsCustom(pin)) then return pin end
	return AutoSection(entry)
end

-- Junk: what the bags show under Junk (grey, not a quest's, not given another section; or put in Junk).
function Items.IsJunk(entry)
	return Items.Section(entry) == "Junk"
end

-- Money ------------------------------------------------------------------------------------------------------------------

-- What a vendor pays for one (0: nothing). item: a link or an id.
function Items.SellPrice(item)
	if not item then return 0 end
	local price = Clean(select(11, Safe(ItemInfo, item)))
	return type(price) == "number" and price or 0
end

-- An amount of copper with the game's coin icons. red: in a quiet red (what you can't pay).
function Items.Coins(copper, red)
	if type(copper) ~= "number" then return "" end
	local text = Safe(GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString), copper)
	text = text or ("%dc"):format(copper)
	return red and (RED_TEXT .. text .. "|r") or text
end
