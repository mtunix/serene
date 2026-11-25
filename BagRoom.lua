local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- "make room" on Serene's bags (Bags.lua draws the window; this, the glass above it): the stack a vendor pays least
-- for, glowing in its cell, in a small glass above the bags. Delete it, or skip it for the next cheapest, until one
-- is gone; or keep it: never suggested again (undone with Alt-right-click on it). It opens by itself when the bags
-- open full.
--   ns.BagRoom.Toggle(), OpenIfFull(), Close()
--   ns.BagRoom.Suggest(win, live)   each refresh of the bags: the suggestion read again
--   ns.BagRoom.Suggested()          "bag:slot" of the item suggested, its cell to glow (nil: none)

local INK, SOFT, MUTED_RGB = ns.INK, ns.SOFT_RGB, ns.MUTED_RGB
local GOLD = { 1, 0.82, 0.35 }
local bags = ns.bags -- (the bags' measures and words: Bags.lua)
local SIZE, PAD, GLASS, Text, Word, Drags = bags.SIZE, bags.PAD, bags.GLASS, bags.Text, bags.Word, bags.Drags
local Refresh, Window, Kept, Keep, SpecialKind = bags.Refresh, bags.Window, bags.Kept, bags.Keep, bags.SpecialKind

local Items = ns.Items
local Container = C_Container or {}
local NumSlots, SlotInfo, BagIDs, FreeSlots = Items.NumSlots, Items.Slot, Items.Bags, Items.FreeSlots
local Describe, KEYRING, Money = Items.Describe, Items.KEYRING, Items.Coins

-- The cheapest item, to delete -------------------------------------------------------------------------------------------
-- "make room" at the top: a small glass above the bags with the stack worth least at a vendor. Skip: the next
-- cheapest (that item is kept till the glass closes). Delete: gone, and the glass closes. Items a vendor won't buy
-- (a hearthstone, quest items...), locked ones and the keyring are never suggested.

local PickupItem = Container.PickupContainerItem or _G.PickupContainerItem
local ROOM_WIDTH = 280
local room                 -- the glass
local skipped = {}         -- itemID -> true: kept, while the glass is open
local suggested            -- "bag:slot" of the item suggested (its cell glows: Bags.lua asks)

-- What a vendor pays for the whole stack (nil: nothing, it won't buy it).
local function Worth(entry)
	local price = Items.SellPrice(entry.link)
	if price <= 0 then return nil end
	return price * entry.count
end

-- The cheapest stack in the bags not skipped (ties: the poorer quality, then the first in bag order).
local function Cheapest()
	local best, bestWorth
	for _, bag in ipairs(BagIDs()) do
		if bag ~= KEYRING then
			for slot = 1, NumSlots(bag) do
				local entry = SlotInfo(bag, slot)
				if entry and entry.id and not skipped[entry.id] and not Kept(entry.id) and not entry.locked
					and not entry.quest then
					Describe(entry)
					local worth = entry.classID ~= 12 and Worth(entry)
					if worth and (not best or worth < bestWorth
						or (worth == bestWorth and (entry.quality or 1) < (best.quality or 1))) then
						best, bestWorth = entry, worth
					end
				end
			end
		end
	end
	return best, bestWorth
end

local function Delete()
	local entry = room and room.entry
	if not entry then return end
	-- (the slot read again: the bags may have changed since it was suggested)
	local now = SlotInfo(entry.bag, entry.slot)
	if not now or now.link ~= entry.link or now.count ~= entry.count or now.locked then return Refresh(Window()) end
	-- (something already on the cursor: let go first, or the pickup would swap it into the slot)
	if Safe(GetCursorInfo) then Safe(ClearCursor) end
	Safe(PickupItem, entry.bag, entry.slot)
	local kind, id = Safe(GetCursorInfo)
	if Clean(kind) ~= "item" or Clean(id) ~= entry.id then
		Safe(ClearCursor)
		return ns.Print("bags: couldn't pick it up, nothing was deleted.")
	end
	Safe(DeleteCursorItem)
	if Clean(Safe(CursorHasItem)) then
		Safe(ClearCursor)
		return ns.Print("bags: the game kept it, nothing was deleted.")
	end
	ns.Print(("deleted %s%s (%s at a vendor)"):format(entry.link, entry.count > 1 and (" ×" .. entry.count) or "",
		Money(room.worth)))
	room:Hide()
	Refresh(Window())
end

local function Skip()
	local entry = room and room.entry
	if entry then skipped[entry.id] = true end
	Refresh(Window())
end

local function KeepIt()
	local entry = room and room.entry
	if not entry then return end
	ns.Print(("bags: %s won't be suggested again (Alt-right-click it to undo)."):format(entry.link or entry.name or "it"))
	Keep(entry.id, true)
end

local ToggleRoom -- (below)

local function MakeRoom()
	local bags = Window()
	room = CreateFrame("Frame", "SereneBagsRoom", bags)
	room:SetSize(ROOM_WIDTH, 30 + SIZE + PAD)
	room:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, 6)
	room:SetClampedToScreen(true)
	room:EnableMouse(true)
	room:Hide()
	Drags(room, bags) -- (Shift and drag: the bags move, the glass with them)
	local ground = room:CreateTexture(nil, "BACKGROUND", nil, -8)
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS)
	local rule = room:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)

	room.title = Text(room, "GameFontNormalSmall", MUTED_RGB)
	room.title:SetPoint("TOPLEFT", room, "TOPLEFT", PAD, -10)
	room.title:SetText("THE CHEAPEST IN YOUR BAGS")
	-- (its words made on the bags, for their drag and click-after-drag guard, then moved into the glass)
	room.close = Word(bags, "×", function() ToggleRoom() end)
	room.close:SetParent(room)
	room.close:SetPoint("TOPRIGHT", room, "TOPRIGHT", -PAD + 3, -5)

	-- the item: its icon (the game's tooltip on it), its name and count, what a vendor pays
	local item = CreateFrame("Button", nil, room)
	item:SetSize(SIZE, SIZE)
	item:SetPoint("TOPLEFT", room, "TOPLEFT", PAD, -30)
	local itemGround = item:CreateTexture(nil, "BACKGROUND")
	itemGround:SetAllPoints()
	itemGround:SetColorTexture(1, 1, 1, 0.045)
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
	item.icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 1)
	item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	item:SetScript("OnEnter", function(self)
		local entry = room.entry
		if not entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetBagItem, GameTooltip, entry.bag, entry.slot) then
			Safe(GameTooltip.SetHyperlink, GameTooltip, entry.link)
		end
		GameTooltip:Show()
	end)
	item:SetScript("OnLeave", function() if ns.HideTip then ns.HideTip() else GameTooltip:Hide() end end)
	room.item = item
	room.name = Text(room, "GameFontHighlight")
	room.name:SetPoint("TOPLEFT", item, "TOPRIGHT", 8, -2)
	room.name:SetPoint("RIGHT", room, "RIGHT", -PAD, 0)
	room.name:SetWordWrap(false)
	room.worthText = Text(room, "GameFontHighlightSmall", MUTED_RGB)
	room.worthText:SetPoint("BOTTOMLEFT", item, "BOTTOMRIGHT", 8, 2)

	-- delete (in gold: what matters), skip
	room.delete = Word(bags, "delete", Delete)
	room.delete:SetParent(room)
	room.delete:SetPoint("BOTTOMRIGHT", room, "BOTTOMRIGHT", -PAD + 3, PAD - 2)
	room.delete.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	room.delete:HookScript("OnLeave", function(self) self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
	room.skip = Word(bags, "skip", Skip, function(tooltip)
		tooltip:AddLine("Skip", SOFT[1], SOFT[2], SOFT[3])
		tooltip:AddLine(ns.MUTED .. "The next cheapest, for now|r", nil, nil, nil, true)
	end)
	room.skip:SetParent(room)
	room.skip:SetPoint("RIGHT", room.delete, "LEFT", -10, 0)
	room.keep = Word(bags, "keep", KeepIt, function(tooltip)
		tooltip:AddLine("Keep", SOFT[1], SOFT[2], SOFT[3])
		tooltip:AddLine(ns.MUTED .. "Never suggest it again. Alt-right-click it in your bags to undo.|r", nil, nil, nil,
			true)
	end)
	room.keep:SetParent(room)
	room.keep:SetPoint("RIGHT", room.skip, "LEFT", -10, 0)

	room:SetScript("OnHide", function(self)
		skipped, suggested, self.entry, self.worth = {}, nil, nil, nil
	end)
end

ToggleRoom = function()
	if not room then MakeRoom() end
	room:SetShown(not room:IsShown())
	Refresh(Window())
end

-- (no free slot left in your own bags, special bags aside: "make room" opens with them)
local function BagsFull()
	local any = false
	for _, bag in ipairs(BagIDs()) do
		if NumSlots(bag) > 0 then
			local free, family = FreeSlots(bag)
			if not SpecialKind(bag, family) then
				any = true
				if free > 0 then return false end
			end
		end
	end
	return any
end

-- (each refresh of the bags: the suggestion read again, its cell to glow)
local function Suggest(win, live)
	if not win.roomWord then return end
	win.roomWord:SetShown(live)
	if room and room:IsShown() and not live then room:Hide() end
	if not (room and room:IsShown()) then
		suggested = nil
		win.roomWord:SetWords("make room")
		return
	end
	win.roomWord:SetWords("|cffffd100make room|r")
	local entry, worth = Cheapest()
	room.entry, room.worth = entry, worth
	suggested = entry and (entry.bag .. ":" .. entry.slot) or nil
	room.item:SetShown(entry ~= nil)
	room.delete:SetShown(entry ~= nil)
	room.skip:SetShown(entry ~= nil)
	room.keep:SetShown(entry ~= nil)
	if entry then
		room.item.icon:SetTexture(entry.icon)
		room.name:ClearAllPoints()
		room.name:SetPoint("TOPLEFT", room.item, "TOPRIGHT", 8, -2)
		room.name:SetPoint("RIGHT", room, "RIGHT", -PAD, 0)
		local color = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[entry.quality]
		local hex = color and type(color.r) == "number" and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
		room.name:SetText((hex or ns.SOFT) .. entry.name .. "|r" .. (entry.count > 1 and (ns.SOFT .. "  ×" .. entry.count .. "|r") or ""))
		room.worthText:SetText(Money(worth) .. ns.MUTED .. "  at a vendor|r")
	else
		room.name:ClearAllPoints()
		room.name:SetPoint("TOPLEFT", room, "TOPLEFT", PAD, -36)
		room.name:SetPoint("RIGHT", room, "RIGHT", -PAD, 0)
		room.name:SetText(ns.MUTED .. (next(skipped) and "Nothing cheaper left: all skipped." or "Nothing a vendor buys.") .. "|r")
		room.worthText:SetText("")
	end
end

ns.BagRoom = {
	Toggle = function() ToggleRoom() end,
	OpenIfFull = function()
		if not BagsFull() then return end
		if not room then MakeRoom() end
		room:Show()
	end,
	Close = function() if room then room:Hide() end end,
	Suggest = Suggest,
	Suggested = function() return suggested end,
}
