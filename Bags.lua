local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Serene's bags and bank.                                                   (/serene bags on|off: after a reload)
-- * One glass window for all your bags, bottom right (Shift and drag: move it); the bank in the same glass beside
--   them, as a merchant's window (Shift and drag on it: both move), or where you put it (Settings). They open and
--   close as the game's do: B, the bag buttons, a merchant, a banker.
-- * Items in quiet sections: Equipment, Consumables, Quest, Trade goods, Ammo, Keys, Other, Junk, and your own
--   first (Alt-right-click an item: its section; right click a section of yours: remove it). One item over
--   several stacks: one cell, the whole count. Free slots: one cell at the foot (drop an item on it), the room
--   left in special bags (reagents, quiver, soul bag...) beside it.
-- * Quality as a soft line under the icon (uncommon and better; quest items: gold), junk dimmed, a short glow on
--   what just came.
-- * Remembered: your bags and bank, and those of your other characters on this realm. The name at the top: whose
--   to look at; "bank" at the top: the bank, from anywhere. Item tooltips say how many are in the bank or on your
--   other characters (with the game's tooltip lines: Shift, when calm tooltips keep addons' lines for it).
-- * Your bag slots: "bags" at the top shows them in a row (the bank's: "bags" there, or "tabs" where each tab holds a
--   bag, Forever's bank: a slot for each tab, the next to buy a "+"). Drop
--   a bag on one: put on, or swapped; drag one away: taken off; the mouse over one: its items stand out.
-- * "make room" at the top: the cheapest stack in your bags (what a vendor pays for it), glowing in its cell, in a
--   small glass above the window. Delete it, or skip it for the next cheapest, until one is gone; or keep it: never
--   suggested again (undone with Alt-right-click on it). It opens by itself when the bags open full.
-- The item buttons are the game's own (click, drag, use, split, tooltips as always); the game's bag and bank
-- windows stay, followed by these, only out of sight.

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local INK, SOFT, MUTED_RGB = ns.INK, ns.SOFT_RGB, ns.MUTED_RGB
local GOLD = { 1, 0.82, 0.35 }
local SIZE, GAP, PAD = 34, 4, 12      -- a cell, the room between cells, the room inside the glass
local HEAD, SECTION, SECTION_GAP = 30, 18, 8
local FOOT, TABS_ROW = 50, 22
local SLOT = 26                       -- a bag slot in the row under the header
local SLOTS_ROW = SLOT + 10
local GLOW_TIME = 3                   -- seconds a new item glows
local GLASS = 0.9
local JUNK_ALPHA = 0.5

-- (reading the bags and what an item is, its section and its price: Items.lua)
local Items = ns.Items
local AUTO = Items.SECTIONS
local IS_AUTO = {}
for _, name in ipairs(AUTO) do IS_AUTO[name] = true end
-- (a special bag's kind, by the lowest bit of its family)
local FAMILY = { [1] = "quiver", [2] = "ammo", [4] = "soul", [8] = "leather", [16] = "inscription", [32] = "herbs",
	[64] = "enchanting", [128] = "engineering", [256] = "keys", [512] = "gems", [1024] = "mining" }
local QUALITY = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
	[6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 }, [8] = { 0, 0.8, 1 } }
local QUEST_LINE = { 1, 0.82, 0 }

local bags, bank           -- the two windows
local hidden               -- where the game's own windows wait, out of sight
local bankLive = false     -- talking to a banker now
local revealing = false    -- the game's bank shown for a moment (to buy a tab)
local syncing = false
local protectedButtons = false -- the game's item buttons are protected here: laid out only out of a fight
local glowAt, glowed = {}, {}  -- "bag:slot" -> when its glow began / glowed this opening
local glowUntil = 0            -- (no glow after this: nothing to animate)
local bagsByBank = false       -- the bags opened because a banker was spoken to (closed with the bank)
local countsIndex              -- itemID -> { name -> { bags, bank } }, built when asked
local suggested                -- "bag:slot" of the item "make room" suggests deleting (its cell glows)
local Refresh, Menu            -- (below)

-- Reading the bags ----------------------------------------------------------------------------------------------------

local Container = C_Container or {}
local NumSlots, IdOf, SlotInfo, BagIDs = Items.NumSlots, Items.IdOf, Items.Slot, Items.Bags
local KEYRING, REAGENT_BAG = Items.KEYRING, Items.REAGENT_BAG

local function FreeSlots(bag)
	local free, family = Safe(Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots, bag)
	return Clean(free) or 0, Clean(family) or 0
end

local function BankTabs()
	local types = Enum and Enum.BankType
	local tabs = types and C_Bank and C_Bank.FetchPurchasedBankTabData and Safe(C_Bank.FetchPurchasedBankTabData, types.Character)
	local list = {}
	for _, tab in ipairs(type(tabs) == "table" and tabs or {}) do
		local id = Clean(tab.ID)
		if id then list[#list + 1] = { id = id, name = Clean(tab.name) } end
	end
	return list
end

-- Every container of the bank: your character's tabs; a bank of the older kind: its own slots and its bags.
local function BankIDs()
	local list = {}
	for _, tab in ipairs(BankTabs()) do list[#list + 1] = tab.id end
	if not list[1] then
		list[1] = BANK_CONTAINER or -1
		local first = Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1 or (NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
	end
	return list
end

-- The bank of the newer kind (tabs to buy, no bag slots), or the older (its own slots and bags).
local function Tabbed()
	if BankTabs()[1] then return true end
	local types = Enum and Enum.BankType
	if types and C_Bank and C_Bank.CanPurchaseBankTab and Clean(Safe(C_Bank.CanPurchaseBankTab, types.Character)) then
		return true
	end
	return not _G.GetNumBankSlots
end

-- The inventory slot a bag sits in (what the game puts a bag in, or takes one from).
local function InvSlot(bag)
	local slot = Clean(Safe(Container.ContainerIDToInventoryID or _G.ContainerIDToInventoryID, bag))
	return type(slot) == "number" and slot or nil
end

-- The bag slots: { bag, inv, name, has (its icon), locked (not bought), buyable (the next to buy) }.
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
		slot.inv = InvSlot(slot.bag) or (slot.index and Clean(Safe(_G.BankButtonIDToInvSlotID, slot.index, 1))) or nil
	end
	slot.has = slot.inv and not slot.locked and Clean(Safe(GetInventoryItemTexture, "player", slot.inv)) or nil
	slot.busy = slot.has and Clean(Safe(_G.IsInventoryItemLocked, slot.inv)) and true or false
	return slot
end

-- What kind of room a bag holds: nil for any item, else a short word ("reagents", "quiver"...).
local function SpecialKind(bag, family)
	if bag == KEYRING then return "keys" end
	if REAGENT_BAG and bag == REAGENT_BAG then return "reagents" end
	if not family or family == 0 then return nil end
	for bit_, word in pairs(FAMILY) do
		if bit and bit.band and bit.band(family, bit_) ~= 0 then return word end
	end
	return "special"
end

-- All items in these containers, the first free slot for any item, the free room in special bags.
local function Scan(ids)
	local entries, free, special = {}, { count = 0 }, {}
	for _, bag in ipairs(ids) do
		local size = NumSlots(bag)
		if size > 0 then
			local _, family = FreeSlots(bag)
			local kind = SpecialKind(bag, family)
			for slot = 1, size do
				local entry = SlotInfo(bag, slot)
				if entry then
					entries[#entries + 1] = entry
				elseif kind then
					special[kind] = (special[kind] or 0) + 1
				else
					free.count = free.count + 1
					if not free.bag then free.bag, free.slot = bag, slot end
				end
			end
		end
	end
	return entries, free, special
end

-- Sections ------------------------------------------------------------------------------------------------------------

local Describe, IsCustom, SectionOf = Items.Describe, Items.IsCustom, Items.Section

-- One cell per item (stackable items over several slots together).
local function Cells(entries)
	local cells, byLink = {}, {}
	for _, entry in ipairs(entries) do
		Describe(entry)
		local cell = entry.merge and byLink[entry.link]
		if cell then
			cell.count = cell.count + entry.count
			-- (the cell's button is the first stack not locked: one put in a mail or a trade, the next answers the
			-- click; the cell is grey only when every stack is)
			if cell.locked and not entry.locked then cell.live = entry end
			cell.locked = cell.locked and entry.locked
			cell.slots[#cell.slots + 1] = entry
		else
			cell = { first = entry, live = entry, count = entry.count, locked = entry.locked, quality = entry.quality,
				slots = { entry }, quest = entry.quest or entry.classID == 12 }
			if entry.merge then byLink[entry.link] = cell end
			cells[#cells + 1] = cell
		end
	end
	return cells
end

local function Earlier(a, b)
	local x, y = a.first, b.first
	if x.quality ~= y.quality then return x.quality > y.quality end
	if x.classID ~= y.classID then return x.classID < y.classID end
	if x.subclassID ~= y.subclassID then return x.subclassID < y.subclassID end
	if x.name ~= y.name then return x.name < y.name end
	if a.count ~= b.count then return a.count > b.count end
	if x.bag ~= y.bag then return (x.bag or 0) < (y.bag or 0) end
	return (x.slot or 0) < (y.slot or 0)
end

local function Sections(entries)
	local byName = {}
	for _, cell in ipairs(Cells(entries)) do
		local name = SectionOf(cell.first)
		byName[name] = byName[name] or {}
		table.insert(byName[name], cell)
	end
	local list = {}
	local function Add(name, custom)
		local cells = byName[name]
		if not cells then return end
		byName[name] = nil
		table.sort(cells, Earlier)
		list[#list + 1] = { name = name, cells = cells, custom = custom }
	end
	for _, name in ipairs(ns.db.bagCats) do Add(name, true) end
	for _, name in ipairs(AUTO) do Add(name, false) end
	return list
end

-- What is remembered ----------------------------------------------------------------------------------------------------

local function Me()
	return Clean(Safe(GetRealmName)) or "?", Clean(Safe(UnitName, "player")) or "?"
end

local function Realm()
	local realm = Me()
	ns.db.inv[realm] = ns.db.inv[realm] or {}
	return ns.db.inv[realm]
end

local function Mine()
	local realm, name = Me()
	local characters = Realm()
	local me = characters[name] or {}
	characters[name] = me
	me.class = Clean(select(2, Safe(UnitClass, "player"))) or me.class
	me.money = Clean(Safe(GetMoney)) or me.money
	return me
end

local function Remember(where, entries, free, special)
	local me = Mine()
	local items = {}
	for _, entry in ipairs(entries) do items[#items + 1] = { entry.link, entry.count, entry.quality } end
	me[where] = items
	me[where .. "Free"] = free.count
	me[where .. "Special"] = special
	me[where .. "At"] = time()
	countsIndex = nil
end

local function Remembered(name, where)
	local character = Realm()[name]
	if not character or type(character[where]) ~= "table" then return nil end
	local entries = {}
	for _, item in ipairs(character[where]) do
		if type(item[1]) == "string" then
			entries[#entries + 1] = { link = item[1], count = item[2] or 1, quality = item[3], id = IdOf(item[1]) }
		end
	end
	return entries, { count = character[where .. "Free"] or 0 }, character[where .. "Special"] or {}, character
end

local function ClassHex(class)
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local color = colors and class and colors[class]
	if not color then return ns.SOFT end
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
end

local function Ago(at)
	if type(at) ~= "number" then return nil end
	local seconds = time() - at
	if seconds < 3600 then return "just now" end
	if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
	local days = math.floor(seconds / 86400)
	return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

local Money = Items.Coins

-- The look of a cell ----------------------------------------------------------------------------------------------------

local HIDE = { "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture", "JunkIcon",
	"UpgradeIcon", "flash", "searchOverlay", "ItemContextOverlay", "ExtendedSlot", "IconQuestTexture",
	"ItemSlotBackground", "LevelLinkLockTexture", "ProfessionQualityOverlay" }

local function Region(button, key)
	local name = button.GetName and button:GetName()
	return button[key] or (name and _G[name .. key])
end

-- (an item "make room" never suggests deleting)
local function Kept(id)
	return id and ns.db.bagKeep and ns.db.bagKeep[id] and true or false
end

-- Serene's own pieces on a cell: a faint ground, the quality line, the glow, the free count, the "keep" dot.
local function Decorate(button)
	local ground = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	ground:SetAllPoints()
	ground:SetColorTexture(1, 1, 1, 0.045)
	local edge = button:CreateTexture(nil, "OVERLAY", nil, 6)
	edge:SetHeight(2)
	edge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 1)
	edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 1)
	edge:Hide()
	local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
	glow:SetTexture(MEDIA .. "Glow")
	glow:SetBlendMode("ADD")
	glow:SetPoint("TOPLEFT", button, "TOPLEFT", -8, 8)
	glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 8, -8)
	glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	glow:SetAlpha(0)
	local freeText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	freeText:SetPoint("CENTER", button, "CENTER", 0, 0)
	freeText:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3])
	button.sereneEdge, button.sereneGlow, button.sereneFree = edge, glow, freeText
	-- (kept from "make room": a small gold dot in the corner, a dark rim so it reads on any icon)
	local keepRim = button:CreateTexture(nil, "OVERLAY", nil, 6)
	keepRim:SetTexture(MEDIA .. "Disc")
	keepRim:SetSize(8, 8)
	keepRim:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
	keepRim:SetVertexColor(0, 0, 0, 0.75)
	local keepDot = button:CreateTexture(nil, "OVERLAY", nil, 7)
	keepDot:SetTexture(MEDIA .. "Disc")
	keepDot:SetSize(5, 5)
	keepDot:SetPoint("CENTER", keepRim, "CENTER", 0, 0)
	keepDot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	button.sereneKeep, button.sereneKeepRim = keepDot, keepRim
	keepDot:Hide()
	keepRim:Hide()
end

local function KeepDot(button, cell)
	if not button.sereneKeep then return end
	local on = cell and cell.first and Kept(cell.first.id) or false
	button.sereneKeep:SetShown(on)
	button.sereneKeepRim:SetShown(on)
end

local function Edge(button, quality, quest)
	local color = type(quality) == "number" and QUALITY[quality]
	local game = _G.ITEM_QUALITY_COLORS and type(quality) == "number" and _G.ITEM_QUALITY_COLORS[quality]
	if color and game and type(game.r) == "number" then color = { game.r, game.g, game.b } end
	if quest then color, quality = QUEST_LINE, 2 end
	if color and quality >= 2 then
		button.sereneEdge:SetColorTexture(color[1], color[2], color[3], 0.9)
		button.sereneEdge:Show()
	else
		button.sereneEdge:Hide()
	end
end

-- The game's item button made calm: its frame, borders and marks gone, the icon cropped, the count quiet.
local function Dress(button)
	button:SetSize(SIZE, SIZE)
	for _, key in ipairs(HIDE) do
		local region = Region(button, key)
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
	end
	for _, anim in ipairs({ "newitemglowAnim", "flashAnim" }) do
		if type(button[anim]) == "table" and button[anim].Stop then Safe(button[anim].Stop, button[anim]) end
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	local icon = Region(button, "icon") or Region(button, "Icon") or Region(button, "IconTexture")
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	button.sereneIcon = icon
	local count = Region(button, "Count")
	if count then
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 4)
		count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	end
	button.sereneCount = count
	for _, get in ipairs({ "GetHighlightTexture", "GetPushedTexture" }) do
		local texture = button[get] and button[get](button)
		if texture then
			texture:SetColorTexture(1, 1, 1, get == "GetPushedTexture" and 0.12 or 0.08)
			texture:SetAllPoints()
		end
	end
	Decorate(button)
end

local function SetIcon(button, icon)
	if _G.SetItemButtonTexture then
		Safe(_G.SetItemButtonTexture, button, icon)
	elseif button.sereneIcon then
		button.sereneIcon:SetTexture(icon)
	end
	if button.sereneIcon then button.sereneIcon:SetShown(icon ~= nil) end
end

local function SetCount(button, count)
	if _G.SetItemButtonCount then
		Safe(_G.SetItemButtonCount, button, count)
	elseif button.sereneCount then
		button.sereneCount:SetText(count and count > 1 and count or "")
		button.sereneCount:SetShown(count and count > 1)
	end
	if button.sereneCount then button.sereneCount:SetTextColor(SOFT[1], SOFT[2], SOFT[3]) end
end

-- Live cells: the game's buttons ------------------------------------------------------------------------------------------

local made = 0

-- Each bag's buttons live in a frame of their own carrying the bag's number: the game's buttons read it there.
local function Holder(win, bag)
	local holder = win.holders[bag]
	if holder then return holder end
	holder = CreateFrame("Frame", nil, win)
	holder:SetID(bag)
	holder:SetAllPoints(win)
	holder.IsCombinedBagContainer = function() return false end
	holder.GetBagID = function(self) return self:GetID() end
	win.holders[bag] = holder
	return holder
end

local OnItemClick -- (below)

local function LiveButton(win, bag, slot)
	win.buttons[bag] = win.buttons[bag] or {}
	local button = win.buttons[bag][slot]
	if button then return button end
	if protectedButtons and InCombatLockdown() then return nil end
	made = made + 1
	local holder = Holder(win, bag)
	local name = "SereneBagsItem" .. made
	local ok, created = pcall(CreateFrame, "ItemButton", name, holder, "ContainerFrameItemButtonTemplate")
	if not ok or not created then
		ok, created = pcall(CreateFrame, "Button", name, holder, "ContainerFrameItemButtonTemplate")
	end
	if not ok or not created then return nil end
	button = created
	button:SetID(slot)
	if button.SetBagID and Clean(Safe(button.GetBagID, button)) ~= bag then Safe(button.SetBagID, button, bag) end
	if made == 1 then protectedButtons = Clean(Safe(button.IsProtected, button)) and true or false end
	Dress(button)
	button:HookScript("OnClick", OnItemClick)
	button.sereneBag, button.sereneSlot = bag, slot
	win.buttons[bag][slot] = button
	return button
end

local function Cooldown(button, bag, slot)
	local frame = Region(button, "Cooldown")
	if not frame then return end
	local start, duration, enable = Safe(Container.GetContainerItemCooldown or _G.GetContainerItemCooldown, bag, slot)
	if _G.CooldownFrame_Set and Clean(start) and Clean(duration) then
		Safe(_G.CooldownFrame_Set, frame, start, duration, enable)
	elseif frame.SetCooldown then
		Safe(frame.SetCooldown, frame, start or 0, duration or 0)
	end
end

local function Glow(button, cell, live)
	local glow, at = button.sereneGlow, nil
	if live and cell and suggested then
		-- (the item "make room" suggests: a steady glow, till it is deleted or skipped)
		for _, entry in ipairs(cell.slots) do
			if entry.bag .. ":" .. entry.slot == suggested then
				button.sereneGlowAt = nil
				glow:SetAlpha(0.6)
				return
			end
		end
	end
	if live and cell then
		for _, entry in ipairs(cell.slots) do
			local key = entry.bag .. ":" .. entry.slot
			if not glowed[key] and C_NewItems and C_NewItems.IsNewItem and Clean(Safe(C_NewItems.IsNewItem, entry.bag, entry.slot)) then
				glowed[key], glowAt[key] = true, GetTime()
			end
			at = glowAt[key] or at
		end
	end
	button.sereneGlowAt = at
	if at then glowUntil = math.max(glowUntil, at + GLOW_TIME) end
	glow:SetAlpha(at and math.max(0, 1 - (GetTime() - at) / GLOW_TIME) or 0)
end

local function PaintLive(button, cell, freeCount)
	local entry = cell and cell.first
	SetIcon(button, entry and entry.icon or nil)
	SetCount(button, cell and cell.count or 0)
	if _G.SetItemButtonDesaturated then Safe(_G.SetItemButtonDesaturated, button, cell and cell.locked or false) end
	if button.SetHasItem then Safe(button.SetHasItem, button, entry and entry.icon or nil) end
	if button.sereneIcon then button.sereneIcon:SetAlpha(cell and cell.quality == 0 and JUNK_ALPHA or 1) end
	Edge(button, cell and cell.quality, cell and cell.quest)
	Cooldown(button, button.sereneBag, button.sereneSlot)
	Glow(button, cell, true)
	KeepDot(button, cell)
	button.sereneFree:SetText(freeCount and freeCount > 0 and freeCount or "")
	button.sereneCell = cell
end

-- Remembered cells: plain buttons -------------------------------------------------------------------------------------------

local function OfflineButton(win, index)
	local button = win.offline[index]
	if button then return button end
	button = CreateFrame("Button", nil, win)
	button:SetSize(SIZE, SIZE)
	button:RegisterForClicks("AnyUp")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.sereneIcon = icon
	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 4)
	count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	button.sereneCount = count
	local light = button:CreateTexture(nil, "HIGHLIGHT")
	light:SetAllPoints()
	light:SetColorTexture(1, 1, 1, 0.08)
	Decorate(button)
	button:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		Safe(GameTooltip.SetHyperlink, GameTooltip, self.link)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		if ns.HideTip then ns.HideTip() else GameTooltip:Hide() end
	end)
	button:SetScript("OnClick", OnItemClick)
	win.offline[index] = button
	return button
end

local function PaintOffline(button, cell)
	local entry = cell.first
	button.link, button.sereneCell = entry.link, cell
	button.sereneIcon:SetTexture(entry.icon)
	button.sereneIcon:SetAlpha(cell.quality == 0 and JUNK_ALPHA or 0.85)
	button.sereneCount:SetText(cell.count > 1 and cell.count or "")
	Edge(button, cell.quality, cell.quest)
	button.sereneGlow:SetAlpha(0)
	KeepDot(button, cell)
	button.sereneFree:SetText("")
end

-- A small menu (whose bags, an item's section) ---------------------------------------------------------------------------

local MENU_ROW, MENU_WIDTH = 20, 180
local menu
local menuLast = 0

local function MakeMenu()
	menu = CreateFrame("Frame", "SereneBagsMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	local ground = menu:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.94)
	local rule = menu:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	menu.rows = {}
	local edit = CreateFrame("EditBox", nil, menu)
	edit:SetAutoFocus(false)
	edit:SetFontObject("GameFontHighlightSmall")
	edit:SetHeight(MENU_ROW)
	edit:SetMaxLetters(32)
	edit:SetTextInsets(4, 4, 0, 0)
	local line = edit:CreateTexture(nil, "BACKGROUND")
	line:SetAllPoints()
	line:SetColorTexture(1, 1, 1, 0.06)
	edit.hint = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	edit.hint:SetPoint("LEFT", edit, "LEFT", 4, 0)
	edit.hint:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3])
	edit:SetScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() menu:Hide() end)
	edit:SetScript("OnEnterPressed", function(self)
		local text = strtrim(self:GetText() or "")
		self:ClearFocus()
		menu:Hide()
		if text ~= "" and self.done then self.done(text) end
	end)
	edit:Hide()
	menu.edit = edit
	menu:SetScript("OnUpdate", function(self)
		if self:IsMouseOver(4, -4, -4, 4) or edit:HasFocus() then menuLast = GetTime() return end
		if GetTime() - menuLast > 1.2 then self:Hide() end
	end)
	tinsert(UISpecialFrames, "SereneBagsMenu")
end

local function MenuRow(index)
	local row = menu.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, menu)
	row:SetSize(MENU_WIDTH - 16, MENU_ROW)
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.light = row:CreateTexture(nil, "BACKGROUND")
	row.light:SetAllPoints()
	row.light:SetColorTexture(SOFT[1], SOFT[2], SOFT[3], 0.06)
	row.light:Hide()
	row.knob = row:CreateTexture(nil, "ARTWORK")
	row.knob:SetTexture(MEDIA .. "Disc")
	row.knob:SetSize(7, 7)
	row.knob:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.knob:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	row:SetScript("OnEnter", function(self) if self.action then self.light:Show() end end)
	row:SetScript("OnLeave", function(self) self.light:Hide() end)
	row:SetScript("OnClick", function(self)
		if not self.action then return end
		menu:Hide()
		self.action()
	end)
	menu.rows[index] = row
	return row
end

-- rows: { text, action (nil: a title), on (a gold dot), muted, edit (a text field: called with the words) }
Menu = function(owner, rows)
	if not menu then MakeMenu() end
	if menu:IsShown() and menu.owner == owner then return menu:Hide() end
	if ns.HideTip then ns.HideTip() end
	menu.owner = owner
	menu.edit:Hide()
	local y = -8
	for index, spec in ipairs(rows) do
		local row = MenuRow(index)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
		if spec.edit then
			row:Hide()
			menu.edit:ClearAllPoints()
			menu.edit:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
			menu.edit:SetWidth(MENU_WIDTH - 16)
			menu.edit:SetText("")
			menu.edit.done = spec.edit
			menu.edit.hint:SetText(spec.text or "A new section...")
			menu.edit.hint:Show()
			menu.edit:Show()
		else
			row.text:SetText(spec.text)
			local color = spec.action and (spec.muted and MUTED_RGB or SOFT) or GOLD
			row.text:SetTextColor(color[1], color[2], color[3])
			row.knob:SetShown(spec.on and true or false)
			row.action = spec.action
			row:Show()
		end
		y = y - MENU_ROW
	end
	for index = #rows + 1, #menu.rows do menu.rows[index]:Hide() end
	menu:SetSize(MENU_WIDTH, -y + 8)
	menu:ClearAllPoints()
	local x, top = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, top / scale + 10)
	menuLast = GetTime()
	menu:Show()
end

-- Sections of your own: Alt-right-click an item ---------------------------------------------------------------------------

local function RefreshAll()
	if bags and bags:IsShown() then Refresh(bags) end
	if bank and bank:IsShown() then Refresh(bank) end
end

local function Pin(id, name)
	ns.db.bagPins[id] = name
	RefreshAll()
end

local function Keep(id, on)
	ns.db.bagKeep = ns.db.bagKeep or {}
	ns.db.bagKeep[id] = on and true or nil
	RefreshAll()
end

local function SectionMenu(owner, cell)
	local entry = cell.first
	local id = entry.id
	if not id then return end
	local pin = ns.db.bagPins[id]
	local rows = { { text = entry.name ~= "" and entry.name or "Item" } }
	for _, name in ipairs(ns.db.bagCats) do
		rows[#rows + 1] = { text = name, on = pin == name, action = function() Pin(id, name) end }
	end
	for _, name in ipairs(AUTO) do
		rows[#rows + 1] = { text = name, muted = true, on = pin == name, action = function() Pin(id, name) end }
	end
	rows[#rows + 1] = { text = "A section of your own...", edit = function(text)
		if IS_AUTO[text] then return Pin(id, text) end
		if not IsCustom(text) then table.insert(ns.db.bagCats, text) end
		Pin(id, text)
	end }
	if pin then
		rows[#rows + 1] = { text = "Back to its own section", muted = true, action = function() Pin(id, nil) end }
	end
	local kept = Kept(id)
	rows[#rows + 1] = { text = "Never suggest deleting", on = kept, action = function() Keep(id, not kept) end }
	Menu(owner, rows)
end

local function RemoveSection(name)
	for index, custom in ipairs(ns.db.bagCats) do
		if custom == name then table.remove(ns.db.bagCats, index) break end
	end
	for id, pin in pairs(ns.db.bagPins) do
		if pin == name then ns.db.bagPins[id] = nil end
	end
	RefreshAll()
end

OnItemClick = function(self, button)
	if button ~= "RightButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
	local cell = self.sereneCell
	if cell then SectionMenu(self, cell) end
end

-- The windows -------------------------------------------------------------------------------------------------------

local function Text(parent, font, color)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH("LEFT")
	if color then text:SetTextColor(color[1], color[2], color[3]) end
	return text
end

local function SavePosition(win)
	local key = win.kind == "bags" and "bagsPos" or "bankPos"
	if win.kind == "bags" then
		local right, bottom = win:GetRight(), win:GetBottom()
		if right and bottom then ns.db[key] = { x = right - UIParent:GetRight(), y = bottom } end
	else
		local left, top = win:GetLeft(), win:GetTop()
		if left and top then ns.db[key] = { x = left, y = top - UIParent:GetTop() } end
	end
end

-- The bank beside the bags (as a merchant's window), or where you put it.
local function BesideBags() return ns.db.bankAt ~= "free" end

local function Place(win)
	win:ClearAllPoints()
	local pos = ns.db[win.kind == "bags" and "bagsPos" or "bankPos"]
	local known = type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
	if win.kind == "bags" then
		win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", known and pos.x or -24, known and pos.y or 110)
	elseif BesideBags() and bags then
		-- (their feet level; a merchant's window already beside the bags: beside that one)
		local merchant = _G.SereneMerchant
		local beside = merchant and merchant:IsShown() and ns.AnchoredTo(merchant, bags) and merchant or bags
		win:SetPoint("BOTTOMRIGHT", beside, "BOTTOMLEFT", -10, 0)
	else
		win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", known and pos.x or 24, known and pos.y or -110)
	end
end

-- (Shift and drag, anywhere on the glass but the items: the window moves; the bank beside the bags: the bags move,
-- and it with them)
local function Drags(frame, win)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		if not IsShiftKeyDown() then return end
		local target = win
		if win.kind == "bank" and BesideBags() then
			if not (bags and bags:IsShown()) then return end
			target = bags
		end
		win.moving, target.moving, win.dragging = true, true, target
		if ns.HideTip then ns.HideTip() end
		target:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		if not win.moving then return end
		local target = win.dragging or win
		win.moving, target.moving, win.dragging = false, false, nil
		win.droppedAt, target.droppedAt = GetTime(), GetTime()
		target:StopMovingOrSizing()
		SavePosition(target)
		Place(target)
		if target ~= win then
			Refresh(target)
			Refresh(win)
		end
	end)
end

-- A word in the header or foot: muted, white under the mouse, a tooltip with what a click does.
local function Word(win, text, onClick, tip)
	local word = CreateFrame("Button", nil, win)
	word:SetHeight(18)
	word:RegisterForClicks("AnyUp")
	word.text = Text(word, "GameFontHighlightSmall", MUTED_RGB)
	word.text:SetPoint("CENTER")
	function word:SetWords(words)
		self.text:SetText(words)
		self:SetWidth(math.ceil(Clean(Safe(self.text.GetStringWidth, self.text)) or 30) + 6)
	end
	word:SetWords(text)
	word:SetScript("OnClick", function(self, button)
		if GetTime() - (win.droppedAt or 0) < 0.2 then return end -- (the end of a drag)
		onClick(self, button)
	end)
	word:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 1, 1)
		if tip and ns.ShowTip then
			ns.ShowTip(self, function(tooltip) tip(tooltip) end, "ANCHOR_TOP")
		end
	end)
	word:SetScript("OnLeave", function(self)
		self.text:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3])
		if ns.HideTip then ns.HideTip() end
	end)
	Drags(word, win)
	return word
end

local function SectionHeader(win, index)
	local header = win.headers[index]
	if header then return header end
	header = CreateFrame("Button", nil, win)
	header:SetHeight(SECTION)
	header:RegisterForClicks("RightButtonUp")
	header.text = Text(header, "GameFontNormalSmall", MUTED_RGB)
	header.text:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 4)
	header:SetScript("OnClick", function(self)
		if not self.custom then return end
		local name = self.name
		Menu(self, { { text = name }, { text = "Remove this section", action = function() RemoveSection(name) end } })
	end)
	Drags(header, win)
	win.headers[index] = header
	return header
end

local function Viewing(win)
	local _, me = Me()
	return win.viewing or me
end

local function IsLive(win)
	local _, me = Me()
	if Viewing(win) ~= me then return false end
	return win.kind == "bags" or bankLive
end

local function CharacterMenu(win, owner)
	local _, me = Me()
	local names = {}
	for name in pairs(Realm()) do
		if name ~= me then names[#names + 1] = name end
	end
	table.sort(names)
	table.insert(names, 1, me)
	local rows = { { text = win.kind == "bags" and "Whose bags" or "Whose bank" } }
	for _, name in ipairs(names) do
		local character = Realm()[name] or {}
		rows[#rows + 1] = { text = ClassHex(character.class) .. name .. "|r", on = Viewing(win) == name,
			action = function()
				win.viewing = name ~= me and name or nil
				Refresh(win)
			end }
	end
	Menu(owner, rows)
end

local OpenBank, ToggleRoom -- (below)

local function MakeWindow(kind)
	local win = CreateFrame("Frame", kind == "bags" and "SereneBags" or "SereneBank", UIParent)
	win.kind = kind
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:SetSize(PAD * 2 + SIZE, HEAD + FOOT)
	win:Hide()
	win.holders, win.buttons, win.offline, win.headers, win.slots = {}, {}, {}, {}, {}
	Drags(win, win)

	local ground = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS)
	local rule = win:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)

	-- the header: whose, and (bags) the bank; a quiet cross
	win.who = Word(win, "", function(self) CharacterMenu(win, self) end, function(tooltip)
		tooltip:AddLine(win.kind == "bags" and "Bags" or "Bank", SOFT[1], SOFT[2], SOFT[3])
		if ns.TipHint then
			ns.TipHint(tooltip, "Click: another character's")
			ns.TipHint(tooltip, "Shift and drag: move the window")
		end
	end)
	win.who.text:SetFontObject("GameFontNormal")
	win.who:SetPoint("TOPLEFT", win, "TOPLEFT", PAD - 3, -7)
	win.close = Word(win, "×", function() win:Hide() end)
	win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD + 3, -7)
	win.note = Text(win, "GameFontHighlightSmall", MUTED_RGB)
	win.note:SetPoint("LEFT", win.who, "RIGHT", 4, 0)
	if kind == "bags" then
		win.bankWord = Word(win, "bank", function() OpenBank(Viewing(win)) end, function(tooltip)
			tooltip:AddLine("Bank", SOFT[1], SOFT[2], SOFT[3])
			tooltip:AddLine(ns.MUTED .. "What is in it, as last seen at a banker|r", nil, nil, nil, true)
		end)
		win.bankWord:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
		-- (a row under the header, on demand: your bag slots)
		win.slotsWord = Word(win, "bags", function()
			win.showSlots = not win.showSlots
			Refresh(win)
		end, function(tooltip)
			tooltip:AddLine("Your bag slots", SOFT[1], SOFT[2], SOFT[3])
			tooltip:AddLine(ns.MUTED .. "Put on a bag, swap one, take one off|r", nil, nil, nil, true)
		end)
		win.slotsWord:SetPoint("RIGHT", win.bankWord, "LEFT", -8, 0)
		-- (the cheapest item, to delete for room)
		win.roomWord = Word(win, "make room", function() ToggleRoom() end, function(tooltip)
			tooltip:AddLine("Make room", SOFT[1], SOFT[2], SOFT[3])
			tooltip:AddLine(ns.MUTED .. "The cheapest item in your bags, by what a vendor pays: delete it, or skip it "
				.. "for the next|r", nil, nil, nil, true)
		end)
		win.roomWord:SetPoint("RIGHT", win.slotsWord, "LEFT", -8, 0)
	else
		-- (a row under the header, on demand: the bank's tabs, or bag slots, and buying one more)
		win.tabsWord = Word(win, "tabs", function()
			win.showTabs = not win.showTabs
			Refresh(win)
		end, function(tooltip)
			if win.bankBags then
				tooltip:AddLine("The bank's bag slots", SOFT[1], SOFT[2], SOFT[3])
				tooltip:AddLine(ns.MUTED .. "Put on a bag, swap one, take one off, buy one more|r", nil, nil, nil, true)
			elseif win.tabBags then
				tooltip:AddLine("The bank's tabs and their bags", SOFT[1], SOFT[2], SOFT[3])
				tooltip:AddLine(ns.MUTED .. "Put a bag in a tab, swap one, take one off, buy one more|r", nil, nil, nil, true)
			else
				tooltip:AddLine("The bank's tabs", SOFT[1], SOFT[2], SOFT[3])
				tooltip:AddLine(ns.MUTED .. "How full each is, and buying one more|r", nil, nil, nil, true)
			end
		end)
		win.tabsWord:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
		win.tabsText = Text(win, "GameFontHighlightSmall", MUTED_RGB)
		win.tabsText:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -HEAD - 4)
		win.buyWord = Word(win, "", function() if win.buy then win.buy() end end, function(tooltip)
			tooltip:AddLine(win.buyTip or "", SOFT[1], SOFT[2], SOFT[3])
			tooltip:AddLine(ns.MUTED .. "Opens the game's own bank page for it|r", nil, nil, nil, true)
		end)
		win.buyWord:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD + 3, -HEAD - 1)
	end
	win.empty = Text(win, "GameFontHighlightSmall", MUTED_RGB)

	-- the foot: free room, and money
	win.freeText = Text(win, "GameFontHighlightSmall", MUTED_RGB)
	win.money = Text(win, "GameFontHighlightSmall", SOFT)
	win.money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, PAD + 10)
	win.ghost = CreateFrame("Frame", nil, win) -- (the free cell, remembered: nothing to drop on)
	win.ghost:SetSize(SIZE, SIZE)
	win.ghost:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, PAD)
	local ghostGround = win.ghost:CreateTexture(nil, "BACKGROUND")
	ghostGround:SetAllPoints()
	ghostGround:SetColorTexture(1, 1, 1, 0.045)
	win.ghost.text = Text(win.ghost, "GameFontHighlightSmall", MUTED_RGB)
	win.ghost.text:SetPoint("CENTER")

	-- (new items glow a moment)
	win:SetScript("OnUpdate", function(self)
		local now = GetTime()
		if now > glowUntil + 0.1 then return end
		for _, row in pairs(self.buttons) do
			for _, button in pairs(row) do
				local at = button.sereneGlowAt
				if at then
					local alpha = 1 - (now - at) / GLOW_TIME
					button.sereneGlow:SetAlpha(math.max(0, alpha))
					if alpha <= 0 then button.sereneGlowAt = nil end
				end
			end
		end
	end)
	tinsert(UISpecialFrames, win:GetName())
	Place(win)
	return win
end

-- The bag slots row --------------------------------------------------------------------------------------------------------

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
local function SlotsHover(win)
	for _, button in ipairs(win.slots) do
		if button.slot and button:IsShown() and ns.Over(button) then
			return button:GetScript("OnEnter")(button)
		end
	end
	Spotlight(win, nil)
end

-- The bags' row: shown with "bags", for your own bags at hand.
local function SlotsRow(win, live)
	win.rowHeight = 0
	win.slotsWord:SetShown(live)
	win.slotsWord:SetWords(win.showSlots and live and "|cffffd100bags|r" or "bags")
	if not (live and win.showSlots) then return HideSlots(win) end
	PlaceSlots(win, BagSlots())
	win.rowHeight = SLOTS_ROW
end

-- Making room: the cheapest item, to delete -------------------------------------------------------------------------------
-- "make room" at the top: a small glass above the bags with the stack worth least at a vendor. Skip: the next
-- cheapest (that item is kept till the glass closes). Delete: gone, and the glass closes. Items a vendor won't buy
-- (a hearthstone, quest items...), locked ones and the keyring are never suggested.

local PickupItem = Container.PickupContainerItem or _G.PickupContainerItem
local ROOM_WIDTH = 280
local room                 -- the glass
local skipped = {}         -- itemID -> true: kept, while the glass is open

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
	if not now or now.link ~= entry.link or now.count ~= entry.count or now.locked then return Refresh(bags) end
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
	Refresh(bags)
end

local function Skip()
	local entry = room and room.entry
	if entry then skipped[entry.id] = true end
	Refresh(bags)
end

local function KeepIt()
	local entry = room and room.entry
	if not entry then return end
	ns.Print(("bags: %s won't be suggested again (Alt-right-click it to undo)."):format(entry.link or entry.name or "it"))
	Keep(entry.id, true)
end

local function MakeRoom()
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
	Refresh(bags)
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

-- Laying out ------------------------------------------------------------------------------------------------------------

local function Columns()
	return math.max(4, math.min(24, math.floor(tonumber(ns.db.bagColumns) or 10)))
end

local function SpecialWords(special)
	local words = {}
	for kind, count in pairs(special or {}) do words[#words + 1] = kind .. " " .. count end
	table.sort(words)
	return table.concat(words, "  ·  ")
end

local function Layout(win, sections, live, free, special, character)
	local columns = Columns()
	local width = PAD * 2 + columns * SIZE + (columns - 1) * GAP
	local used = {}
	local y = -HEAD - (win.rowHeight or 0)
	local headerIndex, offlineIndex = 0, 0
	for _, section in ipairs(sections) do
		headerIndex = headerIndex + 1
		local header = SectionHeader(win, headerIndex)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
		header:SetWidth(width - PAD * 2)
		header.text:SetText(section.name:upper())
		local color = section.custom and SOFT or MUTED_RGB
		header.text:SetTextColor(color[1], color[2], color[3])
		header.name, header.custom = section.name, section.custom
		header:Show()
		y = y - SECTION
		for index, cell in ipairs(section.cells) do
			local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
			local button
			if live then
				button = LiveButton(win, cell.live.bag, cell.live.slot)
				if button then PaintLive(button, cell) end
			else
				offlineIndex = offlineIndex + 1
				button = OfflineButton(win, offlineIndex)
				PaintOffline(button, cell)
			end
			if button then
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + column * (SIZE + GAP), y - row * (SIZE + GAP))
				button:Show()
				used[button] = true
			end
		end
		y = y - math.ceil(#section.cells / columns) * (SIZE + GAP) + GAP - SECTION_GAP
	end
	for index = headerIndex + 1, #win.headers do win.headers[index]:Hide() end

	-- nothing to show
	win.empty:Hide()
	if not sections[1] then
		win.empty:ClearAllPoints()
		win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y - 4)
		win.empty:SetWidth(width - PAD * 2)
		win.empty:SetText(character == false and "Not seen yet: visit a banker once." or "Empty.")
		win.empty:Show()
		y = y - 24
	end

	-- the foot: the free cell (the game's own, to drop an item on), the free room in special bags, money
	local freeButton = live and free.bag and LiveButton(win, free.bag, free.slot)
	if freeButton then
		PaintLive(freeButton, nil, free.count)
		freeButton:ClearAllPoints()
		freeButton:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, PAD)
		freeButton:Show()
		used[freeButton] = true
		win.ghost:Hide()
	else
		win.ghost.text:SetText(free.count > 0 and free.count or "")
		win.ghost:Show()
	end
	local words = (free.count or 0) .. " free"
	local specials = SpecialWords(special)
	if specials ~= "" then words = words .. "   " .. specials end
	win.freeText:ClearAllPoints()
	win.freeText:SetPoint("LEFT", win, "BOTTOMLEFT", PAD + SIZE + 8, PAD + SIZE / 2)
	win.freeText:SetText(words)
	win.money:ClearAllPoints()
	win.money:SetPoint("RIGHT", win, "BOTTOMRIGHT", -PAD, PAD + SIZE / 2)
	win.money:SetText(win.kind == "bags" and Money(character and character.money) or "")

	-- what is not shown now
	for _, row in pairs(win.buttons) do
		for _, button in pairs(row) do
			if not used[button] then
				button:Hide()
				button.sereneCell = nil
			end
		end
	end
	for index = offlineIndex + 1, #win.offline do
		win.offline[index]:Hide()
		win.offline[index].sereneCell = nil
	end
	win:SetSize(width, -y + FOOT)
end

-- The bank's tabs row: how full each is, and one more to buy (on the game's own page: its confirmation, its price).
-- A bank with bag slots: the slots instead (the next to buy among them).
local function TabsRow(win, live)
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
			cost = type(data) == "table" and Clean(data.tabCost or data.cost) or nil
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
		win.buy = function()
			local frame = _G.BankFrame
			if not frame then return end
			revealing = true
			frame:SetParent(UIParent)
			win:Hide()
		end
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

Refresh = function(win)
	if not win or not win:IsShown() then return end
	if win.moving then return end
	local live = IsLive(win)
	if live and protectedButtons and InCombatLockdown() then win.pending = true return end
	win.pending = false
	local where = win.kind == "bags" and "bags" or "bank"
	local entries, free, special, character
	if live then
		entries, free, special = Scan(win.kind == "bags" and BagIDs() or BankIDs())
		Remember(where, entries, free, special)
		character = Mine()
	else
		entries, free, special, character = Remembered(Viewing(win), where)
		if not entries then entries, free, special, character = {}, { count = 0 }, {}, false end
	end
	local name = Viewing(win)
	win.who:SetWords(ClassHex(character and character.class) .. name .. "|r")
	local notes = {}
	if win.kind == "bank" then notes[#notes + 1] = "bank" end
	if not live and character then
		local ago = Ago(character[where .. "At"])
		if ago then notes[#notes + 1] = ago end
	end
	win.note:SetText(notes[1] and ("·  " .. table.concat(notes, "  ·  ")) or "")
	if win.bankWord then
		win.bankWord:SetWords((bank and bank:IsShown()) and "|cffffd100bank|r" or "bank")
	end
	if win.kind == "bank" then TabsRow(win, live) else SlotsRow(win, live) end
	Suggest(win, live)
	Layout(win, Sections(entries), live, free, special, character)
	SlotsHover(win)
end

-- The bank: open from anywhere (remembered), or at a banker (live).
OpenBank = function(name)
	if not bank then return end
	local _, me = Me()
	if bank:IsShown() and Viewing(bank) == (name or me) then return bank:Hide() end
	bank.viewing = (name and name ~= me) and name or nil
	bank:Show()
	Refresh(bank)
	if bags and bags:IsShown() then Refresh(bags) end
end

-- The game's windows, out of sight and followed ------------------------------------------------------------------------

local function GameBagFrames()
	local list = {}
	if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
	for index = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. index]
		if frame then list[#list + 1] = frame end
	end
	return list
end

local function GameBagsOpen()
	for _, frame in ipairs(GameBagFrames()) do
		if Clean(Safe(frame.IsShown, frame)) then return true end
	end
	return false
end

-- Serene's bags open while the game's are (B, the bag buttons, merchants and the bank open and close those).
local function Sync()
	if syncing or not bags then return end
	local open = GameBagsOpen()
	if open ~= (bags:IsShown() and true or false) then bags:SetShown(open) end
end

local function CloseBankInteraction()
	if C_Bank and C_Bank.CloseBankFrame then return Safe(C_Bank.CloseBankFrame) end
	if C_PlayerInteractionManager and C_PlayerInteractionManager.ClearInteraction and Enum.PlayerInteractionType then
		return Safe(C_PlayerInteractionManager.ClearInteraction, Enum.PlayerInteractionType.Banker)
	end
	if _G.CloseBankFrame then Safe(_G.CloseBankFrame) end
end

local function HideGameWindows()
	hidden = CreateFrame("Frame", nil, UIParent)
	hidden:Hide()
	for _, frame in ipairs(GameBagFrames()) do frame:SetParent(hidden) end
	if _G.BankFrame then _G.BankFrame:SetParent(hidden) end
	for _, name in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
		"ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, Sync) end
	end
	for _, frame in ipairs(GameBagFrames()) do
		hooksecurefunc(frame, "Show", Sync)
		hooksecurefunc(frame, "Hide", Sync)
	end
end

-- Counts in item tooltips -------------------------------------------------------------------------------------------------

local function Index()
	if countsIndex then return countsIndex end
	countsIndex = {}
	for name, character in pairs(Realm()) do
		for _, where in ipairs({ "bags", "bank" }) do
			for _, item in ipairs(type(character[where]) == "table" and character[where] or {}) do
				local id = IdOf(item[1])
				if id then
					countsIndex[id] = countsIndex[id] or {}
					local counts = countsIndex[id][name] or { bags = 0, bank = 0 }
					countsIndex[id][name] = counts
					counts[where] = counts[where] + (item[2] or 1)
				end
			end
		end
	end
	return countsIndex
end

local function CountWords(counts)
	local words = {}
	if counts.bags > 0 then words[#words + 1] = "bags " .. counts.bags end
	if counts.bank > 0 then words[#words + 1] = "bank " .. counts.bank end
	return table.concat(words, "  ·  ")
end

local function OnItemTooltip(tooltip, data)
	if not ns.On("bags") or not ns.On("bagCounts") then return end
	if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
	local id = type(data) == "table" and Clean(data.id)
	if type(id) ~= "number" then
		local _, link = Safe(tooltip.GetItem, tooltip)
		id = IdOf(Clean(link))
	end
	local holders = id and Index()[id]
	if not holders then return end
	local _, me = Me()
	local others = {}
	for name in pairs(holders) do
		if name ~= me then others[#others + 1] = name end
	end
	local mine = holders[me]
	-- (only what you would not see anyway: the bank, or your other characters)
	if not others[1] and not (mine and mine.bank > 0) then return end
	table.sort(others)
	if mine then table.insert(others, 1, me) end
	tooltip:AddLine(" ")
	for _, name in ipairs(others) do
		local character = Realm()[name] or {}
		tooltip:AddDoubleLine(ClassHex(character.class) .. name .. "|r", ns.MUTED .. CountWords(holders[name]) .. "|r")
	end
	if (tonumber(Clean(tooltip.shownMoneyFrames)) or 0) == 0 then tooltip:Show() end
end

local function HookTooltips()
	local processor = _G.TooltipDataProcessor
	local types = Enum and Enum.TooltipDataType
	if processor and processor.AddTooltipPostCall and types and types.Item then
		pcall(processor.AddTooltipPostCall, types.Item, OnItemTooltip)
		return
	end
	for _, tooltip in ipairs({ GameTooltip, _G.ItemRefTooltip }) do
		if tooltip and tooltip.HasScript and Safe(tooltip.HasScript, tooltip, "OnTooltipSetItem") then
			tooltip:HookScript("OnTooltipSetItem", function(self) OnItemTooltip(self) end)
		end
	end
end

-- Events -------------------------------------------------------------------------------------------------------------------

local dirty = {}
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
	self:Hide()
	for win in pairs(dirty) do
		dirty[win] = nil
		if win:IsShown() then
			Refresh(win)
		elseif win == bags then
			-- (closed: still remembered)
			local entries, free, special = Scan(BagIDs())
			Remember("bags", entries, free, special)
		end
	end
end)

local function Dirty(win)
	if not win then return end
	dirty[win] = true
	ticker:Show()
end

local function OnEvent(_, event)
	if event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" or event == "BAG_NEW_ITEMS_UPDATED"
		or event == "BAG_CONTAINER_UPDATE" then
		Dirty(bags)
		if bankLive then Dirty(bank) end
	elseif event == "BAG_UPDATE_COOLDOWN" then
		if bags:IsShown() then Dirty(bags) end
	elseif event == "PLAYER_MONEY" then
		Mine()
		if bags:IsShown() then Dirty(bags) end
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" or event == "BANK_TABS_CHANGED"
		or event == "BANK_TAB_SETTINGS_UPDATED" or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
		if bankLive then Dirty(bank) end
	elseif event == "BANKFRAME_OPENED" then
		bankLive = true
		bank.viewing = nil
		bank:Show()
		Dirty(bank)
		-- (the game's bank, out of sight, does not open the bags itself)
		if not GameBagsOpen() and _G.OpenAllBags then
			Safe(_G.OpenAllBags)
			bagsByBank = true
		end
		Sync()
	elseif event == "BANKFRAME_CLOSED" then
		bankLive = false
		if revealing then
			revealing = false
			if _G.BankFrame and hidden then _G.BankFrame:SetParent(hidden) end
		end
		if bank:IsShown() and not bank.viewing then bank:Hide() end
		if bagsByBank and bags:IsShown() then bags:Hide() end
		bagsByBank = false
	elseif event == "PLAYER_REGEN_ENABLED" then
		if bags.pending then Dirty(bags) end
		if bank.pending then Dirty(bank) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		Dirty(bags)
	end
end

local function Init()
	if not ns.On("bags") then return end
	bags = MakeWindow("bags")
	bank = MakeWindow("bank")
	bags:SetScript("OnShow", function(self)
		if not self.viewing and BagsFull() then
			if not room then MakeRoom() end
			room:Show()
		end
		Refresh(self)
	end)
	bags:SetScript("OnHide", function()
		if menu then menu:Hide() end
		if room then room:Hide() end
		-- (what glowed has been seen)
		if C_NewItems and C_NewItems.RemoveNewItem then
			for key in pairs(glowed) do
				local bag, slot = key:match("^(-?%d+):(%d+)$")
				Safe(C_NewItems.RemoveNewItem, tonumber(bag), tonumber(slot))
			end
		end
		glowed, glowAt = {}, {}
		bags.viewing = nil
		bagsByBank = false
		-- (closed here: the game's closed too, so the next B opens them again)
		if GameBagsOpen() and _G.CloseAllBags then
			syncing = true
			Safe(_G.CloseAllBags)
			syncing = false
		end
	end)
	bank:SetScript("OnShow", function(self) Place(self) end)
	bank:SetScript("OnHide", function()
		if menu then menu:Hide() end
		if ns.PlaceMerchant then ns.PlaceMerchant() end -- (beside the bank: now beside the bags)
		if bankLive and not revealing and not bank.viewing then CloseBankInteraction() end
		bank.viewing = nil
		if bags:IsShown() then Dirty(bags) end
	end)
	HideGameWindows()
	HookTooltips()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "BAG_NEW_ITEMS_UPDATED",
		"PLAYER_MONEY", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "BANK_TABS_CHANGED",
		"BANK_TAB_SETTINGS_UPDATED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_REGEN_ENABLED",
		"PLAYER_ENTERING_WORLD", "BAG_CONTAINER_UPDATE", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", OnEvent)
	Dirty(bags)
	-- (the game's bag window is now out of sight: addons that move or change it have nothing left to do)
	if not ns.db.bagsNoted then
		local others = {}
		for _, addon in ipairs({ "TheBag", "ForeverCombinedReagentBag" }) do
			local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
			if loaded and Clean(Safe(loaded, addon)) then others[#others + 1] = addon end
		end
		if others[1] then
			ns.Print("bags: " .. table.concat(others, " and ") .. " change the game's bag window, which Serene's bags "
				.. "now keep out of sight: you can switch them off.")
		end
		ns.db.bagsNoted = true
	end
end

local function OnRefresh()
	if not bags then return end
	if bank:IsShown() then Place(bank) end
	RefreshAll()
end

-- (the merchant's window, beside the bags, opened or closed: the bank beside it, or beside the bags again)
function ns.PlaceBank()
	if bank and bank:IsShown() and not bank.moving then Place(bank) end
end

function ns.BagsDebug()
	if not bags then return ns.Print("bags: off") end
	ns.Print(("bags: shown %s, game's open %s, protected buttons %s, bank live %s, buttons made %d"):format(
		tostring(bags:IsShown()), tostring(GameBagsOpen()), tostring(protectedButtons), tostring(bankLive), made))
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

ns.BagsSections = Sections -- (tests)

table.insert(ns.modules, { init = Init, refresh = OnRefresh })
