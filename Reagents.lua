local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Reagents kept in mind. A spell on your bars that uses up a reagent (a rune, a shard, a seed, arrows for a shot)
-- shows how many times it can still be cast (the game's own count); at the warning or fewer, that count turns a
-- warm amber. At a merchant who sells such a reagent: one quiet line says so, and Serene's merchant window marks it.
-- Counts are read out of a fight (they are secret in one): the last known stays until it ends.
--   (Settings > Action bars > Ranks and reagents)

local LOW = { 0.98, 0.62, 0.3 }   -- running low: a warm amber
local OUT = { 0.95, 0.42, 0.38 }  -- none left: the soft red
local SOFT = ns.SOFT_RGB

local CAB = _G.C_ActionBar
local Actions = ns.Actions
local low = {}        -- button -> casts left, while running low
local reagents = {}   -- spellID -> { item names } (read from its tooltip, once)
local lowItems = {}   -- item name -> casts left (the lowest of the spells using it)
local painted = {}    -- button -> its count's colour set by Serene (given back once no longer low)
local queued = false

-- How many casts the reagents allow (nil: not a reagent spell, or not readable now).
local function Casts(slot, id)
	local consumable = CAB and CAB.IsConsumableAction and Clean(Safe(CAB.IsConsumableAction, slot))
	if consumable ~= true and not (C_Spell and C_Spell.IsConsumableSpell and Clean(Safe(C_Spell.IsConsumableSpell, id))) then
		return nil
	end
	local count = CAB and CAB.GetActionUseCount and Clean(Safe(CAB.GetActionUseCount, slot))
	if type(count) ~= "number" and _G.GetActionCount then count = Clean(Safe(_G.GetActionCount, slot)) end
	return type(count) == "number" and count or nil
end

-- The reagents a spell names in its tooltip ("Reagents: Rune of Teleportation").
local function Prefix()
	local text = rawget(_G, "SPELL_REAGENTS")
	if type(text) == "string" then
		text = text:gsub("%%s", ""):gsub("|n", ""):gsub("%s+$", "")
		if text ~= "" then return text end
	end
	return "Reagents:"
end

local function ReagentsOf(slot, id)
	if reagents[id] then return reagents[id] end
	if not (C_TooltipInfo and C_TooltipInfo.GetAction) then return nil end
	local data = Safe(C_TooltipInfo.GetAction, slot)
	local lines = data and Clean(data.lines)
	if type(lines) ~= "table" then return nil end
	local prefix = Prefix()
	for _, line in ipairs(lines) do
		local text = Clean(line.leftText)
		if type(text) == "string" then
			text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if text:sub(1, #prefix) == prefix then
				local names = {}
				for name in text:sub(#prefix + 1):gmatch("[^,]+") do
					name = strtrim(name)
					if name ~= "" then names[#names + 1] = name end
				end
				reagents[id] = names
				return names
			end
		end
	end
	return nil
end

local function Paint(button)
	local count = Actions.Region(button, "Count")
	if not count then return end
	local left = ns.On("barReagents") and low[button]
	-- (a count never coloured is left as the game draws it)
	if left == nil and not painted[button] then return end
	painted[button] = left ~= nil or nil
	local c = left == nil and SOFT or (left <= 0 and OUT or LOW)
	pcall(count.SetTextColor, count, c[1], c[2], c[3])
end

local function Look()
	queued = false
	if InCombatLockdown() then return end
	wipe(lowItems)
	local limit = tonumber(ns.db and ns.db.barReagentLow) or 5
	-- (every action button, Serene's action bars on or not)
	Actions.Each(function(button)
		local slot = Actions.Slot(button)
		local id = slot and Actions.SpellOn(slot)
		local casts = id and Casts(slot, id)
		if casts and casts <= limit then
			low[button] = casts
			for _, name in ipairs(ReagentsOf(slot, id) or {}) do
				if not lowItems[name] or lowItems[name] > casts then lowItems[name] = casts end
			end
		else
			low[button] = nil
		end
		Paint(button)
	end)
end

local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0.3, Look)
end

-- (Vendor.lua: an item the merchant sells that you are running low on; casts left, or nil)
function ns.ReagentLow(name)
	if not ns.On("barReagents") or type(name) ~= "string" then return nil end
	return lowItems[name]
end

-- At a merchant: what he sells that you are running low on, in one quiet line.
local function Merchant()
	if not ns.On("barReagents") or not next(lowItems) then return end
	local api = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	local found = {}
	for index = 1, Clean(Safe(_G.GetMerchantNumItems)) or 0 do
		local name
		local info = api and Safe(api, index)
		if type(info) == "table" then name = Clean(info.name) else name = Clean(Safe(_G.GetMerchantItemInfo, index)) end
		if name and lowItems[name] then found[#found + 1] = ("%s (%d left)"):format(name, lowItems[name]) end
	end
	if #found > 0 then ns.Print("running low, sold here: " .. table.concat(found, ", ")) end
end

local function Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_USES",
		"UNIT_INVENTORY_CHANGED", "MERCHANT_SHOW" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "MERCHANT_SHOW" then
			Look()
			return Merchant()
		end
		Queue()
	end)
end

local function Refresh() Queue() end

function ns.ReagentsDebug()
	local buttons, items = 0, {}
	for _ in pairs(low) do buttons = buttons + 1 end
	for name, left in pairs(lowItems) do items[#items + 1] = name .. " " .. left end
	ns.Print(("reagents: %s, warn at %s; %d buttons low%s"):format(tostring(ns.On("barReagents")),
		tostring(ns.db.barReagentLow), buttons, #items > 0 and (" (" .. table.concat(items, ", ") .. ")") or ""))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
