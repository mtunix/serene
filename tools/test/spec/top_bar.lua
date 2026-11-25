-- TopBar.lua's money: your gold kept per character (SereneDB.gold[realm][name]), and the gold word's tooltip: yours,
-- what you earned or spent this session, your other characters on this realm (richest first) and all of it together.
-- (The coins themselves, ns.TopCoins: spec/tooltip.lua.)

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
	eq(Line(lines, ME), ns.TopCoins(100000), "yours")
	eq(Others(lines), { "Banker", "Alt" }, "richest first; another realm's not")
	eq(Line(lines, "All on " .. REALM), ns.TopCoins(2650000), "all together")
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
	ok(earned and earned:find(ns.TopCoins(12345), 1, true), "earned 1g 23s 45c (got " .. tostring(earned) .. ")")
	wow.money = 90000
	wow.fire("PLAYER_MONEY")
	local spent = Line(Tip(), "Spent this session")
	ok(spent and spent:find(ns.TopCoins(10000), 1, true), "spent 1g (got " .. tostring(spent) .. ")")
	clean()
end)
