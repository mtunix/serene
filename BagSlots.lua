local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The row under the bags' header, and under the bank's (Bags.lua draws the windows; this, the slots in them):
-- * "bags" on the bags: your bag slots, each with its bag's icon and the room left in it. Drop a bag on one: put on,
--   or swapped; drag one away (or click it): taken off; the mouse over one: its items stand out, the rest fade.
-- * "tabs" on the bank (at a banker): the bank's tabs, how full each is, and one more to buy (on the game's own bank
--   page: its price, its confirmation). Forever's bank, where each tab holds a bag: a slot for each tab, the next to
--   buy a "+". A bank of the older kind: its bag slots, the next to buy among them.

local SOFT, MUTED_RGB = ns.SOFT_RGB, ns.MUTED_RGB
local SLOT = 26                       -- a bag slot in the row
local SLOTS_ROW = SLOT + 10
local TABS_ROW = 22                   -- the tabs as words: how full each is
local bags = ns.bags                  -- (the windows' measures, and their words: Bags.lua)
local PAD, HEAD, GAP, Text = bags.PAD, bags.HEAD, bags.GAP, bags.Text

local Items = ns.Items
local Container = C_Container or {}
local NumSlots, FreeSlots, BankTabs, BankIDs = Items.NumSlots, Items.FreeSlots, Items.BankTabs, Items.BankBags
local REAGENT_BAG = Items.REAGENT_BAG
local Money = Items.Coins

-- The slots ------------------------------------------------------------------------------------------------------------

-- The bank of the newer kind (tabs to buy, no bag slots), or the older (its own slots and bags).
local function Tabbed()
	if BankTabs()[1] then return true end
	local types = Enum and Enum.BankType
	if types and C_Bank and C_Bank.CanPurchaseBankTab and Clean(Safe(C_Bank.CanPurchaseBankTab, types.Character)) then
		return true
	end
	return not _G.GetNumBankSlots -- (no call for the older bank's slots: only the newer kind)
end

-- The inventory slot a bag sits in (what the game puts a bag in, or takes one from).
local function InvSlot(bag)
	local slot = Clean(Safe(Container.ContainerIDToInventoryID or _G.ContainerIDToInventoryID, bag))
	return type(slot) == "number" and slot or nil
end

-- The bag slots: { bag, inv, name, has (its icon), busy (the game has it locked), locked (not bought), buyable (the
-- next to buy) }; ReadSlot fills in inv, has and busy.
local function BagSlots()
	local list = {}
	for bag = 1, (NUM_BAG_SLOTS or 4) do list[#list + 1] = { bag = bag, name = "Bag slot" } end
	if REAGENT_BAG then list[#list + 1] = { bag = REAGENT_BAG, name = "Reagent bag slot" } end
	return list
end

local function BankBagSlots()
	local list = {}
	if Tabbed() then return list end
	local bought = Clean(Safe(_G.GetNumBankSlots)) or 0
	local first = Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1 or (NUM_BAG_SLOTS or 4) + 1
	for index = 1, (NUM_BANKBAGSLOTS or 7) do
		local slot = { bag = first + index - 1, index = index, name = "Bank bag slot" }
		slot.locked = index > bought
		slot.buyable = index == bought + 1
		list[#list + 1] = slot
	end
	return list
end

-- The newer bank's tabs as slots (Forever): each tab holds a bag of its own, in an inventory slot the game names
-- (C_Bank.BankBagTypeAndIDToInvSlot). Empty when the game has no such slots: the tabs are then only words.
local TabInvSlot = C_Bank and C_Bank.BankBagTypeAndIDToInvSlot
local function TabInv(index, id)
	local types = Enum and Enum.BankType
	if not (TabInvSlot and types) then return nil end
	-- (unknown whether the game wants the tab's index or its id: both asked, /serene debug shows each)
	for _, key in ipairs({ index, id }) do
		local inv = Clean(Safe(TabInvSlot, types.Character, key))
		if type(inv) == "number" and inv > 0 then return inv end
	end
end

local function BankTabSlots()
	local list, any = {}, false
	for index, tab in ipairs(BankTabs()) do
		local inv = TabInv(index, tab.id)
		any = any or inv ~= nil
		list[#list + 1] = { bag = tab.id, index = index, tab = true, tabInv = inv or false,
			name = tab.name or ("Tab " .. index) }
	end
	return any and list or {}
end

local function ReadSlot(slot)
	if slot.tab then
		slot.inv = slot.tabInv or nil
	else
		-- (the older bank's bag slots: by their number, 1 asking for a bag slot rather than an item slot)
		slot.inv = InvSlot(slot.bag) or (slot.index and Clean(Safe(_G.BankButtonIDToInvSlotID, slot.index, 1))) or nil
	end
	slot.has = slot.inv and not slot.locked and Clean(Safe(GetInventoryItemTexture, "player", slot.inv)) or nil
	slot.busy = slot.has and Clean(Safe(_G.IsInventoryItemLocked, slot.inv)) and true or false
	return slot
end

-- The row ----------------------------------------------------------------------------------------------------------------

local EMPTY_SLOT = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local PutBag = _G.PutItemInBag or Container.PutItemInBag
local PickupBag = _G.PickupBagFromSlot or Container.PickupBagFromSlot

local function PutOn(inv)
	if PutBag then return Safe(PutBag, inv) end
	if _G.EquipCursorItem then Safe(_G.EquipCursorItem, inv) end
end

-- (the mouse over a bag: the cells holding what is in it stay, the others fade)
local function Spotlight(win, bag)
	for _, row in pairs(win.buttons) do
		for _, button in pairs(row) do
			local cell, keep = button.sereneCell, bag == nil
			if cell and not keep then
				for _, entry in ipairs(cell.slots) do
					if entry.bag == bag then keep = true break end
				end
			end
			button:SetAlpha((keep or not cell) and 1 or 0.25)
		end
	end
end

local function SlotTip(win, button)
	local slot = button.slot
	if not slot or not ns.ShowTip then return end
	ns.ShowTip(button, function(tooltip)
		if slot.has then
			Safe(tooltip.SetInventoryItem, tooltip, "player", slot.inv)
			if slot.tab then tooltip:AddLine(ns.MUTED .. "In " .. slot.name .. "|r") end
			local size = NumSlots(slot.bag)
			if size > 0 then tooltip:AddLine(ns.MUTED .. ("%d of %d free"):format(FreeSlots(slot.bag), size) .. "|r") end
			if ns.TipHint then
				ns.TipHint(tooltip, "Drop a bag here: swap them")
				ns.TipHint(tooltip, "Drag (or click): take it off")
			end
		elseif slot.locked then
			tooltip:AddLine(slot.name, SOFT[1], SOFT[2], SOFT[3])
			tooltip:AddLine(ns.MUTED .. "Not bought yet|r")
			if slot.buyable and win.buy then
				if win.buyCost then tooltip:AddLine(Money(win.buyCost), 1, 1, 1) end
				if ns.TipHint then ns.TipHint(tooltip, "Click: buy it (on the game's own bank page)") end
			end
		else
			tooltip:AddLine(slot.name, SOFT[1], SOFT[2], SOFT[3])
			local size = slot.bag and NumSlots(slot.bag) or 0
			if size > 0 then tooltip:AddLine(ns.MUTED .. ("%d of %d free"):format(FreeSlots(slot.bag), size) .. "|r") end
			if slot.inv then
				tooltip:AddLine(ns.MUTED .. (slot.tab and "No bag in it" or "Empty") .. "|r")
				if ns.TipHint then ns.TipHint(tooltip, "Drop a bag here: put it on") end
			end
		end
	end, "ANCHOR_TOP")
end

local function SlotButton(win, index)
	local button = win.slots[index]
	if button then return button end
	button = CreateFrame("Button", nil, win)
	button:SetSize(SLOT, SLOT)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	-- (framed like the item cells: a soft grey line, a dark ring inside it, the icon within)
	local ground = button:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.85)
	button.lines = ns.Hairline(button, { 0.62, 0.62, 0.62, 0.55 })
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
	button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	button.free = Text(button, "NumberFontNormalSmall", SOFT)
	button.free:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
	button.plus = Text(button, "GameFontHighlight", MUTED_RGB)
	button.plus:SetPoint("CENTER")
	button.plus:SetText("+")
	local light = button:CreateTexture(nil, "HIGHLIGHT")
	light:SetAllPoints()
	light:SetColorTexture(1, 1, 1, 0.08)
	button:SetScript("OnClick", function(self, mouse)
		local slot = self.slot
		if not slot then return end
		if slot.locked then
			if slot.buyable and win.buy then win.buy() end
			return
		end
		if not slot.inv then return end
		if CursorHasItem and CursorHasItem() then return PutOn(slot.inv) end
		if not slot.has then return end
		if IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			local link = Clean(Safe(GetInventoryItemLink, "player", slot.inv))
			if link and Safe(HandleModifiedItemClick, link) then return end
		end
		if mouse == "LeftButton" and PickupBag then Safe(PickupBag, slot.inv) end
	end)
	button:SetScript("OnDragStart", function(self)
		local slot = self.slot
		if slot and slot.has and PickupBag then Safe(PickupBag, slot.inv) end
	end)
	button:SetScript("OnReceiveDrag", function(self)
		local slot = self.slot
		if slot and slot.inv and not slot.locked then PutOn(slot.inv) end
	end)
	button:SetScript("OnEnter", function(self)
		SlotTip(win, self)
		local slot = self.slot
		if slot and slot.bag and (slot.has or (slot.tab and not slot.locked)) then Spotlight(win, slot.bag) end
	end)
	button:SetScript("OnLeave", function()
		if ns.HideTip then ns.HideTip() else GameTooltip:Hide() end
		Spotlight(win, nil)
	end)
	win.slots[index] = button
	return button
end

local function HideSlots(win, from)
	for index = from or 1, #win.slots do
		win.slots[index]:Hide()
		win.slots[index].slot = nil
	end
end

-- The row under the header: one button per bag slot, its bag's icon and its free room.
local function PlaceSlots(win, list)
	for index, slot in ipairs(list) do
		ReadSlot(slot)
		local button = SlotButton(win, index)
		button.slot = slot
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (index - 1) * (SLOT + GAP), -HEAD - 4)
		if slot.has then
			button.icon:SetTexture(slot.has)
			button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			button.icon:SetAlpha(1)
			button.icon:SetDesaturated(slot.busy)
			local size = NumSlots(slot.bag)
			button.free:SetText(size > 0 and FreeSlots(slot.bag) or "")
		else
			button.icon:SetTexture(EMPTY_SLOT)
			button.icon:SetTexCoord(0, 1, 0, 1)
			button.icon:SetAlpha(slot.locked and 0.08 or 0.3)
			button.icon:SetDesaturated(true)
			local size = (slot.tab and not slot.locked and slot.bag) and NumSlots(slot.bag) or 0
			button.free:SetText(size > 0 and FreeSlots(slot.bag) or "")
		end
		button.plus:SetShown(slot.buyable and win.buy ~= nil or false)
		local faint = slot.locked and not slot.buyable
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do button.lines[side]:SetAlpha(faint and 0.35 or 1) end
		button.lines:Fit()
		button:Show()
	end
	HideSlots(win, #list + 1)
end

-- (after a refresh: the tooltip and the faded cells follow what changed under the mouse)
function ns.BagSlotsHover(win)
	for _, button in ipairs(win.slots) do
		if button.slot and button:IsShown() and ns.Over(button) then
			return button:GetScript("OnEnter")(button)
		end
	end
	Spotlight(win, nil)
end

-- The bags' row: shown with "bags", for your own bags at hand.
function ns.BagSlotsRow(win, live)
	win.rowHeight = 0
	win.slotsWord:SetShown(live)
	win.slotsWord:SetWords(win.showSlots and live and "|cffffd100bags|r" or "bags")
	if not (live and win.showSlots) then return HideSlots(win) end
	PlaceSlots(win, BagSlots())
	win.rowHeight = SLOTS_ROW
end

-- The bank's tabs row: how full each is, and one more to buy (on the game's own page: its confirmation, its price).
-- A bank with bag slots: the slots instead (the next to buy among them).
function ns.BankTabsRow(win, live)
	win.rowHeight = 0
	win.tabsWord:SetShown(live)
	win.tabsText:Hide()
	win.buyWord:Hide()
	win.buy, win.buyCost = nil, nil
	if not live then return HideSlots(win) end
	local slots = BankBagSlots()
	win.bankBags = slots[1] ~= nil
	local words = {}
	local tabs = BankTabs()
	local named = {}
	for _, tab in ipairs(tabs) do named[tab.id] = tab.name end
	for index, id in ipairs(BankIDs()) do
		local size = NumSlots(id)
		if size > 0 then
			local free = FreeSlots(id)
			local name = named[id] or (id == (BANK_CONTAINER or -1) and "Bank") or ("Bag " .. (index - 1))
			words[#words + 1] = ("%s %d/%d"):format(name, size - free, size)
		end
	end
	-- (a bank with no room at all yet: the row shows itself, to buy the first tab)
	if not words[1] then win.showTabs = true end
	local word = win.bankBags and "bags" or "tabs"
	win.tabsWord:SetWords(win.showTabs and ("|cffffd100" .. word .. "|r") or word)
	if not win.showTabs then return HideSlots(win) end
	-- (one more: a tab of the newer bank, a bag slot of the older)
	local types = Enum and Enum.BankType
	local cost, what
	if not win.bankBags then
		if types and C_Bank and Clean(Safe(C_Bank.CanPurchaseBankTab, types.Character)) then
			local data = C_Bank.FetchNextPurchasableBankTabData and Safe(C_Bank.FetchNextPurchasableBankTabData, types.Character)
			cost = type(data) == "table" and Clean(data.tabCost or data.cost) or nil -- (whichever key the client fills)
			what = "tab"
		end
	else
		local bought, full = Safe(_G.GetNumBankSlots)
		if Clean(full) == false then
			cost, what = Clean(Safe(_G.GetBankSlotCost, bought)), "bag slot"
		end
	end
	if what then
		win.buyTip, win.buyCost = "Buy a " .. what, cost
		win.buyWord:SetWords("buy a " .. what .. (cost and ("  " .. Money(cost)) or ""))
		win.buy = win.Reveal
	end
	if win.bankBags then
		-- (the slots, the one to buy among them: a "+")
		PlaceSlots(win, slots)
		win.rowHeight = SLOTS_ROW
		return
	end
	-- (tabs holding bags: a slot for each, like the bags' row; the next tab to buy: a "+")
	local tabSlots = BankTabSlots()
	win.tabBags = tabSlots[1] ~= nil
	if win.tabBags then
		if what == "tab" then
			tabSlots[#tabSlots + 1] = { tab = true, tabInv = false, locked = true, buyable = true,
				name = "Tab " .. (#tabSlots + 1) }
		end
		PlaceSlots(win, tabSlots)
		win.rowHeight = SLOTS_ROW
		if what then win.buyWord:Show() end
		return
	end
	HideSlots(win)
	win.tabsText:SetText(words[1] and table.concat(words, "  ·  ") or "No tabs yet")
	win.tabsText:Show()
	win.rowHeight = TABS_ROW
	if what then win.buyWord:Show() end
end

-- /serene debug (from Bags'): each tab, the inventory slot its bag sits in, asked by the tab's index and by its id.
function ns.BankTabsDebug()
	local tabs = {}
	for index, tab in ipairs(BankTabs()) do
		local types = Enum and Enum.BankType
		local byIndex = TabInvSlot and types and Clean(Safe(TabInvSlot, types.Character, index))
		local byId = TabInvSlot and types and Clean(Safe(TabInvSlot, types.Character, tab.id))
		tabs[#tabs + 1] = ("%d (bag %s): slot %s / by id %s, %d slots"):format(index, tostring(tab.id), tostring(byIndex),
			tostring(byId), NumSlots(tab.id))
	end
	ns.Print("bank tabs: " .. (tabs[1] and table.concat(tabs, "; ") or "none") .. (TabInvSlot and "" or " (no bag slots API)"))
end
