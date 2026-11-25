local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Supplies: one button that always holds the best you carry of its kind, kept up to date as your bags change.
--   food     the best food for your level (conjured first; food kept for its Well Fed buff only when nothing else)
--   water    the best drink
--   health   a healthstone, else the best healing potion
--   mana     the best mana potion (or a mana gem)
--   bandage  the best bandage you can use
-- Each is one of your character's macros ("Serene Food"...), made the first time you ask for it (Settings > Action
-- bars > Supplies, or /serene supply food): it comes onto the cursor, put it on any bar. Serene rewrites the macro
-- out of a fight (the game allows none in one). Run out: the button keeps the last one, its count at 0.
--   /serene supply food|water|health|mana|bandage

local KINDS = {
	{ key = "food", macro = "Serene Food", label = "Food" },
	{ key = "water", macro = "Serene Water", label = "Water" },
	{ key = "health", macro = "Serene Heal", label = "Health" },
	{ key = "mana", macro = "Serene Mana", label = "Mana" },
	{ key = "bandage", macro = "Serene Bandage", label = "Bandage" },
}
ns.SUPPLY_KINDS = KINDS
local ICON = 134400        -- the question mark: with #showtooltip the macro shows the item's own icon
local BAGS = 4             -- the backpack and the four bags (0-4; the reagent bag holds no supplies)
local HEALTHSTONES = {     -- (a healthstone first: it doesn't share the potions' cooldown)
	[5512] = true, [19004] = true, [19005] = true, [5511] = true, [19006] = true, [19007] = true,
	[5509] = true, [19008] = true, [19009] = true, [5510] = true, [19010] = true, [19011] = true,
	[9421] = true, [19012] = true, [19013] = true,
}
local SPELLS = { food = 433, water = 430, health = 441, mana = 2023, bandage = 746 } -- Food, Drink, Healing Potion,
                                                                                     -- Restore Mana, First Aid

local store       -- this character's: { last = { kind -> itemID } }
local names = {}  -- kind -> the item spell's name in your language
local queued, fightWaits = false, false
local chosen = {} -- kind -> itemID (the last look)

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return Clean(Safe(C_Spell.GetSpellName, id)) end
	return Clean((Safe(GetSpellInfo, id)))
end

local function ItemSpell(item)
	local get = C_Item and C_Item.GetItemSpell or _G.GetItemSpell
	return Clean((Safe(get, item)))
end

local function Instant(item)
	local get = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	local _, _, _, _, _, class, subclass = Safe(get, item)
	return Clean(class), Clean(subclass)
end

local function Info(item)
	local get = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
	local name, _, _, level, minLevel, _, _, _, _, _, price = Safe(get, item)
	return Clean(name), Clean(level), Clean(minLevel), Clean(price)
end

local function Usable(item)
	local get = C_Item and C_Item.IsUsableItem or _G.IsUsableItem
	return Clean((Safe(get, item))) ~= false
end

-- Which kind an item is (nil: none of them).
local function KindOf(item)
	if HEALTHSTONES[item] then return "health" end
	local class, subclass = Instant(item)
	-- (consumables only: class 0; subclass 7 is Bandage)
	if class ~= 0 then return nil end
	local spell = ItemSpell(item)
	if subclass == 7 or (spell and spell == names.bandage) then return "bandage" end
	if not spell then return nil end
	if spell == names.food then return "food" end
	if spell == names.water then return "water" end
	if spell == names.health then return "health" end
	if spell == names.mana then return "mana" end
	return nil
end

-- The best of each kind in your bags.
local function Choose()
	local level = Clean(Safe(UnitLevel, "player")) or 1
	local found = {} -- kind -> { item = id, score = ..., count = ... }
	local counts = {}
	local get = C_Container and C_Container.GetContainerItemInfo
	local slots = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
	for bag = 0, BAGS do
		for slot = 1, Clean(Safe(slots, bag)) or 0 do
			local info = get and Safe(get, bag, slot)
			local item = type(info) == "table" and Clean(info.itemID)
			if type(item) == "number" then
				counts[item] = (counts[item] or 0) + (Clean(info.stackCount) or 1)
			end
		end
	end
	for item, count in pairs(counts) do
		local kind = KindOf(item)
		if kind then
			local name, itemLevel, minLevel, price = Info(item)
			if name and (minLevel or 0) <= level and Usable(item) then
				-- (higher level first; conjured, free, before bought; a smaller stack before a bigger, to free room)
				-- (each part too small to outweigh the one before it)
				local conjured = price == 0 and 1 or 0
				local buff = kind == "food" and ns.MakesWellFed and ns.MakesWellFed(item) and 1 or 0
				local score = (1 - buff) * 1e6 + (HEALTHSTONES[item] and 5e5 or 0) + (itemLevel or 0) * 100
					+ conjured * 10 - math.min(count, 9) / 10
				if not found[kind] or found[kind].score < score then
					found[kind] = { item = item, score = score }
				end
			end
		end
	end
	return found
end

local function Body(item)
	if not item then return "#showtooltip" end
	return ("#showtooltip\n/use item:%d"):format(item)
end

local function MacroIndex(kind)
	local index = Clean(Safe(GetMacroIndexByName, kind.macro))
	return type(index) == "number" and index > 0 and index or nil
end

-- Each of Serene's supply macros rewritten for what is best now (only those you made).
local function Update()
	queued = false
	if not store or not ns.On("barSupplies") then return end
	if InCombatLockdown() then
		fightWaits = true
		return
	end
	local found = Choose()
	for _, kind in ipairs(KINDS) do
		local best = found[kind.key] and found[kind.key].item
		if best then store.last[kind.key] = best end
		chosen[kind.key] = best
		local index = MacroIndex(kind)
		if index then
			local item = best or store.last[kind.key]
			-- (rewritten only when it differs, with or without the trailing newline the game may add: each edit
			-- fires UPDATE_MACROS, which looks again)
			local _, _, body = Safe(GetMacroInfo, index)
			if Clean(body) ~= Body(item) .. "\n" and Clean(body) ~= Body(item) then
				Safe(EditMacro, index, kind.macro, ICON, Body(item))
			end
		end
	end
end

local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0.5, Update)
end

-- A supply button onto the cursor (made first, if it isn't yet), to put on a bar.
function ns.SupplyPickup(key)
	if not store then return end
	local kind
	for _, k in ipairs(KINDS) do if k.key == key then kind = k end end
	if not kind then return ns.Print("supply: food, water, health, mana or bandage") end
	if InCombatLockdown() then return ns.Print("supplies: not in a fight") end
	local index = MacroIndex(kind)
	if not index then
		local found = Choose()
		local item = found[key] and found[key].item or store.last[key]
		-- (true: one of this character's macros, not the account's)
		local ok, made = pcall(CreateMacro, kind.macro, ICON, Body(item), true)
		index = ok and Clean(made)
		if type(index) ~= "number" then
			return ns.Print("supplies: no room for another macro of this character's (/macro)")
		end
	end
	if not ns.On("barSupplies") then ns.db.barSupplies = true end
	Update()
	Safe(ClearCursor)
	Safe(PickupMacro, index)
	ns.Print(("supplies: \"%s\" on the cursor - put it on a bar"):format(kind.label))
end

local function Init()
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	ns.db.supplies = ns.db.supplies or {}
	ns.db.supplies[who] = ns.db.supplies[who] or {}
	store = ns.db.supplies[who]
	store.last = store.last or {}
	for key, id in pairs(SPELLS) do names[key] = SpellName(id) end
	local events = CreateFrame("Frame")
	-- (GET_ITEM_INFO_RECEIVED: an item whose info was not loaded yet counts once it is)
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
		"GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "UPDATE_MACROS" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if not fightWaits then return end
			fightWaits = false
		end
		if event == "PLAYER_ENTERING_WORLD" then
			-- (a spell's name may not be loaded yet at login)
			for key, id in pairs(SPELLS) do names[key] = names[key] or SpellName(id) end
		end
		Queue()
	end)
end

local function Refresh() Queue() end

function ns.SuppliesDebug()
	local parts = {}
	for _, kind in ipairs(KINDS) do
		local item = chosen[kind.key]
		local name = item and Info(item)
		parts[#parts + 1] = ("%s %s%s"):format(kind.key, name or (item and tostring(item)) or "-",
			MacroIndex(kind) and "" or " (no macro)")
	end
	ns.Print(("supplies: %s; %s"):format(tostring(ns.On("barSupplies")), table.concat(parts, ", ")))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
