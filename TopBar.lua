local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The top bar: what Titan Panel told you, in Serene's glass.
-- * One dark band at the top of the screen, fading at both ends, a fine gold rule under it; only as wide as what it
--   says, so the portraits and the compass keep their place (nothing is moved).
-- * Its words, side by side: the queue you are in (while in one: the compass and its eye rest away),
--   the zone and where you stand, experience, money, free bag slots, the worst-worn piece
--   of gear, the loot rule (in a group only), frames per second and latency, the volume, the time.
--   Quiet labels, soft values; gold or red only when something wants you (bags nearly full, gear breaking).
-- * Each word has its tooltip (Serene's glass) and a click: the world map, bags, calendar... The mouse wheel over
--   the volume changes it.
-- * Right click: which words it shows. Shift and drag: move it (the menu puts it back in the middle).
-- When it shows is Fade.lua's: like the menu and bags, it rests away and comes back under the mouse (worn gear or
-- full bags, or a queue, bring it back too); or away in fights only, or always (/serene top hover|calm|always).
-- /serene top on|off

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local INK = ns.INK
local GOLD = { 1, 0.82, 0.35 }
local SOFT = ns.SOFT_RGB
local HEIGHT, FADE, PAD, GAP = 20, 36, 6, 9
local SIZE = 11
local EVERY = 0.5 -- seconds between two looks at the words

local WARN = "|cffffd100"
local BAD = "|cffff6a5a"
local RESTED = "|cff8fb8ff"

local ZONE_COLORS = {
	sanctuary = { 0.55, 0.85, 1 }, friendly = { 0.55, 0.92, 0.55 }, hostile = { 1, 0.5, 0.45 },
	contested = { 1, 0.78, 0.4 }, arena = { 1, 0.5, 0.45 }, combat = { 1, 0.5, 0.45 },
}
local DEFAULT_ZONE = { 1, 0.92, 0.75 }

-- The words, in their order on the bar.
local ORDER = { "queue", "zone", "coords", "xp", "gold", "bags", "repair", "loot", "perf", "volume", "clock" }
local NAMES = {
	queue = "Queue (while in one)", zone = "Zone", coords = "Coordinates", xp = "Experience", gold = "Money", bags = "Bag space",
	repair = "Durability", loot = "Loot rule (in a group)", perf = "Frames and latency", volume = "Volume",
	clock = "Time",
}

local bar, menu
local items = {}
local laid = "" -- what the bar was laid out for (each word's width)

local function Label(text) return ns.MUTED .. text .. "|r" end

local function Text(parent)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", SIZE, "")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
	text:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	return text
end

local function Shown(key)
	local list = ns.db.topItems
	return type(list) == "table" and list[key] and true or false
end

local function GetVar(name)
	if C_CVar and C_CVar.GetCVar then return Clean(Safe(C_CVar.GetCVar, name)) end
	return Clean(Safe(GetCVar, name))
end

local function SetVar(name, value)
	if C_CVar and C_CVar.SetCVar then return Safe(C_CVar.SetCVar, name, value) end
	return Safe(SetCVar, name, value)
end

-- Money ------------------------------------------------------------------------------------------------------------

local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:1:0|t"
local function Coins(copper, short)
	copper = math.floor(math.abs(copper or 0))
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. COIN:format("Gold") end
	if s > 0 or (g > 0 and not short) then parts[#parts + 1] = s .. COIN:format("Silver") end
	if (c > 0 or #parts == 0) and not (short and g > 0) then parts[#parts + 1] = c .. COIN:format("Copper") end
	return table.concat(parts, " ")
end
ns.TopCoins = Coins -- (tests)

local session = { money = nil, xp = 0, started = GetTime() }

local function Realm() return Clean(Safe(GetRealmName)) or "?" end
local function Me() return Clean(Safe(UnitName, "player")) or "?" end

local function SaveMoney()
	local money = Clean(Safe(GetMoney))
	if type(money) ~= "number" then return end
	if session.money == nil then session.money = money end
	ns.db.gold = type(ns.db.gold) == "table" and ns.db.gold or {}
	local realm = Realm()
	ns.db.gold[realm] = type(ns.db.gold[realm]) == "table" and ns.db.gold[realm] or {}
	local _, class = Safe(UnitClass, "player")
	ns.db.gold[realm][Me()] = { money = money, class = Clean(class) }
end

-- Experience ---------------------------------------------------------------------------------------------------------

local lastXP, lastMax, lastLevel

local function MaxLevel()
	local most = Clean(Safe(GetMaxLevelForPlayerExpansion)) or Clean(Safe(GetMaxPlayerLevel)) or MAX_PLAYER_LEVEL
	return type(most) == "number" and most or 60
end

local function AtMax()
	local level = Clean(Safe(UnitLevel, "player"))
	return type(level) == "number" and level >= MaxLevel()
end

-- (experience earned this session, across a level gained)
local function CountXP()
	local xp, most, level = Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player")), Clean(Safe(UnitLevel, "player"))
	if type(xp) ~= "number" or type(most) ~= "number" or type(level) ~= "number" then return end
	if lastXP then
		if level > lastLevel then
			session.xp = session.xp + (lastMax - lastXP) + xp
		elseif xp > lastXP then
			session.xp = session.xp + (xp - lastXP)
		end
	end
	lastXP, lastMax, lastLevel = xp, most, level
end

local function Duration(seconds)
	seconds = math.floor(seconds)
	if seconds >= 3600 then return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
	if seconds >= 60 then return ("%dm"):format(math.floor(seconds / 60)) end
	return ("%ds"):format(seconds)
end

-- Bags ---------------------------------------------------------------------------------------------------------------

local function BagSpace()
	local get = C_Container and C_Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
	local size = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
	local free, total, special = 0, 0, {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local slots = Clean(Safe(size, bag)) or 0
		if slots > 0 then
			local open, kind = Safe(get, bag)
			open, kind = Clean(open) or 0, Clean(kind) or 0
			if kind == 0 then
				free, total = free + open, total + slots
			else
				special[#special + 1] = { bag = bag, free = open, total = slots }
			end
		end
	end
	return free, total, special
end

local function BagWords(free)
	if free == 0 then return BAD end
	if free <= 4 then return WARN end
	return ""
end

-- Durability ---------------------------------------------------------------------------------------------------------

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function Worn()
	local lowest, pieces = nil, {}
	for _, slot in ipairs(SLOTS) do
		local now, most = Safe(GetInventoryItemDurability, slot)
		now, most = Clean(now), Clean(most)
		if type(now) == "number" and type(most) == "number" and most > 0 then
			local part = now / most
			pieces[#pieces + 1] = { slot = slot, part = part }
			if not lowest or part < lowest then lowest = part end
		end
	end
	return lowest, pieces
end

local function WornColor(part)
	if part <= 0.2 then return BAD end
	if part <= 0.5 then return WARN end
	return ""
end

local scan
local function RepairCost(slot)
	if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
		local data = Safe(C_TooltipInfo.GetInventoryItem, "player", slot)
		return type(data) == "table" and Clean(data.repairCost) or 0
	end
	if not scan then
		scan = CreateFrame("GameTooltip", "SereneTopScanTip", nil, "GameTooltipTemplate")
	end
	scan:SetOwner(WorldFrame, "ANCHOR_NONE")
	scan:ClearLines()
	local _, _, cost = Safe(scan.SetInventoryItem, scan, "player", slot)
	scan:Hide()
	return Clean(cost) or 0
end

-- Loot ---------------------------------------------------------------------------------------------------------------

local LOOT = {
	freeforall = "Free for all", roundrobin = "Round robin", master = "Master looter", group = "Group loot",
	needbeforegreed = "Need before greed", personal = "Personal",
	[0] = "Free for all", [1] = "Round robin", [2] = "Master looter", [3] = "Group loot", [4] = "Need before greed",
	[5] = "Personal",
}

local function LootRule()
	if not Clean(Safe(IsInGroup)) then return nil end
	local get = C_PartyInfo and C_PartyInfo.GetLootMethod or _G.GetLootMethod
	local method = Clean(Safe(get))
	if method == nil then return nil end
	local threshold = Clean(Safe(GetLootThreshold))
	return LOOT[method] or tostring(method), threshold
end

local function QualityColor(quality)
	local color = type(quality) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex or "|cffffffff"
end

-- Clock --------------------------------------------------------------------------------------------------------------

local function Clock()
	if GameTime_GetTime then
		local text = Clean(Safe(GameTime_GetTime, true))
		if type(text) == "string" and text ~= "" then return text end
	end
	return date("%H:%M")
end

local function Invites()
	local count = C_Calendar and Clean(Safe(C_Calendar.GetNumPendingInvites))
	return type(count) == "number" and count or 0
end

-- Coordinates --------------------------------------------------------------------------------------------------------

local function Coordinates()
	local map = C_Map and Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	if not map then return nil end
	local position = Safe(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = Safe(position.GetXY, position)
	x, y = Clean(x), Clean(y)
	if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
	return x * 100, y * 100
end

-- The queue ----------------------------------------------------------------------------------------------------------

local function Waited(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local LFG_CATEGORIES = { "LE_LFG_CATEGORY_LFD", "LE_LFG_CATEGORY_RF", "LE_LFG_CATEGORY_SCENARIO",
	"LE_LFG_CATEGORY_LFR", "LE_LFG_CATEGORY_FLEXRAID", "LE_LFG_CATEGORY_WORLDPVP", "LE_LFG_CATEGORY_BATTLEFIELD" }
local LFG_STATE = { queued = "searching", rolecheck = "role check", proposal = "ready", suspended = "paused" }

-- Every queue you are in: { name, state, ready, waited, estimate } (seconds).
local function Queues()
	local list, grouped = {}, false
	-- (the dungeon finder and its kin)
	if GetLFGMode then
		local seen = {}
		for _, key in ipairs(LFG_CATEGORIES) do
			local category = _G[key]
			if type(category) == "number" and not seen[category] then
				seen[category] = true
				local mode = Clean(Safe(GetLFGMode, category))
				if mode == "lfgparty" or mode == "abandonedInDungeon" then grouped = true end
				local state = LFG_STATE[mode]
				if state then
					local entry = { name = "Group finder", state = state, ready = mode == "proposal" }
					if mode == "queued" and GetLFGQueueStats then
						-- (hasData ... instanceName 11, averageWait 12, ... myWait 16, queuedTime 17)
						local stats = { Safe(GetLFGQueueStats, category) }
						local name, average, mine, since = Clean(stats[11]), Clean(stats[12]), Clean(stats[16]), Clean(stats[17])
						if type(name) == "string" and name ~= "" then entry.name = name end
						if type(since) == "number" and since > 0 then entry.waited = GetTime() - since end
						local wait = type(mine) == "number" and mine > 0 and mine or average
						if type(wait) == "number" and wait > 0 then entry.estimate = wait end
					end
					list[#list + 1] = entry
				end
			end
		end
	end
	-- (battlegrounds)
	local most = Clean(Safe(GetMaxBattlefieldID)) or MAX_BATTLEFIELD_QUEUES or 0
	for index = 1, (type(most) == "number" and most or 0) do
		local status, map = Safe(GetBattlefieldStatus, index)
		status, map = Clean(status), Clean(map)
		if status == "queued" or status == "confirm" then
			local entry = { name = type(map) == "string" and map ~= "" and map or "Battleground",
				state = status == "confirm" and "ready" or "searching", ready = status == "confirm" }
			local waited = Clean(Safe(GetBattlefieldTimeWaited, index))
			if type(waited) == "number" and waited > 0 then entry.waited = waited / 1000 end
			local estimate = Clean(Safe(GetBattlefieldEstimatedWaitTime, index))
			if type(estimate) == "number" and estimate > 0 then entry.estimate = estimate / 1000 end
			list[#list + 1] = entry
		elseif status == "active" then
			grouped = true
		end
	end
	-- (the group finder's listings: your own group listed, or groups you asked to join)
	local lfg = C_LFGList
	if lfg then
		if Clean(Safe(lfg.HasActiveEntryInfo)) then list[#list + 1] = { name = "Your group", state = "listed" } end
		local applications = Clean(Safe(lfg.GetApplications))
		if type(applications) == "table" then
			local applied, invited = 0, 0
			for _, id in ipairs(applications) do
				local _, status = Safe(lfg.GetApplicationInfo, id)
				status = Clean(status)
				if status == "applied" then applied = applied + 1 elseif status == "invited" then invited = invited + 1 end
			end
			if invited > 0 then list[#list + 1] = { name = "Group finder", state = "invited", ready = true } end
			if applied > 0 then
				list[#list + 1] = { name = "Group finder", state = applied == 1 and "applied" or (applied .. " applied") }
			end
		end
	end
	-- (the eye shown, the game's reason unknown here)
	if #list == 0 and not grouped and ns.QueueShown and ns.QueueShown() then
		list[#list + 1] = { name = "Group finder", state = "searching" }
	end
	table.sort(list, function(a, b) return (a.ready and 1 or 0) > (b.ready and 1 or 0) end)
	return list
end

local function QueueState(entry)
	if entry.ready then return WARN .. entry.state .. "|r" end
	if entry.waited then return ns.SOFT .. Waited(entry.waited) .. "|r" end
	return ns.SOFT .. entry.state .. "|r"
end

-- The eye's own click (its menu leaves the queue), or the group finder.
local function ClickEye(button)
	local eye = ns.QueueShown and ns.QueueShown()
	if eye then
		if eye.GetScript and eye:GetScript("OnClick") and eye.Click then return Safe(eye.Click, eye, button) end
		local up = eye.GetScript and eye:GetScript("OnMouseUp")
		if up then return Safe(up, eye, button) end
	end
	if button == "RightButton" then return end
	for _, name in ipairs({ "PVEFrame_ToggleFrame", "ToggleLFDParentFrame", "ToggleLFGParentFrame", "ToggleLFGFrame" }) do
		if type(_G[name]) == "function" then return Safe(_G[name]) end
	end
end

-- Volume -------------------------------------------------------------------------------------------------------------

local function Volume()
	local on = GetVar("Sound_EnableAllSound")
	local master = tonumber(GetVar("Sound_MasterVolume") or "") or 1
	return on ~= "0", master
end

local function SetVolume(delta)
	local _, master = Volume()
	master = math.max(0, math.min(1, math.floor((master + delta) * 20 + 0.5) / 20))
	SetVar("Sound_MasterVolume", tostring(master))
end

local function ToggleSound()
	if _G.Sound_ToggleSound then return Safe(_G.Sound_ToggleSound) end
	local on = Volume()
	SetVar("Sound_EnableAllSound", on and "0" or "1")
end

-- The words: what each says, its tooltip, its click -------------------------------------------------------------

local function Hint(tip, text) ns.TipHint(tip, text) end

local DEF = {}

DEF.zone = {
	text = function()
		local zone = Clean(Safe(GetMinimapZoneText)) or Clean(Safe(GetZoneText)) or ""
		local c = ZONE_COLORS[Clean(Safe(GetZonePVPInfo)) or ""] or DEFAULT_ZONE
		return zone, c
	end,
	tip = function(tip)
		tip:AddLine(Clean(Safe(GetZoneText)) or "", GOLD[1], GOLD[2], GOLD[3])
		local sub = Clean(Safe(GetSubZoneText))
		if sub and sub ~= "" then tip:AddLine(ns.SOFT .. sub .. "|r") end
		local _, faction = Safe(GetZonePVPInfo)
		faction = Clean(faction)
		if type(faction) == "string" and faction ~= "" then tip:AddLine(Label(faction)) end
		local home = Clean(Safe(GetBindLocation))
		if home then tip:AddDoubleLine(Label("Hearthstone"), ns.SOFT .. home .. "|r") end
		Hint(tip, "Click: world map")
	end,
	click = function()
		if _G.ToggleWorldMap then Safe(_G.ToggleWorldMap) end
	end,
}

DEF.coords = {
	text = function()
		local x, y = Coordinates()
		if not x then return nil end
		return ns.MUTED .. ("%.1f  %.1f"):format(x, y) .. "|r"
	end,
	tip = function(tip)
		local x, y = Coordinates()
		tip:SetText(NAMES.coords)
		if x then tip:AddLine(ns.SOFT .. ("%.1f, %.1f"):format(x, y) .. "|r") end
		Hint(tip, "Click: world map")
	end,
	click = function() DEF.zone.click() end,
}

DEF.xp = {
	text = function()
		if AtMax() then return nil end
		local xp, most = Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player"))
		if type(xp) ~= "number" or type(most) ~= "number" or most <= 0 then return nil end
		local rested = Clean(Safe(GetXPExhaustion))
		local value = ("%d%%"):format(math.floor(xp / most * 100))
		if type(rested) == "number" and rested > 0 then value = RESTED .. value .. "|r" end
		return Label("xp ") .. value
	end,
	tip = function(tip)
		local xp, most = Clean(Safe(UnitXP, "player")) or 0, Clean(Safe(UnitXPMax, "player")) or 1
		local level = Clean(Safe(UnitLevel, "player")) or 0
		local rested = Clean(Safe(GetXPExhaustion)) or 0
		tip:SetText(("Level %d"):format(level))
		local big = BreakUpLargeNumbers or tostring
		tip:AddDoubleLine(Label("Experience"), ns.SOFT .. ("%s / %s  (%.1f%%)"):format(big(xp), big(most), xp / most * 100) .. "|r")
		tip:AddDoubleLine(Label("To level"), ns.SOFT .. big(most - xp) .. "|r")
		if rested > 0 then
			tip:AddDoubleLine(Label("Rested"), RESTED .. ("%s  (%.0f%%)"):format(big(rested), rested / most * 100) .. "|r")
		end
		local spent = GetTime() - session.started
		if session.xp > 0 and spent > 60 then
			local hourly = session.xp / spent * 3600
			tip:AddLine(" ")
			tip:AddDoubleLine(Label("This session"), ns.SOFT .. big(session.xp) .. "|r")
			tip:AddDoubleLine(Label("Per hour"), ns.SOFT .. big(math.floor(hourly)) .. "|r")
			tip:AddDoubleLine(Label("Level in"), ns.SOFT .. Duration((most - xp) / hourly * 3600) .. "|r")
		end
	end,
}

DEF.gold = {
	text = function()
		local money = Clean(Safe(GetMoney))
		if type(money) ~= "number" then return nil end
		return Coins(money, true)
	end,
	tip = function(tip)
		SaveMoney()
		local money = Clean(Safe(GetMoney)) or 0
		tip:SetText(NAMES.gold)
		tip:AddDoubleLine(ns.SOFT .. Me() .. "|r", Coins(money))
		if session.money and money ~= session.money then
			local change = money - session.money
			tip:AddDoubleLine(Label(change > 0 and "Earned this session" or "Spent this session"),
				(change > 0 and "|cff80e080+" or "|cffff8080-") .. "|r" .. Coins(change))
		end
		local realm = Realm()
		local others, total = {}, money
		for name, saved in pairs(type(ns.db.gold) == "table" and ns.db.gold[realm] or {}) do
			if name ~= Me() and type(saved) == "table" and type(saved.money) == "number" then
				others[#others + 1] = { name = name, money = saved.money, class = saved.class }
				total = total + saved.money
			end
		end
		if #others > 0 then
			table.sort(others, function(a, b) return a.money > b.money end)
			tip:AddLine(" ")
			for _, other in ipairs(others) do
				local color = RAID_CLASS_COLORS and other.class and RAID_CLASS_COLORS[other.class]
				local name = color and ("|c%s%s|r"):format(color.colorStr or "ffffffff", other.name) or other.name
				tip:AddDoubleLine(name, Coins(other.money))
			end
			tip:AddLine(" ")
			tip:AddDoubleLine(Label("All on " .. realm), Coins(total))
		end
		Hint(tip, "Click: bags")
	end,
	click = function()
		if _G.ToggleAllBags then Safe(_G.ToggleAllBags) elseif _G.OpenAllBags then Safe(_G.OpenAllBags) end
	end,
}

DEF.bags = {
	text = function()
		local free, total = BagSpace()
		if total == 0 then return nil end
		return Label("bags ") .. BagWords(free) .. free .. (BagWords(free) ~= "" and "|r" or "")
	end,
	tip = function(tip)
		local free, total, special = BagSpace()
		tip:SetText(NAMES.bags)
		tip:AddDoubleLine(Label("Free"), ns.SOFT .. ("%d of %d"):format(free, total) .. "|r")
		for _, bag in ipairs(special) do
			local name = bag.bag == 0 and "Backpack" or Clean(Safe(C_Container and C_Container.GetBagName or _G.GetBagName, bag.bag)) or ("Bag " .. bag.bag)
			tip:AddDoubleLine(Label(name), ns.SOFT .. ("%d of %d"):format(bag.free, bag.total) .. "|r")
		end
		Hint(tip, "Click: bags")
	end,
	click = function() DEF.gold.click() end,
	warn = function()
		local free, total = BagSpace()
		return total > 0 and free == 0
	end,
}

DEF.repair = {
	text = function()
		local lowest = Worn()
		if not lowest then return nil end
		local color = WornColor(lowest)
		return Label("gear ") .. color .. ("%d%%"):format(math.floor(lowest * 100 + 0.5)) .. (color ~= "" and "|r" or "")
	end,
	tip = function(tip)
		local _, pieces = Worn()
		tip:SetText(NAMES.repair)
		table.sort(pieces, function(a, b) return a.part < b.part end)
		local cost, listed = 0, 0
		for _, piece in ipairs(pieces) do
			cost = cost + (RepairCost(piece.slot) or 0)
			if piece.part < 1 and listed < 8 then
				listed = listed + 1
				local link = Clean(Safe(GetInventoryItemLink, "player", piece.slot)) or "?"
				local color = WornColor(piece.part)
				tip:AddDoubleLine(link, (color ~= "" and color or ns.SOFT) .. ("%d%%"):format(math.floor(piece.part * 100 + 0.5)) .. "|r")
			end
		end
		if listed == 0 then tip:AddLine(Label("Nothing worn")) end
		if cost > 0 then
			tip:AddLine(" ")
			tip:AddDoubleLine(Label("Repair"), Coins(cost))
		end
		Hint(tip, "Click: your character")
	end,
	click = function()
		if _G.ToggleCharacter then Safe(_G.ToggleCharacter, "PaperDollFrame") end
	end,
	warn = function()
		local lowest = Worn()
		return lowest ~= nil and lowest <= 0.2
	end,
}

DEF.loot = {
	text = function()
		local rule, threshold = LootRule()
		if not rule then return nil end
		return Label("loot ") .. QualityColor(threshold) .. rule .. "|r"
	end,
	tip = function(tip)
		local rule, threshold = LootRule()
		tip:SetText("Loot")
		if rule then tip:AddDoubleLine(Label("Rule"), ns.SOFT .. rule .. "|r") end
		local name = type(threshold) == "number" and _G["ITEM_QUALITY" .. threshold .. "_DESC"]
		if name then tip:AddDoubleLine(Label("From"), QualityColor(threshold) .. name .. "|r") end
	end,
}

DEF.queue = {
	text = function()
		local list = Queues()
		if #list == 0 then return nil end
		local more = #list > 1 and Label(" +" .. (#list - 1)) or ""
		return Label("queue ") .. QueueState(list[1]) .. more
	end,
	tip = function(tip)
		tip:SetText("Queue")
		local list = Queues()
		if #list == 0 then tip:AddLine(Label("Not in a queue")) end
		for _, entry in ipairs(list) do
			local state = entry.waited and (entry.state .. "  " .. Waited(entry.waited)) or entry.state
			tip:AddDoubleLine(ns.SOFT .. entry.name .. "|r", entry.ready and (WARN .. state .. "|r") or (ns.SOFT .. state .. "|r"))
			if entry.estimate and not entry.ready then
				tip:AddDoubleLine(Label("  usual wait"), Label(Waited(entry.estimate)))
			end
		end
		Hint(tip, "Click: group finder")
		Hint(tip, "Right click: the queue's menu (leave it)")
	end,
	click = function(button) ClickEye(button) end,
	rightClick = true, -- (the queue's own menu; Shift right click is the bar's menu there)
	-- (in a queue the bar stays, the compass's eye being away)
	warn = function() return #Queues() > 0 end,
}

DEF.perf = {
	text = function()
		local fps = Clean(Safe(GetFramerate)) or 0
		local _, _, home, world = Safe(GetNetStats)
		local ms = math.max(Clean(home) or 0, Clean(world) or 0)
		local color = ms >= 400 and BAD or (ms >= 200 and WARN or "")
		return ("%d"):format(fps) .. Label(" fps  ") .. color .. ms .. (color ~= "" and "|r" or "") .. Label(" ms")
	end,
	tip = function(tip)
		local into, out, home, world = Safe(GetNetStats)
		tip:SetText(NAMES.perf)
		tip:AddDoubleLine(Label("Frames per second"), ns.SOFT .. ("%.0f"):format(Clean(Safe(GetFramerate)) or 0) .. "|r")
		tip:AddDoubleLine(Label("Latency, home"), ns.SOFT .. (Clean(home) or 0) .. " ms|r")
		tip:AddDoubleLine(Label("Latency, world"), ns.SOFT .. (Clean(world) or 0) .. " ms|r")
		tip:AddDoubleLine(Label("Bandwidth"), ns.SOFT .. ("%.1f in  %.1f out  KB/s"):format(Clean(into) or 0, Clean(out) or 0) .. "|r")
		-- (addons' memory: looked at only now, and never in a fight)
		if InCombatLockdown() or not UpdateAddOnMemoryUsage then return end
		Safe(UpdateAddOnMemoryUsage)
		local count = Clean(Safe(C_AddOns and C_AddOns.GetNumAddOns or _G.GetNumAddOns)) or 0
		local info = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
		local list, total = {}, 0
		for index = 1, count do
			local used = Clean(Safe(GetAddOnMemoryUsage, index)) or 0
			if used > 0 then
				local _, title = Safe(info, index)
				list[#list + 1] = { name = Clean(title) or "?", used = used }
				total = total + used
			end
		end
		table.sort(list, function(a, b) return a.used > b.used end)
		local function Memory(kb) return kb >= 1024 and ("%.1f MB"):format(kb / 1024) or ("%.0f KB"):format(kb) end
		tip:AddLine(" ")
		tip:AddDoubleLine(Label("Addons' memory"), ns.SOFT .. Memory(total) .. "|r")
		for index = 1, math.min(8, #list) do
			tip:AddDoubleLine(Label("  " .. list[index].name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), ns.SOFT .. Memory(list[index].used) .. "|r")
		end
	end,
}

DEF.volume = {
	text = function()
		local on, master = Volume()
		if not on then return Label("sound off") end
		return Label("vol ") .. ("%d%%"):format(math.floor(master * 100 + 0.5))
	end,
	tip = function(tip)
		local on = Volume()
		tip:SetText(on and NAMES.volume or "Sound off")
		for _, row in ipairs({ { "Master", "Sound_MasterVolume" }, { "Effects", "Sound_SFXVolume" },
			{ "Music", "Sound_MusicVolume" }, { "Ambience", "Sound_AmbienceVolume" }, { "Dialog", "Sound_DialogVolume" } }) do
			local value = tonumber(GetVar(row[2]) or "")
			if value then tip:AddDoubleLine(Label(row[1]), ns.SOFT .. ("%d%%"):format(math.floor(value * 100 + 0.5)) .. "|r") end
		end
		Hint(tip, "Mouse wheel: louder, quieter")
		Hint(tip, "Click: sound on / off")
	end,
	click = function() ToggleSound() end,
	wheel = function(delta) SetVolume(delta * 0.05) end,
}

DEF.clock = {
	text = function()
		local mark = Invites() > 0 and (WARN .. "• |r") or ""
		return mark .. Clock()
	end,
	tip = function(tip)
		tip:SetText(date("%A, %d %B"))
		tip:AddDoubleLine(Label("Local time"), ns.SOFT .. date("%H:%M") .. "|r")
		local h, m = Safe(GetGameTime)
		h, m = Clean(h), Clean(m)
		if type(h) == "number" then tip:AddDoubleLine(Label("Realm time"), ns.SOFT .. ("%02d:%02d"):format(h, m) .. "|r") end
		tip:AddDoubleLine(Label("This session"), ns.SOFT .. Duration(GetTime() - session.started) .. "|r")
		local invites = Invites()
		if invites > 0 then
			tip:AddLine(invites == 1 and "1 invitation" or (invites .. " invitations"), GOLD[1], GOLD[2], GOLD[3])
		end
		Hint(tip, "Click: calendar")
		Hint(tip, "Right click: clock and alarm")
	end,
	click = function(button)
		if button == "RightButton" then
			if _G.TimeManager_Toggle then Safe(_G.TimeManager_Toggle) end
		elseif ns.OpenCalendar then
			ns.OpenCalendar()
		end
	end,
	rightClick = true, -- (the clock keeps its right click; Shift right click is the menu there)
}

-- The bar ------------------------------------------------------------------------------------------------------------

local ToggleMenu -- (below)

local function SavePosition()
	local x, top = bar:GetCenter(), bar:GetTop()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if not x or not top then return end
	local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
	ns.db.topPos = { x = x * scale - width / 2, y = top * scale - height }
end

local function Place()
	bar:ClearAllPoints()
	local pos = ns.db.topPos
	if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
		bar:SetPoint("TOP", UIParent, "TOP", pos.x, pos.y)
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
	end
end

local function MakeItem(key)
	local item = CreateFrame("Button", nil, bar)
	item:SetHeight(HEIGHT)
	item:RegisterForClicks("AnyUp")
	item:RegisterForDrag("LeftButton")
	item.text = Text(item)
	item.text:SetPoint("CENTER", item, "CENTER", 0, 0)
	item.dot = Text(bar)
	item.dot:SetText("·")
	item.dot:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
	item.key = key
	local def = DEF[key]
	item:SetScript("OnClick", function(self, button)
		if GetTime() - (self.droppedAt or 0) < 0.2 then return end
		if button == "RightButton" and (not def.rightClick or IsShiftKeyDown()) then return ToggleMenu(self) end
		if def.click then def.click(button) end
		if bar.Refresh then bar.Refresh() end
	end)
	item:SetScript("OnDragStart", function(self)
		if not IsShiftKeyDown() then return end
		self.moving = true
		ns.HideTip()
		bar:StartMoving()
	end)
	item:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving, self.droppedAt = false, GetTime()
		bar:StopMovingOrSizing()
		SavePosition()
		Place()
	end)
	item:SetScript("OnEnter", function(self)
		ns.ShowTip(self, function(tip)
			def.tip(tip)
			Hint(tip, "Right click" .. (def.rightClick and " with Shift" or "") .. ": what the bar shows")
			Hint(tip, "Shift and drag: move the bar")
		end, bar:GetTop() and bar:GetTop() > UIParent:GetHeight() / 2 and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
	end)
	item:SetScript("OnLeave", function() ns.HideTip() end)
	if def.wheel then
		item:EnableMouseWheel(true)
		item:SetScript("OnMouseWheel", function(self, delta)
			def.wheel(delta)
			bar.Refresh()
			if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
		end)
	end
	items[key] = item
	return item
end

-- What each word says now, and the bar laid out again when a width changed.
local function Refresh()
	if not bar or not ns.On("top") then return end
	local shape = {}
	for _, key in ipairs(ORDER) do
		local item = items[key]
		local text, color
		if Shown(key) then
			local ok, said, c = pcall(DEF[key].text)
			if ok then text, color = said, c end
		end
		if type(text) == "string" and text ~= "" then
			item.text:SetText(text)
			if color then item.text:SetTextColor(color[1], color[2], color[3]) end
			local width = math.ceil(Clean(Safe(item.text.GetStringWidth, item.text)) or 40)
			item.width = width
			item:Show()
			shape[#shape + 1] = key .. width
		else
			item.width = nil
			item:Hide()
			item.dot:Hide()
		end
	end
	shape = table.concat(shape, ",")
	if shape == laid then return end
	laid = shape
	local x, first = FADE - PAD, true
	for _, key in ipairs(ORDER) do
		local item = items[key]
		if item.width then
			if not first then
				item.dot:ClearAllPoints()
				item.dot:SetPoint("CENTER", bar, "LEFT", x + GAP, 0)
				item.dot:Show()
				x = x + GAP * 2
			else
				item.dot:Hide()
			end
			first = false
			item:ClearAllPoints()
			item:SetPoint("LEFT", bar, "LEFT", x, 0)
			item:SetWidth(item.width + PAD * 2)
			x = x + item.width + PAD * 2
		end
	end
	bar:SetWidth(math.max(x + FADE - PAD, FADE * 2 + 20))
end

local function Gradient(texture, fromAlpha, toAlpha)
	if texture.SetGradient and CreateColor then
		texture:SetColorTexture(1, 1, 1, 1)
		texture:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], fromAlpha), CreateColor(INK[1], INK[2], INK[3], toAlpha))
	else
		texture:SetColorTexture(INK[1], INK[2], INK[3], (fromAlpha + toAlpha) / 2)
	end
end

local function RuleGradient(texture, fromAlpha, toAlpha)
	if texture.SetGradient and CreateColor then
		texture:SetColorTexture(1, 1, 1, 1)
		texture:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], fromAlpha), CreateColor(GOLD[1], GOLD[2], GOLD[3], toAlpha))
	else
		texture:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], (fromAlpha + toAlpha) / 2)
	end
end

local function MakeBar()
	bar = CreateFrame("Frame", "SereneTopBar", UIParent)
	bar:SetHeight(HEIGHT)
	bar:SetWidth(200)
	bar:SetFrameStrata("LOW")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(false)
	local DARK = 0.62
	local middle = bar:CreateTexture(nil, "BACKGROUND")
	middle:SetColorTexture(INK[1], INK[2], INK[3], DARK)
	middle:SetPoint("TOPLEFT", bar, "TOPLEFT", FADE, 0)
	middle:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -FADE, 0)
	local left = bar:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPRIGHT", middle, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", middle, "BOTTOMLEFT")
	left:SetWidth(FADE)
	Gradient(left, 0, DARK)
	local right = bar:CreateTexture(nil, "BACKGROUND")
	right:SetPoint("TOPLEFT", middle, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", middle, "BOTTOMRIGHT")
	right:SetWidth(FADE)
	Gradient(right, DARK, 0)
	-- (a fine gold rule under the band, fading at its ends)
	local RULE = 0.4
	local rule = bar:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", FADE, 0)
	rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -FADE, 0)
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], RULE)
	local ruleLeft = bar:CreateTexture(nil, "BORDER")
	ruleLeft:SetHeight(1)
	ruleLeft:SetPoint("RIGHT", rule, "LEFT")
	ruleLeft:SetWidth(FADE)
	RuleGradient(ruleLeft, 0, RULE)
	local ruleRight = bar:CreateTexture(nil, "BORDER")
	ruleRight:SetHeight(1)
	ruleRight:SetPoint("LEFT", rule, "RIGHT")
	ruleRight:SetWidth(FADE)
	RuleGradient(ruleRight, RULE, 0)
	for _, key in ipairs(ORDER) do MakeItem(key) end
	bar.Refresh = Refresh
	Place()
end

-- The menu: which words the bar shows ----------------------------------------------------------------------------

local MENU_ROW, MENU_WIDTH = 20, 190
local menuLast = 0

local function MenuRow(index, text, onClick)
	local row = CreateFrame("Button", nil, menu)
	row:SetSize(MENU_WIDTH - 16, MENU_ROW)
	row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8 - (index - 1) * MENU_ROW)
	row.text = Text(row)
	row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.text:SetText(text)
	row.light = row:CreateTexture(nil, "BACKGROUND")
	row.light:SetAllPoints()
	row.light:SetColorTexture(SOFT[1], SOFT[2], SOFT[3], 0.06)
	row.light:Hide()
	row:SetScript("OnEnter", function(self) self.light:Show() end)
	row:SetScript("OnLeave", function(self) self.light:Hide() end)
	row:SetScript("OnClick", onClick)
	return row
end

local function MenuUpdate()
	for _, row in ipairs(menu.rows) do
		if row.key then
			local on = Shown(row.key)
			row.knob:SetVertexColor(on and GOLD[1] or SOFT[1], on and GOLD[2] or SOFT[2], on and GOLD[3] or SOFT[3], on and 1 or 0.25)
			row.text:SetAlpha(on and 1 or 0.55)
		end
	end
end

local function MakeMenu()
	menu = CreateFrame("Frame", "SereneTopMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	local ground = menu:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.92)
	local rule = menu:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	menu.rows = {}
	for index, key in ipairs(ORDER) do
		local row = MenuRow(index, NAMES[key], function()
			ns.db.topItems[key] = not Shown(key)
			MenuUpdate()
			Refresh()
		end)
		row.key = key
		row.knob = row:CreateTexture(nil, "ARTWORK")
		row.knob:SetTexture(MEDIA .. "Disc")
		row.knob:SetSize(8, 8)
		row.knob:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		menu.rows[#menu.rows + 1] = row
	end
	local back = MenuRow(#ORDER + 1, Label("Back to the middle"), function()
		ns.db.topPos = nil
		Place()
		menu:Hide()
	end)
	menu.rows[#menu.rows + 1] = back
	menu:SetSize(MENU_WIDTH, 16 + (#ORDER + 1) * MENU_ROW)
	-- (gone a moment after the mouse left it)
	menu:SetScript("OnUpdate", function(self)
		if self:IsMouseOver(4, -4, -4, 4) then menuLast = GetTime() return end
		if GetTime() - menuLast > 1.2 then self:Hide() end
	end)
	tinsert(UISpecialFrames, "SereneTopMenu")
end

ToggleMenu = function(owner)
	if not menu then MakeMenu() end
	if menu:IsShown() then return menu:Hide() end
	ns.HideTip()
	MenuUpdate()
	menu:ClearAllPoints()
	if (bar:GetTop() or 0) > UIParent:GetHeight() / 2 then
		menu:SetPoint("TOP", owner, "BOTTOM", 0, -4)
	else
		menu:SetPoint("BOTTOM", owner, "TOP", 0, 4)
	end
	menuLast = GetTime()
	menu:Show()
end

-- Fade.lua: is the bar wanted now (beside the mouse)?  --------------------------------------------------------------

function ns.TopNeeded(fighting)
	if not bar or not ns.On("top") then return false end
	local show = ns.db.topShow
	if show == "always" then return true end
	if fighting then return false end
	if show == "calm" then return true end
	-- (on hover only: worn gear, full bags or a queue bring it back)
	for _, key in ipairs(ORDER) do
		local def = DEF[key]
		if def.warn and Shown(key) then
			local ok, warn = pcall(def.warn)
			if ok and warn then return true end
		end
	end
	return false
end

-- Switched on and off -----------------------------------------------------------------------------------------------

local function Apply()
	if not bar then return end
	local on = ns.On("top")
	bar:SetShown(on)
	if not on and menu then menu:Hide() end
	laid = ""
	Refresh()
end

local function Init()
	SaveMoney()
	CountXP()
	MakeBar()
	Apply()
	local since = 0
	bar:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < EVERY then return end
		since = 0
		Refresh()
	end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "BAG_UPDATE",
		"UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
		"GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED", "CVAR_UPDATE", "PLAYER_ENTERING_WORLD",
		"LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_PROPOSAL_SHOW", "LFG_ROLE_CHECK_SHOW", "UPDATE_BATTLEFIELD_STATUS",
		"LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_APPLICATION_STATUS_UPDATED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_MONEY" then SaveMoney() end
		if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then CountXP() end
		Refresh()
	end)
	-- (Titan Panel still loaded: both bars at the top of the screen)
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	if ns.On("top") and Safe(loaded, "Titan") then
		ns.Print("Titan Panel is loaded too: switch it off in the AddOns list to keep only Serene's top bar (or /serene top off).")
	end
end

-- /serene debug: the bar now, and again in 3 seconds (time to put the mouse over it).
local function TopReport(when)
	if not bar then return ns.Print("top bar (" .. when .. "): not made") end
	local function N(v) v = Clean(v) return type(v) == "number" and ("%.0f"):format(v) or tostring(v) end
	local function A(v) v = Clean(v) return type(v) == "number" and ("%.2f"):format(v) or tostring(v) end
	local cx, cy = GetCursorPosition()
	local scale = Clean(Safe(bar.GetEffectiveScale, bar)) or 1
	local over = Safe(bar.IsMouseOver, bar)
	ns.Print(("top bar (%s): shown %s, visible %s, left %s top %s width %s height %s, opacity %s (seen %s), screen %s, mouse at %s,%s, over it %s (Serene: %s), parent %s, points %s"):format(
		when, tostring(Safe(bar.IsShown, bar)), tostring(Safe(bar.IsVisible, bar)),
		N(Safe(bar.GetLeft, bar)), N(Safe(bar.GetTop, bar)), N(Safe(bar.GetWidth, bar)), N(Safe(bar.GetHeight, bar)),
		A(Safe(bar.GetAlpha, bar)), A(Safe(bar.GetEffectiveAlpha, bar)), A(Safe(UIParent.GetAlpha, UIParent)),
		N(cx / scale), N(cy / scale), tostring(over), tostring(ns.Over(bar)),
		tostring(bar:GetParent() and Safe(bar:GetParent().GetName, bar:GetParent())), N(Safe(bar.GetNumPoints, bar))))
end
function ns.TopDebug()
	TopReport("now")
	ns.Print("put the mouse over the top bar: looked at again in 3 seconds")
	C_Timer.After(3, function()
		TopReport("3 seconds later")
		if ns.FadeTopDebug then ns.FadeTopDebug() end
	end)
end

table.insert(ns.modules, { init = Init, refresh = Apply })
