local _, ns = ...
local Clean = ns.Clean

-- Capture: real lines from this client, kept for Serene's tests (tools/test). Off unless asked for.
--   /serene capture on      start (stays on across reloads), /serene capture off, /serene capture clear
-- What it keeps, in SereneDB.capture (written to the SavedVariables file at the next /reload or logout):
--   chat     the game's own sentences as they arrive (loot, rolls, money, experience, reputation, system lines),
--            each once, with the event's arguments. Players' own words are never kept: for what people say (say,
--            channels, whispers...) only the shape is kept (the channel, the flags), the words and names replaced.
--   tooltip  an item tooltip's lines as the game gives them (left and right text, the line's type), once per item.
-- Then: python3 tools/test/import_saved.py turns them into fixtures the tests replay.

local GAME_SAYS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
	"CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL", "CHAT_MSG_CURRENCY", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_OPENING",
	"CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_ACHIEVEMENT" }
local PEOPLE_SAY = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_INSTANCE_CHAT" }
local PER_EVENT = 150  -- lines kept per event
local ITEMS = 120      -- tooltips kept

local IS_PEOPLE = {}
for _, event in ipairs(PEOPLE_SAY) do IS_PEOPLE[event] = true end

local function Store()
	local db = ns.db
	if type(db.capture) ~= "table" then db.capture = {} end
	local c = db.capture
	c.chat = type(c.chat) == "table" and c.chat or {}
	c.tooltip = type(c.tooltip) == "table" and c.tooltip or {}
	c.seen = type(c.seen) == "table" and c.seen or {}
	return c
end

local function On() return ns.db and ns.db.capturing == true end

-- An event's arguments, saveable: secrets and frames left out (false), players' words and names replaced.
local function Args(event, ...)
	local args = {}
	for index = 1, math.min(select("#", ...), 17) do
		local value = Clean((select(index, ...)))
		local kind = type(value)
		if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then value = false end
		args[index] = value
	end
	if IS_PEOPLE[event] then
		-- (the words: their length and whether they held a link or a web address, nothing else)
		local text = type(args[1]) == "string" and args[1] or ""
		local shape = "words"
		if text:find("|H") then shape = shape .. " |Hitem:2589::::::::60:::::|h[Linen Cloth]|h" end
		if text:find("https?://") or text:find("www%.") then shape = shape .. " https://example.com/x" end
		args[1] = shape
		for _, at in ipairs({ 2, 5 }) do
			if type(args[at]) == "string" and args[at] ~= "" then args[at] = "Someone-Somerealm" end
		end
		args[12] = args[12] and "Player-0-00000000" or args[12]
	end
	return args
end

local function OnChat(_, event, ...)
	if not On() then return end
	local c = Store()
	local list = c.chat[event] or {}
	c.chat[event] = list
	if #list >= PER_EVENT then return end
	local args = Args(event, ...)
	local key = event .. "\1" .. tostring(args[1])
	if c.seen[key] then return end
	c.seen[key] = true
	list[#list + 1] = args
end

local function OnTooltip(tooltip, data)
	if not On() or type(data) ~= "table" then return end
	local id = Clean(data.id)
	if type(id) ~= "number" then return end
	local c = Store()
	if c.tooltip[id] or #c.tooltip >= ITEMS then return end
	local lines = {}
	for index, line in ipairs(type(data.lines) == "table" and data.lines or {}) do
		lines[index] = { left = Clean(line.leftText) or false, right = Clean(line.rightText) or false,
			type = Clean(line.type) or false, price = Clean(line.price) or false }
	end
	c.tooltip[id] = { lines = lines, owner = tooltip and Clean(ns.Safe(tooltip.GetName, tooltip)) or false }
end

function ns.Capture(word)
	if word == "on" then
		ns.db.capturing = true
		Store()
	elseif word == "off" then
		ns.db.capturing = nil
	elseif word == "clear" then
		ns.db.capture = nil
	end
	local c = type(ns.db.capture) == "table" and ns.db.capture or {}
	local lines, items = 0, 0
	for _, list in pairs(c.chat or {}) do lines = lines + #list end
	for _ in pairs(c.tooltip or {}) do items = items + 1 end
	ns.Print(("capture %s: %d chat lines, %d item tooltips kept (/reload writes them out)"):format(
		On() and "|cff80ff80on|r" or "|cffff8080off|r", lines, items))
end

local function Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs(GAME_SAYS) do pcall(events.RegisterEvent, events, event) end
	for _, event in ipairs(PEOPLE_SAY) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", OnChat)
	local processor = _G.TooltipDataProcessor
	local types = Enum and Enum.TooltipDataType
	if processor and processor.AddTooltipPostCall and types and types.Item then
		pcall(processor.AddTooltipPostCall, types.Item, OnTooltip)
	end
end

table.insert(ns.modules, { init = Init })
