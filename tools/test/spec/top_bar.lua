-- TopBar.lua's money: your gold kept per character (SereneDB.gold[realm][name]), and the gold word's tooltip: yours,
-- what you earned or spent this session, your other characters on this realm (richest first) and all of it together.
-- And the room in your bags, on the band and on MenuBar's bags word: ordinary bags only, a quiver apart.
-- (The coins themselves, Items.Coins: spec/tooltip.lua.)

local ns = wow.load()

local REALM, ME = wow.player.realm, wow.player.name

-- The band's gold word.
local function GoldWord()
	for _, child in ipairs({ SereneTopBar:GetChildren() }) do
		if rawget(child, "key") == "gold" then return child end
	end
end

-- The gold tooltip, as left and right words, one pair per line.
local function Tip()
	local word = GoldWord()
	word:GetScript("OnEnter")(word)
	local lines = {}
	for index = 1, GameTooltip:NumLines() do
		local left, right = _G["GameTooltipTextLeft" .. index], _G["GameTooltipTextRight" .. index]
		lines[#lines + 1] = { left and left:GetText() or "", right and right:IsShown() and right:GetText() or "" }
	end
	return lines
end

-- The line whose left words contain this, and its right words.
local function Line(lines, words)
	for _, line in ipairs(lines) do
		if line[1]:find(words, 1, true) then return line[2] end
	end
end

-- The other characters' names, in the tooltip's order.
local function Others(lines)
	local names = {}
	for _, line in ipairs(lines) do
		for _, name in ipairs({ "Alt", "Banker", "Twink" }) do
			if line[1]:find(name, 1, true) then names[#names + 1] = name end
		end
	end
	return names
end

local function Login(saved)
	wow.login(saved or {})
	wow.advance(0.5)
end

test("your money is kept, per realm and character, and kept current", function()
	wow.money = 123456
	Login()
	eq(ns.db.gold[REALM][ME], { money = 123456, class = "WARRIOR" }, "at login")
	wow.money = 150000
	wow.fire("PLAYER_MONEY")
	eq(ns.db.gold[REALM][ME].money, 150000, "after money came")
	clean()
end)

test("the gold tooltip: yours, your other characters on this realm richest first, and all of them together", function()
	wow.money = 100000
	Login({ gold = { [REALM] = { Alt = { money = 50000, class = "MAGE" }, Banker = { money = 2500000 } },
		Elsewhere = { Twink = { money = 999999 } } } })
	local lines = Tip()
	eq(Line(lines, ME), ns.Items.Coins(100000), "yours")
	eq(Others(lines), { "Banker", "Alt" }, "richest first; another realm's not")
	eq(Line(lines, "All on " .. REALM), ns.Items.Coins(2650000), "all together")
	clean()
end)

test("alone on the realm: no list of others, no total", function()
	Login()
	local lines = Tip()
	eq(Others(lines), {})
	eq(Line(lines, "All on"), nil)
	clean()
end)

test("this session: what you earned, or what you spent", function()
	wow.money = 100000
	Login()
	eq(Line(Tip(), "this session"), nil, "nothing yet")
	wow.money = 112345
	wow.fire("PLAYER_MONEY")
	local earned = Line(Tip(), "Earned this session")
	ok(earned and earned:find(ns.Items.Coins(12345), 1, true), "earned 1g 23s 45c (got " .. tostring(earned) .. ")")
	wow.money = 90000
	wow.fire("PLAYER_MONEY")
	local spent = Line(Tip(), "Spent this session")
	ok(spent and spent:find(ns.Items.Coins(10000), 1, true), "spent 1g (got " .. tostring(spent) .. ")")
	clean()
end)

-- Bags -------------------------------------------------------------------------------------------------------------------

local function Word(key)
	for _, child in ipairs({ SereneTopBar:GetChildren() }) do
		if rawget(child, "key") == key then return child end
	end
end

test("the bags word: the room in your ordinary bags; a quiver's on its own in the tooltip", function()
	wow.bags[0] = { size = 4, [1] = { id = 2589, count = 5 } }
	wow.bags[1] = { size = 6, family = 1 }
	wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20 }
	Login()
	ok(Word("bags").text:GetText():find("3", 1, true), "3 free, the quiver's 6 not counted")
	local word = Word("bags")
	word:GetScript("OnEnter")(word)
	local quiver
	for index = 1, GameTooltip:NumLines() do
		if (_G["GameTooltipTextLeft" .. index]:GetText() or ""):find("Bag 1", 1, true) then
			quiver = _G["GameTooltipTextRight" .. index]:GetText()
		end
	end
	ok(quiver and quiver:find("6 of 6", 1, true), "the quiver on its own (got " .. tostring(quiver) .. ")")
	clean()
end)

test("bags full: the band comes back by itself (on hover otherwise), the word in red", function()
	wow.bags[0] = { size = 2, [1] = { id = 2589, count = 5 }, [2] = { id = 2589, count = 5 } }
	wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20 }
	Login({ topShow = "hover" })
	ok(ns.TopNeeded(false), "wanted, full")
	ok(Word("bags").text:GetText():find("0", 1, true), "none free")
	wow.bags[0][2] = nil
	no(ns.TopNeeded(false), "room again: on hover only")
	clean()
end)

test("the menu band's bags word: the room left in the ordinary bags", function()
	wow.bags[0] = { size = 4, [1] = { id = 2589, count = 5 } }
	wow.bags[1] = { size = 6, family = 1 }
	wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20 }
	Login()
	local word
	for _, child in ipairs({ SereneMenuBar:GetChildren() }) do
		if rawget(child, "bags") then word = child end
	end
	ok(word, "the bags word")
	wow.fire("BAG_UPDATE")
	wow.advance(1.5)
	eq(word.count:GetText(), "3")
	clean()
end)
