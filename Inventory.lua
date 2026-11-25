local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- What each of your characters carries, remembered: their bags and bank as last seen, their money and class, by realm
-- and name (SereneDB.inv). Bags.lua keeps it (each look at your bags, and at the bank while at a banker) and shows it
-- (another character's bags, the bank from anywhere). Item tooltips say how many are in the bank or on your other
-- characters: only what you wouldn't see anyway (with "bags" and "bagCounts" on).
--   ns.Inventory.Me()                       the realm and your name
--   Realm(), Mine()                         every character on this realm; yours (its money and class kept fresh)
--   Remember(where, entries, free, special) "bags" or "bank", as just scanned
--   Remembered(name, where)                 a character's, as entries again: entries, free, special, character
--   ClassHex(class)                         a class's colour, as a text colour

local IdOf = ns.Items.IdOf
local countsIndex -- itemID -> { name -> { bags, bank } }, built when asked

local function Me()
	return Clean(Safe(GetRealmName)) or "?", Clean(Safe(UnitName, "player")) or "?"
end

local function Realm()
	local realm = Me()
	ns.db.inv[realm] = ns.db.inv[realm] or {}
	return ns.db.inv[realm]
end

local function Mine()
	local _, name = Me()
	local characters = Realm()
	local me = characters[name] or {}
	characters[name] = me
	me.class = Clean(select(2, Safe(UnitClass, "player"))) or me.class
	me.money = Clean(Safe(GetMoney)) or me.money
	return me
end

local function Remember(where, entries, free, special)
	local me = Mine()
	local items = {}
	for _, entry in ipairs(entries) do items[#items + 1] = { entry.link, entry.count, entry.quality } end
	me[where] = items
	me[where .. "Free"] = free.count
	me[where .. "Special"] = special
	me[where .. "At"] = time()
	countsIndex = nil -- (the tooltips' counts made again when next asked)
end

local function Remembered(name, where)
	local character = Realm()[name]
	if not character or type(character[where]) ~= "table" then return nil end
	local entries = {}
	for _, item in ipairs(character[where]) do
		if type(item[1]) == "string" then
			entries[#entries + 1] = { link = item[1], count = item[2] or 1, quality = item[3], id = IdOf(item[1]) }
		end
	end
	return entries, { count = character[where .. "Free"] or 0 }, character[where .. "Special"] or {}, character
end

local function ClassHex(class)
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local color = colors and class and colors[class]
	if not color then return ns.SOFT end
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
end


ns.Inventory = { Me = Me, Realm = Realm, Mine = Mine, Remember = Remember, Remembered = Remembered,
	ClassHex = ClassHex }

-- Counts in item tooltips -------------------------------------------------------------------------------------------------

local function Index()
	if countsIndex then return countsIndex end
	countsIndex = {}
	for name, character in pairs(Realm()) do
		for _, where in ipairs({ "bags", "bank" }) do
			for _, item in ipairs(type(character[where]) == "table" and character[where] or {}) do
				local id = IdOf(item[1])
				if id then
					countsIndex[id] = countsIndex[id] or {}
					local counts = countsIndex[id][name] or { bags = 0, bank = 0 }
					countsIndex[id][name] = counts
					counts[where] = counts[where] + (item[2] or 1)
				end
			end
		end
	end
	return countsIndex
end

local function CountWords(counts)
	local words = {}
	if counts.bags > 0 then words[#words + 1] = "bags " .. counts.bags end
	if counts.bank > 0 then words[#words + 1] = "bank " .. counts.bank end
	return table.concat(words, "  ·  ")
end

local function OnItemTooltip(tooltip, data)
	if not ns.On("bags") or not ns.On("bagCounts") then return end
	if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
	local id = type(data) == "table" and Clean(data.id)
	if type(id) ~= "number" then
		local _, link = Safe(tooltip.GetItem, tooltip)
		id = IdOf(Clean(link))
	end
	local holders = id and Index()[id]
	if not holders then return end
	local _, me = Me()
	local others = {}
	for name in pairs(holders) do
		if name ~= me then others[#others + 1] = name end
	end
	local mine = holders[me]
	-- (only what you would not see anyway: the bank, or your other characters)
	if not others[1] and not (mine and mine.bank > 0) then return end
	table.sort(others)
	if mine then table.insert(others, 1, me) end
	tooltip:AddLine(" ")
	for _, name in ipairs(others) do
		local character = Realm()[name] or {}
		tooltip:AddDoubleLine(ClassHex(character.class) .. name .. "|r", ns.MUTED .. CountWords(holders[name]) .. "|r")
	end
	if (tonumber(Clean(tooltip.shownMoneyFrames)) or 0) == 0 then tooltip:Show() end
end

local function HookTooltips()
	local processor = _G.TooltipDataProcessor
	local types = Enum and Enum.TooltipDataType
	if processor and processor.AddTooltipPostCall and types and types.Item then
		pcall(processor.AddTooltipPostCall, types.Item, OnItemTooltip)
		return
	end
	for _, tooltip in ipairs({ GameTooltip, _G.ItemRefTooltip }) do
		if tooltip and tooltip.HasScript and Safe(tooltip.HasScript, tooltip, "OnTooltipSetItem") then
			tooltip:HookScript("OnTooltipSetItem", function(self) OnItemTooltip(self) end)
		end
	end
end

table.insert(ns.modules, { init = function() if ns.On("bags") then HookTooltips() end end })
