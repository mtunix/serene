local ADDON, ns = ...

-- The player card: the mouse over a name in the chat shows who that is, as far as the game knows: level, race and
-- class (the name in its class colour), guild and rank, where they are, and whether they are a friend, in your guild
-- or in your group. Nothing is asked of the server on hover; what is known comes from:
--   your group, your guild's roster and your friends list (live, with the zone);
--   players you have seen: targeted, under the mouse, on a nameplate (remembered with the time);
--   the chat itself (the speaker's class and race), and /who answers (shift-click a name to ask).

local Safe, Clean = ns.Safe, ns.Clean

local MUTED = ns.MUTED
local SOFT = ns.SOFT
local GUILD = "|cff7fd67f"
local OLD = 600 -- seconds: a remembered level older than this says when it was seen

local known = {} -- by Key(name): what was seen of a player, and when

local function Text(value)
	value = Clean(value)
	if type(value) == "string" and value ~= "" then return value end
end

local function Number(value)
	value = Clean(value)
	if type(value) == "number" and value > 0 then return value end
end

-- One name for a player: without your own realm, without case.
local function Key(name)
	name = Text(name)
	if not name then return nil end
	name = Safe(Ambiguate, name, "none") or name
	return name:lower()
end

local function Same(a, b)
	local ka, kb = Key(a), Key(b)
	return ka ~= nil and ka == kb
end

-- The class's own token ("DRUID") from a class name in the game's language.
local function ClassFile(localized)
	if not localized then return nil end
	for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
		if type(names) == "table" then
			for file, name in pairs(names) do
				if name == localized then return file end
			end
		end
	end
	return (localized:upper():gsub("%s", "")) -- (not in the game's lists: the English token, as a guess)
end

local function ClassColor(file)
	local color = file and ((C_ClassColor and Safe(C_ClassColor.GetClassColor, file))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]))
	if type(color) == "table" and color.r then
		local function B(v) return math.floor(v * 255 + 0.5) end
		return ("|cff%02x%02x%02x"):format(B(color.r), B(color.g), B(color.b))
	end
end

-- Remembering ---------------------------------------------------------------------------------------------------------

-- Into what is known of a player, the values given (only those known; a newer one over an older one).
local function Learn(name, facts)
	local key = Key(name)
	if not key then return end
	local card = known[key] or {}
	known[key] = card
	card.name = card.name or Text(name)
	for field, value in pairs(facts) do
		if value ~= nil then card[field] = value end
	end
	if facts.level then card.seen = GetTime() end -- (the card's "seen ... ago" is the level's age)
end

local function FromGUID(name, guid)
	guid = Text(guid)
	if not (name and guid) or not guid:find("^Player") then return end
	local className, classFile, race = Safe(GetPlayerInfoByGUID, guid)
	Learn(name, { class = Text(className), classFile = Text(classFile), race = Text(race) })
end

local function FromUnit(unit)
	if not Clean(Safe(UnitIsPlayer, unit)) then return end
	local name = Text(Safe(GetUnitName, unit, true)) or Text(Safe(UnitName, unit))
	if not name then return end
	local className, classFile = Safe(UnitClass, unit)
	local guild, rank = Safe(GetGuildInfo, unit)
	local level = Clean(Safe(UnitLevel, unit))
	Learn(name, {
		level = (type(level) == "number" and level ~= 0) and level or nil, -- (0: not known yet)
		class = Text(className), classFile = Text(classFile), race = Text(Safe(UnitRace, unit)),
		guild = Text(guild), rank = Text(rank),
	})
end

local function FromGroup()
	local raid = Clean(Safe(IsInRaid))
	local count = Number(Safe(GetNumGroupMembers)) or 0
	-- (party1 to party4: a party's count includes you, who have no party unit)
	for at = 1, raid and count or math.min(count, 4) do
		FromUnit((raid and "raid" or "party") .. at)
	end
end

-- A /who answer.
local function FromWho()
	local list = C_FriendList
	local count = list and Number(Safe(list.GetNumWhoResults)) or 0
	for at = 1, count do
		local info = Safe(list.GetWhoInfo, at)
		if type(info) == "table" and Text(info.fullName) then
			Learn(info.fullName, { level = Number(info.level), class = Text(info.classStr), race = Text(info.raceStr),
				classFile = Text(info.filename), guild = Text(info.fullGuildName), zone = Text(info.area),
				zoneAt = GetTime() })
		end
	end
end

-- A /who answer of one player comes as a line in the chat.
local function FromWhoLine(text)
	text = Text(text)
	if not (text and ns.FormatMatch) or not text:find("|Hplayer:") then return end
	local args = WHO_LIST_GUILD_FORMAT and ns.FormatMatch(text, WHO_LIST_GUILD_FORMAT)
	local guild = true
	if not args then args, guild = WHO_LIST_FORMAT and ns.FormatMatch(text, WHO_LIST_FORMAT), false end
	if not args or not args[1] then return end
	local level = tonumber(args[3])
	Learn(args[1], { level = level, race = args[4], class = args[5], classFile = ClassFile(args[5]),
		guild = guild and args[6] or nil, zone = guild and args[7] or args[6], zoneAt = GetTime() })
end

-- Live: where someone is now, from your group, your guild and your friends ------------------------------------------

local function InGroup(name)
	if Same(name, Safe(UnitName, "player")) then return "player" end
	local raid = Clean(Safe(IsInRaid))
	local count = Number(Safe(GetNumGroupMembers)) or 0
	for at = 1, raid and count or math.min(count, 4) do
		local unit = (raid and "raid" or "party") .. at
		if Same(name, Safe(GetUnitName, unit, true)) then return unit, raid and at end
	end
end

local function MapName(unit)
	local map = C_Map and Number(Safe(C_Map.GetBestMapForUnit, unit))
	local info = map and Safe(C_Map.GetMapInfo, map)
	return type(info) == "table" and Text(info.name) or nil
end

local function GroupFacts(name, card)
	local unit, raidIndex = InGroup(name)
	if not unit then return end
	FromUnit(unit)
	card.group = unit ~= "player"
	card.zone = raidIndex and Text(select(7, Safe(GetRaidRosterInfo, raidIndex))) or MapName(unit)
	card.online = Clean(Safe(UnitIsConnected, unit)) ~= false -- (unknown is not offline)
end

local function GuildFacts(name, card)
	if not Clean(Safe(IsInGuild)) then return end
	local guildName = Text(Safe(GetGuildInfo, "player"))
	for at = 1, Number(Safe(GetNumGuildMembers)) or 0 do
		local who, rank, _, level, className, zone, note, _, online, status, classFile = Safe(GetGuildRosterInfo, at)
		if Same(name, who) then
			Learn(name, { level = Number(level), class = Text(className), classFile = Text(classFile),
				guild = guildName, rank = Text(rank) })
			card.guildmate = true
			card.zone = card.zone or Text(zone)
			card.online = Clean(online) and true or false
			card.note = card.note or Text(note)
			card.away = Number(status) == 1 and "Away" or Number(status) == 2 and "Busy" or nil
			return
		end
	end
end

local function FriendFacts(name, card)
	local info = C_FriendList and Safe(C_FriendList.GetFriendInfo, name)
	if type(info) ~= "table" then return end
	local className = Text(info.className)
	Learn(name, { level = Number(info.level), class = className, classFile = ClassFile(className) })
	card.friend = true
	card.online = info.connected and true or false
	card.zone = card.zone or Text(info.area)
	card.note = card.note or Text(info.notes)
	card.away = card.away or (info.afk and "Away") or (info.dnd and "Busy") or nil
end

-- The card --------------------------------------------------------------------------------------------------------

local function Ago(seconds)
	if seconds < 3600 then return ("%d min ago"):format(math.max(1, math.floor(seconds / 60))) end
	return ("%d h ago"):format(math.floor(seconds / 3600))
end

local function Show(owner, name, lineID)
	-- the speaker of that line, by the game's own record
	if lineID and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
		FromGUID(name, Safe(C_ChatInfo.GetChatLineSenderGUID, lineID))
	end
	local live = {}
	GroupFacts(name, live)
	GuildFacts(name, live)
	FriendFacts(name, live)
	local card = known[Key(name)] or {}

	local shown = Text(Safe(Ambiguate, name, "none")) or name
	local color = ClassColor(card.classFile) or SOFT
	ns.ShowTip(owner, function(tip)
		tip:AddLine(color .. shown .. "|r" .. (live.away and (MUTED .. "  " .. live.away .. "|r") or ""))

		local who = {}
		if card.level then who[#who + 1] = (LEVEL or "Level") .. " " .. card.level end
		if card.race then who[#who + 1] = card.race end
		if card.class then who[#who + 1] = (color ~= SOFT and color or "") .. card.class .. "|r" end
		if #who > 0 then
			local old = card.level and card.seen and not (live.group or live.guildmate or live.friend)
				and GetTime() - card.seen > OLD
			tip:AddLine(SOFT .. table.concat(who, " ") .. "|r" .. (old and (MUTED .. "  (seen " ..
				Ago(GetTime() - card.seen) .. ")|r") or ""))
		end
		if card.guild then
			tip:AddLine(GUILD .. "<" .. card.guild .. ">|r" .. (card.rank and (MUTED .. "  " .. card.rank .. "|r") or ""))
		end

		if live.online == false then
			tip:AddLine(MUTED .. (FRIENDS_LIST_OFFLINE or "Offline") .. "|r")
		else
			local zone = live.zone
			-- (a zone from /who, trusted for five minutes: people move)
			if not zone and card.zone and card.zoneAt and GetTime() - card.zoneAt < 300 then zone = card.zone end
			if zone then tip:AddLine(SOFT .. zone .. "|r") end
		end
		if live.note then tip:AddLine(MUTED .. "\"" .. live.note .. "\"|r", nil, nil, nil, true) end

		local ties = {}
		if live.friend then ties[#ties + 1] = "Friend" end
		if live.guildmate then ties[#ties + 1] = "Guild" end
		if live.group then ties[#ties + 1] = "Group" end
		if #ties > 0 then tip:AddLine(MUTED .. table.concat(ties, " · ") .. "|r") end
		if not card.level then ns.TipHint(tip, "Shift-click to look them up") end
	end)
	return true
end

-- The mouse over a link (Chat.lua asks): a player's name shows the card.
function ns.PlayerCard(owner, link)
	if not (ns.On("chat") and ns.On("card")) or type(link) ~= "string" then return false end
	local payload = link:match("^player:(.+)$")
	if not payload then return false end
	local name, lineID = payload:match("^([^:]+):?(%d*)")
	if not name or name == "" then return false end
	-- (a card that fails to build: no card, never an error on hover)
	local ok, shown = pcall(Show, owner, name, tonumber(lineID))
	return ok and shown or false
end

-- Listening -------------------------------------------------------------------------------------------------------

local CHAT = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE" }

local listener = CreateFrame("Frame")
listener:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_TARGET_CHANGED" then Safe(FromUnit, "target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then Safe(FromUnit, "mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then Safe(FromUnit, (...))
	elseif event == "GROUP_ROSTER_UPDATE" then Safe(FromGroup)
	elseif event == "WHO_LIST_UPDATE" then Safe(FromWho)
	elseif event == "CHAT_MSG_SYSTEM" then Safe(FromWhoLine, (...))
	elseif event == "PLAYER_GUILD_UPDATE" then
		if C_GuildInfo and C_GuildInfo.GuildRoster then Safe(C_GuildInfo.GuildRoster) end
	else -- (a chat line)
		local sender, guid = select(2, ...), select(12, ...)
		Safe(FromGUID, Text(sender), guid)
	end
end)

ns.modules[#ns.modules + 1] = { init = function()
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
		"GROUP_ROSTER_UPDATE", "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM", "PLAYER_GUILD_UPDATE" }) do
		pcall(listener.RegisterEvent, listener, event)
	end
	for _, event in ipairs(CHAT) do pcall(listener.RegisterEvent, listener, event) end
	-- the guild's roster, read once now (the game keeps it fresh after that)
	if C_GuildInfo and C_GuildInfo.GuildRoster then Safe(C_GuildInfo.GuildRoster)
	elseif GuildRoster then Safe(GuildRoster) end
	Safe(FromGroup)
end }
