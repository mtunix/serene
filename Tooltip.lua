local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Calm tooltips.                                                           (/serene tooltip on|off, tipcalm on|off)
-- * Glass: the game's frame and border gone, a dark pane like the chat's behind the words, a faint hairline on top;
--   the health bar under a unit a thin, dim line. What is shown as an icon (an item, a spell, a buff or debuff) is in
--   a hairline of the game's gold all round instead.
-- * A soft arrival: a tooltip fades in instead of popping up. Over the action bars, the menu and the bags it waits a
--   moment first, so the mouse passing over a row of buttons brings nothing.
-- * Quiet colours: the first line keeps its colour (an item's quality, a class, friend or foe); the other white
--   lines turn warm white, the game's yellow a muted gold; a unit's faction and PvP lines grey, "(Player)" dropped.
-- * How-to lines (Serene's "Click: ...", Alt-click at merchants) only with Shift held, or after a moment.
-- * Item comparison only with Shift (the game's setting, given back when this is switched off).
-- * In a fight (tipcalm): the tooltips of the world (units, objects) and of the action bars wait; Shift or the key
--   "show the whole interface" shows them. Enemies, chat links, your portrait, your bags still show.
-- * What addons add under an item (prices, recipes, sources...) waits for Shift (tipmore): the tooltip ends after
--   the game's own lines, a small "Shift" in its corner.
-- * An item's vendor price (tipvendor), for the whole stack, where the game shows none; kept above the Shift cut,
--   like the game's own sell price line.
-- * A player as a card (tipcard): their race in a round icon, ringed blue (Alliance) or red (Horde), their class in a
--   small badge on it; beside it the name in its class colour and the level, under it the guild. Shift: the words.
-- Only opacities, colours, sizes and words change, on the game's own tooltips: nothing of the game's code is replaced.

local FADE_IN = 0.12        -- seconds for a tooltip to come
local BUTTON_WAIT = 0.25    -- seconds over a bar's or the menu's button before its tooltip comes
local HINT_AFTER = 1.2      -- seconds before the how-to lines come on their own
local GRACE = 0.3           -- seconds after a tooltip went in which the next one comes at once (no fade, no wait):
                            -- moving along a list, or a list refreshing its tooltip (the auction house)
local GLASS = 0.82          -- the pane's darkness
local HAIR = 0.07           -- the hairline on top
local BAR_HEIGHT, BAR_ALPHA = 2, 0.55
local QUIET_GOLD = { 0.84, 0.74, 0.48 }
local INK, SOFT_RGB, MUTED_RGB = ns.INK, ns.SOFT_RGB, ns.MUTED_RGB
local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local RIGHT_GAP = 16        -- room between a line's left and right words
local CUE_ROOM = 10         -- room at the bottom for the "Shift" in the corner
local RACE_SIZE, CLASS_SIZE = 30, 18
local CLASS_OUT = 5         -- how far the class badge reaches beyond the race icon (right, and down)
local CARD_GAP = 9          -- room between the icons and the words
local FACTION_RING = { Alliance = { 0.28, 0.55, 1 }, Horde = { 0.92, 0.2, 0.16 } }
local NEUTRAL_RING = { 0.6, 0.6, 0.6 }

-- (the tooltips of what is shown as an icon: in a hairline of gold. Names missing on this client are skipped.)
local ICON_KINDS = { "Item", "Spell", "UnitAura", "Macro", "PetAction", "Totem", "Toy", "Mount" }
local SIDES = { "top", "bottom", "left", "right" }

local STYLED = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1",
	"ItemRefShoppingTooltip2" }
local styled = {} -- tooltip -> true

-- Buttons whose tooltips wait a moment (and, in a fight, for Shift: the action bars only).
local ACTION_NAMES = { "^ActionButton%d", "^MultiBar", "^PetActionButton%d", "^StanceButton%d", "^ShapeshiftButton%d",
	"^PossessButton%d", "^OverrideActionBarButton%d", "^BT4Button", "^BT4PetButton", "^BT4StanceButton",
	"^DominosActionButton", "^ElvUI_Bar" }
local MENU_NAMES = { "MicroButton$", "^CharacterBag%dSlot", "^MainMenuBarBackpackButton", "^KeyRingButton",
	"^BagBarExpandToggle" }

local tip = GameTooltip
local fighting = false
local state = {
	owner = nil,     -- the frame the tooltip is shown for (nil: none, the next one comes fresh)
	since = 0,       -- when it came
	wait = 0,        -- seconds it waits before fading in
	alpha = 1,       -- its opacity while Serene drives it
	fading = false,  -- Serene drives its opacity (coming, or waiting)
	world = false,   -- a unit or an object in the world
	action = false,  -- an action bar's button
	redo = nil,      -- builds it again (with its how-to lines)
	pending = false, -- a how-to line is waiting
	hinted = false,  -- the how-to lines are shown now
	redoing = false, -- (being built again: a hide in between is not a leave)
	goneAt = -math.huge, -- when the last fully seen tooltip went
}

local function Named(frame, patterns)
	local name = type(frame) == "table" and frame.GetName and Clean(Safe(frame.GetName, frame))
	if type(name) ~= "string" then return false end
	for _, pattern in ipairs(patterns) do
		if name:find(pattern) then return true end
	end
	return false
end

-- The look -------------------------------------------------------------------------------------------------------

-- An icon's tooltip in a hairline of the game's gold, which takes the faint line's place on top.
local function Rim(tooltip, on)
	local rim = tooltip.sereneRim
	if not rim then return end
	on = on and ns.On("tooltip") or false
	rim.on = on
	if on then rim:Fit() end -- (one pixel at the tooltip's own scale, which the game changes for some owners)
	for _, side in ipairs(SIDES) do rim[side]:SetShown(on) end
	tooltip.sereneHair:SetShown(ns.On("tooltip") and not on)
end

local function Dress(tooltip, on)
	if type(tooltip) ~= "table" or not tooltip.CreateTexture then return end
	if on and not tooltip.sereneGlass then
		local glass = tooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
		glass:SetAllPoints(tooltip)
		glass:SetColorTexture(INK[1], INK[2], INK[3], GLASS)
		local hair = tooltip:CreateTexture(nil, "BACKGROUND", nil, -7)
		hair:SetHeight(1)
		hair:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 0, 0)
		hair:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", 0, 0)
		hair:SetColorTexture(1, 1, 1, HAIR)
		local rim = ns.Hairline(tooltip, ns.LINE, "BORDER")
		for _, side in ipairs(SIDES) do rim[side]:Hide() end
		tooltip.sereneGlass, tooltip.sereneHair, tooltip.sereneRim = glass, hair, rim
	end
	if tooltip.sereneGlass then
		tooltip.sereneGlass:SetShown(on)
		tooltip.sereneHair:SetShown(on and not tooltip.sereneRim.on)
		if not on then Rim(tooltip, false) end
	end
	local nine = tooltip.NineSlice
	if type(nine) == "table" and nine.SetAlpha then
		pcall(nine.SetAlpha, nine, on and 0 or 1)
	elseif tooltip.SetBackdropColor then
		-- (an older tooltip with a backdrop: the game sets its colours again on each hide)
		if on then
			pcall(tooltip.SetBackdropColor, tooltip, 0, 0, 0, 0)
			pcall(tooltip.SetBackdropBorderColor, tooltip, 0, 0, 0, 0)
		else
			local back, edge = _G.TOOLTIP_DEFAULT_BACKGROUND_COLOR, _G.TOOLTIP_DEFAULT_COLOR
			if back then pcall(tooltip.SetBackdropColor, tooltip, back.r, back.g, back.b) end
			if edge then pcall(tooltip.SetBackdropBorderColor, tooltip, edge.r, edge.g, edge.b) end
		end
	end
end

-- The health bar under a unit: a thin, dim line.
local function Bar(on)
	local bar = _G.GameTooltipStatusBar
	if type(bar) ~= "table" or not bar.SetHeight then return end
	-- (the game's height, given back when switched off)
	if not bar.sereneHeight then bar.sereneHeight = Clean(Safe(bar.GetHeight, bar)) or 8 end
	pcall(bar.SetHeight, bar, on and BAR_HEIGHT or bar.sereneHeight)
	pcall(bar.SetAlpha, bar, on and BAR_ALPHA or 1)
end

-- Item comparison only with Shift: the game's setting turned off once, given back when this is switched off (turned
-- on again in the game's options meanwhile, it stays on).
local function GetSetting(name)
	local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
	return get and Clean(Safe(get, name))
end

local function SetSetting(name, value)
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	if set then Safe(set, name, value) end
end

local function Compare(on)
	local db = ns.db
	if on and not db.tipCompareDone then
		if GetSetting("alwaysCompareItems") == "1" then
			db.tipCompare = "1"
			SetSetting("alwaysCompareItems", "0")
		end
		db.tipCompareDone = true
	elseif not on and db.tipCompareDone then
		if db.tipCompare then SetSetting("alwaysCompareItems", db.tipCompare) end
		db.tipCompare, db.tipCompareDone = nil, nil
	end
end

-- Quiet colours ----------------------------------------------------------------------------------------------------

local function Line(tooltip, side, index)
	local name = Clean(Safe(tooltip.GetName, tooltip))
	return name and _G[name .. "Text" .. side .. index]
end

local function Hush(line)
	if type(line) ~= "table" or not line.GetTextColor then return end
	local r, g, b = Safe(line.GetTextColor, line)
	r, g, b = Clean(r), Clean(g), Clean(b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
	-- (white, and the game's yellow, 1 0.82 0: the near matches allow for rounding)
	if r > 0.97 and g > 0.97 and b > 0.97 then
		line:SetTextColor(SOFT_RGB[1], SOFT_RGB[2], SOFT_RGB[3])
	elseif r > 0.97 and math.abs(g - 0.82) < 0.04 and b < 0.05 then
		line:SetTextColor(QUIET_GOLD[1], QUIET_GOLD[2], QUIET_GOLD[3])
	end
end

-- A unit's lines nobody reads: grey.
local noise
local function Noise()
	if noise then return noise end
	noise = {}
	for _, key in ipairs({ "PVP", "FACTION_ALLIANCE", "FACTION_HORDE" }) do
		local text = _G[key]
		if type(text) == "string" and text ~= "" then noise[text] = true end
	end
	return noise
end

-- (" (Player)" in the client's language, its pattern characters escaped)
local PLAYER_MARK = type(_G.PLAYER) == "string" and _G.PLAYER ~= ""
	and ("%s*%(" .. _G.PLAYER:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "%)")

local function HushUnit(tooltip)
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	for index = 2, count do
		local line = Line(tooltip, "Left", index)
		local text = line and Clean(Safe(line.GetText, line))
		if type(text) == "string" then
			if Noise()[text] then
				line:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3])
			elseif PLAYER_MARK and text:find(PLAYER_MARK) then
				line:SetText((text:gsub(PLAYER_MARK, "")))
			end
		end
	end
end

local function Hushed(tooltip, unit)
	if not (ns.On("tooltip") and styled[tooltip]) then return end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	for index = 2, count do
		Hush(Line(tooltip, "Left", index))
		Hush(Line(tooltip, "Right", index))
	end
	if unit then HushUnit(tooltip) end
end

-- Shorter: lines kept, lines waiting for Shift ------------------------------------------------------------------
-- A tooltip cut short keeps its first lines; the others are only made unseen, and the tooltip ends (and narrows)
-- after the last one kept. Shift (or the key), and they are back: the game draws the tooltip whole again.
--   item    the game's own lines kept; the addons' after them wait
--   player  the card's two rows kept; its third row (the words) and the addons' lines, moved up under it, wait

local CUT = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
local cuttable = {} -- tooltip -> true
local cuts = {}     -- tooltip -> { kind, keep, filled, total, touched, more, n, height }

local function More()
	return (IsShiftKeyDown() or (ns.IsPeeking and ns.IsPeeking())) and true or false
end

local function Fade(region, alpha)
	if type(region) == "table" and region.SetAlpha then pcall(region.SetAlpha, region, alpha) end
end

local function Number(region, method)
	if type(region) ~= "table" or not region[method] then return nil end
	local value = Clean(Safe(region[method], region))
	return type(value) == "number" and value or nil
end

local function Words(region)
	if type(region) ~= "table" or not region.GetText then return nil end
	if region.IsShown and not Safe(region.IsShown, region) then return nil end
	local text = Clean(Safe(region.GetText, region))
	return type(text) == "string" and text ~= "" and text or nil
end

-- (a line's width: its words, or the width the game gave it to wrap in)
local function Width(region)
	local words, given = Number(region, "GetStringWidth") or 0, Number(region, "GetWidth") or 0
	return (given > 0 and given < words) and given or words
end

-- What else hangs on a tooltip's lines: coins, icons.
local function Extras(tooltip)
	local list = {}
	local name = Clean(Safe(tooltip.GetName, tooltip))
	if not name then return list end
	for _, kind in ipairs({ "MoneyFrame", "Texture" }) do
		for index = 1, 40 do -- (numbered from 1 with no gaps: the first missing ends the list)
			local region = _G[name .. kind .. index]
			if not region then break end
			list[#list + 1] = region
		end
	end
	return list
end

local function Cue(tooltip)
	if not tooltip.sereneCue then
		local cue = tooltip:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		cue:SetText("Shift")
		cue:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3], 0.8)
		cue:Hide()
		tooltip.sereneCue = cue
	end
	return tooltip.sereneCue
end

-- The tooltip ends after line `last` (and the cue, if any), as narrow as its words allow. False: it could not be
-- measured (not anchored yet: the comparison tooltips, between being filled and placed).
local function Fit(tooltip, last, cue, keptExtra, floor)
	local first, final = Line(tooltip, "Left", 1), Line(tooltip, "Left", last)
	local top, left, right = Number(tooltip, "GetTop"), Number(tooltip, "GetLeft"), Number(tooltip, "GetRight")
	local firstTop, firstLeft = Number(first, "GetTop"), Number(first, "GetLeft")
	local bottom = Number(final, "GetBottom")
	if not (top and left and right and firstTop and firstLeft and bottom) then return false end
	if floor and floor < bottom then bottom = floor end
	local padY, padX = top - firstTop, firstLeft - left
	pcall(tooltip.SetHeight, tooltip, top - bottom + padY + (cue and CUE_ROOM or 0))
	if cue then
		cue:ClearAllPoints()
		cue:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", -padX, 5)
	end
	-- (coins or an icon kept beside the words: the width left as the game made it)
	if keptExtra then return true end
	local widest = cue and Width(cue) or 0
	for index = 1, last do
		local line, other = Line(tooltip, "Left", index), Line(tooltip, "Right", index)
		local width = Width(line) + ((Number(line, "GetLeft") or firstLeft) - firstLeft)
		if Words(other) then width = width + RIGHT_GAP + Width(other) end
		widest = math.max(widest, width)
	end
	local old = right - left
	local width = math.ceil(widest + padX * 2)
	if width >= old - 1 then return true end
	pcall(tooltip.SetWidth, tooltip, width)
	-- (words the game placed for the old width, beyond the new edge: the old width back)
	local edge = Number(tooltip, "GetRight")
	if not edge then return true end
	for index = 1, last do
		for _, side in ipairs({ "Left", "Right" }) do
			local region = Line(tooltip, side, index)
			local reach = Words(region) and Number(region, "GetRight")
			if reach and reach > edge - padX + 2 then
				pcall(tooltip.SetWidth, tooltip, old)
				return true
			end
		end
	end
	return true
end

local PlaceCard -- (below)

-- Move line `from`'s words to line `to` (an addon's line under the card), `from` left empty.
local function Move(tooltip, from, to)
	for _, side in ipairs({ "Left", "Right" }) do
		local source, target = Line(tooltip, side, from), Line(tooltip, side, to)
		if source and target then
			local text = Words(source)
			if text then
				target:SetText(text)
				target:SetTextColor(Safe(source.GetTextColor, source))
				target:Show()
			else
				target:SetText("")
				if side == "Right" then target:Hide() end
			end
			source:SetText("")
			if side == "Right" then source:Hide() end
		end
	end
end

-- Lay a cut tooltip out again: after the game drew it, a line added, Shift pressed or let go.
local function Pass(tooltip, force)
	local c = cuts[tooltip]
	if not c or not tooltip:IsShown() then return end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	if c.kind == "player" then
		for from = c.total + 1, count do
			c.filled = c.filled + 1
			if from ~= c.filled then Move(tooltip, from, c.filled) end
		end
		c.total = math.max(c.total, count)
	else
		c.filled, c.total = count, count
	end
	c.touched = math.max(c.touched, count)
	local more = More()
	local height = Number(tooltip, "GetHeight")
	if not force and count == c.n and more == c.more and height == c.height then return end
	c.n, c.more = count, more
	local last = math.min(more and c.filled or c.keep, count)
	for index = 1, count do
		local alpha = index <= last and 1 or 0
		Fade(Line(tooltip, "Left", index), alpha)
		Fade(Line(tooltip, "Right", index), alpha)
	end
	local cue = Cue(tooltip)
	local waiting = not more and c.filled > c.keep
	cue:SetShown(waiting)
	local extras = Extras(tooltip)
	if last >= count then
		-- (nothing waits: the tooltip as the game made it)
		for _, region in ipairs(extras) do Fade(region, 1) end
		c.height = height
		if c.kind == "player" then PlaceCard(tooltip) end
		return
	end
	local floor = c.kind == "player" and PlaceCard(tooltip) or nil
	local cutoff = Number(Line(tooltip, "Left", last), "GetBottom")
	local keptExtra = false
	for _, region in ipairs(extras) do
		local shown = region.IsShown and Safe(region.IsShown, region)
		local top = shown and Number(region, "GetTop")
		local below = top and cutoff and top < cutoff + 1
		Fade(region, below and 0 or 1)
		if top and not below then keptExtra = true end
	end
	-- (not measured: no height kept, so the next frame lays it out again)
	c.height = Fit(tooltip, last, waiting and cue or nil, keptExtra, floor) and Number(tooltip, "GetHeight") or nil
end

-- A line or coins added to a cut tooltip after it was drawn (an addon late with its prices): unseen at once, not a
-- frame later.
local function Late(tooltip)
	local c = cuts[tooltip]
	if not c or More() then return end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	if count <= c.keep then return end
	Fade(Line(tooltip, "Left", count), 0)
	Fade(Line(tooltip, "Right", count), 0)
end

local function LateMoney(tooltip)
	if type(tooltip) ~= "table" or not cuts[tooltip] then return end
	Late(tooltip)
	local c = cuts[tooltip]
	local name = Clean(Safe(tooltip.GetName, tooltip))
	local index = Clean(rawget(tooltip, "numMoneyFrames")) -- (the game's own count: the coins just added are the last)
	if c and not More() and name and type(index) == "number" and (Clean(Safe(tooltip.NumLines, tooltip)) or 0) > c.keep then
		Fade(_G[name .. "MoneyFrame" .. index], 0)
	end
end

local function Uncut(tooltip)
	local c = cuts[tooltip]
	if not c then return end
	cuts[tooltip] = nil
	for index = 1, c.touched do
		Fade(Line(tooltip, "Left", index), 1)
		Fade(Line(tooltip, "Right", index), 1)
	end
	for _, region in ipairs(Extras(tooltip)) do Fade(region, 1) end
	if tooltip.sereneCue then tooltip.sereneCue:Hide() end
	local card = tooltip.sereneCard
	if card and card.shown then
		card.shown = false
		for _, region in ipairs(card.regions) do region:Hide() end
	end
end

-- How many of an item tooltip's lines are the game's own: up to the last line whose words the game's data has.
local function GameLines(tooltip, data)
	local lines = type(data) == "table" and data.lines
	if type(lines) ~= "table" then return nil end
	local surface = TooltipUtil and TooltipUtil.SurfaceArgs
	local said = {}
	for _, info in ipairs(lines) do
		if type(info) == "table" then
			-- (a line whose words still sit in its args: brought up to leftText)
			if info.leftText == nil and surface then Safe(surface, info) end
			local text = Clean(info.leftText)
			if type(text) == "string" and text:find("%S") then said[text] = true end
		end
	end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	for index = count, 1, -1 do
		local text = Words(Line(tooltip, "Left", index))
		if text and said[text] then return index end
	end
	return nil
end

-- The line coins are anchored to (the game's "Sell Price:" is a blank line with coins on it, on older clients).
local function CoinLine(tooltip, index)
	local line = Line(tooltip, "Left", index)
	if not line then return false end
	for _, region in ipairs(Extras(tooltip)) do
		if region.GetPoint and region.IsShown and Safe(region.IsShown, region) then
			local _, anchor = Safe(region.GetPoint, region, 1)
			if anchor == line then return true end
		end
	end
	return false
end

-- (`priced`: the index of the vendor price row, Serene's words: the game's own row, or one written after its lines)
local function CutItem(tooltip, data, priced)
	local keep = GameLines(tooltip, data)
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	if not keep or keep < 1 then return end
	-- the price is the game's too
	if keep < count and CoinLine(tooltip, keep + 1) then keep = keep + 1 end
	if priced and priced <= count and priced > keep then keep = priced end
	cuts[tooltip] = { kind = "item", keep = keep, filled = count, total = count, touched = count }
end

-- The vendor's price ---------------------------------------------------------------------------------------------
-- What a merchant pays for an item, for the whole stack in your bags: "Vendor  ×20   3s 40c". Forever draws its own
-- "Sell Price:" row (a typed line in the tooltip's data; none for what merchants won't buy): that row is written
-- over in these words as it is drawn, so it stays among the game's lines, above the Shift cut, whatever addons do
-- with it (VendorPricePlus blanks it when Auctionator is loaded). Elsewhere a line of its own after the game's.

local Coins = ns.Items.Coins

local function PriceWords(count)
	return ns.SOFT .. "Vendor|r" .. (count > 1 and (ns.MUTED .. "  ×" .. count .. "|r") or "")
end

local function TipInfo(tooltip)
	-- (the info being filled right now first, as in a line call; else what the tooltip shows)
	for _, method in ipairs({ "GetProcessingTooltipInfo", "GetPrimaryTooltipInfo" }) do
		local info = tooltip[method] and Safe(tooltip[method], tooltip)
		if type(info) == "table" then return info end
	end
	return nil
end

-- How many of it: the stack in a bag or bank slot, else one.
local function StackOf(tooltip)
	local info = TipInfo(tooltip)
	local getter = info and Clean(info.getterName)
	local args = info and info.getterArgs
	local count
	if getter == "GetBagItem" and type(args) == "table" and C_Container and C_Container.GetContainerItemInfo then
		local item = Safe(C_Container.GetContainerItemInfo, args[1], args[2])
		count = type(item) == "table" and Clean(item.stackCount)
	elseif getter == "GetInventoryItem" and type(args) == "table" and _G.GetInventoryItemCount then
		count = Clean(Safe(_G.GetInventoryItemCount, args[1], args[2]))
	end
	-- (not read from the slot: the count on the bag button the tooltip is shown for)
	if type(count) ~= "number" and (getter == "GetBagItem" or getter == "GetBagItemChild" or getter == "GetInventoryItem") then
		local owner = Safe(tooltip.GetOwner, tooltip)
		count = type(owner) == "table" and Clean(rawget(owner, "count"))
	end
	return (type(count) == "number" and count > 1) and count or 1
end

local function EachPrice(tooltip, data)
	local item = type(data) == "table" and (Clean(data.hyperlink) or Clean(data.id))
	if not item then
		local _, link = Safe(tooltip.GetItem, tooltip)
		item = Clean(link)
	end
	if not item then return nil end
	local each = ns.Items.SellPrice(item)
	return each > 0 and each or nil
end

-- The game's row: where it will be drawn (before), then written over (after).
local SELL_LABEL = type(_G.SELL_PRICE) == "string" and _G.SELL_PRICE or "Sell Price"

-- (no pre-call: the row among the last lines, by its words, or blanked by an addon)
local function SellRowNear(tooltip, count)
	for index = count, math.max(1, count - 1), -1 do
		local line = Line(tooltip, "Left", index)
		local text = line and Clean(Safe(line.GetText, line))
		if text == nil or text == "" or (type(text) == "string" and (text:find(SELL_LABEL, 1, true) or text:find("Vendor", 1, true))) then
			return index
		end
	end
	return nil
end

local function BeforeSellRow(tooltip)
	if not styled[tooltip] then return end
	tooltip.sereneSellAt = (Clean(Safe(tooltip.NumLines, tooltip)) or 0) + 1
end

local function AfterSellRow(tooltip, lineData)
	if not styled[tooltip] then return end
	local index = tooltip.sereneSellAt
	tooltip.sereneSellAt = nil
	if not ns.On("tipvendor") then return end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	if type(index) ~= "number" then index = SellRowNear(tooltip, count) end
	if not index or index > count then return end -- (not drawn)
	local left, right = Line(tooltip, "Left", index), Line(tooltip, "Right", index)
	if not (left and right and left.SetText and right.SetText) then return end
	if CoinLine(tooltip, index) then -- (drawn with the game's coins: kept as it is)
		tooltip.sereneVendorRow = index
		return
	end
	local stack = StackOf(tooltip)
	local total = type(lineData) == "table" and Clean(lineData.price)
	if type(total) ~= "number" or total <= 0 then
		local info = TipInfo(tooltip)
		local each = EachPrice(tooltip, info and info.tooltipData)
		if not each then return end
		total = each * stack
	end
	left:SetText(PriceWords(stack))
	left:Show()
	right:SetText("|cffffffff" .. Coins(total) .. "|r")
	right:Show()
	tooltip.sereneVendorRow = index
end

local function HookSellRow()
	local processor = _G.TooltipDataProcessor
	local kinds = Enum and Enum.TooltipDataLineType
	local sell = kinds and kinds.SellPrice
	if not (processor and processor.AddLinePostCall and sell ~= nil) then return end
	if processor.AddLinePreCall then pcall(processor.AddLinePreCall, sell, BeforeSellRow) end
	pcall(processor.AddLinePostCall, sell, AfterSellRow)
end

-- Whether the game's data says a merchant buys it (nil: it does not say).
local function Sellable(data)
	local kinds = Enum and Enum.TooltipDataLineType
	local sell = kinds and kinds.SellPrice
	if sell == nil or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	for _, info in ipairs(data.lines) do
		if type(info) == "table" and Clean(info.type) == sell then return true end
	end
	return false
end

-- The price row's index once the game's lines are written: its own row written over, or else a line added (where
-- the game drew no row and no coins). The second value: a line was added.
local function VendorPrice(tooltip, data)
	local row = tooltip.sereneVendorRow
	tooltip.sereneVendorRow, tooltip.sereneSellAt = nil, nil
	if not ns.On("tipvendor") or (tooltip ~= tip and tooltip ~= _G.ItemRefTooltip) then return nil end
	if row then return row end
	if (tonumber(Clean(rawget(tooltip, "shownMoneyFrames"))) or 0) > 0 then return nil end -- (the game's own)
	if Sellable(data) == false then return nil end
	local each = EachPrice(tooltip, data)
	if not each then return nil end
	local stack = StackOf(tooltip)
	tooltip:AddDoubleLine(PriceWords(stack), "|cffffffff" .. Coins(each * stack) .. "|r")
	return Clean(Safe(tooltip.NumLines, tooltip)), true
end

-- A player as a card ------------------------------------------------------------------------------------------------

local RACE_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- (the character creation's sheets, where the game does not name them itself)
local RACE_COORDS = {
	HUMAN_MALE = { 0, 0.125, 0, 0.25 }, DWARF_MALE = { 0.125, 0.25, 0, 0.25 }, GNOME_MALE = { 0.25, 0.375, 0, 0.25 },
	NIGHTELF_MALE = { 0.375, 0.5, 0, 0.25 }, TAUREN_MALE = { 0, 0.125, 0.25, 0.5 }, SCOURGE_MALE = { 0.125, 0.25, 0.25, 0.5 },
	TROLL_MALE = { 0.25, 0.375, 0.25, 0.5 }, ORC_MALE = { 0.375, 0.5, 0.25, 0.5 },
	HUMAN_FEMALE = { 0, 0.125, 0.5, 0.75 }, DWARF_FEMALE = { 0.125, 0.25, 0.5, 0.75 },
	GNOME_FEMALE = { 0.25, 0.375, 0.5, 0.75 }, NIGHTELF_FEMALE = { 0.375, 0.5, 0.5, 0.75 },
	TAUREN_FEMALE = { 0, 0.125, 0.75, 1 }, SCOURGE_FEMALE = { 0.125, 0.25, 0.75, 1 },
	TROLL_FEMALE = { 0.25, 0.375, 0.75, 1 }, ORC_FEMALE = { 0.375, 0.5, 0.75, 1 },
}
local CLASS_COORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local CROP = 0.08 -- (the sheets' painted edges cut away: the round ring is the edge)
local CARD_TEXT = RACE_SIZE + CLASS_OUT + CARD_GAP -- where the card's words start

-- Room before a row's words: a blank inline picture, measured in that row's font (its width grows with the font).
local ruler
local function Indent(line, width)
	if not ruler then
		ruler = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		ruler:Hide()
	end
	local font, size, flags
	if type(line) == "table" and line.GetFont then font, size, flags = Safe(line.GetFont, line) end
	if not font and _G.GameTooltipText then font, size, flags = Safe(_G.GameTooltipText.GetFont, _G.GameTooltipText) end
	if font then pcall(ruler.SetFont, ruler, font, size, flags) end
	ruler:SetText("|T" .. MEDIA .. "Blank:1:100|t")
	local per = (Number(ruler, "GetStringWidth") or 100) / 100
	if per <= 0 then per = 1 end
	return "|T" .. MEDIA .. "Blank:1:" .. math.max(1, math.floor(width / per + 0.5)) .. "|t"
end

local function Crop(texture, l, r, t, b)
	local dx, dy = (r - l) * CROP, (b - t) * CROP
	texture:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
end

-- An icon: from the game's atlas if it has one by that name, else from a sheet.
local function Paint(texture, atlases, sheet, coords)
	local get = C_Texture and C_Texture.GetAtlasInfo
	for _, atlas in ipairs(atlases) do
		if atlas == "sheet" then
			if coords then
				texture:SetTexture(sheet)
				Crop(texture, coords[1], coords[2], coords[3], coords[4])
				return true
			end
		else
			local info = get and Safe(get, atlas)
			local file = type(info) == "table" and (info.file or info.filename)
			if file then
				texture:SetTexture(file)
				Crop(texture, info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0, info.bottomTexCoord or 1)
				return true
			end
		end
	end
	return false
end

-- A round icon: the picture inside a disc, a ring around it.
local function Round(tooltip, size, level)
	local icon = tooltip:CreateTexture(nil, "ARTWORK", nil, level)
	icon:SetSize(size, size)
	if tooltip.CreateMaskTexture and icon.AddMaskTexture then
		local mask = tooltip:CreateMaskTexture()
		mask:SetTexture(MEDIA .. "BadgeDisc", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	end
	local rim = tooltip:CreateTexture(nil, "ARTWORK", nil, level + 1)
	rim:SetTexture(MEDIA .. "BadgeRim")
	rim:SetAllPoints(icon)
	return icon, rim
end

local function CardRegions(tooltip)
	if tooltip.sereneCard then return tooltip.sereneCard end
	local card = { shown = false }
	card.race, card.raceRim = Round(tooltip, RACE_SIZE, 1)
	card.classGround = tooltip:CreateTexture(nil, "ARTWORK", nil, 3)
	card.classGround:SetTexture(MEDIA .. "BadgeDisc")
	card.classGround:SetVertexColor(INK[1], INK[2], INK[3], 1)
	card.classGround:SetSize(CLASS_SIZE + 2, CLASS_SIZE + 2)
	card.class, card.classRim = Round(tooltip, CLASS_SIZE, 4)
	card.class:SetPoint("BOTTOMRIGHT", card.race, "BOTTOMRIGHT", CLASS_OUT, -CLASS_OUT)
	card.classGround:SetPoint("CENTER", card.class, "CENTER", 0, 0)
	card.classRim:SetVertexColor(INK[1], INK[2], INK[3], 1)
	card.regions = { card.race, card.raceRim, card.classGround, card.class, card.classRim }
	for _, region in ipairs(card.regions) do region:Hide() end
	tooltip.sereneCard = card
	return card
end

-- The race icon beside the card's two rows, in the middle of them. Returns how low the icons reach (the tooltip
-- must hold them).
PlaceCard = function(tooltip)
	local card = tooltip.sereneCard
	if not (card and card.shown) then return nil end
	local first, second = Line(tooltip, "Left", 1), Line(tooltip, "Left", 2)
	local top, bottom = Number(first, "GetTop"), Number(second, "GetBottom")
	local drop = (top and bottom) and math.floor(((top - bottom) - RACE_SIZE) / 2 + 0.5) or 0
	card.race:ClearAllPoints()
	card.race:SetPoint("TOPLEFT", first, "TOPLEFT", 0, -drop)
	return top and (top - drop - RACE_SIZE - CLASS_OUT) or nil
end

local function Hex(color)
	if type(color) ~= "table" or type(color.r) ~= "number" then return nil end
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
end

local function SetRow(tooltip, index, left, right, rightColor)
	local line, other = Line(tooltip, "Left", index), Line(tooltip, "Right", index)
	if not line then return end
	line:SetText(left)
	line:SetTextColor(SOFT_RGB[1], SOFT_RGB[2], SOFT_RGB[3])
	line:Show()
	if other then
		if right then
			other:SetText(right)
			local color = rightColor or SOFT_RGB
			other:SetTextColor(color.r or color[1], color.g or color[2], color.b or color[3])
			other:Show()
		else
			other:SetText("")
			other:Hide()
		end
	end
end

-- The card: false when the unit is no player, or what it is cannot be read (a fight's secret values).
local function Card(tooltip, data)
	local _, unit = Safe(tooltip.GetUnit, tooltip)
	unit = Clean(unit)
	if type(unit) ~= "string" or not Clean(Safe(UnitIsPlayer, unit)) then return false end
	-- (the name as the game wrote it: first name and surname; else the unit's)
	local name = Clean(Safe(UnitName, unit))
	local written = Words(Line(tooltip, "Left", 1))
	if type(written) == "string" and type(name) == "string" then
		-- (its colour codes and tags such as <AFK> taken out)
		written = written:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*<[^>]*>%s*", " ")
		written = strtrim and strtrim(written) or written:match("^%s*(.-)%s*$")
		if written ~= "" and written:find(name, 1, true) then name = written end
	end
	local className, classFile = Safe(UnitClass, unit)
	local raceName, raceFile = Safe(UnitRace, unit)
	className, classFile, raceName, raceFile = Clean(className), Clean(classFile), Clean(raceName), Clean(raceFile)
	if type(name) ~= "string" or type(classFile) ~= "string" or type(raceFile) ~= "string" then return false end
	local level = Clean(Safe(UnitLevel, unit))
	local faction, factionName = Safe(UnitFactionGroup, unit)
	faction, factionName = Clean(faction), Clean(factionName)
	local guild = Clean(Safe(GetGuildInfo, unit))
	local female = Clean(Safe(UnitSex, unit)) == 3 -- (1 unknown, 2 male, 3 female)

	-- the words
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local classColor = Hex(colors and colors[classFile]) or ns.SOFT
	local status = Clean(Safe(UnitIsAFK, unit)) and (_G.AFK or "AFK")
		or Clean(Safe(UnitIsDND, unit)) and (_G.DND or "DND")
		or Clean(Safe(UnitIsDeadOrGhost, unit)) and (_G.DEAD or "Dead") or nil
	local first = Indent(Line(tooltip, "Left", 1), CARD_TEXT) .. classColor .. name .. "|r" .. (status and (ns.MUTED .. "  " .. status .. "|r") or "")
	local levelText, levelColor
	if type(level) == "number" then
		local difficulty = _G.GetCreatureDifficultyColor or _G.GetQuestDifficultyColor
		levelText = level > 0 and tostring(level) or "??"
		-- (??: a skull, in red)
		levelColor = level > 0 and difficulty and Safe(difficulty, level) or { r = 1, g = 0.1, b = 0.1 }
	end
	local who = (raceName or "") .. ((raceName and className) and " " or "") .. (className or "")
	local second = Indent(Line(tooltip, "Left", 2), CARD_TEXT) .. ns.MUTED .. (guild and ("<" .. guild .. ">") or who) .. "|r"
	local words = {}
	if type(level) == "number" then words[#words + 1] = (_G.LEVEL or "Level") .. " " .. (levelText or "") end
	if guild and who ~= "" then words[#words + 1] = who end
	local third = Indent(Line(tooltip, "Left", 3), CARD_TEXT) .. ns.MUTED .. table.concat(words, " ") .. (factionName and ("  ·  " .. factionName) or "") .. "|r"

	-- the lines: the card's three rows over the game's first lines, the game's others emptied, the addons' moved up
	local game = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	-- (the data's lines are the game's: any beyond them an addon already added)
	local said = type(data) == "table" and type(data.lines) == "table" and #data.lines
	if said and said > 0 and said < game then game = said end
	while (Clean(Safe(tooltip.NumLines, tooltip)) or 0) < 3 do tooltip:AddLine(" ") end
	local count = Clean(Safe(tooltip.NumLines, tooltip)) or 0
	SetRow(tooltip, 1, first, levelText, levelColor)
	SetRow(tooltip, 2, second)
	SetRow(tooltip, 3, third)
	for index = 4, game do
		local line, other = Line(tooltip, "Left", index), Line(tooltip, "Right", index)
		if line then line:SetText("") end
		if other then other:SetText("") other:Hide() end
	end
	local filled = 3
	for from = math.max(game, 3) + 1, count do
		filled = filled + 1
		if from ~= filled then Move(tooltip, from, filled) end
	end
	cuts[tooltip] = { kind = "player", keep = 2, filled = filled, total = count, touched = count }

	-- the icons
	local card = CardRegions(tooltip)
	local race = raceFile:lower() == "scourge" and "undead" or raceFile:lower() -- (the atlases' word for Forsaken)
	local gender = female and "female" or "male"
	local raced = Paint(card.race, { "raceicon128-" .. race .. "-" .. gender, "sheet", "raceicon-" .. race .. "-" .. gender },
		RACE_SHEET, (_G.RACE_ICON_TCOORDS or RACE_COORDS)[raceFile:upper() .. "_" .. gender:upper()]
			or RACE_COORDS[raceFile:upper() .. "_" .. gender:upper()])
	local classed = Paint(card.class, { "sheet", "classicon-" .. classFile:lower() }, CLASS_SHEET,
		(_G.CLASS_ICON_TCOORDS or CLASS_COORDS)[classFile] or CLASS_COORDS[classFile])
	local ring = FACTION_RING[faction] or NEUTRAL_RING
	card.raceRim:SetVertexColor(ring[1], ring[2], ring[3], 1)
	card.shown = true
	card.race:SetShown(raced)
	card.raceRim:SetShown(raced)
	card.class:SetShown(raced and classed)
	card.classRim:SetShown(raced and classed)
	card.classGround:SetShown(raced and classed)
	card.race:ClearAllPoints()
	card.race:SetPoint("TOPLEFT", Line(tooltip, "Left", 1), "TOPLEFT", 0, 0)
	return true
end

-- Whether the game's data is about something shown as an icon.
local function Iconic(kind, types)
	kind = Clean(kind)
	if kind == nil or not types then return false end
	for _, name in ipairs(ICON_KINDS) do
		if types[name] ~= nil and types[name] == kind then return true end
	end
	return false
end

-- The game's words written: quiet, cut short, a card, a gold rim. (`as`: "unit", "item" or "spell", where the game
-- hands no data)
local function OnData(tooltip, data, as)
	if not styled[tooltip] then return end
	Uncut(tooltip)
	local types = Enum and Enum.TooltipDataType
	local kind = type(data) == "table" and data.type
	local unit = as == "unit" or (types and kind ~= nil and kind == types.Unit) or false
	local item = as == "item" or (types and kind ~= nil and kind == types.Item) or false
	Rim(tooltip, item or as == "spell" or Iconic(kind, types))
	local priced, added
	if item then priced, added = VendorPrice(tooltip, data) end
	-- (a card only on GameTooltip; one that cannot be made falls back to quiet colours)
	if ns.On("tooltip") and not (unit and tooltip == tip and ns.On("tipcard") and Card(tooltip, data)) then
		Hushed(tooltip, unit)
		if item and cuttable[tooltip] and ns.On("tipmore") then CutItem(tooltip, data, priced) end
	end
	if added then tooltip:Show() end -- (sized for the new line)
end

-- Coming softly -----------------------------------------------------------------------------------------------------

local function Peeking()
	return (IsShiftKeyDown() or (ns.IsPeeking and ns.IsPeeking())) and true or false
end

-- (the unit under the mouse is one you can attack: its tooltip shows in a fight too)
local function Enemy()
	if not state.world then return false end
	return Clean(Safe(UnitExists, "mouseover")) and Clean(Safe(UnitCanAttack, "player", "mouseover")) and true or false
end

-- In a fight, the world's and the action bars' tooltips wait (enemies' show).
local function Held()
	return fighting and (state.world or state.action) and ns.On("tooltip") and ns.On("tipcalm") and not Peeking()
		and not Enemy()
end

local function Write(alpha)
	pcall(tip.SetAlpha, tip, alpha)
end

-- A tooltip for a new frame: from nothing, after a moment over a button.
local function Fresh(owner)
	-- (one was seen just now, or still is: this one comes at once)
	local recent = (tip:IsShown() and state.owner ~= nil and not state.fading) or GetTime() - state.goneAt < GRACE
	state.owner, state.since = owner, GetTime()
	state.world = owner == UIParent or owner == WorldFrame -- (the game's owners for units and objects in the world)
	state.action = Named(owner, ACTION_NAMES)
	state.wait = (state.action or Named(owner, MENU_NAMES)) and not IsShiftKeyDown() and BUTTON_WAIT or 0
	state.redo, state.pending, state.hinted = nil, false, false
	if ns.On("tooltip") and not recent then
		state.alpha, state.fading = 0, true
		Write(0)
	elseif ns.On("tooltip") then
		state.alpha, state.fading, state.wait = 1, false, 0
		Write(1)
	else
		state.alpha, state.fading = 1, false
	end
end

local function Redo()
	local redo = state.redo
	if not redo or not tip:IsShown() then return end
	state.hinted = true
	state.redoing = true
	pcall(redo)
	state.redoing = false
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
	if not tip:IsShown() then self:Hide() return end
	-- (cut tooltips: Shift pressed or let go, the game draws them whole again; a line added, laid out again)
	for tooltip, c in pairs(cuts) do
		if tooltip:IsShown() then
			if More() ~= c.more then pcall(tooltip.Show, tooltip) else Pass(tooltip) end
		end
	end
	if not ns.On("tooltip") then
		if state.fading then
			state.fading, state.alpha = false, 1
			Write(1)
		end
		self:Hide()
		return
	end
	local now = GetTime()
	if Held() then
		state.alpha, state.fading = 0, true
		state.since, state.wait = now, 0
		Write(0)
		return
	end
	if state.fading then
		if now - state.since >= state.wait then
			state.alpha = ns.Approach(state.alpha, 1, elapsed, FADE_IN, FADE_IN)
			if state.alpha >= 1 then state.fading = false end
		end
		Write(state.alpha)
	end
	if state.pending and not state.hinted and now - state.since >= state.wait + HINT_AFTER then Redo() end
end)

-- Serene's own tooltips ------------------------------------------------------------------------------------------

-- How-to lines: shown now? (always, while calm tooltips are off)
function ns.TipHints()
	return not ns.On("tooltip") or state.hinted or IsShiftKeyDown()
end

-- A how-to line: added now, or later (Shift, or a moment).
function ns.TipHint(tooltip, text)
	if ns.TipHints() then
		tooltip:AddLine(ns.MUTED .. text .. "|r", nil, nil, nil, true)
	else
		state.pending = true
	end
end

-- (a tooltip Serene adds a how-to line to, not built by ShowTip: how to build it again with the line)
function ns.TipLater(redo)
	state.pending, state.redo = true, redo
end

-- One of Serene's tooltips: its lines from build(tooltip), under the mouse unless an anchor is given.
function ns.ShowTip(owner, build, anchor)
	tip:SetOwner(owner, anchor or "ANCHOR_CURSOR")
	state.pending = false
	build(tip)
	tip:Show()
	state.redo = state.pending and function() ns.ShowTip(owner, build, anchor) end or nil
end

-- The mouse gone: the tooltip fades away (calm), or goes at once.
function ns.HideTip()
	if state.owner ~= nil and not state.fading then state.goneAt = GetTime() end
	state.owner, state.redo, state.pending, state.fading = nil, nil, false, false
	if ns.On("tooltip") and tip.FadeOut then
		pcall(tip.FadeOut, tip)
	else
		tip:Hide()
	end
end

-- Switched on and off ------------------------------------------------------------------------------------------

local function Refresh()
	local on = ns.On("tooltip")
	-- (switched: the next tooltip comes as asked; the one shown now drawn whole)
	for tooltip in pairs(cuts) do
		Uncut(tooltip)
		if tooltip:IsShown() then pcall(tooltip.Show, tooltip) end
	end
	for tooltip in pairs(styled) do Dress(tooltip, on) end
	Bar(on)
	Compare(on)
	if not on and state.fading then
		state.fading, state.alpha = false, 1
		Write(1)
	end
end

local function Init()
	for _, name in ipairs(STYLED) do
		local tooltip = _G[name]
		if type(tooltip) == "table" and tooltip.HookScript then
			styled[tooltip] = true
			tooltip:HookScript("OnShow", function(self)
				if ns.On("tooltip") then Dress(self, true) end
			end)
			-- (the rim is the data's to give: a tooltip of plain words, a unit's, an object's has none)
			if Safe(tooltip.HasScript, tooltip, "OnTooltipCleared") then
				tooltip:HookScript("OnTooltipCleared", function(self) Rim(self, false) end)
			end
			tooltip:HookScript("OnHide", function(self) Rim(self, false) end)
		end
	end

	for _, name in ipairs(CUT) do
		local tooltip = _G[name]
		if type(tooltip) == "table" and tooltip.HookScript then
			cuttable[tooltip] = true
			-- (GameTooltip's own Show hook is below, with its fade)
			if tooltip ~= tip then hooksecurefunc(tooltip, "Show", function(self) Pass(self, true) end) end
			if Safe(tooltip.HasScript, tooltip, "OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", Uncut) end
			tooltip:HookScript("OnHide", Uncut)
			for _, method in ipairs({ "AddLine", "AddDoubleLine" }) do
				if tooltip[method] then hooksecurefunc(tooltip, method, Late) end
			end
		end
	end
	if _G.SetTooltipMoney then hooksecurefunc("SetTooltipMoney", LateMoney) end
	-- (the comparison tooltips are unanchored while the game fills them, placed only after their Show: laid out
	-- again each time they are placed, before they are drawn. A quest reward redoes this every 0.2 s, and twice
	-- each time, the second through the game's C comparison call, which a hook on TooltipComparisonManager
	-- doesn't see; laid out a frame late, the tooltip of what you wear flickered between its full and its cut size.)
	for tooltip in pairs(cuttable) do
		if tooltip ~= tip and tooltip.SetPoint then
			hooksecurefunc(tooltip, "SetPoint", function(self) Pass(self, true) end)
		end
	end

	hooksecurefunc(tip, "SetOwner", function(_, owner)
		Uncut(tip)
		Rim(tip, false)
		if owner ~= state.owner then Fresh(owner) end
	end)
	hooksecurefunc(tip, "Show", function()
		if ns.On("tooltip") and state.fading then Write(state.alpha) end
		Pass(tip, true)
		driver:Show()
	end)
	tip:HookScript("OnShow", function() driver:Show() end)
	tip:HookScript("OnHide", function()
		if state.redoing then return end
		if state.owner ~= nil and not state.fading then state.goneAt = GetTime() end
		state.owner, state.redo, state.pending, state.fading = nil, nil, false, false
	end)

	HookSellRow()

	-- (the words: once the game has written them)
	local processor = _G.TooltipDataProcessor
	if processor and processor.AddTooltipPostCall then
		pcall(processor.AddTooltipPostCall, processor.AllTypes or "ALL", function(tooltip, data)
			OnData(tooltip, data)
		end)
	else
		for tooltip in pairs(styled) do
			for script, as in pairs({ OnTooltipSetItem = "item", OnTooltipSetSpell = "spell", OnTooltipSetUnit = "unit" }) do
				if tooltip.HasScript and Safe(tooltip.HasScript, tooltip, script) then
					tooltip:HookScript(script, function(self) OnData(self, nil, as) end)
				end
			end
		end
	end

	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "MODIFIER_STATE_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, key, down)
		if event == "PLAYER_REGEN_DISABLED" then
			fighting = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			fighting = false
		elseif type(key) == "string" and key:find("SHIFT$") and down == 1 and state.pending and not state.hinted then
			Redo()
		end
	end)
	fighting = InCombatLockdown() and true or false -- (a reload in a fight: no REGEN_DISABLED comes)
	Refresh()
end

table.insert(ns.modules, { init = Init, refresh = Refresh })

ns.TooltipState = state -- (tests)
ns.TooltipHushed = Hushed -- (tests)
ns.TooltipCuts = cuts -- (tests)
