local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Serene's merchant window.                                          (/serene merchant on|off: at once, no reload)
-- * The merchant's goods in one quiet list in glass, no pages: the icon, the name in its quality's colour, a muted
--   word of what matters (how many you have, how many he has left, why you can't use it), the price on the right.
--   Beside Serene's bags, or where the game's window opens (Settings).
-- * The game's clicks: right click buys one; Shift-click: how many (with its "Stack"); Alt-click: a full stack;
--   Ctrl-click: try it on; a left click or a drag: on the cursor, to drop in the bags. An item of the bags dropped
--   on the window: sold.
-- * Over the list: a search and "usable only". In the foot: buy and buyback, the repair and the junk beside your
--   money.
-- * At every merchant (with this window or the game's): the junk sold (greys, and what you put in the bags' Junk
--   section; a grey you put in another section stays), then everything repaired (the guild's money first, if
--   chosen); one quiet line says so. Opening the merchant with Shift held: nothing done by itself.
-- The game's window stays open, out of sight: a right click in the bags still sells, its confirmations still ask
-- (tokens, items that can't be returned, an expensive item), closing either ends the visit.

local INK, SOFT, MUTED_RGB = ns.INK, ns.SOFT_RGB, ns.MUTED_RGB
local MUTED = ns.MUTED
local GOLD = { 1, 0.82, 0.35 }
local RED_TEXT = "|cffdb6b61"   -- what you can't use or can't pay: a quiet red
local WIDTH, PAD = 380, 12
local HEAD, FILTER, ROW, FOOT = 30, 26, 26, 36
local FEWEST, MOST = 6, 14      -- rows the list shows (more: the mouse wheel)
local ICON = 20
local GLASS = 0.9
local OFF_SCREEN = -10000
local HIGH_PRICE = rawget(_G, "MERCHANT_HIGH_PRICE_COST") or 1500000 -- (the game's line for an expensive purchase)
local MAX_COSTS = 3             -- tokens and items a price may ask
local SELL_DELAY = 0.15         -- seconds between two items sold, as the server expects
local MAX_SELL = 120

local function G(name) return rawget(_G, name) end

local win, scroll, child, proxy
local open = false      -- at a merchant
local leaving = false   -- the window hidden by the visit's end (not by you: nothing to close)
local kept              -- where the game's window stood before it went out of sight
local clamped           -- (and whether it was kept on the screen: never while out of it)
local page = "buy"      -- "buy" or "buyback"
local query = ""
local rows, entries = {}, {}
local reasons = {}      -- this visit: "index:id" -> why you can't use it (words), or false
local qualities = {}    -- itemID -> its colour code
local Draw              -- (below)

local Container = C_Container or {}
local Instant = (C_Item and C_Item.GetItemInfoInstant) or G("GetItemInfoInstant")

local Items = ns.Items
local IdOf, Coins = Items.IdOf, Items.Coins

local function Money() return Clean(Safe(GetMoney)) or 0 end

-- The name's colour: its quality's (common in Serene's warm white).
local function QualityCode(id)
	if not id then return ns.SOFT end
	if qualities[id] then return qualities[id] end
	local quality = C_Item and C_Item.GetItemQualityByID and Clean(Safe(C_Item.GetItemQualityByID, id))
	local color = type(quality) == "number" and quality ~= 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
	if not quality then return ns.SOFT end -- (not known yet: asked again later)
	local code = ns.SOFT
	if color and type(color.r) == "number" then
		code = ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
	end
	qualities[id] = code
	return code
end

-- How many you have: in the bags, and in the bank (as the game last saw it).
local function Owned(id)
	local count = (C_Item and C_Item.GetItemCount) or G("GetItemCount")
	if not (id and count) then return 0, 0 end
	local bags = Clean(Safe(count, id)) or 0
	local all = Clean(Safe(count, id, true)) or bags
	return bags, math.max(0, all - bags)
end

-- Reading the merchant --------------------------------------------------------------------------------------------

-- An item he sells: { index, id, link, name, icon, price, lot, available, maxStack, purchasable, usable, extended,
-- refundable, costs = { { icon, value, link, currency } }, afford } or nil.
local function Offer(index)
	local api = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	local info = api and Safe(api, index)
	local o
	if type(info) == "table" then
		o = { name = Clean(info.name), icon = Clean(info.texture), price = Clean(info.price) or 0,
			lot = Clean(info.stackCount) or 1, available = Clean(info.numAvailable),
			purchasable = Clean(info.isPurchasable) ~= false, usable = Clean(info.isUsable) ~= false,
			extended = Clean(info.hasExtendedCost) and true or false }
	else
		local name, icon, price, lot, available, purchasable, usable, extended = Safe(G("GetMerchantItemInfo"), index)
		o = { name = Clean(name), icon = Clean(icon), price = Clean(price) or 0, lot = Clean(lot) or 1,
			available = Clean(available), purchasable = Clean(purchasable) ~= false, usable = Clean(usable) ~= false,
			extended = Clean(extended) and true or false }
	end
	if not o.name then return nil end
	o.index = index
	o.lot = math.max(1, o.lot)
	o.link = Clean(Safe(G("GetMerchantItemLink"), index))
	o.id = Clean(Safe(G("GetMerchantItemID"), index)) or IdOf(o.link)
	o.maxStack = math.max(o.lot, Clean(Safe(G("GetMerchantItemMaxStack"), index)) or o.lot)
	local refundable = C_MerchantFrame and C_MerchantFrame.IsMerchantItemRefundable
	o.refundable = not refundable or Clean(Safe(refundable, index)) ~= false
	o.costs = {}
	if o.extended and (Clean(Safe(G("GetMerchantItemCostInfo"), index)) or 0) > 0 then
		for cost = 1, MAX_COSTS do
			local icon, value, link, currency = Safe(G("GetMerchantItemCostItem"), index, cost)
			icon = Clean(icon)
			if icon then
				o.costs[#o.costs + 1] = { icon = icon, value = Clean(value) or 0, link = Clean(link), currency = Clean(currency) }
			end
		end
	end
	local afford = G("CanAffordMerchantItem")
	if afford then
		o.afford = Clean(Safe(afford, index)) ~= false
	else
		o.afford = Money() >= o.price
	end
	return o
end

local function Lots(o, count) return math.max(1, math.ceil((count or o.lot) / o.lot)) end

-- What count of it costs (whole lots): its gold, and the tokens and items he asks.
local function PriceText(o, count, colored)
	if o.buyback then return Coins(o.price, colored and o.price > Money()) end
	local lots = Lots(o, count)
	local parts = {}
	if o.price > 0 then parts[#parts + 1] = Coins(o.price * lots, colored and not o.afford) end
	for _, cost in ipairs(o.costs) do
		parts[#parts + 1] = ("%d|T%s:0:0:2:0|t"):format(cost.value * lots, tostring(cost.icon))
	end
	if not parts[1] then return MUTED .. "free|r" end
	return table.concat(parts, "  ")
end

-- Why you can't use it ------------------------------------------------------------------------------------------------

-- The game's words as a pattern: "Requires Level %d" -> "^Requires Level (%d+)$".
local function Pattern(format)
	if type(format) ~= "string" then return nil end
	local escaped = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	escaped = escaped:gsub("%%d", "(%%d+)")
	escaped = escaped:gsub("%%s", "(.+)")
	return "^" .. escaped .. "$"
end

-- (the most specific first: "Requires Level 40" and "Requires Tailoring (150)" before "Requires %s")
local SHORT = {
	{ Pattern(G("ITEM_MIN_LEVEL")), function(level) return "level " .. level end },
	{ Pattern(G("ITEM_MIN_SKILL")), function(skill, rank) return skill .. " " .. rank end },
	{ Pattern(G("ITEM_REQ_REPUTATION")), function(faction, standing) return faction .. " " .. standing:lower() end },
	{ Pattern(G("ITEM_CLASSES_ALLOWED")), function(classes) return classes end },
	{ Pattern(G("ITEM_RACES_ALLOWED")), function(races) return races end },
	{ Pattern(G("ITEM_REQ_SKILL")), function(skill) return skill end },
}

local function Short(text)
	for _, rule in ipairs(SHORT) do
		if rule[1] then
			local a, b = text:match(rule[1])
			if a then return rule[2](a, b) end
		end
	end
	return text
end

local function IsRed(color)
	if type(color) ~= "table" then return false end
	local r, g, b
	if color.GetRGB then r, g, b = color:GetRGB() else r, g, b = color.r, color.g, color.b end
	r, g, b = Clean(r), Clean(g), Clean(b)
	return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.3 and b < 0.3
end

local scanner -- (no C_TooltipInfo: a hidden tooltip, read line by line)

-- The lines of the merchant's item's tooltip: { { text, red } }.
local function Lines(index)
	local list = {}
	local get = C_TooltipInfo and C_TooltipInfo.GetMerchantItem
	if get then
		local data = Safe(get, index)
		local lines = type(data) == "table" and type(data.lines) == "table" and data.lines or {}
		for _, line in ipairs(lines) do
			for _, side in ipairs({ "left", "right" }) do
				local text = Clean(line[side .. "Text"])
				if type(text) == "string" and text ~= "" then
					list[#list + 1] = { text = text, red = IsRed(line[side .. "Color"]) }
				end
			end
		end
		return list
	end
	if not scanner then scanner = CreateFrame("GameTooltip", "SereneMerchantScan", nil, "GameTooltipTemplate") end
	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	Safe(scanner.SetMerchantItem, scanner, index)
	for line = 1, Clean(Safe(scanner.NumLines, scanner)) or 0 do
		for _, side in ipairs({ "Left", "Right" }) do
			local text = _G["SereneMerchantScanText" .. side .. line]
			local words = text and text:IsShown() and Clean(text:GetText())
			if type(words) == "string" and words ~= "" then
				local r, g, b = text:GetTextColor()
				list[#list + 1] = { text = words, red = IsRed({ r = r, g = g, b = b }) }
			end
		end
	end
	scanner:Hide()
	return list
end

local KNOWN = G("ITEM_SPELL_KNOWN")
local RECIPE, MISC = 9, 15 -- (item classes whose tooltip may say "Already known", usable or not)

-- Why you can't use it, in a few words ("known", "level 40", "Tailoring 150"), or nil. Read once a visit.
local function Reason(o)
	local key = o.index .. ":" .. tostring(o.id)
	if reasons[key] ~= nil then return reasons[key] or nil end
	local blocked = not o.usable or not o.purchasable
	local class = o.id and Clean(select(6, Safe(Instant, o.id)))
	local found = false
	if blocked or class == RECIPE or class == MISC then
		local lines = Lines(o.index)
		if not lines[1] then return blocked and "can't use" or nil end -- (not read yet: again next time)
		for _, line in ipairs(lines) do
			if KNOWN and line.text == KNOWN then found = "known" break end
		end
		if not found and blocked then
			for index, line in ipairs(lines) do
				if index > 1 and line.red then found = Short(line.text) break end
			end
			found = found or "can't use"
		end
	end
	reasons[key] = found
	return found or nil
end

-- Buying ----------------------------------------------------------------------------------------------------------

-- The merchant still there, still selling this item at this place.
local function Still(o)
	return open and Clean(Safe(G("GetMerchantItemID"), o.index)) == o.id
end

-- The game's item button as its window would hand it to its confirmations: they then ask as they do there.
local function Proxy(o)
	if not proxy then
		proxy = CreateFrame("Button")
		proxy:Hide()
	end
	proxy:SetID(o.index)
	proxy.price = o.price
	proxy.extendedCost = o.extended or nil
	proxy.showNonrefundablePrompt = not o.refundable or nil
	proxy.link, proxy.name, proxy.texture, proxy.count = o.link, o.name, o.icon, o.lot
	return proxy
end

-- (no confirmation of the game's for it: Serene asks)
local function Ask(o, quantity)
	if not StaticPopupDialogs.SERENE_MERCHANT_BUY then
		StaticPopupDialogs.SERENE_MERCHANT_BUY = {
			text = "Buy %s?", button1 = G("YES") or "Yes", button2 = G("NO") or "No",
			OnAccept = function(_, data)
				if data and Still(data.o) then Safe(G("BuyMerchantItem"), data.o.index, data.quantity) end
			end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	Safe(StaticPopup_Show, "SERENE_MERCHANT_BUY", ("%d %s for %s"):format(quantity, o.name, PriceText(o, quantity)), nil,
		{ o = o, quantity = quantity })
end

-- count of it bought (whole lots), the game's way: tokens, items that can't be returned and an expensive lot
-- through its confirmations. Nothing bought when the merchant changed meanwhile.
local function Buy(o, count)
	if not (o and Still(o)) then return end
	local buy = G("BuyMerchantItem")
	local confirmExtended, confirmHigh = G("MerchantFrame_ConfirmExtendedItemCost"), G("MerchantFrame_ConfirmHighCostItem")
	local quantity = Lots(o, count) * o.lot
	local single = quantity == o.lot
	if o.extended or not o.refundable then
		if confirmExtended then return Safe(confirmExtended, Proxy(o), not single and quantity or nil) end
		return Ask(o, quantity)
	end
	if o.price * Lots(o, quantity) >= HIGH_PRICE then
		if single and confirmHigh then return Safe(confirmHigh, Proxy(o)) end
		return Ask(o, quantity)
	end
	if single then Safe(buy, o.index) else Safe(buy, o.index, quantity) end
end

-- The most of it one purchase may take: a stack, what he has left, what you can pay.
local function Most(o)
	local most = o.maxStack
	if o.available and o.available >= 0 then most = math.min(most, o.available * o.lot) end
	if o.price > 0 then most = math.min(most, math.floor(Money() / o.price) * o.lot) end
	for _, cost in ipairs(o.costs) do
		if cost.link and not cost.currency and cost.value > 0 then
			local have = Owned(IdOf(cost.link))
			most = math.min(most, math.floor(have / cost.value) * o.lot)
		end
	end
	return math.max(0, most)
end

-- Shift-click: the game's popup to choose how many (Merchant.lua adds its "Stack" to it).
local function HowMany(row, o)
	local most = Most(o)
	if most <= o.lot then return end
	row.SplitStack = function(_, split)
		split = tonumber(split)
		if split and split > 0 then Buy(o, split) end
	end
	local frame = G("StackSplitFrame")
	if frame and frame.OpenStackSplitFrame then
		frame:OpenStackSplitFrame(most, row, "BOTTOMLEFT", "TOPLEFT", o.lot)
	elseif G("OpenStackSplitFrame") then
		Safe(G("OpenStackSplitFrame"), most, row, "BOTTOMLEFT", "TOPLEFT", o.lot)
	end
end

-- An item of the bags on the cursor, dropped here: sold (a merchant's item on the cursor: put back).
local function DropSell()
	if not open then return false end
	local kind = Clean(Safe(G("GetCursorInfo")))
	if kind == "item" then
		local sell = G("SellCursorItem")
		if sell then Safe(sell) else Safe(G("PickupMerchantItem"), 0) end
		return true
	elseif kind == "merchant" then
		Safe(G("ClearCursor"))
		return true
	end
	return false
end

-- Junk and repairs --------------------------------------------------------------------------------------------------

local SlotInfo, SellPrice = Items.Slot, Items.SellPrice

-- The junk worth something, in bag order, and what it is worth. Junk is what the bags show under Junk
-- (Items.IsJunk): grey and not a quest's, or put in Junk; a grey given another section is kept.
local function FindJunk()
	local found, worth = {}, 0
	for _, bag in ipairs(Items.Bags()) do
		for slot = 1, Items.NumSlots(bag) do
			local info = #found < MAX_SELL and SlotInfo(bag, slot)
			if info and info.id and not info.noValue and not info.locked and Items.IsJunk(info) then
				local price = SellPrice(info.link)
				if price > 0 then
					found[#found + 1] = { bag = bag, slot = slot, id = info.id }
					worth = worth + price * info.count
				end
			end
		end
	end
	return found, worth
end

-- The merchant buys items (the game shows its junk button only then; without the button: the server says).
local function Buys()
	local button = G("MerchantSellAllJunkButton")
	if button then return button:IsShown() and true or false end
	return true
end

local seller = CreateFrame("Frame")
local queue, sinceSell, earned, soldCount, afterSale = {}, 0, 0, 0, nil

local function Selling() return queue[1] ~= nil or soldCount > 0 end

local function StopSelling()
	wipe(queue)
	seller:SetScript("OnUpdate", nil)
	if soldCount > 0 and earned > 0 then
		ns.Print(("sold %d junk for %s"):format(soldCount, Coins(earned)))
	end
	earned, soldCount = 0, 0
	local after = afterSale
	afterSale = nil
	if after and open then after() end
	if Draw then Draw() end
end

local function SellNext(_, elapsed)
	if not open then return StopSelling() end
	sinceSell = sinceSell + elapsed
	if sinceSell < SELL_DELAY then return end
	sinceSell = 0
	local item = table.remove(queue, 1)
	if not item then return StopSelling() end
	-- (the slot read again: the bags may have changed in between)
	local info = SlotInfo(item.bag, item.slot)
	if info and info.id == item.id and not info.locked then
		Safe(Container.UseContainerItem or G("UseContainerItem"), item.bag, item.slot)
		earned = earned + SellPrice(info.link) * info.count
		soldCount = soldCount + info.count
	end
	if not queue[1] then
		-- (the last sale's money needs a moment)
		seller:SetScript("OnUpdate", nil)
		C_Timer.After(0.5, function() if not queue[1] then StopSelling() end end)
	end
end

-- items ({ bag, slot, id }) sold one by one; after() once they are.
local function Sell(items, after)
	if not (open and Buys()) or InCombatLockdown() or not items[1] then
		if after then after() end
		return
	end
	for _, item in ipairs(items) do queue[#queue + 1] = item end
	afterSale = after
	sinceSell = SELL_DELAY
	seller:SetScript("OnUpdate", SellNext)
	if Draw then Draw() end
end

local function RepairCost()
	if not Clean(Safe(G("CanMerchantRepair"))) then return nil end
	local cost, can = Safe(G("GetRepairAllCost"))
	cost = Clean(cost)
	return type(cost) == "number" and cost > 0 and Clean(can) and cost or nil
end

local function RepairWithGold(cost)
	if Money() < cost then return ns.Print(("not enough money to repair (%s)"):format(Coins(cost))) end
	Safe(G("RepairAllItems"), false)
	ns.Print(("repaired for %s"):format(Coins(cost)))
end

-- The guild's repair asked: judged when the server has answered (1.5 s), what is left paid with your gold.
local guildAsked
local function JudgeGuild()
	local cost = guildAsked
	guildAsked = nil
	if not (cost and open) then return end
	local left = RepairCost()
	if not left then return ns.Print(("repaired for %s (the guild's money)"):format(Coins(cost))) end
	RepairWithGold(left)
end

local function Repair()
	local cost = RepairCost()
	if not cost or guildAsked then return end
	if ns.On("repairGuild") and Clean(Safe(G("CanGuildBankRepair"))) then
		-- (-1: no limit)
		local allowance = Clean(Safe(G("GetGuildBankWithdrawMoney"))) or 0
		if allowance == -1 or allowance >= cost then
			guildAsked = cost
			Safe(G("RepairAllItems"), true)
			C_Timer.After(1.5, JudgeGuild)
			return
		end
	end
	RepairWithGold(cost)
end

-- A visit begins: the junk sold, then (with its gold) the repair.
local function Arrive()
	if not open or IsShiftKeyDown() then return end
	local function Repaired() if ns.On("autoRepair") then Repair() end end
	if ns.On("sellJunk") then
		local junk = FindJunk()
		if junk[1] then return Sell(junk, Repaired) end
	end
	Repaired()
end

-- The window -----------------------------------------------------------------------------------------------------------

local function Text(parent, font, color)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH("LEFT")
	if color then text:SetTextColor(color[1], color[2], color[3]) end
	return text
end

-- A word in the header or foot: muted (gold when on), white under the mouse, a tooltip with what a click does.
local function Word(text, onClick, tip)
	local word = CreateFrame("Button", nil, win)
	word:SetHeight(18)
	word:RegisterForClicks("AnyUp")
	word.text = Text(word, "GameFontHighlightSmall", MUTED_RGB)
	word.text:SetPoint("CENTER")
	function word:SetWords(words)
		self.text:SetText(words)
		self:SetWidth(math.ceil(Clean(Safe(self.text.GetStringWidth, self.text)) or 30) + 6)
	end
	function word:Paint()
		local color = self.on and GOLD or MUTED_RGB
		self.text:SetTextColor(color[1], color[2], color[3])
	end
	word:SetWords(text)
	word:SetScript("OnClick", function(self, button) onClick(self, button) end)
	word:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 1, 1)
		if tip and ns.ShowTip then ns.ShowTip(self, tip, "ANCHOR_TOP") end
	end)
	word:SetScript("OnLeave", function(self)
		self:Paint()
		if ns.HideTip then ns.HideTip() end
	end)
	return word
end

local function HideTooltip()
	local hide = G("GameTooltip_Hide")
	if hide then Safe(hide) else GameTooltip:Hide() end
end

local function OnRowEnter(row)
	row.light:Show()
	local e = row.entry
	if not e then return end
	GameTooltip:SetOwner(row, ns.db.merchantAt == "game" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
	if e.buyback then
		Safe(GameTooltip.SetBuybackItem, GameTooltip, e.index)
	else
		Safe(GameTooltip.SetMerchantItem, GameTooltip, e.index)
		Safe(G("GameTooltip_ShowCompareItem"), GameTooltip)
	end
	GameTooltip:Show()
end

local function OnRowLeave(row)
	row.light:Hide()
	HideTooltip()
end

local function OnRowClick(row, button)
	local e = row.entry
	if not e or DropSell() then return end
	if e.buyback then return Safe(G("BuybackItem"), e.index) end
	if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
		if ns.MerchantBuyStack then ns.MerchantBuyStack(e.index) end
		return
	end
	-- (the game's modified clicks: a link in the chat, trying it on; then how many)
	if e.link and IsModifiedClick() and Safe(G("HandleModifiedItemClick"), e.link) then return end
	if IsModifiedClick("SPLITSTACK") then return HowMany(row, e) end
	if button == "RightButton" or e.extended or not e.refundable then return Buy(e) end
	Safe(G("PickupMerchantItem"), e.index)
end

local function Row(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, child)
	row:SetHeight(ROW)
	row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW)
	row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:RegisterForDrag("LeftButton")
	row.sereneMerchantRow = true -- (Merchant.lua: its "Stack" in the popup for these too)
	row.light = row:CreateTexture(nil, "BACKGROUND")
	row.light:SetAllPoints()
	row.light:SetColorTexture(SOFT[1], SOFT[2], SOFT[3], 0.06)
	row.light:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -2)
	row.count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	row.price = Text(row, "GameFontHighlightSmall", SOFT)
	row.price:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.price:SetJustifyH("RIGHT")
	row.meta = Text(row, "GameFontHighlightSmall", MUTED_RGB)
	row.meta:SetPoint("RIGHT", row.price, "LEFT", -10, 0)
	row.meta:SetJustifyH("RIGHT")
	row.name = Text(row, "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", OnRowLeave)
	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnDragStart", function(self)
		local e = self.entry
		if e and not e.buyback and not e.extended and e.refundable then Safe(G("PickupMerchantItem"), e.index) end
	end)
	row:SetScript("OnReceiveDrag", DropSell)
	rows[index] = row
	return row
end

-- The muted words beside the name: why you can't use it (quiet red), or how many he has left and you have.
local function Meta(e)
	if e.reason then return RED_TEXT .. e.reason .. "|r" end
	local words = {}
	-- (a reagent of a spell on your bars that you are running low on, Reagents.lua)
	local left = not e.buyback and ns.ReagentLow and ns.ReagentLow(e.name)
	if left then words[#words + 1] = ("|cfffa9e4crunning low · %d|r"):format(left) end
	if not e.buyback and type(e.available) == "number" and e.available >= 0 then
		words[#words + 1] = e.available == 0 and "sold out" or (e.available .. " left")
	end
	if ns.On("merchantCounts") and e.id then
		local bags, bank = Owned(e.id)
		if bags > 0 then words[#words + 1] = "have " .. bags end
		if bank > 0 then words[#words + 1] = "bank " .. bank end
	end
	return table.concat(words, "  ·  ")
end

local function Fill(row, e)
	row.entry = e
	row:SetID(e.index)
	row.icon:SetTexture(e.icon)
	row.count:SetText(e.lot > 1 and e.lot or "")
	local dim = e.reason ~= nil or e.available == 0
	row.icon:SetDesaturated(dim)
	row.icon:SetAlpha(dim and 0.5 or 1)
	row.name:SetText(QualityCode(e.id) .. e.name .. "|r")
	row.name:SetAlpha(dim and 0.55 or 1)
	row.meta:SetText(Meta(e))
	row.price:SetText(PriceText(e, e.lot, true))
	row:Show()
end

-- What the list shows: the goods (searched, usable only) or what you sold him.
local function Gather()
	wipe(entries)
	local find = strtrim(query or ""):lower()
	local usableOnly = ns.On("merchantSearch") and ns.On("merchantUsable")
	if page == "buyback" then
		for index = 1, Clean(Safe(G("GetNumBuybackItems"))) or 0 do
			local name, icon, price, count = Safe(G("GetBuybackItemInfo"), index)
			name = Clean(name)
			if name and (find == "" or name:lower():find(find, 1, true)) then
				local link = Clean(Safe(G("GetBuybackItemLink"), index))
				entries[#entries + 1] = { buyback = true, index = index, name = name, icon = Clean(icon),
					price = Clean(price) or 0, lot = Clean(count) or 1, link = link, id = IdOf(link), costs = {} }
			end
		end
		return
	end
	for index = 1, Clean(Safe(G("GetMerchantNumItems"))) or 0 do
		local o = Offer(index)
		if o and (find == "" or o.name:lower():find(find, 1, true)) then
			o.reason = Reason(o)
			if not (usableOnly and o.reason) then entries[#entries + 1] = o end
		end
	end
end

-- (the list longer than its room: a thin gold line tells where)
local function Thumb()
	local most = math.max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0))
	local seen = scroll:GetHeight() or 0
	if most <= 0 or seen <= 0 then return win.thumb:Hide() end
	local length = math.max(24, seen * seen / (most + seen))
	local at = (seen - length) * (scroll:GetVerticalScroll() / most)
	win.thumb:ClearAllPoints()
	win.thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 3, -at)
	win.thumb:SetHeight(length)
	win.thumb:Show()
end

local function ScrollTop()
	if scroll then scroll:SetVerticalScroll(0) end
end

-- The foot: buy and buyback, then from the right your money, the repair, the junk.
local function Foot()
	local buyback = Clean(Safe(G("GetNumBuybackItems"))) or 0
	win.buyTab.on, win.backTab.on = page == "buy", page == "buyback"
	win.backTab:SetWords(buyback > 0 and ("buyback " .. buyback) or "buyback")
	win.buyTab:Paint()
	win.backTab:Paint()
	win.money:SetText(Coins(Money()))
	local cost = RepairCost()
	win.repair.cost = cost
	win.repair:SetShown(cost ~= nil and not guildAsked)
	if cost then win.repair:SetWords("repair " .. Coins(cost, Money() < cost)) end
	local junk, worth = FindJunk()
	win.junk.items = junk
	win.junk:SetShown(junk[1] ~= nil and not Selling() and Buys())
	if junk[1] then win.junk:SetWords("junk " .. Coins(worth)) end
	local previous = win.money
	for _, word in ipairs({ win.repair, win.junk }) do
		if word:IsShown() then
			word:ClearAllPoints()
			word:SetPoint("RIGHT", previous, "LEFT", -8, 0)
			previous = word
		end
	end
	win.title:SetText(Clean(Safe(UnitName, "npc")) or "Merchant")
end

-- Its size: as many rows as his goods (at least FEWEST, at most MOST), the same whatever the search.
local function Layout()
	local searching = ns.On("merchantSearch")
	win.search:SetShown(searching)
	win.usable:SetShown(searching)
	local top = HEAD + (searching and FILTER or 0)
	local goods = Clean(Safe(G("GetMerchantNumItems"))) or 0
	local lines = math.max(FEWEST, math.min(MOST, goods))
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -top)
	scroll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -6, -top)
	scroll:SetHeight(lines * ROW)
	win:SetHeight(top + lines * ROW + 4 + FOOT)
	win.usable.on = ns.On("merchantUsable")
	win.usable:Paint()
end

Draw = function()
	if not (win and win:IsShown()) then return end
	Layout()
	Gather()
	for index, e in ipairs(entries) do Fill(Row(index), e) end
	for index = #entries + 1, #rows do
		rows[index].entry = nil
		rows[index]:Hide()
	end
	child:SetHeight(math.max(1, #entries * ROW))
	local most = math.max(0, child:GetHeight() - (scroll:GetHeight() or 0))
	if scroll:GetVerticalScroll() > most then scroll:SetVerticalScroll(most) end
	if entries[1] then
		win.empty:Hide()
	else
		win.empty:SetText(query ~= "" and "Nothing matches" or page == "buyback" and "Nothing to buy back"
			or (ns.On("merchantSearch") and ns.On("merchantUsable")) and "Nothing you can use" or "Nothing for sale")
		win.empty:Show()
	end
	Foot()
	Thumb()
end

-- Beside Serene's bags (their foot level with its; the bank already beside them: beside the bank), or where the
-- game's window opens.
local function Place()
	win:ClearAllPoints()
	local bags = G("SereneBags")
	if ns.db.merchantAt ~= "game" and bags then
		local bank = G("SereneBank")
		local beside = bank and bank:IsShown() and ns.AnchoredTo(bank, bags) and bank or bags
		win:SetPoint("BOTTOMRIGHT", beside, "BOTTOMLEFT", -10, 0)
	else
		win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
end

local function ShowPage(name)
	page = name
	ScrollTop()
	Draw()
end

local function MakeWindow()
	win = CreateFrame("Frame", "SereneMerchant", UIParent)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetSize(WIDTH, 300)
	win:Hide()

	local ground = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS)
	local rule = win:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)

	-- the header: whose goods; a quiet cross
	win.close = Word("×", function() win:Hide() end)
	win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD + 3, -7)
	win.title = Text(win, "GameFontNormal")
	win.title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -9)
	win.title:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
	win.title:SetWordWrap(false)

	-- the search, and "usable only"
	win.usable = Word("usable only", function()
		ns.db.merchantUsable = not ns.db.merchantUsable
		ScrollTop()
		Draw()
	end, function(tooltip)
		tooltip:AddLine("Usable only", SOFT[1], SOFT[2], SOFT[3])
		tooltip:AddLine(MUTED .. "Hides what you can't use: known recipes, too high a level, another class...|r", nil, nil, nil, true)
	end)
	win.usable:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD + 3, -HEAD - 2)
	local search = CreateFrame("EditBox", nil, win)
	search:SetAutoFocus(false)
	search:SetFontObject("GameFontHighlightSmall")
	search:SetHeight(18)
	search:SetMaxLetters(40)
	search:SetTextInsets(6, 6, 0, 0)
	search:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -HEAD - 2)
	search:SetPoint("RIGHT", win.usable, "LEFT", -8, 0)
	local field = search:CreateTexture(nil, "BACKGROUND")
	field:SetAllPoints()
	field:SetColorTexture(1, 1, 1, 0.06)
	search.hint = Text(search, "GameFontHighlightSmall", MUTED_RGB)
	search.hint:SetPoint("LEFT", search, "LEFT", 6, 0)
	search.hint:SetText("Search...")
	search:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "")
		if text == query then return end
		query = text
		ScrollTop()
		Draw()
	end)
	search:SetScript("OnEscapePressed", function(self)
		if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
	end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	win.search = search

	-- the list
	scroll = CreateFrame("ScrollFrame", nil, win)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 12, 1)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, child:GetHeight() - (self:GetHeight() or 0))
		self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * ROW * 3)))
		Thumb()
	end)
	win.thumb = win:CreateTexture(nil, "OVERLAY")
	win.thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	win.thumb:SetWidth(2)
	win.thumb:Hide()
	win.empty = Text(win, "GameFontHighlightSmall", MUTED_RGB)
	win.empty:SetPoint("TOP", scroll, "TOP", 0, -24)

	-- the foot: a hairline, buy and buyback, your money, the repair, the junk
	local line = win:CreateTexture(nil, "BORDER")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, FOOT - 2)
	line:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, FOOT - 2)
	line:SetColorTexture(1, 1, 1, 0.06)
	win.buyTab = Word("buy", function() ShowPage("buy") end)
	win.buyTab:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD - 3, 9)
	win.backTab = Word("buyback", function() ShowPage("buyback") end, function(tooltip)
		tooltip:AddLine("Buy back", SOFT[1], SOFT[2], SOFT[3])
		tooltip:AddLine(MUTED .. "What you sold him, for what he paid|r", nil, nil, nil, true)
	end)
	win.backTab:SetPoint("LEFT", win.buyTab, "RIGHT", 4, 0)
	win.money = Text(win, "GameFontHighlightSmall", SOFT)
	win.money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 13)
	win.repair = Word("", function() Repair() C_Timer.After(0.5, Draw) end, function(tooltip)
		tooltip:AddLine("Repair everything", SOFT[1], SOFT[2], SOFT[3])
		if ns.On("repairGuild") and Clean(Safe(G("CanGuildBankRepair"))) then
			tooltip:AddLine(MUTED .. "With the guild's money, if it allows|r", nil, nil, nil, true)
		end
	end)
	win.junk = Word("", function(self) Sell(self.items or {}) end, function(tooltip)
		tooltip:AddLine("Sell the junk", SOFT[1], SOFT[2], SOFT[3])
		tooltip:AddLine(MUTED .. "Greys, and what you put in the bags' Junk section|r", nil, nil, nil, true)
	end)

	-- an item of the bags dropped on the window: sold
	win:SetScript("OnReceiveDrag", DropSell)
	win:SetScript("OnMouseUp", DropSell)
	win:SetScript("OnShow", function() Place() Draw() end)
	-- (closed by you, its cross or Escape: the visit ends, as with the game's window)
	win:SetScript("OnHide", function()
		HideTooltip()
		local split = G("StackSplitFrame")
		local owner = split and (split.owner or split.Owner)
		if type(owner) == "table" and owner.sereneMerchantRow then split:Hide() end
		search:ClearFocus()
		if ns.PlaceBank then ns.PlaceBank() end -- (the bank beside this window: beside the bags again)
		if not leaving and open then Safe(G("CloseMerchant")) end
	end)
	tinsert(UISpecialFrames, "SereneMerchant")
end

-- The game's window, out of sight -----------------------------------------------------------------------------------

local function Wanted() return ns.On("merchant") end

-- The game's window out of sight (still open: the game's clicks on the bags, its confirmations), or back.
local function Aside(away)
	local frame = G("MerchantFrame")
	if not frame then return end
	if away then
		local _, _, _, x = frame:GetPoint(1)
		if x ~= OFF_SCREEN then
			kept = {}
			for index = 1, frame:GetNumPoints() do kept[index] = { frame:GetPoint(index) } end
		end
		if frame.IsClampedToScreen and frame:IsClampedToScreen() then
			clamped = true
			frame:SetClampedToScreen(false)
		end
		frame:SetAlpha(0)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFF_SCREEN, 0)
	elseif kept then
		frame:SetAlpha(1)
		frame:ClearAllPoints()
		for _, point in ipairs(kept) do frame:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
		kept = nil
		if clamped then frame:SetClampedToScreen(true) end
		clamped = nil
	end
end

local function HideWindow()
	if not (win and win:IsShown()) then return end
	leaving = true
	win:Hide()
	leaving = false
end

local function Visit(on)
	open = on
	if on then
		wipe(reasons)
		page, query = "buy", ""
		if win then win.search:SetText("") end
		ScrollTop()
		if Wanted() then
			Aside(true)
			-- (the game's window may come a moment after the event)
			C_Timer.After(0, function() if open and Wanted() then Aside(true) end end)
			if not win then MakeWindow() end
			if win:IsShown() then Draw() else win:Show() end
		end
		-- (after the game's window has shown: its junk button tells whether he buys)
		C_Timer.After(0, Arrive)
	else
		HideWindow()
	end
end

-- Events -------------------------------------------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
	self:Hide()
	Draw()
end)

local function Soon()
	if win and win:IsShown() then ticker:Show() end
end

local function OnEvent(_, event, kind)
	if event == "MERCHANT_SHOW" then
		if not open then Visit(true) end
	elseif event == "MERCHANT_CLOSED" then
		if open then Visit(false) end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local merchant = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant
		if open and merchant and kind == merchant then Visit(false) end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		wipe(qualities)
		Soon()
	elseif open then
		Soon()
	end
end

local function Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE",
		"PLAYER_MONEY", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "GUILDBANK_UPDATE_MONEY",
		"GET_ITEM_INFO_RECEIVED", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", OnEvent)
	local frame = G("MerchantFrame")
	if frame then
		-- (out of sight before its first frame is drawn, and each time the game places its windows again)
		frame:HookScript("OnShow", function() Aside(Wanted()) end)
		if G("UpdateUIPanelPositions") then
			hooksecurefunc("UpdateUIPanelPositions", function() if open and Wanted() then Aside(true) end end)
		end
		-- (the game's window put away by itself: the visit ends with it)
		frame:HookScript("OnHide", function()
			C_Timer.After(0, function() if open and not frame:IsShown() then Visit(false) end end)
		end)
	end
	-- (another addon's merchant window too: two windows)
	if not ns.db.merchantNoted then
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or G("IsAddOnLoaded")
		if loaded and Clean(Safe(loaded, "Wanderer")) then
			ns.Print("merchants: Wanderer has a merchant window of its own: switch one of them off.")
		end
		ns.db.merchantNoted = true
	end
end

-- (switched in the settings, even at a merchant: the window chosen now is the one shown)
local function OnRefresh()
	if not Wanted() then
		Aside(false)
		HideWindow()
	elseif open then
		Aside(true)
		if not win then MakeWindow() end
		if not win:IsShown() then win:Show() end
	end
	if win and win:IsShown() then
		Place()
		Draw()
	end
end

ns.MerchantFindJunk = FindJunk -- (tests)

-- (the bank beside the bags, opened or closed: this window beside it, or beside the bags again)
function ns.PlaceMerchant()
	if win and win:IsShown() then Place() end
end

table.insert(ns.modules, { init = Init, refresh = OnRefresh })
