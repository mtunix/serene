-- Chat.lua: the chat in glass. Its pure parts: words without links or colours, what a message says of you (named,
-- whispered), channel names without their zone, friends coming online quietly; and each message's backdrop.

local ns = wow.load()
local MUTED = ns.MUTED

test("Strip: links as their words, no colours", function()
	local cases = {
		{ "|cff40ff40|Hplayer:Bob:1|h[Bob]|h|r: |cffffffff|Hitem:1|h[Linen]|h|r", "[Bob]: [Linen]" },
		{ "|Hchannel:GUILD|h[G]|h plain", "[G] plain" },
		{ "nothing to strip", "nothing to strip" },
	}
	for _, case in ipairs(cases) do eq(ns.ChatStrip(case[1]), case[2], case[1]) end
end)

-- What a message says of you --------------------------------------------------------------------------------------------

local function Veil()
	local holder = CreateFrame("Frame")
	return { edge = holder:CreateTexture(), tint = holder:CreateTexture() }
end

test("MarkOf: a whisper, your name said by someone else, or nothing", function()
	wow.login(nil) -- (your name, "Tester", learnt at login)
	local cases = {
		{ "|Hplayer:Bob:2:WHISPER|h[Bob]|h whispers: hi", "whisper" },
		{ "|HBNplayer:Ann:3|h[Ann]|h whispers: hi", "whisper" },
		{ "|Hchannel:GUILD|h[G]|h |Hplayer:Bob:1:GUILD|h[Bob]|h: hey Tester, come", "named" },
		{ "|Hplayer:Bob:1:GUILD|h[Bob]|h: TESTER!", "named" },
		{ "|Hplayer:Tester:4:GUILD|h[Tester]|h: tester here", nil },
		{ "|Hplayer:Bob:1:GUILD|h[Bob]|h: the testers are here", nil },
		{ "|Hplayer:Bob:1:GUILD|h[Bob]|h: nothing about you", nil },
	}
	for _, case in ipairs(cases) do
		local v = Veil()
		eq(ns.ChatMarkOf(v, case[1]), case[2], case[1])
	end
end)

test("MarkOf: read again only when the words change; a secret message marks nothing", function()
	wow.login(nil)
	local v = Veil()
	eq(ns.ChatMarkOf(v, "|Hplayer:Bob:2:WHISPER|h[Bob]|h whispers: hi"), "whisper")
	local edge = wow.state(v.edge).color
	eq(ns.ChatMarkOf(v, "|Hplayer:Bob:2:WHISPER|h[Bob]|h whispers: hi"), "whisper")
	ok(wow.state(v.edge).color == edge, "the same words: nothing painted again")
	eq(ns.ChatMarkOf(v, wow.secret("x")), nil)
	eq(v.text, nil)
	eq(ns.ChatMarkOf(v, nil), nil)
end)

-- Channel names without their zone ----------------------------------------------------------------------------------------

-- A window with the game's own channel list (and their zone channel ids).
local function Channels(list, zones)
	local f = CreateFrame("ScrollingMessageFrame", nil, UIParent)
	f.channelList, f.zoneChannelList = list, zones or {}
	return f
end

local function Short(f, channel, zoneID, base)
	return { ns.ChatShortChannel(f, "CHAT_MSG_CHANNEL", "hello", "Bob", "Common", channel, "", "", zoneID, 2, base, 0, 77) }
end

test("ShortChannel: '2. Trade - City' as '2. Trade', when the window knows the channel", function()
	local f = Channels({ "General", "Trade" }, { 1, 2 })
	eq(Short(f, "2. Trade - City", 2, "Trade"),
		{ false, "hello", "Bob", "Common", "2. Trade", "", "", 2, 2, "Trade", 0, 77 }, "found by its zone channel id")
	eq(Short(f, "1. General - Elwynn Forest", 0, "General")[5], "1. General", "found by its base name")
end)

test("ShortChannel: left as it is when the window's entry is longer, unknown, or has no zone", function()
	local f = Channels({ "Trade - City" }, { 2 })
	eq(Short(f, "2. Trade - City", 2, "Trade"), { false }, "the window's own name is longer: keep the long one")
	eq(Short(Channels({ "General" }, { 1 }), "2. Trade - City", 2, "Trade"), { false }, "not this window's channel")
	eq(Short(f, "4. MyChannel", 0, "MyChannel"), { false }, "no zone in the name")
	eq(Short(f, wow.secret("2. Trade - City"), 2, "Trade"), { false }, "a secret name")
	eq({ ns.ChatShortChannel(f, "CHAT_MSG_CHANNEL", "", "Bob", "", "2. Trade - City", "", "", 2, 2, "Trade") }, { false },
		"no words")
end)

-- Friends coming and going ---------------------------------------------------------------------------------------------------

test("QuietSystem: friends and guild coming online or going offline, quiet and short", function()
	wow.login(nil)
	eq({ ns.ChatQuietSystem(nil, "CHAT_MSG_SYSTEM", "|Hplayer:Bob|h[Bob]|h has come online.", "", 1) },
		{ false, MUTED .. "|Hplayer:Bob|hBob|h came online|r", "", 1 })
	eq({ ns.ChatQuietSystem(nil, "CHAT_MSG_SYSTEM", "Bob has gone offline.") },
		{ false, MUTED .. "Bob went offline|r" })
	eq({ ns.ChatQuietSystem(nil, "CHAT_MSG_SYSTEM", "You are now Away.") }, { false }, "another system line")
	ns.db.quiet = false
	eq({ ns.ChatQuietSystem(nil, "CHAT_MSG_SYSTEM", "Bob has gone offline.") }, { false }, "quiet off")
end)

test("through the chat's filters: a friend's line comes quiet", function()
	wow.login(nil)
	eq(wow.say("CHAT_MSG_SYSTEM", "Bob has gone offline."), MUTED .. "Bob went offline|r")
	clean()
end)

-- Each message's backdrop ------------------------------------------------------------------------------------------------------

test("a backdrop behind each message seen, none behind an empty or hidden one", function()
	local lines = {}
	for index = 1, 3 do
		local fs = ChatFrame1:CreateFontString()
		fs:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMLEFT", 0, index * 14)
		fs:SetSize(200, 12)
		-- (the stub's layout is crude, and Chat.lua anchors the lines again: each placed inside the window by hand)
		fs.GetBottom = function() return 250 + index * 14 end
		fs.GetTop = function() return 262 + index * 14 end
		lines[index] = fs
	end
	lines[1]:SetText("|Hplayer:Bob:2:WHISPER|h[Bob]|h whispers: hi")
	lines[2]:SetText("")
	lines[3]:SetText("hidden words")
	lines[3]:Hide()
	ChatFrame1.visibleLines = lines
	wow.login(nil)
	wow.advance(0.5)
	local v = ns.ChatVeil(lines[1])
	ok(v, "a veil for the first line")
	ok(v.solid:IsShown(), "its backdrop shown")
	eq(v.mark, "whisper")
	ok(v.edge:IsShown(), "a whisper's edge")
	no(ns.ChatVeil(lines[2]).solid:IsShown(), "no words: no backdrop")
	no(ns.ChatVeil(lines[3]).solid:IsShown(), "hidden: no backdrop")
	-- (the line fading: its backdrop with it)
	lines[1]:SetAlpha(0.5)
	wow.advance(0.1)
	eq(v.solid:GetAlpha(), 0.5)
	clean()
end)

test("ChatAlign runs once the chat is dressed", function()
	wow.login(nil)
	wow.advance(0.5)
	ns.ChatAlign()
	clean()
end)
