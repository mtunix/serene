-- ChatLoot.lua: the game's loot, roll, money, experience and reputation sentences read, and said in few lines.
-- The sentences are the game's own (globalstrings.lua, classic_era English: its roll sentences begin with a
-- "|HlootHistory:%d|h[Loot]|h: " link of their own).

local ns = wow.load()
local MUTED = ns.MUTED

-- A chat window with the game's history buffer: the newest line first, as the game keeps it.
local function Window()
	local f = CreateFrame("ScrollingMessageFrame", nil, UIParent)
	local lines = {}
	f.lines = lines
	f.historyBuffer = { GetEntryAtIndex = function(_, index) return lines[index] end }
	f.AddMessage = function(_, text, r, g, b)
		table.insert(lines, 1, { message = text, timestamp = GetTime(), r = r, g = g, b = b })
	end
	f.RemoveMessagesByPredicate = function(_, drop)
		for index = #lines, 1, -1 do if drop(lines[index]) then table.remove(lines, index) end end
	end
	f.MarkDisplayDirty = function() end
	return f
end

-- The window's words, oldest first.
local function Texts(f)
	local out = {}
	for index = #f.lines, 1, -1 do out[#out + 1] = f.lines[index].message end
	return out
end

local LINK = "|cff1eff00|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"
local EGG = "|cffffffff|Hitem:4655::::::::60:::::|h[Raptor Egg]|h|r"

-- The game's sentence filled in. Arguments before the ones the sentence is about (the roll's own link id) are numbers.
local function Say(format, ...)
	local codes = select(2, format:gsub("%%%d?%$?[sd]", ""))
	local args = {}
	for _ = 1, codes - select("#", ...) do args[#args + 1] = 12 end
	for index = 1, select("#", ...) do args[#args + 1] = (select(index, ...)) end
	return (format:format(unpack(args)))
end

-- Format strings ------------------------------------------------------------------------------------------------------

test("FormatPattern: the game's sentence as an anchored pattern, its codes as captures", function()
	local cases = {
		{ "%s receives loot: %s.", "^(.+) receives loot: (.+)%.$", { 1, 2 } },
		{ "You receive loot: %sx%d.", "^You receive loot: (.+)x(%d+)%.$", { 1, 2 } },
		{ "Need Roll - %d for %s by %s", "^Need Roll %- (%d+) for (.+) by (.+)$", { 1, 2, 3 } },
		{ "|HlootHistory:%d|h[Loot]|h: %s won: %s", "^|HlootHistory:(%d+)|h%[Loot%]|h: (.+) won: (.+)$", { 1, 2, 3 } },
		{ "%2$s was given to %1$s (100%)", "^(.+) was given to (.+) %(100%%%)$", { 2, 1 } },
		{ "a+b*c? ^$", "^a%+b%*c%? %^%$$", {} },
	}
	for _, case in ipairs(cases) do
		local pattern, order = ns.FormatPattern(case[1])
		eq(pattern, case[2], case[1])
		eq(order, case[3], case[1] .. " (order)")
	end
	eq(ns.FormatPattern(nil), nil)
	eq(ns.FormatPattern(""), nil)
	eq(ns.FormatPattern(5), nil)
end)

test("FormatMatch: the arguments in the format's own order, and how many", function()
	local args, count = ns.FormatMatch("Sopra receives loot: " .. LINK .. ".", LOOT_ITEM)
	eq(args, { "Sopra", LINK })
	eq(count, 2)
	-- (a language that puts its arguments the other way round: "%2$s ... %1$s")
	args = ns.FormatMatch("Linen goes to Sopra", "%2$s goes to %1$s")
	eq(args, { "Sopra", "Linen" })
	eq(ns.FormatMatch("Something else entirely", LOOT_ITEM), nil)
	eq(ns.FormatMatch("Sopra receives loot: x.", nil), nil)
end)

-- Reading the sentences -------------------------------------------------------------------------------------------------

-- Every sentence ChatLoot knows: its name, what it says (kind, choice), its arguments, and whether it is about you.
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
	{ "LOOT_ROLL_PASSED", "choice", "pass", { "who", "item" } },
	{ "LOOT_ROLL_ALL_PASSED", "allpassed", nil, { "item" } },
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
local VALUES = { who = "Sopra", item = LINK, roll = 87, count = 3 }

local function Expected(s)
	local said = { kind = s[2], choice = s[3], self = s[5] or false }
	for _, field in ipairs(s[4]) do said[field] = VALUES[field] end
	if said.self then said.who = "You" end
	return said
end

local function Filled(s, format)
	local values = {}
	for _, field in ipairs(s[4]) do values[#values + 1] = VALUES[field] end
	return Say(format, unpack(values))
end

test("LootRead: every loot and roll sentence of the game, read for what it says", function()
	for _, s in ipairs(SENTENCES) do
		ok(type(_G[s[1]]) == "string", s[1] .. " is in globalstrings.lua")
		local text = Filled(s, _G[s[1]])
		eq(ns.LootRead(text), Expected(s), s[1] .. ": " .. text)
	end
end)

test("LootRead: a client without the sentences reads the English ones Serene carries", function()
	local game = {}
	for _, s in ipairs(SENTENCES) do game[s[1]] = _G[s[1]] _G[s[1]] = nil end
	for _, s in ipairs(SENTENCES) do
		-- (the English sentence: the game's without its roll link)
		local format = game[s[1]]:gsub("^|HlootHistory:%%d|h%[Loot%]|h: ", "")
		local text = Filled(s, format)
		eq(ns.LootRead(text), Expected(s), s[1] .. " (English): " .. text)
	end
end)

test("LootRead: a line that isn't loot is not understood", function()
	for _, text in ipairs({ "Hello there", "", "Sopra receives loot:", "You receive loot: ." }) do
		eq(ns.LootRead(text), nil, text)
	end
end)

-- Loot in few lines ----------------------------------------------------------------------------------------------------

local function Loot(f, text, lineID)
	return ns.LootFilter(f, "CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, lineID)
end

test("one player's loot in a row is one line, joined while it comes", function()
	wow.login(nil)
	local f = Window()
	ok(Loot(f, "Sopra receives loot: " .. LINK .. "."), "the game's line hidden")
	eq(Texts(f), { "Sopra looted " .. LINK })
	wow.advance(3)
	ok(Loot(f, "Sopra receives loot: " .. EGG .. "x2."))
	eq(Texts(f), { "Sopra looted " .. LINK .. ", " .. EGG .. "x2" }, "joined on the same line")
	-- (yours too: "You looted")
	ok(Loot(f, "You receive loot: " .. LINK .. "."))
	eq(Texts(f)[2], "You looted " .. LINK, "another looter: a line of their own")
end)

test("loot after a pause, or after another line, starts a new line", function()
	wow.login(nil)
	local f = Window()
	Loot(f, "Sopra receives loot: " .. LINK .. ".")
	wow.advance(9)
	Loot(f, "Sopra receives loot: " .. EGG .. ".")
	eq(#Texts(f), 2, "more than 8 seconds apart")
	f:AddMessage("Someone says: hi")
	Loot(f, "Sopra receives loot: " .. LINK .. ".")
	eq(Texts(f), { "Sopra looted " .. LINK, "Sopra looted " .. EGG, "Someone says: hi", "Sopra looted " .. LINK },
		"a line said between: never written back above it")
end)

test("loot lines are left as the game wrote them when loot (or the chat) is off, or when not understood", function()
	wow.login(nil)
	local f = Window()
	no(Loot(f, "Mysterious words"), "not understood")
	no(Loot(f, wow.secret("Sopra receives loot: x.")), "a secret line")
	ns.db.loot = false
	no(Loot(f, "Sopra receives loot: " .. LINK .. "."), "loot off")
	ns.db.loot, ns.db.chat = true, false
	no(Loot(f, "Sopra receives loot: " .. LINK .. "."), "chat off")
	eq(Texts(f), {})
end)

-- Rolls ------------------------------------------------------------------------------------------------------------

local function Roll(f, name, ...)
	return Loot(f, Say(_G[name], ...))
end

test("a roll: every choice and roll on one line, then its winner; the winner's loot line dropped", function()
	wow.login(nil)
	local f = Window()
	local head = "|cffa0a0a0|Haddon:Serene:roll:1|h[Roll]|h|r " .. EGG .. " "
	ok(Roll(f, "LOOT_ROLL_GREED", "Sopra", EGG))
	eq(Texts(f), { head .. MUTED .. "· rolling (1)|r" })
	ok(Roll(f, "LOOT_ROLL_NEED", "Bob", EGG))
	ok(Roll(f, "LOOT_ROLL_ROLLED_GREED", 12, EGG, "Sopra"))
	ok(Roll(f, "LOOT_ROLL_ROLLED_NEED", 87, EGG, "Bob"))
	eq(Texts(f), { head .. MUTED .. "· rolling (2)|r" }, "still one line")
	ok(Roll(f, "LOOT_ROLL_WON", "Bob", EGG))
	eq(Texts(f), { head .. "→ Bob " .. MUTED .. "(Need 87)|r" })
	ok(Loot(f, "Bob receives loot: " .. EGG .. "."), "the winner's loot: already said")
	eq(#Texts(f), 1)
end)

test("everyone passing on an item says so on its line", function()
	wow.login(nil)
	local f = Window()
	Roll(f, "LOOT_ROLL_PASSED", "Sopra", EGG)
	Roll(f, "LOOT_ROLL_ALL_PASSED", EGG)
	eq(Texts(f), { "|cffa0a0a0|Haddon:Serene:roll:1|h[Roll]|h|r " .. EGG .. " " .. MUTED .. "· everyone passed|r" })
end)

test("a roll line written lower down again when other lines came since", function()
	wow.login(nil)
	local f = Window()
	Roll(f, "LOOT_ROLL_GREED", "Sopra", EGG)
	f:AddMessage("Someone says: hi")
	Roll(f, "LOOT_ROLL_NEED", "Bob", EGG)
	local texts = Texts(f)
	eq(#texts, 2, "the old line taken out")
	eq(texts[1], "Someone says: hi")
	ok(texts[2]:find("rolling (2)", 1, true), "the roll's line, newest, at the bottom")
end)

test("one sentence heard by two windows moves the roll once, and each window shows it", function()
	wow.login(nil)
	local a, b = Window(), Window()
	local text = Say(LOOT_ROLL_NEED, "Bob", EGG)
	ok(Loot(a, text, 501))
	ok(Loot(b, text, 501))
	ok(Texts(a)[1]:find("rolling (1)", 1, true), "window a")
	ok(Texts(b)[1]:find("rolling (1)", 1, true), "window b: the same state, not counted twice")
end)

test("a new choice on an item already won is a new roll", function()
	wow.login(nil)
	local f = Window()
	Roll(f, "LOOT_ROLL_NEED", "Bob", EGG)
	Roll(f, "LOOT_ROLL_WON", "Bob", EGG)
	Roll(f, "LOOT_ROLL_GREED", "Sopra", EGG)
	local texts = Texts(f)
	eq(#texts, 2)
	ok(texts[2]:find("roll:2", 1, true) and texts[2]:find("rolling (1)", 1, true), texts[2])
end)

test("the mouse over [Roll]: who chose what, the winner first", function()
	wow.login(nil)
	local f = Window()
	Roll(f, "LOOT_ROLL_ROLLED_GREED", 12, EGG, "Sopra")
	Roll(f, "LOOT_ROLL_ROLLED_NEED", 87, EGG, "Bob")
	Roll(f, "LOOT_ROLL_WON", "Bob", EGG)
	ok(ns.RollTooltip(f, "addon:Serene:roll:1"))
	local lines = wow.state(GameTooltip).lines
	eq(lines[1].left, EGG)
	ok(lines[2].left:find("Bob  (won)", 1, true), "the highest roll first, marked")
	ok(lines[2].right:find("Need 87", 1, true))
	ok(lines[3].left:find("Sopra", 1, true))
	no(ns.RollTooltip(f, "addon:Serene:roll:99"), "an unknown roll")
	no(ns.RollTooltip(f, "item:2589"), "not a roll")
end)

-- Money, experience, reputation -----------------------------------------------------------------------------------------

test("LootCoins: copper in a sentence of money", function()
	local cases = {
		{ "You loot 1 Gold, 2 Silver, 3 Copper", 10203 },
		{ "You loot 5 Copper", 5 },
		{ "You loot 12 Silver", 1200 },
		{ "Your share of the loot is 1 Silver, 20 Copper.", 120 },
		{ "Nothing here", nil },
	}
	for _, case in ipairs(cases) do eq(ns.LootCoins(case[1]), case[2], case[1]) end
end)

local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local function Gain(f, event, text) return ns.GainsFilter(f, event, text) end

test("money, experience and reputation: one quiet line that grows", function()
	wow.login(nil)
	local f = Window()
	ok(Gain(f, "CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper"))
	eq(Texts(f), { MUTED .. "+1" .. SILVER .. " 20" .. COPPER .. "|r" })
	ok(Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 540 experience."))
	ok(Gain(f, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Stormwind reputation has increased by 50."))
	ok(Gain(f, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Defias Brotherhood reputation has decreased by 25."))
	ok(Gain(f, "CHAT_MSG_MONEY", "You loot 5 Copper"))
	eq(Texts(f), { MUTED .. "+1" .. SILVER .. " 25" .. COPPER .. "  ·  +540 XP  ·  Stormwind +50  ·  Defias Brotherhood -25|r" })
end)

test("a quest's reward said by the game's system joins the line; other system lines are left alone", function()
	wow.login(nil)
	local f = Window()
	ok(Gain(f, "CHAT_MSG_SYSTEM", "Experience gained: 500."))
	ok(Gain(f, "CHAT_MSG_SYSTEM", "Received 2 Silver."))
	eq(Texts(f), { MUTED .. "+2" .. SILVER .. "  ·  +500 XP|r" })
	no(Gain(f, "CHAT_MSG_SYSTEM", "You are now Away."))
	no(Gain(f, "CHAT_MSG_SAY", "540"), "not a gains event")
end)

test("the gains line keeps growing 20 seconds, 90 in a fight", function()
	wow.login(nil)
	local f = Window()
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	wow.advance(21)
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	eq(#Texts(f), 2, "a new line after 20 s")
	ns.LootFighting(true)
	wow.advance(60)
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	eq(#Texts(f), 2, "in a fight: still the same line after 60 s")
	eq(Texts(f)[2], MUTED .. "+20 XP|r")
end)

test("a fight starting and ending switches the gains' time (PLAYER_REGEN events)", function()
	wow.login(nil)
	local f = Window()
	wow.fight(true)
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	wow.advance(60)
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	eq(#Texts(f), 1)
	wow.fight(false)
	wow.advance(25)
	Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
	eq(#Texts(f), 2)
end)

test("gains left alone when off, secret, or not understood", function()
	wow.login(nil)
	local f = Window()
	no(Gain(f, "CHAT_MSG_MONEY", "Nothing of value"))
	no(Gain(f, "CHAT_MSG_COMBAT_XP_GAIN", "no number"))
	no(Gain(f, "CHAT_MSG_COMBAT_FACTION_CHANGE", "Something about factions"))
	no(Gain(f, "CHAT_MSG_MONEY", wow.secret("You loot 5 Copper")))
	ns.db.gains = false
	no(Gain(f, "CHAT_MSG_MONEY", "You loot 5 Copper"))
	eq(Texts(f), {})
end)

-- Through the game's filters -------------------------------------------------------------------------------------------

test("through the chat's filters: loot and gains lines replaced by Serene's", function()
	wow.login(nil)
	local f = Window()
	wow.chatFrame = f
	local shown, kept = wow.say("CHAT_MSG_LOOT", "Sopra receives loot: " .. LINK .. ".")
	no(kept, "the game's loot line hidden")
	shown, kept = wow.say("CHAT_MSG_MONEY", "You loot 3 Copper")
	no(kept, "the game's money line hidden")
	shown, kept = wow.say("CHAT_MSG_LOOT", "Not loot at all")
	ok(kept, "a line not understood: shown as the game wrote it")
	eq(Texts(f), { "Sopra looted " .. LINK, MUTED .. "+3" .. COPPER .. "|r", "Not loot at all" })
	clean()
end)

-- Writing a line again ---------------------------------------------------------------------------------------------------

test("LootRefresh: the newest line written again in place; an older one moved to the bottom", function()
	local f = Window()
	local entry = ns.LootRefresh(f, nil, "one")
	eq(Texts(f), { "one" })
	local again = ns.LootRefresh(f, entry, "one, two")
	ok(again == entry, "the same entry, still the newest")
	eq(Texts(f), { "one, two" })
	f:AddMessage("between")
	local moved = ns.LootRefresh(f, again, "one, two, three")
	ok(moved ~= again, "a new entry")
	eq(Texts(f), { "between", "one, two, three" })
end)
