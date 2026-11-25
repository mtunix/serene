local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- A full stack at a merchant:
-- * the popup to choose how many (shift-click an item) gets a third button, "Stack": one full stack bought; with
--   Serene's merchant window on, the popup itself is in glass (wherever it opens: the bags' split too);
-- * Alt-click an item: a full stack bought at once (its tooltip says how many, for how much).
-- A stack is the item's own (20 fish, 200 arrows...), fewer if you can't pay for all or the merchant has fewer.
-- Not for items paid with tokens or other items (the game's own confirmation stays for those).

local MUTED = ns.MUTED
local GOLD_TEXT = ns.GOLD_TEXT

-- The merchant's item at this index: price, lot size, supply, purchasable, paid in tokens or items.
local function ItemInfo(index)
	local api = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	if api then
		local info = Safe(api, index)
		if type(info) == "table" then
			return info.price, info.stackCount, info.numAvailable, info.isPurchasable, info.hasExtendedCost
		end
	end
	local _, _, price, bundle, available, purchasable, _, extended = Safe(GetMerchantItemInfo, index)
	return price, bundle, available, purchasable, extended
end

local function StackSize(link)
	local id = ns.Items.IdOf(link)
	if id and C_Item and C_Item.GetItemMaxStackSizeByID then
		local size = Clean(Safe(C_Item.GetItemMaxStackSizeByID, id))
		if type(size) == "number" then return size end
	end
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	return Clean(select(8, Safe(get, link))) -- (the 8th value: its max stack)
end

-- What a full stack of the merchant's item at this index would be: how many, at what cost (nil: none, and why).
local function Plan(index)
	local price, bundle, available, purchasable, extended = ItemInfo(index)
	price, bundle, available = Clean(price), Clean(bundle) or 1, Clean(available)
	if Clean(extended) or Clean(purchasable) == false or type(price) ~= "number" then return nil end
	local link = Clean(Safe(GetMerchantItemLink, index))
	local stack = type(link) == "string" and StackSize(link)
	if type(stack) ~= "number" or stack <= 1 then return nil end
	bundle = math.max(1, bundle)
	local count = stack
	local short
	-- (what you can pay for)
	if price > 0 then
		local each = price / bundle
		local money = Clean(Safe(GetMoney)) or 0
		local afford = math.floor(money / each + 1e-6) -- (a hair over: a division's rounding never costs one)
		if afford < count then count, short = afford, "money" end
	end
	-- (what the merchant has: a limited supply counts bundles; -1 is no limit)
	if type(available) == "number" and available >= 0 and available * bundle < count then
		count, short = available * bundle, "supply"
	end
	count = math.floor(count / bundle) * bundle
	if count <= 0 then return nil, short end
	return { count = count, stack = stack, bundle = bundle, cost = math.ceil(price / bundle * count), short = short }
end

local Money = ns.Items.Coins

local HIGH_PRICE = rawget(_G, "MERCHANT_HIGH_PRICE_COST") or 1500000 -- (the game's line for an expensive purchase)

local function Purchase(index, plan)
	-- (the merchant sells at most so many at once: bought in parts)
	local most = Clean(Safe(GetMerchantItemMaxStack, index)) or plan.count
	most = math.max(plan.bundle, math.floor(most / plan.bundle) * plan.bundle)
	local left = plan.count
	while left > 0 do
		local now = math.min(left, most)
		Safe(BuyMerchantItem, index, now)
		left = left - now
	end
	if plan.short then
		ns.Print(("%d bought (%s)"):format(plan.count,
			plan.short == "money" and "all you can pay for" or "all the merchant has"))
	end
end

local function ItemID(index)
	return Clean(Safe(GetMerchantItemID, index))
end

-- An expensive stack asked first, as the game asks for an expensive purchase (and Serene's window does); bought
-- only if the merchant still offers the same item at that place, planned again then (money, supply may have changed).
local function Confirm(index, plan)
	if not StaticPopupDialogs.SERENE_MERCHANT_STACK then
		StaticPopupDialogs.SERENE_MERCHANT_STACK = {
			text = "Buy %s?", button1 = rawget(_G, "YES") or "Yes", button2 = rawget(_G, "NO") or "No",
			OnAccept = function(_, data)
				if not data or not ns.On("vendor") or (data.id and ItemID(data.index) ~= data.id) then return end
				local again = Plan(data.index)
				if again then Purchase(data.index, again) end
			end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	local link = Clean(Safe(GetMerchantItemLink, index)) or "it"
	Safe(StaticPopup_Show, "SERENE_MERCHANT_STACK", ("%d %s for %s"):format(plan.count, link, Money(plan.cost)), nil,
		{ index = index, id = ItemID(index) })
end

local function Buy(index)
	if not ns.On("vendor") then return end
	local plan, why = Plan(index)
	if not plan then
		if why == "money" then ns.Print("not enough money for one more") end
		return
	end
	if plan.cost >= HIGH_PRICE then return Confirm(index, plan) end
	Purchase(index, plan)
end

-- The popup: Serene's look, and its third button -------------------------------------------------------------------
-- With Serene's merchant window on, the game's popup is dressed in glass: no art, a hairline of the game's gold, the
-- number on a faint field between its two arrows, the buttons flat words (Okay in gold). The game's frame and its
-- own buttons, only restyled; with it off, all of it as the game had it.

local SPLIT_W, SPLIT_H = 172, 72
local SPLIT_PAD, SPLIT_BUTTON = 10, 20

local stackButton
local saved = {}   -- region -> how the game had it: { points, width, height }
local moved = {}   -- regions placed by Serene now
local low          -- how high the game puts its buttons (measured once, before anything moved)
local dressed = false
local art          -- the game's textures in the popup -> their alpha
local mine = {}    -- Serene's own pieces
local plates = {}  -- button -> its flat plate
local fonts = {}   -- button -> the game's font objects
local quietFont

local function Split() return _G.StackSplitFrame end

local function Owner()
	local frame = Split()
	local owner = frame and (frame.owner or frame.Owner) -- (either key, as the client's popup names it)
	if type(owner) ~= "table" or not owner.GetName then return nil end
	if owner.sereneMerchantRow then return owner end -- (a row of Serene's merchant window, Vendor.lua)
	local name = owner:GetName() or ""
	if not name:match("^MerchantItem%d+ItemButton$") then return nil end
	return owner
end

-- (the popup's parts: by their old global names, or by the newer template's keys)
local function GameButtons()
	local frame = Split()
	return _G.StackSplitOkayButton or (frame and frame.OkayButton), _G.StackSplitCancelButton or (frame and frame.CancelButton)
end

local function Arrows()
	local frame = Split()
	return _G.StackSplitLeftButton or (frame and frame.LeftButton), _G.StackSplitRightButton or (frame and frame.RightButton)
end

local function Number()
	local frame = Split()
	return _G.StackSplitText or (frame and frame.StackSplitText)
end

-- Placing: the game's way remembered the first time, given back when Serene lets go.
local function Hold(region)
	if not saved[region] then
		local points = {}
		for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
		saved[region] = { points = points, width = region:GetWidth(), height = region:GetHeight() }
	end
	moved[region] = true
	region:ClearAllPoints()
end

local function LetGo()
	for region in pairs(moved) do
		local was = saved[region]
		if #was.points > 0 then
			region:ClearAllPoints()
			for _, point in ipairs(was.points) do region:SetPoint(unpack(point)) end
		end
		region:SetSize(was.width, was.height)
	end
	moved = {}
end

-- The game's textures of a frame (its own, not Serene's): the art to hide.
local function GameArt(frame, into)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" and not mine[region] then
			into[region] = region:GetAlpha()
		end
	end
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local texture = frame[key] and frame[key](frame)
		if texture and not mine[texture] then into[texture] = texture:GetAlpha() end
	end
end

local function Mine(region) mine[region] = true return region end

local function PaintButton(button)
	local plate = plates[button]
	if not plate then return end
	local over = button:IsMouseOver() and button:IsEnabled()
	plate:SetColorTexture(1, 1, 1, over and 0.12 or 0.06)
end

local function PaintArrow(arrow)
	local over = dressed and arrow:IsMouseOver() and arrow:IsEnabled()
	local alpha = not dressed and 1 or (not arrow:IsEnabled() and 0.25) or (over and 1) or 0.6
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
		local texture = arrow[key] and arrow[key](arrow)
		if texture then texture:SetAlpha(alpha) end
	end
end

-- A red button of the game, flat: its art away, a faint plate, its word quiet (or gold).
local function FlatButton(button, gold)
	if plates[button] then return end
	GameArt(button, art)
	local plate = Mine(button:CreateTexture(nil, "BACKGROUND", nil, -7))
	plate:SetAllPoints()
	plates[button] = plate
	fonts[button] = { button:GetNormalFontObject(), button:GetHighlightFontObject(), button:GetDisabledFontObject(), gold = gold }
	button:HookScript("OnEnter", PaintButton)
	button:HookScript("OnLeave", PaintButton)
end

local function Pieces()
	local frame = Split()
	if mine.ready then return end
	art = {}
	GameArt(frame, art)
	if frame.NineSlice then art[frame.NineSlice] = frame.NineSlice:GetAlpha() end
	local okay, cancel = GameButtons()
	FlatButton(okay, true)
	FlatButton(cancel)
	if stackButton then FlatButton(stackButton) end
	for _, arrow in ipairs({ Arrows() }) do
		if arrow then
			local highlight = arrow.GetHighlightTexture and arrow:GetHighlightTexture()
			if highlight then art[highlight] = highlight:GetAlpha() end
			arrow:HookScript("OnEnter", PaintArrow)
			arrow:HookScript("OnLeave", PaintArrow)
			-- (the game greys an arrow at either end of the count)
			if arrow.Enable then hooksecurefunc(arrow, "Enable", PaintArrow) end
			if arrow.Disable then hooksecurefunc(arrow, "Disable", PaintArrow) end
			if arrow.SetEnabled then hooksecurefunc(arrow, "SetEnabled", PaintArrow) end
		end
	end
	quietFont = CreateFont("SereneSplitQuiet")
	quietFont:CopyFontObject(GameFontHighlightSmall)
	quietFont:SetTextColor(ns.MUTED_RGB[1], ns.MUTED_RGB[2], ns.MUTED_RGB[3])
	local glass = Mine(frame:CreateTexture(nil, "BACKGROUND", nil, -8))
	glass:SetAllPoints()
	glass:SetColorTexture(ns.INK[1], ns.INK[2], ns.INK[3], 0.92)
	mine.glass = glass
	mine.lines = ns.Hairline(frame)
	for _, line in pairs({ mine.lines.top, mine.lines.bottom, mine.lines.left, mine.lines.right }) do Mine(line) end
	local field = Mine(frame:CreateTexture(nil, "BORDER"))
	field:SetColorTexture(1, 1, 1, 0.06)
	mine.field = field
	local number = Number()
	if number then mine.color = { number:GetTextColor() } mine.justify = number:GetJustifyH() end
	mine.ready = true
end

local function ShowMine(on)
	for _, key in ipairs({ "glass", "field" }) do mine[key]:SetShown(on) end
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do mine.lines[side]:SetShown(on) end
	for region, alpha in pairs(art) do region:SetAlpha(on and 0 or alpha) end
	for button, plate in pairs(plates) do
		plate:SetShown(on)
		local was = fonts[button]
		if on then
			button:SetNormalFontObject(was.gold and GameFontNormalSmall or quietFont)
			button:SetHighlightFontObject(GameFontHighlightSmall)
			button:SetDisabledFontObject(GameFontDisableSmall)
			PaintButton(button)
		else
			if was[1] then button:SetNormalFontObject(was[1]) end
			if was[2] then button:SetHighlightFontObject(was[2]) end
			if was[3] then button:SetDisabledFontObject(was[3]) end
		end
	end
	local number = Number()
	if number then
		local color = on and ns.SOFT_RGB or mine.color
		if color then number:SetTextColor(color[1], color[2], color[3]) end
		number:SetJustifyH(on and "CENTER" or mine.justify or "RIGHT")
	end
	for _, arrow in ipairs({ Arrows() }) do if arrow then PaintArrow(arrow) end end
end

-- Serene's layout: the number on its field between the arrows, the buttons in a row under it.
local function LayoutSerene(buttons)
	local frame = Split()
	-- (its size only: where it opens is the game's, at the item clicked)
	if not mine.size then mine.size = { frame:GetWidth(), frame:GetHeight() } end
	frame:SetSize(SPLIT_W, SPLIT_H)
	mine.field:ClearAllPoints()
	-- (34: the padding, an arrow and its gap on each side)
	mine.field:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, -SPLIT_PAD)
	mine.field:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -SPLIT_PAD)
	mine.field:SetHeight(24)
	local number = Number()
	if number then
		Hold(number)
		number:SetPoint("LEFT", mine.field, "LEFT", 6, 0)
		number:SetPoint("RIGHT", mine.field, "RIGHT", -6, 0)
		number:SetHeight(24)
	end
	local left, right = Arrows()
	if left then Hold(left) left:SetPoint("RIGHT", mine.field, "LEFT", -4, 0) left:SetSize(16, 16) end
	if right then Hold(right) right:SetPoint("LEFT", mine.field, "RIGHT", 4, 0) right:SetSize(16, 16) end
	local width = math.floor((SPLIT_W - SPLIT_PAD * 2 - 4 * (#buttons - 1)) / #buttons)
	for index, button in ipairs(buttons) do
		Hold(button)
		button:SetSize(width, SPLIT_BUTTON)
		if index == 1 then
			button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SPLIT_PAD, SPLIT_PAD)
		else
			button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 4, 0)
		end
	end
	mine.lines:Fit()
end

-- The game's look with three buttons: the same red buttons, a little narrower, side by side.
local function LayoutGame(buttons)
	local frame = Split()
	local width = math.floor(((frame:GetWidth() or 172) - 24 - 8) / 3) -- (12 at each side, 4 between)
	for index, button in ipairs(buttons) do
		Hold(button)
		button:SetWidth(width)
		if index == 1 then
			button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, low or 12)
		else
			button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 4, 0)
		end
	end
end

local function Dress(three)
	local frame = Split()
	local okay, cancel = GameButtons()
	if not (frame and okay and cancel) then return false end
	-- (the game's height for its buttons: measured before anything moves)
	if not low and okay:GetBottom() and frame:GetBottom() then
		low = math.floor(okay:GetBottom() - frame:GetBottom() + 0.5)
	end
	-- (every opening starts again from the game's own layout)
	LetGo()
	local buttons = three and { okay, stackButton, cancel } or { okay, cancel }
	local on = ns.On("merchant")
	if on then
		Pieces()
		-- (the Stack button may be made after the rest was dressed)
		if stackButton then FlatButton(stackButton) end
	end
	-- (never dressed: nothing to give back, the game's look left alone)
	if on or dressed then
		dressed = on
		ShowMine(on)
	end
	if on then
		LayoutSerene(buttons)
	else
		if mine.size then frame:SetSize(mine.size[1], mine.size[2]) end
		if three then LayoutGame(buttons) end
	end
	return true
end

local function MakeButton()
	local frame = Split()
	stackButton = CreateFrame("Button", "SereneStackSplitStackButton", frame, "UIPanelButtonTemplate")
	stackButton:SetHeight(select(2, GameButtons()) and select(2, GameButtons()):GetHeight() or 24)
	stackButton:SetText("Stack")
	stackButton:SetScript("OnClick", function()
		local owner = Owner()
		if owner then Buy(owner:GetID()) end
		frame:Hide()
	end)
	stackButton:SetScript("OnEnter", function(self)
		local owner = Owner()
		local plan = owner and Plan(owner:GetID())
		if not plan then return end
		ns.ShowTip(self, function(tip)
			tip:AddLine(("Buy %d for %s"):format(plan.count, Money(plan.cost)), ns.SOFT_RGB[1], ns.SOFT_RGB[2], ns.SOFT_RGB[3])
			if plan.short then
				tip:AddLine(MUTED .. (plan.short == "money" and "(all you can pay for)" or "(all the merchant has)") .. "|r")
			end
		end, "ANCHOR_RIGHT")
	end)
	stackButton:SetScript("OnLeave", function() ns.HideTip() end)
	stackButton:Hide()
end

local function OnSplitShow()
	local owner = ns.On("vendor") and Owner()
	local plan = owner and Plan(owner:GetID())
	if plan and not stackButton then MakeButton() end
	local three = plan and Dress(true)
	if not three then Dress(false) end
	if stackButton then stackButton:SetShown(three and true or false) end
end

-- Alt-click and the tooltip's hint ------------------------------------------------------------------------------------

local hooked = {}
-- (12: the buyback page's buttons, two more than the buy page's ten; looked for again at each merchant)
local function HookButtons()
	for index = 1, 12 do
		local button = _G["MerchantItem" .. index .. "ItemButton"]
		if button and not hooked[button] then
			hooked[button] = true
			button:HookScript("OnClick", function(self)
				if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
					local tab = _G.MerchantFrame and _G.MerchantFrame.selectedTab
					-- (the buy tab only: on buyback the same buttons buy back)
					if tab == nil or tab == 1 then Buy(self:GetID()) end
				end
			end)
		end
	end
end

local function Hint(tooltip, index)
	if not ns.On("vendor") or tooltip ~= GameTooltip then return end
	local plan = Plan(index)
	if not plan then return end
	-- (a how-to line: with Shift, or after a moment, while calm tooltips are on)
	if not ns.TipHints() then
		return ns.TipLater(function() tooltip:SetMerchantItem(index) end)
	end
	tooltip:AddLine(MUTED .. "Alt-click: buy " .. GOLD_TEXT .. plan.count .. "|r" .. MUTED
		.. (plan.count == plan.stack and " (a stack)" or "") .. " for|r " .. Money(plan.cost))
	tooltip:Show()
end

local function Init()
	local frame = _G.StackSplitFrame
	if frame then frame:HookScript("OnShow", OnSplitShow) end
	-- (opened again while open: no OnShow)
	if frame and frame.OpenStackSplitFrame then hooksecurefunc(frame, "OpenStackSplitFrame", OnSplitShow) end
	if _G.OpenStackSplitFrame then hooksecurefunc("OpenStackSplitFrame", OnSplitShow) end
	if frame then frame:HookScript("OnHide", function() if stackButton then stackButton:Hide() end end) end
	if GameTooltip.SetMerchantItem then hooksecurefunc(GameTooltip, "SetMerchantItem", Hint) end
	HookButtons()
	local events = CreateFrame("Frame")
	events:RegisterEvent("MERCHANT_SHOW")
	events:SetScript("OnEvent", HookButtons)
end

ns.MerchantBuyStack = Buy -- (Vendor.lua: Alt-click in Serene's merchant window)

table.insert(ns.modules, { init = Init })
