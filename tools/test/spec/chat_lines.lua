-- ChatLines.lua: each line's new words (short tags, the hour quiet, one speaker's lines grouped), plain words for
-- copying, web addresses as links, and the public channels held through a fight.

local ns = wow.load()

-- A chat window with the game's history buffer: the newest line first, as the game keeps it. Each line added runs
-- ChatLines' hook (as the game's AddMessage would, hooked by ns.LinesPolish).
local function Window()
	local f = CreateFrame("ScrollingMessageFrame", nil, UIParent)
	local lines = {}
	f.lines = lines
	f.historyBuffer = { GetEntryAtIndex = function(_, index) return lines[index] end }
	f.AddMessage = function(self, text)
		table.insert(lines, 1, { message = text, timestamp = GetTime() })
		ns.ChatOnAdded(self, text)
	end
	f.MarkDisplayDirty = function() end
	return f
end

local function Texts(f)
	local out = {}
	for index = #f.lines, 1, -1 do out[#out + 1] = f.lines[index].message end
	return out
end

-- Short tags ------------------------------------------------------------------------------------------------------

test("ShortTags: the channels' names as short tags, still their own links", function()
	local cases = {
		{ "|Hchannel:channel:1|h[1. General - Elwynn Forest]|h", "|Hchannel:channel:1|h[1]|h" },
		{ "|Hchannel:CHANNEL:2|h[2. Trade - City]|h", "|Hchannel:CHANNEL:2|h[2]|h" },
		{ "|Hchannel:GUILD|h[Guild]|h", "|Hchannel:GUILD|h[G]|h" },
		{ "|Hchannel:OFFICER|h[Officer]|h", "|Hchannel:OFFICER|h[O]|h" },
		{ "|Hchannel:PARTY|h[Party]|h", "|Hchannel:PARTY|h[P]|h" },
		{ "|Hchannel:PARTY|h[Party Leader]|h", "|Hchannel:PARTY|h[PL]|h" },
		{ "|Hchannel:RAID|h[Raid]|h", "|Hchannel:RAID|h[R]|h" },
		{ "|Hchannel:RAID|h[Raid Leader]|h", "|Hchannel:RAID|h[RL]|h" },
		{ "|Hchannel:RAID|h[Raid Warning]|h", "|Hchannel:RAID|h[RW]|h" },
		{ "|Hchannel:INSTANCE_CHAT|h[Instance]|h", "|Hchannel:INSTANCE_CHAT|h[I]|h" },
		{ "|Hchannel:INSTANCE_CHAT|h[Instance Leader]|h", "|Hchannel:INSTANCE_CHAT|h[IL]|h" },
		{ "|Hchannel:WHATEVER|h[Something]|h", "|Hchannel:WHATEVER|h[Something]|h" },
		{ "no channel here [Guild]", "no channel here [Guild]" },
	}
	for _, case in ipairs(cases) do
		eq(ns.ChatShortTags(case[1] .. " |Hplayer:Bob:1|h[Bob]|h: hi"), case[2] .. " |Hplayer:Bob:1|h[Bob]|h: hi", case[1])
	end
end)

-- Each line's new words ----------------------------------------------------------------------------------------------

local GUILD_BOB = "|Hchannel:GUILD|h[Guild]|h |Hplayer:Bob:11:GUILD|h[Bob]|h: "

test("a line added gets short tags in the window's history", function()
	wow.login(nil)
	local f = Window()
	f:AddMessage(GUILD_BOB .. "hello")
	eq(Texts(f), { "|Hchannel:GUILD|h[G]|h |Hplayer:Bob:11:GUILD|h[Bob]|h: hello" })
	ns.db.tags = false
	f:AddMessage(GUILD_BOB .. "again")
	eq(Texts(f)[2], GUILD_BOB .. "again", "tags off: as the game wrote it")
end)

test("the game's hour at the start of a line, in a quiet grey", function()
	wow.login(nil)
	wow.cvars.showTimestamps = "%H:%M "
	local f = Window()
	f:AddMessage("21:04 " .. GUILD_BOB .. "hello")
	eq(Texts(f)[1], "|cff7d7d7d21:04 |r|Hchannel:GUILD|h[G]|h |Hplayer:Bob:11:GUILD|h[Bob]|h: hello")
	wow.cvars.showTimestamps = "%I:%M:%S %p "
	f:AddMessage(" 9:04:59 PM System message")
	eq(Texts(f)[2], "|cff7d7d7d 9:04:59 PM |rSystem message")
end)

test("a secret line, or one the window doesn't hold, is left as it is", function()
	wow.login(nil)
	local f = Window()
	local secret = wow.secret(GUILD_BOB .. "x")
	table.insert(f.lines, 1, { message = secret })
	ns.ChatOnAdded(f, secret)
	ok(f.lines[1].message == secret)
	-- (the window's newest entry holds other words: not this line's)
	table.insert(f.lines, 1, { message = "other" })
	ns.ChatOnAdded(f, GUILD_BOB .. "x")
	eq(f.lines[1].message, "other")
	clean()
end)

local INDENT = "^ |TInterface\\AddOns\\Serene\\Media\\Blank:1:%d+|t"

test("one speaker's lines in a row: the name on the first only (group on)", function()
	wow.login({ group = true, ungrouped = true, tags = false }) -- (ungrouped: the one-time migration already done)
	local f = Window()
	f:AddMessage(GUILD_BOB .. "one")
	f:AddMessage(GUILD_BOB .. "two")
	local texts = Texts(f)
	eq(texts[1], GUILD_BOB .. "one")
	ok(texts[2]:find(INDENT .. "two$"), "the second under the first: " .. texts[2])
	-- (another speaker, or the same in another chat: the name again)
	f:AddMessage("|Hchannel:GUILD|h[Guild]|h |Hplayer:Ann:12:GUILD|h[Ann]|h: three")
	f:AddMessage("|Hplayer:Bob:13:WHISPER|h[Bob]|h whispers: four")
	texts = Texts(f)
	ok(texts[3]:find("[Ann]", 1, true), texts[3])
	ok(texts[4]:find("[Bob]", 1, true), "a whisper is another conversation: " .. texts[4])
end)

test("a grouped line keeps the whole group seen as long as itself", function()
	wow.login({ group = true, ungrouped = true })
	local f = Window()
	f:AddMessage(GUILD_BOB .. "one")
	wow.advance(30)
	f:AddMessage(GUILD_BOB .. "two")
	eq(f.lines[2].timestamp, GetTime(), "the first line's time moved up to the newest's")
end)

test("a speaker's group ends after two minutes, or when another line comes between", function()
	wow.login({ group = true, ungrouped = true })
	local f = Window()
	f:AddMessage(GUILD_BOB .. "one")
	wow.advance(121)
	f:AddMessage(GUILD_BOB .. "two")
	ok(Texts(f)[2]:find("[Bob]", 1, true), "after 2 minutes: the name again")
	f:AddMessage("System: something")
	f:AddMessage(GUILD_BOB .. "three")
	ok(Texts(f)[4]:find("[Bob]", 1, true), "a line between: the name again")
end)

test("group off (the default): every line keeps its name", function()
	wow.login(nil)
	local f = Window()
	f:AddMessage(GUILD_BOB .. "one")
	f:AddMessage(GUILD_BOB .. "two")
	ok(Texts(f)[2]:find("[Bob]", 1, true))
end)

test("a new line fades in over 0.3 s, then is left alone", function()
	wow.login(nil)
	local f = Window()
	f:AddMessage("fresh words")
	local new = Texts(f)[1]
	eq(ns.ChatFadeIn(new), 0.05, "just came: faint")
	wow.advance(0.15)
	local half = ns.ChatFadeIn(new)
	ok(half > 0.4 and half < 0.6, "half way: " .. tostring(half))
	wow.advance(0.2)
	eq(ns.ChatFadeIn(new), 1, "once: full")
	eq(ns.ChatFadeIn(new), nil, "then not ours to touch")
	eq(ns.ChatFadeIn("never added"), nil)
end)

-- Plain words ------------------------------------------------------------------------------------------------------------

test("Plain: links as their words, no colours or pictures", function()
	local cases = {
		{ "|cffffd100|Hplayer:Bob:1|h[Bob]|h|r: look |cff1eff00|Hitem:2589|h[Linen Cloth]|h|r",
			"[Bob]: look [Linen Cloth]" },
		{ "|TInterface\\Icons\\coin:0|t  12  gold", "12 gold" },
		{ "   leading spaces", "leading spaces" },
		{ "|Kq1|k friend", "friend" },
		{ "plain words", "plain words" },
	}
	for _, case in ipairs(cases) do eq(ns.ChatPlain(case[1]), case[2], case[1]) end
end)

-- Web addresses ------------------------------------------------------------------------------------------------------------

local function Url(address) return "|cff6cb4ff|Haddon:Serene:url:" .. address .. "|h" .. address .. "|h|r" end

test("Linkify: web addresses become links of ours; the game's own links are left alone", function()
	local cases = {
		{ "see https://example.com/page now", "see " .. Url("https://example.com/page") .. " now" },
		{ "(http://wowhead.com/item=1).", "(http://wowhead.com/item=1).", "a word starting with a bracket isn't one" },
		{ "go to www.wowhead.com.", "go to " .. Url("www.wowhead.com") .. "." },
		{ "HTTPS://LOUD.ORG!", Url("HTTPS://LOUD.ORG") .. "!" },
		{ "www.x is not", "www.x is not" },
		{ "http:// is too short", "http:// is too short" },
		{ "|Hitem:1|h[www.inside.com]|h and www.outside.com", "|Hitem:1|h[www.inside.com]|h and " .. Url("www.outside.com") },
		{ "nothing here", "nothing here" },
	}
	for _, case in ipairs(cases) do eq(ns.ChatLinkify(case[1]), case[2], case[3] or case[1]) end
end)

test("through the chat's filters: an address said in /say comes as a link", function()
	wow.login(nil)
	local shown = wow.say("CHAT_MSG_SAY", "see https://example.com/page", "Bob")
	eq(shown, "see " .. Url("https://example.com/page"))
	shown = wow.say("CHAT_MSG_SAY", "no address", "Bob")
	eq(shown, "no address")
	clean()
end)

test("a click on an address: the copy box with it", function()
	wow.login(nil)
	SetItemRef("addon:Serene:url:https://example.com", "x", "LeftButton")
	local box = _G.SereneCopyBox
	ok(box and box:IsShown(), "the box is shown")
	eq(box.edit:GetText(), "https://example.com")
	clean()
end)

-- Held through a fight ---------------------------------------------------------------------------------------------------

-- A window whose OnEvent hears the replayed lines (the game's own handling, its filters included).
local function Heard()
	local f = CreateFrame("ScrollingMessageFrame", nil, UIParent)
	f.heard = {}
	f:SetScript("OnEvent", function(self, event, text, author)
		-- (the replayed line goes through the filters again: Hold must let it pass)
		if ns.ChatHold(self, event, text, author) then return end
		table.insert(self.heard, { event, text, author })
	end)
	return f
end

test("in a fight the public channels wait, and come once it is over, in order", function()
	wow.login(nil)
	local f = Heard()
	no(ns.ChatHold(f, "CHAT_MSG_CHANNEL", "before", "Bob"), "not fighting: shown at once")
	ns.ChatFighting(true)
	ok(ns.ChatHold(f, "CHAT_MSG_CHANNEL", "one", "Bob"), "held")
	ok(ns.ChatHold(f, "CHAT_MSG_CHANNEL", "two", "Ann"), "held")
	ns.ChatReplay()
	eq(f.heard, {}, "still fighting: nothing replayed")
	ns.ChatFighting(false)
	ns.ChatReplay()
	eq(f.heard, { { "CHAT_MSG_CHANNEL", "one", "Bob" }, { "CHAT_MSG_CHANNEL", "two", "Ann" } })
	ns.ChatReplay()
	eq(#f.heard, 2, "replayed once only")
end)

test("a long fight keeps the newest 80 lines of a window", function()
	wow.login(nil)
	local f = Heard()
	ns.ChatFighting(true)
	for index = 1, 100 do ns.ChatHold(f, "CHAT_MSG_CHANNEL", "line " .. index, "Bob") end
	ns.ChatFighting(false)
	ns.ChatReplay()
	eq(#f.heard, 80)
	eq(f.heard[1][2], "line 21")
	eq(f.heard[80][2], "line 100")
end)

test("nothing waits with calm (or the chat) off", function()
	wow.login({ calm = false })
	local f = Heard()
	ns.ChatFighting(true)
	no(ns.ChatHold(f, "CHAT_MSG_CHANNEL", "one", "Bob"))
	ns.db.calm, ns.db.chat = true, false
	no(ns.ChatHold(f, "CHAT_MSG_CHANNEL", "one", "Bob"))
end)

test("a real fight: channel lines held by the game's filters, replayed half a second after it ends", function()
	wow.login(nil)
	local f = Heard()
	wow.chatFrame = f
	wow.fight(true)
	local _, shown = wow.say("CHAT_MSG_CHANNEL", "LFG deadmines", "Bob", "", "4. LookingForGroup", "", "", 0, 4, "LookingForGroup")
	no(shown, "held in the fight")
	_, shown = wow.say("CHAT_MSG_GUILD", "hi guild", "Ann")
	ok(shown, "the guild always comes at once")
	wow.fight(false)
	eq(#f.heard, 0)
	wow.advance(0.6)
	eq(#f.heard, 1, "replayed after the fight")
	eq(f.heard[1][2], "LFG deadmines")
	clean()
end)
