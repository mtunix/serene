-- This client's own data, replayed: chat lines and item tooltips kept by /serene capture (Capture.lua) and turned
-- into fixtures by tools/test/import_saved.py. The tests below skip until a capture exists.
-- Also: Capture.lua itself (off unless asked, players' words never kept, each line once, bounded).

local ns = wow.load()

local function Fixture(name)
	local chunk = loadfile(wow.root .. "/tools/test/fixtures/" .. name)
	if not chunk then skip("no fixtures/" .. name .. ": /serene capture on in game, /reload, then tools/test/import_saved.py") end
	return chunk()
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Replaying -----------------------------------------------------------------------------------------------------------

test("every captured chat line goes through Serene's chat without an error", function()
	local chat = Fixture("capture_chat.lua")
	wow.login(nil)
	wow.advance(1)
	local lines = 0
	for event, list in pairs(chat) do
		for _, args in ipairs(list) do
			wow.say(event, unpack(args, 1, 17))
			lines = lines + 1
		end
	end
	wow.advance(3)
	ok(lines > 0, "the capture has lines")
	clean()
end)

test("every captured chat line, in a fight (public channels held, gains gathered)", function()
	local chat = Fixture("capture_chat.lua")
	wow.login(nil)
	wow.advance(1)
	wow.fight(true)
	for event, list in pairs(chat) do
		for _, args in ipairs(list) do wow.say(event, unpack(args, 1, 17)) end
	end
	wow.fight(false)
	wow.advance(3)
	clean()
end)

test("a loot line Serene doesn't read is shown as the game wrote it", function()
	local chat = Fixture("capture_chat.lua")
	if not chat.CHAT_MSG_LOOT then skip("no loot lines captured yet") end
	wow.login(nil)
	wow.advance(1)
	local unread, lost = {}, {}
	for _, args in ipairs(chat.CHAT_MSG_LOOT) do
		if not ns.LootRead(args[1]) then
			unread[#unread + 1] = args[1]
			local shown = wow.say("CHAT_MSG_LOOT", unpack(args, 1, 17))
			if shown ~= args[1] then lost[#lost + 1] = args[1] end
		end
	end
	if #unread > 0 then print(("  note: %d captured loot line(s) not read by ChatLoot, e.g. %q"):format(#unread, unread[1])) end
	eq(lost, {}, "unread loot lines changed or hidden")
	clean()
end)

test("every captured roll and loot sentence of the kinds ChatLoot knows is read", function()
	local chat = Fixture("capture_chat.lua")
	if not chat.CHAT_MSG_LOOT then skip("no loot lines captured yet") end
	wow.login(nil)
	local missed = {}
	for _, args in ipairs(chat.CHAT_MSG_LOOT) do
		local text = args[1]
		-- (the kinds ChatLoot.lua's SENTENCES cover: receiving loot and items, and the rolls)
		local known = text:find("receives? loot") or text:find("receives? item") or text:find("Roll %- ")
			or text:find("has selected") or text:find("passed on") or text:find("won:") or text:find("You have selected")
		if known and not ns.LootRead(text) then missed[#missed + 1] = text end
	end
	eq(missed, {}, "sentences of a known kind that ChatLoot didn't read")
end)

test("every captured item tooltip goes through Serene's tooltip without an error", function()
	local tips = Fixture("capture_tooltip.lua")
	wow.login(nil)
	wow.advance(1)
	ok(wow.tooltipPostCalls and #wow.tooltipPostCalls > 0, "Serene added a tooltip post-call")
	local items = 0
	for id, tip in pairs(tips) do
		local data = { type = Enum.TooltipDataType.Item, id = id, lines = {} }
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		for index, line in ipairs(tip.lines) do
			data.lines[index] = { leftText = line.left or nil, rightText = line.right or nil, type = line.type or nil,
				price = line.price or nil }
			if line.right then GameTooltip:AddDoubleLine(line.left or "", line.right) else GameTooltip:AddLine(line.left or "") end
		end
		GameTooltip:Show()
		for _, post in ipairs(wow.tooltipPostCalls) do
			if post[1] == "ALL" or post[1] == Enum.TooltipDataType.Item then
				wow.call("tooltip post-call", post[2], GameTooltip, data)
			end
		end
		GameTooltip:Hide()
		items = items + 1
	end
	ok(items > 0, "the capture has tooltips")
	clean()
end)

-- Capture.lua -----------------------------------------------------------------------------------------------------------

test("capture is off unless asked for", function()
	wow.login(nil)
	wow.fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].", "")
	eq(ns.db.capture, nil, "nothing kept")
	clean()
end)

test("the game's sentences are kept as they are, each once", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	for _ = 1, 3 do wow.fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].", "Tester", "", "", "Tester") end
	wow.fire("CHAT_MSG_MONEY", "You loot 2 Silver, 5 Copper")
	local c = ns.db.capture.chat
	eq(#c.CHAT_MSG_LOOT, 1, "a repeated line kept once")
	eq(c.CHAT_MSG_LOOT[1][1], "You receive loot: [Linen Cloth].")
	eq(c.CHAT_MSG_MONEY[1][1], "You loot 2 Silver, 5 Copper")
	clean()
end)

test("players' words and names are never kept: only the shape", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	wow.fire("CHAT_MSG_WHISPER", "my secret plans www.example.org", "Friend-Realm", "", "", "Friend-Realm", "", 0, 0,
		"", 0, 77, "Player-1-ABCDEF")
	wow.fire("CHAT_MSG_CHANNEL", "WTS |Hitem:25::::::::60:::::|h[Worn Shortsword]|h", "Seller", "Common", "2. Trade - City",
		"Seller", "", 2, 2, "Trade - City", 7, 78, "Player-1-123456")
	local w = ns.db.capture.chat.CHAT_MSG_WHISPER[1]
	no(w[1]:find("secret"), "the words replaced")
	ok(w[1]:find("https://example.com/x", 1, true), "a web address kept as the shape only")
	eq(w[2], "Someone-Somerealm")
	eq(w[5], "Someone-Somerealm")
	eq(w[12], "Player-0-00000000")
	local t = ns.db.capture.chat.CHAT_MSG_CHANNEL[1]
	no(t[1]:find("WTS"), "the words replaced")
	ok(t[1]:find("|Hitem:", 1, true), "a link kept as the shape only")
	eq(t[4], "2. Trade - City", "the channel kept")
	clean()
end)

test("secret values aren't saved", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	wow.fire("CHAT_MSG_SYSTEM", "Quest accepted: The Fargodeep Mine", wow.secret("x"), 5)
	local line = ns.db.capture.chat.CHAT_MSG_SYSTEM[1]
	eq(line[2], false, "a secret becomes false")
	eq(line[3], 5)
	clean()
end)

test("at most 150 lines per event", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	for index = 1, 200 do wow.fire("CHAT_MSG_SYSTEM", "Line " .. index) end
	eq(#ns.db.capture.chat.CHAT_MSG_SYSTEM, 150)
	clean()
end)

test("an item tooltip's lines are kept once per item", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	local lines = { { leftText = "Linen Cloth", type = 0 }, { leftText = "Sell Price:", type = 11, price = 13 } }
	for _ = 1, 2 do
		for _, post in ipairs(wow.tooltipPostCalls) do
			if post[1] == Enum.TooltipDataType.Item then post[2](GameTooltip, { id = 2589, lines = lines }) end
		end
	end
	local tip = ns.db.capture.tooltip[2589]
	ok(tip, "kept")
	eq(tip.lines[2], { left = "Sell Price:", right = false, type = 11, price = 13 })
	eq(Count(ns.db.capture.tooltip), 1)
	clean()
end)

test("/serene capture off stops, clear forgets", function()
	wow.login(nil)
	wow.slash("/serene capture on")
	wow.fire("CHAT_MSG_SYSTEM", "One")
	wow.slash("/serene capture off")
	wow.fire("CHAT_MSG_SYSTEM", "Two")
	eq(#ns.db.capture.chat.CHAT_MSG_SYSTEM, 1)
	eq(ns.db.capturing, nil)
	wow.slash("/serene capture clear")
	eq(ns.db.capture, nil)
	clean()
end)
