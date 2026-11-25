-- Tooltip.lua: the vendor price row, quiet colours, addons' lines waiting for Shift, calm tooltips in a fight.
-- TopBar.lua's coins (ns.TopCoins) at the end.

-- (the game's line callbacks: Forever's typed "Sell Price:" row is written over through these)
local linePre, linePost = {}, {}
TooltipDataProcessor.AddLinePreCall = function(kind, fn) linePre[kind] = fn end
TooltipDataProcessor.AddLinePostCall = function(kind, fn) linePost[kind] = fn end

local ns = wow.load()
local SELL = Enum.TooltipDataLineType.SellPrice

wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20, sell = 13, classID = 7, subclassID = 5 }
wow.items[745] = { name = "Marshal McBride's Documents", quality = 1, classID = 12 }

local function L(index) return _G["GameTooltipTextLeft" .. index] end
local function R(index) return _G["GameTooltipTextRight" .. index] end

local function PostCalls(tooltip, data)
	for _, call in ipairs(wow.tooltipPostCalls or {}) do
		if call[1] == "ALL" or call[1] == data.type then call[2](tooltip, data) end
	end
end

-- The game writing an item's tooltip, as Forever does: its lines, its "Sell Price:" row (opts.row), the data's
-- post-calls (Serene's among them), an addon's line after them (opts.addon), then Show.
-- opts: stack (in a bag slot), row ("typed": the game's typed row, "blank": blanked by an addon, nil: none),
-- price (the row's price), sellable (a typed "Sell Price:" line in the data: true; another type: false),
-- nolines (data with no lines: it can't say whether a merchant buys it), addon (an addon's words).
local function ItemTip(id, opts)
	opts = opts or {}
	local item = wow.items[id]
	local data = { type = Enum.TooltipDataType.Item, id = id, hyperlink = wow.link(id),
		lines = { { leftText = item.name }, { leftText = "Trade Goods" } } }
	if opts.sellable ~= nil then
		data.lines[#data.lines + 1] = { leftText = "Sell Price:", type = opts.sellable and SELL or 0 }
	end
	if opts.nolines then data.lines = nil end
	wow.bags[0] = { size = 4, [1] = { id = id, count = opts.stack or 1 } }
	-- (what the game answers while it builds a tooltip: the call that made it, and its data)
	rawset(GameTooltip, "GetProcessingTooltipInfo", function()
		return { getterName = "GetBagItem", getterArgs = { 0, 1 }, tooltipData = data }
	end)
	GameTooltip:SetOwner(opts.owner or ContainerFrame1, "ANCHOR_NONE")
	GameTooltip:AddLine(item.name, 1, 1, 1)
	GameTooltip:AddLine("Trade Goods", 1, 1, 1)
	if opts.row == "typed" then
		if linePre[SELL] then linePre[SELL](GameTooltip) end
		GameTooltip:AddLine("Sell Price:", 1, 1, 1)
		if linePost[SELL] then linePost[SELL](GameTooltip, { type = SELL, price = opts.price }) end
	elseif opts.row == "blank" then
		GameTooltip:AddLine("", 1, 1, 1)
		if linePost[SELL] then linePost[SELL](GameTooltip, { type = SELL, price = opts.price }) end
	end
	PostCalls(GameTooltip, data)
	if opts.addon then GameTooltip:AddLine(opts.addon, 0.5, 0.8, 1) end
	GameTooltip:Show()
	wow.advance(0.3)
	return data
end

local function Login(saved)
	wow.login(saved)
	wow.advance(0.5)
end

local VENDOR = ns.SOFT .. "Vendor|r"
local function Times(n) return VENDOR .. ns.MUTED .. "  ×" .. n .. "|r" end
local function White(text) return "|cffffffff" .. text .. "|r" end

test("the game's Sell Price row written over: the stack's price", function()
	Login()
	ItemTip(2589, { row = "typed", price = 65, stack = 5 })
	eq(L(3):GetText(), Times(5))
	eq(R(3):GetText(), White("65c"))
	eq(GameTooltip:NumLines(), 3, "no second price line")
	clean()
end)

test("the row with no price in its data: one's price times the stack", function()
	Login()
	ItemTip(2589, { row = "typed", stack = 7 })
	eq(L(3):GetText(), Times(7))
	eq(R(3):GetText(), White("91c"))
end)

test("one of it: 'Vendor' alone, no count", function()
	Login()
	ItemTip(2589, { row = "typed", price = 13 })
	eq(L(3):GetText(), VENDOR)
	eq(R(3):GetText(), White("13c"))
end)

test("the row blanked by another addon (VendorPricePlus): still found and written", function()
	Login()
	ItemTip(2589, { row = "blank", price = 26, stack = 2 })
	eq(L(3):GetText(), Times(2))
	eq(R(3):GetText(), White("26c"))
end)

test("no row from the game, data without lines: a line of Serene's after the game's", function()
	Login()
	ItemTip(2589, { stack = 3, nolines = true })
	eq(GameTooltip:NumLines(), 3)
	eq(L(3):GetText(), Times(3))
	eq(R(3):GetText(), White("39c"))
end)

test("the data has no Sell Price line (Forever: a merchant won't buy it): no price line", function()
	Login()
	ItemTip(2589, { sellable = false })
	eq(GameTooltip:NumLines(), 2)
	ItemTip(2589, {})
	eq(GameTooltip:NumLines(), 2)
end)

test("an item with no sell price: no price line", function()
	Login()
	ItemTip(745)
	eq(GameTooltip:NumLines(), 2)
end)

test("tipvendor off: the game's row as it was, nothing added", function()
	Login({ tipvendor = false })
	ItemTip(2589, { row = "typed", price = 65, stack = 5 })
	eq(L(3):GetText(), "Sell Price:")
	ItemTip(2589, { stack = 2 })
	eq(GameTooltip:NumLines(), 2)
end)

test("addons' lines under an item wait for Shift; the price row stays", function()
	Login()
	ItemTip(2589, { row = "typed", price = 13, addon = "Auctionator: 1g" })
	local cut = ns.TooltipCuts[GameTooltip]
	ok(cut, "the tooltip is cut")
	eq(cut.keep, 3, "the game's two lines and the price row kept")
	eq(L(1):GetAlpha(), 1)
	eq(L(3):GetAlpha(), 1)
	eq(L(4):GetText(), "Auctionator: 1g")
	eq(L(4):GetAlpha(), 0, "the addon's line unseen")
	ok(GameTooltip.sereneCue and GameTooltip.sereneCue:IsShown(), "'Shift' in the corner")
	clean()
end)

test("Shift: the addons' lines back; let go: away again", function()
	Login()
	ItemTip(2589, { row = "typed", price = 13, addon = "Auctionator: 1g" })
	wow.shift = true
	wow.advance(0.2)
	eq(L(4):GetAlpha(), 1)
	no(GameTooltip.sereneCue:IsShown(), "no cue while Shift is held")
	wow.shift = false
	wow.advance(0.2)
	eq(L(4):GetAlpha(), 0)
	clean()
end)

test("tipmore off: nothing waits", function()
	Login({ tipmore = false })
	ItemTip(2589, { row = "typed", price = 13, addon = "Auctionator: 1g" })
	eq(ns.TooltipCuts[GameTooltip], nil)
	eq(L(4):GetAlpha(), 1)
end)

test("the tooltip hidden: every line seen again for the next one", function()
	Login()
	ItemTip(2589, { row = "typed", price = 13, addon = "Auctionator: 1g" })
	GameTooltip:Hide()
	eq(ns.TooltipCuts[GameTooltip], nil)
	eq(L(4):GetAlpha(), 1)
end)

test("quiet colours: white lines warm white, the game's yellow a muted gold, the first line as it was", function()
	Login()
	GameTooltip:SetOwner(ContainerFrame1, "ANCHOR_NONE")
	GameTooltip:AddLine("Thunderfury", 1, 0.5, 0)
	GameTooltip:AddLine("Binds when picked up", 1, 1, 1)
	GameTooltip:AddLine("Use: something", 1, 0.82, 0)
	GameTooltip:AddLine("Green words", 0, 1, 0)
	GameTooltip:Show()
	ns.TooltipHushed(GameTooltip)
	eq({ L(1):GetTextColor() }, { 1, 0.5, 0, 1 })
	local r, g, b = L(2):GetTextColor()
	eq({ r, g, b }, ns.SOFT_RGB)
	r, g, b = L(3):GetTextColor()
	eq({ r, g, b }, { 0.84, 0.74, 0.48 })
	eq({ L(4):GetTextColor() }, { 0, 1, 0, 1 }, "other colours kept")
end)

test("a unit's lines: PvP and faction grey, '(Player)' dropped", function()
	Login({ tipcard = false })
	GameTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	GameTooltip:AddLine("Thrall", 1, 0.1, 0.1)
	GameTooltip:AddLine("Level 60 Orc Shaman (Player)", 1, 1, 1)
	GameTooltip:AddLine("Horde", 1, 1, 1)
	GameTooltip:AddLine("PvP", 1, 1, 1)
	GameTooltip:Show()
	ns.TooltipHushed(GameTooltip, "mouseover")
	eq(L(2):GetText(), "Level 60 Orc Shaman")
	local r, g, b = L(3):GetTextColor()
	eq({ r, g, b }, ns.MUTED_RGB)
	r, g, b = L(4):GetTextColor()
	eq({ r, g, b }, ns.MUTED_RGB)
end)

test("calm tooltips off: no colours changed", function()
	Login({ tooltip = false })
	GameTooltip:SetOwner(ContainerFrame1, "ANCHOR_NONE")
	GameTooltip:AddLine("X", 1, 1, 1)
	GameTooltip:AddLine("Binds when picked up", 1, 1, 1)
	GameTooltip:Show()
	ns.TooltipHushed(GameTooltip)
	eq({ L(2):GetTextColor() }, { 1, 1, 1, 1 })
end)

-- Coming softly, and waiting in a fight ----------------------------------------------------------------------------

local function Over(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:AddLine("Something", 1, 1, 1)
	GameTooltip:Show()
end

test("a tooltip fades in", function()
	Login()
	Over(ContainerFrame1)
	eq(GameTooltip:GetAlpha(), 0, "from nothing")
	wow.advance(0.3)
	eq(GameTooltip:GetAlpha(), 1)
	clean()
end)

test("over an action button: a moment's wait first", function()
	Login()
	Over(ActionButton1)
	eq(ns.TooltipState.action, true)
	wow.advance(0.2)
	eq(GameTooltip:GetAlpha(), 0, "still waiting")
	wow.advance(0.3)
	eq(GameTooltip:GetAlpha(), 1)
end)

test("in a fight: the world's tooltips wait", function()
	Login()
	wow.fight(true)
	Over(WorldFrame)
	wow.advance(1)
	eq(GameTooltip:GetAlpha(), 0)
	wow.fight(false)
	wow.advance(0.5)
	eq(GameTooltip:GetAlpha(), 1, "out of the fight: shown")
	clean()
end)

test("in a fight: an action button's tooltip waits too", function()
	Login()
	wow.fight(true)
	Over(ActionButton1)
	wow.advance(1)
	eq(GameTooltip:GetAlpha(), 0)
end)

test("in a fight: an enemy's tooltip shows", function()
	wow.units.mouseover = { name = "Defias Thug", enemy = true }
	Login()
	wow.fight(true)
	Over(WorldFrame)
	wow.advance(0.5)
	eq(GameTooltip:GetAlpha(), 1)
end)

test("in a fight: Shift shows the world's", function()
	Login()
	wow.fight(true)
	Over(WorldFrame)
	wow.advance(0.3)
	wow.shift = true
	wow.advance(0.3)
	eq(GameTooltip:GetAlpha(), 1)
end)

test("in a fight: the bags' tooltips show", function()
	Login()
	wow.fight(true)
	Over(ContainerFrame1)
	wow.advance(0.5)
	eq(GameTooltip:GetAlpha(), 1)
end)

test("tipcalm off: the world's tooltips show in a fight", function()
	Login({ tipcalm = false })
	wow.fight(true)
	Over(WorldFrame)
	wow.advance(0.5)
	eq(GameTooltip:GetAlpha(), 1)
end)

test("Serene's how-to lines: only with Shift, or after a moment", function()
	Login()
	local owner = CreateFrame("Button", nil, UIParent)
	ns.ShowTip(owner, function(tip)
		tip:AddLine("Serene's button")
		ns.TipHint(tip, "Click: do it")
	end)
	eq(GameTooltip:NumLines(), 1, "no how-to line at first")
	wow.advance(1.5)
	eq(GameTooltip:NumLines(), 2, "after a moment it comes")
	eq(L(2):GetText(), ns.MUTED .. "Click: do it|r")
	clean()
end)

test("Serene's how-to lines at once with Shift held", function()
	Login()
	wow.shift = true
	local owner = CreateFrame("Button", nil, UIParent)
	ns.ShowTip(owner, function(tip)
		tip:AddLine("Serene's button")
		ns.TipHint(tip, "Click: do it")
	end)
	eq(GameTooltip:NumLines(), 2)
end)

test("item comparison only with Shift: the game's setting off, given back when switched off", function()
	wow.cvars.alwaysCompareItems = "1"
	Login()
	eq(wow.cvars.alwaysCompareItems, "0")
	ns.db.tooltip = false
	ns.Refresh()
	eq(wow.cvars.alwaysCompareItems, "1")
end)

-- TopBar's coins -------------------------------------------------------------------------------------------------------

local function Coin(n, kind) return n .. "|TInterface\\MoneyFrame\\UI-" .. kind .. "Icon:0:0:1:0|t" end
local COINS = {
	{ 0, false, Coin(0, "Copper") },
	{ 5, false, Coin(5, "Copper") },
	{ 105, false, Coin(1, "Silver") .. " " .. Coin(5, "Copper") },
	{ 100, false, Coin(1, "Silver") },
	{ 10000, false, Coin(1, "Gold") .. " " .. Coin(0, "Silver") },
	{ 123456, false, Coin(12, "Gold") .. " " .. Coin(34, "Silver") .. " " .. Coin(56, "Copper") },
	{ 123456, true, Coin(12, "Gold") .. " " .. Coin(34, "Silver") },
	{ 10000, true, Coin(1, "Gold") },
	{ 105, true, Coin(1, "Silver") .. " " .. Coin(5, "Copper") },
	{ -250, false, Coin(2, "Silver") .. " " .. Coin(50, "Copper") },
	{ nil, false, Coin(0, "Copper") },
}
test("TopCoins: gold, silver and copper with their icons (short: no copper beside gold)", function()
	for _, case in ipairs(COINS) do
		eq(ns.TopCoins(case[1], case[2]), case[3], tostring(case[1]) .. (case[2] and " short" or ""))
	end
end)
