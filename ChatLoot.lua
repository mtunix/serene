local _, ns = ...
local Safe, Clean, IsSecret = ns.Safe, ns.Clean, ns.IsSecret

-- Loot in few lines.
-- * Loot: what one player loots in a row (a few seconds apart, nothing said between) is one line:
--   "Sopra Bar looted [Raptor Egg], [Keen Raptor Tooth], [Medium Leather]".
-- * Rolls: every choice and roll on one item is one line, written again as the rolls come:
--   "[Roll] [Raptor Egg] · rolling (3)", then "[Roll] [Raptor Egg] → Sopra Bar (Greed 87)". The mouse over [Roll]:
--   who chose what, and their rolls. The winner's "receives loot" line that follows is already said: dropped.
-- * Money, experience, reputation and quest rewards: one quiet line that keeps growing while gains come (longer
--   in a fight):
--   "+1s 20c · +540 XP · Stromgarde +50" (/serene gains on|off).
-- Read from the game's own sentences in your language; a line not understood is left as the game wrote it.
-- /serene loot on|off.

local LOOT_TIME = 8          -- seconds within which a player's loot joins the line before
local ROLL_KEEP = 300        -- seconds a roll is remembered (its tooltip, its winner's loot line)
local MUTED = ns.MUTED
local CHOICE = {
	need = { "Need", "|cff66ff66" }, greed = { "Greed", "|cffffd040" }, disenchant = { "Disenchant", "|cffbf80ff" },
	pass = { "Pass", "|cff9a9a9a" },
}

-- The game's sentences as patterns ---------------------------------------------------------------------------------

-- "%s receives loot: %s." -> a pattern, and the order its captures come in ("%2$s" in some languages).
local function FormatPattern(format)
	if type(format) ~= "string" or format == "" then return nil end
	local order, next = {}, 0
	-- (the format's codes first, "%s", "%d", "%2$s", as marks; then the rest made literal; then the marks)
	local pattern = format:gsub("%%(%d?)%$?([sd])", function(index, kind)
		next = next + 1
		order[#order + 1] = tonumber(index) or next
		return kind == "d" and "\1" or "\2"
	end)
	pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
	return "^" .. pattern .. "$", order
end
ns.FormatPattern = FormatPattern -- (tests)

-- The captures of a match, in the format's own argument order.
local function Match(text, format)
	local pattern, order = FormatPattern(format)
	if not pattern then return nil end
	local found = { text:match(pattern) }
	if not found[1] then return nil end
	local args = {}
	for at, index in ipairs(order) do args[index] = found[at] end
	return args, #order
end
ns.FormatMatch = Match

-- What each sentence says: its kind, and what its arguments are (in order). The longer ones first: "automatically
-- passed on" would read as "passed on", "receives loot: [x]x2." as "receives loot: [x]x2".
local SENTENCES = {
	{ "LOOT_ROLL_PASSED_AUTO", "choice", "pass", { "who", "item" } },
	{ "LOOT_ROLL_PASSED_AUTO_FEMALE", "choice", "pass", { "who", "item" } },
	{ "LOOT_ROLL_PASSED_SELF_AUTO", "choice", "pass", { "item" }, true },
	{ "LOOT_ROLL_NEED_SELF", "choice", "need", { "item" }, true },
	{ "LOOT_ROLL_GREED_SELF", "choice", "greed", { "item" }, true },
	{ "LOOT_ROLL_DISENCHANT_SELF", "choice", "disenchant", { "item" }, true },
	{ "LOOT_ROLL_PASSED_SELF", "choice", "pass", { "item" }, true },
	{ "LOOT_ROLL_NEED", "choice", "need", { "who", "item" } },
	{ "LOOT_ROLL_GREED", "choice", "greed", { "who", "item" } },
	{ "LOOT_ROLL_DISENCHANT", "choice", "disenchant", { "who", "item" } },
	-- (before LOOT_ROLL_PASSED: "Everyone passed on: [x]" would read as a player called Everyone passing)
	{ "LOOT_ROLL_ALL_PASSED", "allpassed", nil, { "item" } },
	{ "LOOT_ROLL_PASSED", "choice", "pass", { "who", "item" } },
	{ "LOOT_ROLL_ROLLED_NEED", "roll", "need", { "roll", "item", "who" } },
	{ "LOOT_ROLL_ROLLED_GREED", "roll", "greed", { "roll", "item", "who" } },
	{ "LOOT_ROLL_ROLLED_DE", "roll", "disenchant", { "roll", "item", "who" } },
	{ "LOOT_ROLL_YOU_WON", "won", nil, { "item" }, true },
	{ "LOOT_ROLL_WON", "won", nil, { "who", "item" } },
	{ "LOOT_ITEM_SELF_MULTIPLE", "loot", nil, { "item", "count" }, true },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "loot", nil, { "item", "count" }, true },
	{ "LOOT_ITEM_MULTIPLE", "loot", nil, { "who", "item", "count" } },
	{ "LOOT_ITEM_SELF", "loot", nil, { "item" }, true },
	{ "LOOT_ITEM_PUSHED_SELF", "loot", nil, { "item" }, true },
	{ "LOOT_ITEM", "loot", nil, { "who", "item" } },
}
-- (the English sentences, should this game lack one of the names)
local ENGLISH = {
	LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item.",
	LOOT_ROLL_PASSED_AUTO_FEMALE = "%s automatically passed on: %s because she cannot loot that item.",
	LOOT_ROLL_PASSED_SELF_AUTO = "You automatically passed on: %s because you cannot loot that item.",
	LOOT_ROLL_NEED_SELF = "You have selected Need for: %s", LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s",
	LOOT_ROLL_DISENCHANT_SELF = "You have selected Disenchant for: %s", LOOT_ROLL_PASSED_SELF = "You passed on: %s",
	LOOT_ROLL_NEED = "%s has selected Need for: %s", LOOT_ROLL_GREED = "%s has selected Greed for: %s",
	LOOT_ROLL_DISENCHANT = "%s has selected Disenchant for: %s", LOOT_ROLL_PASSED = "%s passed on: %s",
	LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s",
	LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s", LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s",
	LOOT_ROLL_ROLLED_DE = "Disenchant Roll - %d for %s by %s",
	LOOT_ROLL_YOU_WON = "You won: %s", LOOT_ROLL_WON = "%s won: %s",
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.", LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.",
	LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d.", LOOT_ITEM_SELF = "You receive loot: %s.",
	LOOT_ITEM_PUSHED_SELF = "You receive item: %s.", LOOT_ITEM = "%s receives loot: %s.",
}

-- One sentence read: { kind, choice, who, item, roll, count, self } or nil.
local function Read(text)
	for _, s in ipairs(SENTENCES) do
		local format = _G[s[1]]
		if type(format) ~= "string" then format = ENGLISH[s[1]] end
		local args, count = Match(text, format)
		if args then
			-- (this game starts its roll sentences with a link of its own, "|HlootHistory:%d|h[Loot]|h: ": arguments
			-- before the ones we know, skipped)
			local skip = math.max(0, (count or 0) - #s[4])
			local said = { kind = s[2], choice = s[3], self = s[5] or false }
			for index, field in ipairs(s[4]) do said[field] = args[index + skip] end
			said.roll, said.count = tonumber(said.roll), tonumber(said.count)
			if said.self then said.who = YOU or "You" end
			return said
		end
	end
end
ns.LootRead = Read -- (tests)

-- Lines of ours -----------------------------------------------------------------------------------------------------

-- The hour as the game writes it before its lines (its option), quiet.
local function Hour()
	local format = Clean(Safe(GetCVar, "showTimestamps"))
	if type(format) ~= "string" or format == "none" or format == "" then return "" end
	-- (BetterDate where the game has it, as it writes its own lines' hour)
	local hour = (_G.BetterDate and Safe(_G.BetterDate, format, time())) or date(format)
	hour = strtrim(tostring(hour or ""))
	return hour ~= "" and (MUTED .. hour .. "|r") or ""
end

local function LootColor()
	local info = ChatTypeInfo and ChatTypeInfo.LOOT
	if type(info) == "table" and info.r then return info.r, info.g, info.b end
	return 0, 0.67, 0 -- (the game's own loot green)
end

-- A line added to a window, and the history entry holding it (written again later).
local function Add(frame, text)
	local r, g, b = LootColor()
	pcall(frame.AddMessage, frame, text, r, g, b)
	local buffer = frame.historyBuffer
	local entry = type(buffer) == "table" and buffer.GetEntryAtIndex and Safe(buffer.GetEntryAtIndex, buffer, 1)
	-- (another addon's hook rewriting the line: not found, and the game's own sentence shows as well)
	if type(entry) == "table" and entry.message == text then return entry end
end

local function Rewrite(frame, entry, text)
	if type(entry) ~= "table" then return end
	entry.message = text
	-- (still fresh: it fades from now)
	if type(entry.timestamp) == "number" then entry.timestamp = GetTime() end
	if frame.MarkDisplayDirty then pcall(frame.MarkDisplayDirty, frame) end
end

local function Newest(frame, entry)
	local buffer = frame.historyBuffer
	return type(buffer) == "table" and buffer.GetEntryAtIndex and Safe(buffer.GetEntryAtIndex, buffer, 1) == entry
end

-- A line of ours taken out of its window.
local function Remove(frame, entry)
	if type(entry) ~= "table" or not frame.RemoveMessagesByPredicate then return false end
	local words = entry.message
	local ok = pcall(frame.RemoveMessagesByPredicate, frame, function(each)
		return each == entry or (type(each) == "string" and not IsSecret(each) and each == words)
	end)
	if ok and frame.MarkDisplayDirty then pcall(frame.MarkDisplayDirty, frame) end
	return ok
end

-- A line of ours with new words: written again where it stands while it is still the newest; else taken out and
-- added again at the bottom (written again higher up, it would come back among faded lines, out of its place).
local function Refresh(frame, entry, text)
	if type(entry) == "table" and Newest(frame, entry) then
		Rewrite(frame, entry, text)
		return entry
	end
	if type(entry) == "table" then Remove(frame, entry) end
	return Add(frame, text)
end
ns.LootRefresh = Refresh -- (tests)

-- Loot: a player's line, joined while they loot in a row ------------------------------------------------------------

local lastLoot = {} -- frame -> { who, items, entry, at, hour }

local function LootText(loot)
	local items = {}
	for _, each in ipairs(loot.items) do
		items[#items + 1] = each.count and each.count > 1 and (each.item .. "x" .. each.count) or each.item
	end
	return loot.hour .. (loot.hour ~= "" and " " or "") .. loot.who .. " looted " .. table.concat(items, ", ")
end

local function OnLoot(frame, said)
	local now = GetTime()
	local loot = lastLoot[frame]
	if loot and loot.who == said.who and now - loot.at < LOOT_TIME and Newest(frame, loot.entry) then
		loot.items[#loot.items + 1] = { item = said.item, count = said.count }
		loot.at = now
		Rewrite(frame, loot.entry, LootText(loot))
		return true
	end
	loot = { who = said.who, items = { { item = said.item, count = said.count } }, at = now, hour = Hour() }
	loot.entry = Add(frame, LootText(loot))
	lastLoot[frame] = loot.entry and loot or nil
	return loot.entry ~= nil
end

-- Rolls: one line per item ------------------------------------------------------------------------------------------

local rolls, rollByID, nextID = {}, {}, 0 -- item link -> its roll (the newest), id -> roll

local function RollFor(item, create)
	local roll = rolls[item]
	-- (a choice after a finished roll starts the item's next roll; a stale roll is forgotten)
	if roll and (roll.done and create == "new" or GetTime() - roll.at > ROLL_KEEP) then roll = nil end
	if not roll and create then
		nextID = nextID + 1
		roll = { id = nextID, item = item, people = {}, order = {}, entries = {}, at = GetTime(), hour = Hour() }
		rolls[item], rollByID[nextID] = roll, roll
	end
	return roll
end

local function Person(roll, who)
	local person = roll.people[who]
	if not person then
		person = { who = who }
		roll.people[who] = person
		roll.order[#roll.order + 1] = person
	end
	return person
end

local function RollText(roll)
	local link = "|cffa0a0a0|Haddon:Serene:roll:" .. roll.id .. "|h[Roll]|h|r"
	local status
	if roll.winner then
		local person = roll.people[roll.winner]
		local how = person and person.choice and CHOICE[person.choice]
		local detail = how and (how[1] .. (person.roll and (" " .. person.roll) or "")) or nil
		status = "→ " .. roll.winner .. (detail and (" " .. MUTED .. "(" .. detail .. ")|r") or "")
	elseif roll.allPassed then
		status = MUTED .. "· everyone passed|r"
	else
		status = MUTED .. "· rolling (" .. #roll.order .. ")|r"
	end
	return roll.hour .. (roll.hour ~= "" and " " or "") .. link .. " " .. roll.item .. " " .. status
end

-- The state, once per sentence (every window hears it); then each window's own line.
local function UpdateRoll(said, lineID)
	local roll
	if said.kind == "choice" then
		roll = RollFor(said.item, "new")
		Person(roll, said.who).choice = said.choice
	elseif said.kind == "roll" then
		roll = RollFor(said.item, true)
		local person = Person(roll, said.who)
		person.choice, person.roll = said.choice, said.roll
	elseif said.kind == "won" then
		roll = RollFor(said.item, true)
		roll.winner, roll.done, roll.wonAt = said.who, true, GetTime()
		Person(roll, said.who)
	elseif said.kind == "allpassed" then
		roll = RollFor(said.item, true)
		roll.allPassed, roll.done = true, true
	end
	if roll then roll.at = GetTime() end
	return roll
end

local function ShowRoll(frame, roll)
	roll.entries[frame] = Refresh(frame, roll.entries[frame], RollText(roll))
	return true
end

-- The winner's "receives loot" right after a roll: already said on the roll's line.
local function WonAlready(said)
	local roll = rolls[said.item]
	-- (30 s: the loot line follows the win at once, a later one is new loot)
	return roll and roll.winner == said.who and roll.wonAt and GetTime() - roll.wonAt < 30 or false
end

-- The filter ----------------------------------------------------------------------------------------------------------

local heard = {} -- lineID -> what it said (the state moved once, every window then shows it)
local function OnLootEvent(frame, _, text, ...)
	if not (ns.On("chat") and ns.On("loot")) then return false end
	if type(text) ~= "string" or IsSecret(text) or type(frame) ~= "table" or not frame.AddMessage then return false end
	local lineID = select(10, ...) -- (the event's lineID, the same in every window)
	if IsSecret(lineID) then lineID = nil end
	local said, roll
	if lineID ~= nil and heard[lineID] then
		said, roll = heard[lineID].said, heard[lineID].roll
	else
		said = Read(text)
		if not said then return false end
		if said.kind ~= "loot" then roll = UpdateRoll(said, lineID) end
		if lineID ~= nil then
			-- (only the newest kept: the windows hear a sentence one after another, before the next comes)
			wipe(heard)
			heard[lineID] = { said = said, roll = roll }
		end
	end
	if said.kind == "loot" then
		if WonAlready(said) then return true end
		return OnLoot(frame, said)
	end
	if roll then return ShowRoll(frame, roll) end
	return false
end
ns.LootFilter = OnLootEvent -- (tests)

-- Money, experience, reputation: one quiet line ---------------------------------------------------------------------

local GAINS_TIME, GAINS_FIGHT_TIME = 20, 90 -- seconds a gains line keeps growing (in a fight: longer)
local gains = {} -- window -> { copper, xp, rep = { name -> amount }, order, entry, at, hour }
local inFight = false

-- Copper in a sentence of money ("You loot 1 Silver, 20 Copper"), or nil.
local COINS = { { "GOLD_AMOUNT", "%d Gold", 10000 }, { "SILVER_AMOUNT", "%d Silver", 100 }, { "COPPER_AMOUNT", "%d Copper", 1 } }
local function Coins(text)
	local total, found = 0, false
	for _, coin in ipairs(COINS) do
		local format = type(_G[coin[1]]) == "string" and _G[coin[1]] or coin[2]
		local word = strtrim((format:gsub("%%d", "")))
		if word ~= "" then
			local amount = text:match("(%d+)%s*" .. word:gsub("%p", "%%%0"))
			if amount then
				total = total + tonumber(amount) * coin[3]
				found = true
			end
		end
	end
	return found and total or nil
end
ns.LootCoins = Coins -- (tests)

-- (the game's format by its name; true: an English sentence as it stands, for the ones without a name here)
local REPUTATION = {
	{ "FACTION_STANDING_INCREASED", 1 }, { "FACTION_STANDING_DECREASED", -1 },
	{ "Reputation with %s increased by %d.", 1, true }, { "Reputation with %s decreased by %d.", -1, true },
	{ "Your reputation with %s has increased by %d.", 1, true }, { "Your reputation with %s has decreased by %d.", -1, true },
}
local function Reputation(text)
	for _, each in ipairs(REPUTATION) do
		local format = each[3] and each[1] or _G[each[1]]
		local args = type(format) == "string" and Match(text, format)
		if args and args[1] and tonumber(args[2]) then return args[1], tonumber(args[2]) * each[2] end
	end
end

-- Money with the game's coin icons: "1[silver] 42[copper]".
local COIN_ICONS = {
	"|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	"|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local function Money(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. COIN_ICONS[1] end
	if s > 0 then parts[#parts + 1] = s .. COIN_ICONS[2] end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COIN_ICONS[3] end
	return table.concat(parts, " ")
end

local function GainsText(g)
	local parts = {}
	if g.copper > 0 then parts[#parts + 1] = "+" .. Money(g.copper) end
	if g.xp > 0 then parts[#parts + 1] = "+" .. g.xp .. " XP" end
	for _, name in ipairs(g.order) do
		local amount = g.rep[name]
		parts[#parts + 1] = name .. " " .. (amount >= 0 and "+" or "") .. amount
	end
	return g.hour .. (g.hour ~= "" and " " or "") .. MUTED .. table.concat(parts, "  ·  ") .. "|r"
end

local GAIN_EVENTS = { CHAT_MSG_MONEY = "money", CHAT_MSG_COMBAT_XP_GAIN = "xp", CHAT_MSG_COMBAT_FACTION_CHANGE = "rep",
	CHAT_MSG_SYSTEM = "system" }

-- A quest's reward said by the game's system: "Experience gained: 500.", "Received 1 Silver, 20 Copper.".
local function QuestReward(text)
	local args = Match(text, type(_G.ERR_QUEST_REWARD_EXP_I) == "string" and _G.ERR_QUEST_REWARD_EXP_I or "Experience gained: %d.")
	if args and tonumber(args[1]) then return nil, tonumber(args[1]) end
	args = Match(text, type(_G.ERR_QUEST_REWARD_MONEY_S) == "string" and _G.ERR_QUEST_REWARD_MONEY_S or "Received %s.")
	if args and args[1] then
		local copper = Coins(args[1])
		if copper then return copper, nil end
	end
end

local function OnGainsEvent(frame, event, text)
	if not (ns.On("chat") and ns.On("gains")) then return false end
	if type(text) ~= "string" or IsSecret(text) or type(frame) ~= "table" or not frame.AddMessage then return false end
	local kind = GAIN_EVENTS[event]
	local copper, xp, faction, amount
	if kind == "money" then
		copper = Coins(text)
		if not copper then return false end
	elseif kind == "xp" then
		xp = tonumber(text:match("(%d+)")) -- (the first number: the gain, before any rested bonus)
		if not xp then return false end
	elseif kind == "rep" then
		faction, amount = Reputation(text)
		if not faction then return false end
	elseif kind == "system" then
		copper, xp = QuestReward(text)
		if not (copper or xp) then return false end
	else
		return false
	end
	local now = GetTime()
	local g = gains[frame]
	if not (g and now - g.at < (inFight and GAINS_FIGHT_TIME or GAINS_TIME)) then
		g = { copper = 0, xp = 0, rep = {}, order = {}, hour = Hour() }
		gains[frame] = g
	end
	g.at = now
	g.copper = g.copper + (copper or 0)
	g.xp = g.xp + (xp or 0)
	if faction then
		if not g.rep[faction] then
			g.rep[faction] = 0
			g.order[#g.order + 1] = faction
		end
		g.rep[faction] = g.rep[faction] + amount
	end
	g.entry = Refresh(frame, g.entry, GainsText(g))
	return true
end
ns.GainsFilter = OnGainsEvent -- (tests)
function ns.LootFighting(value) inFight = value end -- (tests)

-- Under the mouse: who chose what.
function ns.RollTooltip(owner, link)
	local id = type(link) == "string" and tonumber(link:match("^addon:Serene:roll:(%d+)"))
	local roll = id and rollByID[id]
	if not roll then return false end
	ns.ShowTip(owner, function(tip)
		tip:AddLine(roll.item)
		local list = {}
		for _, person in ipairs(roll.order) do list[#list + 1] = person end
		table.sort(list, function(a, b) return (a.roll or -1) > (b.roll or -1) end)
		for _, person in ipairs(list) do
			local how = person.choice and CHOICE[person.choice]
			local right = how and (how[2] .. how[1] .. (person.roll and (" " .. person.roll) or "") .. "|r") or MUTED .. "…|r"
			local won = roll.winner == person.who
			tip:AddDoubleLine((won and ns.GOLD_TEXT or ns.SOFT) .. person.who .. (won and "  (won)" or "") .. "|r", right)
		end
		if roll.allPassed then tip:AddLine(MUTED .. "Everyone passed|r") end
	end)
	return true
end

local function Init()
	if not ns.On("chat") then return end
	local add = _G.ChatFrame_AddMessageEventFilter or (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
	if add then
		pcall(add, "CHAT_MSG_LOOT", OnLootEvent)
		for event in pairs(GAIN_EVENTS) do pcall(add, event, OnGainsEvent) end
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event) inFight = event == "PLAYER_REGEN_DISABLED" end)
end

table.insert(ns.modules, { init = Init })
