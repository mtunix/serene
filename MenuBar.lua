local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The micro menu and the bags as words, right under the top bar: a second band of the same dark glass, its ends
-- fading, a fine gold rule along its bottom; in it quiet words (Character, Spells, Talents, Quests, Guild, Group...,
-- Menu) and the bags with their free room ("Bags 34"). No art of the game's. Away until the mouse comes to the top
-- bar or to it (Fade.lua, "words").
-- * Under the mouse a word brightens, its tooltip says its key; the one whose window is open is gold, over a fine
--   gold line; one that wants you (a flash, something new) has a small gold dot.
-- * The game's own buttons stay where they are, out of sight and out of the mouse's way; each word presses its button (securely: in a fight too), so everything
--   opens exactly as the game opens it.
-- * The bag bar's slots: in the bags window ("bags" at its top). Moved with the top bar (Shift and drag it).
--   /serene menu on|off    (a reload to switch)
--   /serene debug menu

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local INK = ns.INK
local GOLD = { 1, 0.82, 0.35 }
local SOFT = ns.SOFT_RGB
local MUTED = ns.MUTED_RGB
local RED = { 0.95, 0.42, 0.38 }
local HEIGHT, FADE, PAD, SIZE = 22, 36, 7, 11
local DARK, RULE = 0.7, 0.4
local EVERY = 0.25 -- seconds between two looks at the buttons' states

-- The words for the game's buttons (false: left out: the shop, and Help, which the game menu has too). A button
-- not named here gets its own name, spaced ("WorldMapMicroButton" -> "World Map").
local LABELS = {
	CharacterMicroButton = "Character", ProfessionMicroButton = "Professions", SpellbookMicroButton = "Spells",
	PlayerSpellsMicroButton = "Spells", TalentMicroButton = "Talents", AchievementMicroButton = "Achievements",
	QuestLogMicroButton = "Quests", GuildMicroButton = "Guild", SocialsMicroButton = "Social",
	LFDMicroButton = "Group", LFGMicroButton = "Group", CollectionsMicroButton = "Collections",
	EJMicroButton = "Journal", PVPMicroButton = "PvP", WorldMapMicroButton = "Map", MainMenuMicroButton = "Menu",
	HousingMicroButton = "Housing", StoreMicroButton = false, HelpMicroButton = false,
}
local MICRO_BARS = { "MicroMenu", "MicroButtonAndBagsBar" }
local GAME_BARS = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar", "BagsBar" }
local BAG_PARTS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton", "BagBarExpandToggle" }
-- (a button wanting you: one of these shown on it)
local ALERTS = { "FlashBorder", "Flash", "FlashContent", "NotificationOverlay" }

local band
local words = {}      -- index -> word (a secure button)
local gameButtons = {} -- the game's micro buttons, in their order on screen
local laidFor = ""    -- what the band was laid out for
local waiting = false -- a layout waiting for the fight's end
local away = {}       -- game frame -> true while Serene keeps it out of sight

local function Text(parent)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", SIZE, "")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
	return text
end

local function Gradient(texture, color, fromAlpha, toAlpha)
	if texture.SetGradient and CreateColor then
		texture:SetColorTexture(1, 1, 1, 1)
		texture:SetGradient("HORIZONTAL", CreateColor(color[1], color[2], color[3], fromAlpha),
			CreateColor(color[1], color[2], color[3], toAlpha))
	else
		texture:SetColorTexture(color[1], color[2], color[3], (fromAlpha + toAlpha) / 2)
	end
end

-- The game's buttons out of sight ---------------------------------------------------------------------------------------

local holding = false
local function Away(frame)
	if type(frame) ~= "table" or not frame.SetAlpha then return end
	holding = true
	pcall(frame.SetAlpha, frame, 0)
	holding = false
	if frame.EnableMouse and not InCombatLockdown() then pcall(frame.EnableMouse, frame, false) end
	if away[frame] then return end
	away[frame] = true
	-- (the game sets their opacity now and then: back to nothing, right after)
	hooksecurefunc(frame, "SetAlpha", function(self)
		if holding then return end
		holding = true
		pcall(self.SetAlpha, self, 0)
		holding = false
	end)
end

-- (the older bar's own background, where this game has it)
local function StripArt(frame)
	if type(frame) ~= "table" or not frame.GetRegions then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then pcall(region.SetAlpha, region, 0) end
	end
end

-- The game's micro buttons, in their order on screen (rows from the top, each from the left).
local function GameButtons()
	local list, seen = {}, {}
	local function Add(button)
		if type(button) == "table" and button.GetObjectType and not seen[button] then
			seen[button] = true
			list[#list + 1] = button
		end
	end
	if type(_G.MICRO_BUTTONS) == "table" then
		for _, name in ipairs(_G.MICRO_BUTTONS) do Add(_G[name]) end
	end
	for _, barName in ipairs(MICRO_BARS) do
		local bar = _G[barName]
		if type(bar) == "table" and bar.GetChildren then
			for _, child in ipairs({ bar:GetChildren() }) do
				local name = child.GetName and child:GetName()
				if type(name) == "string" and name:find("MicroButton$") then Add(child) end
			end
		end
	end
	local function Spot(button)
		return Clean(Safe(button.GetTop, button)) or 0, Clean(Safe(button.GetLeft, button)) or 0
	end
	table.sort(list, function(a, b)
		local at, al = Spot(a)
		local bt, bl = Spot(b)
		if math.abs(at - bt) > 4 then return at > bt end
		return al < bl
	end)
	return list
end

local function Label(button)
	local name = button:GetName() or ""
	local label = LABELS[name]
	if label ~= nil then return label end
	label = name:gsub("MicroButton$", ""):gsub("(%l)(%u)", "%1 %2")
	return label ~= "" and label or nil
end

-- Bags -----------------------------------------------------------------------------------------------------------------

local function FreeSlots()
	local get = C_Container and C_Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
	if not get then return nil end
	local free = 0
	for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
		local count, family = get(bag)
		count, family = Clean(count), Clean(family)
		if type(count) == "number" and (family == 0 or family == nil) then free = free + count end
	end
	return free
end

-- Open: Serene's bags window, or the game's own where Serene's is off.
local function BagsOpen()
	for _, name in ipairs({ "SereneBags", "ContainerFrameCombinedBags", "ContainerFrame1" }) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsShown and Safe(frame.IsShown, frame) then
			-- (the game's windows wait out of sight while Serene's are on: not counted)
			if name == "SereneBags" or not ns.On("bags") then return true end
		end
	end
	return false
end

-- The words -------------------------------------------------------------------------------------------------------------

local function Paint(word)
	local game = word.game
	local enabled = not game or Safe(game.IsEnabled, game) ~= false
	local open = game and Safe(game.GetButtonState, game) == "PUSHED"
	if word.bags then open = BagsOpen() end
	local color = open and GOLD or (word.over and { 1, 1, 1 }) or SOFT
	word.text:SetTextColor(color[1], color[2], color[3], enabled and 1 or 0.35)
	word.line:SetShown(open and true or false)
	local alert = false
	if game and not open then
		for _, key in ipairs(ALERTS) do
			local part = game[key]
			if type(part) == "table" and part.IsShown and Safe(part.IsShown, part) then alert = true break end
		end
	end
	word.dot:SetShown(alert)
	if word.bags then
		local free = FreeSlots()
		local tint = free == 0 and RED or MUTED
		word.count:SetText(free and tostring(free) or "")
		word.count:SetTextColor(tint[1], tint[2], tint[3], 1)
	end
end

local function Tip(word)
	if not ns.ShowTip then return end
	ns.ShowTip(word, function(tooltip)
		local game = word.game
		local text = game and Clean(game.tooltipText) or nil
		if word.bags then
			local free = FreeSlots()
			tooltip:AddLine("Bags", SOFT[1], SOFT[2], SOFT[3])
			if free then tooltip:AddLine(free .. " free", MUTED[1], MUTED[2], MUTED[3]) end
		else
			tooltip:AddLine(type(text) == "string" and text or word.label, SOFT[1], SOFT[2], SOFT[3])
			local more = game and Clean(game.newbieText)
			if type(more) == "string" and more ~= "" then tooltip:AddLine(more, MUTED[1], MUTED[2], MUTED[3], true) end
		end
	end, "ANCHOR_BOTTOM")
end

local function MakeWord(index)
	local word = CreateFrame("Button", "SereneMenuWord" .. index, band, "SecureActionButtonTemplate")
	word:SetHeight(HEIGHT)
	word:RegisterForClicks("AnyUp", "AnyDown")
	word:SetAttribute("useOnKeyDown", false)
	word:SetAttribute("type", "click")
	word.text = Text(word)
	word.text:SetPoint("CENTER", word, "CENTER", 0, 0)
	word.count = Text(word)
	word.count:SetPoint("LEFT", word.text, "RIGHT", 4, 0)
	word.line = word:CreateTexture(nil, "ARTWORK")
	word.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	word.line:SetHeight(1)
	word.line:SetPoint("BOTTOMLEFT", word, "BOTTOMLEFT", PAD - 1, 3)
	word.line:SetPoint("BOTTOMRIGHT", word, "BOTTOMRIGHT", -PAD + 1, 3)
	word.line:Hide()
	word.dot = word:CreateTexture(nil, "OVERLAY")
	word.dot:SetTexture(MEDIA .. "Disc")
	word.dot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	word.dot:SetSize(4, 4)
	word.dot:SetPoint("BOTTOMLEFT", word.text, "TOPRIGHT", 0, -3)
	word.dot:Hide()
	word:SetScript("OnEnter", function(self)
		self.over = true
		Paint(self)
		Tip(self)
	end)
	word:SetScript("OnLeave", function(self)
		self.over = false
		Paint(self)
		if ns.HideTip then ns.HideTip() else GameTooltip:Hide() end
	end)
	-- (after the click, the window's state: a moment later, once it has opened or closed)
	word:HookScript("OnClick", function(self) C_Timer.After(0.05, function() Paint(self) end) end)
	words[index] = word
	return word
end

-- Where the band goes: its top middle under the top bar's bottom middle (the screen's top middle without it), in
-- UIParent's units. (Placed, not anchored: the band holds secure buttons, the top bar must stay free to move.)
local function Corner()
	local root = Clean(Safe(UIParent.GetEffectiveScale, UIParent)) or 1
	local top = _G.SereneTopBar
	if type(top) == "table" and ns.On("top") and Safe(top.IsShown, top) then
		local scale = (Clean(Safe(top.GetEffectiveScale, top)) or root) / root
		local l, r, b = Clean(Safe(top.GetLeft, top)), Clean(Safe(top.GetRight, top)), Clean(Safe(top.GetBottom, top))
		if l and r and b then return (l + r) / 2 * scale, b * scale end
	end
	local width, height = Clean(Safe(UIParent.GetWidth, UIParent)), Clean(Safe(UIParent.GetHeight, UIParent))
	if width and height then return width / 2, height end
end

local function Layout()
	if InCombatLockdown() then
		waiting = true
		return
	end
	waiting = false
	gameButtons = GameButtons()
	for _, button in ipairs(gameButtons) do Away(button) end
	for _, name in ipairs(BAG_PARTS) do Away(_G[name]) end
	-- (their bars too, whole: what is left of the game's art in them, empty slot frames, the box, stays out of sight)
	for _, name in ipairs(GAME_BARS) do Away(_G[name]) end
	StripArt(_G.MicroButtonAndBagsBar)
	-- the words: the game's shown buttons that have one, then the bags
	local list = {}
	for _, button in ipairs(gameButtons) do
		local label = Label(button)
		if label and Safe(button.IsShown, button) then list[#list + 1] = { label = label, game = button } end
	end
	list[#list + 1] = { label = "Bags", game = _G.MainMenuBarBackpackButton, bags = true }
	local x = FADE - PAD
	local keys = {}
	for index, entry in ipairs(list) do
		local word = words[index] or MakeWord(index)
		word.label, word.game, word.bags = entry.label, entry.game, entry.bags
		word.text:SetText(entry.label)
		if entry.game then
			word:SetAttribute("type", "click")
			word:SetAttribute("clickbutton", entry.game)
		else
			-- (no backpack button in this game: the bags opened as B opens them)
			word:SetAttribute("type", "macro")
			word:SetAttribute("macrotext", "/click SereneMenuBags")
		end
		word.count:SetText(entry.bags and "00" or "")
		local width = math.ceil(Clean(Safe(word.text.GetStringWidth, word.text)) or 40)
		if entry.bags then width = width + 4 + math.ceil(Clean(Safe(word.count.GetStringWidth, word.count)) or 14) end
		word.text:ClearAllPoints()
		word.text:SetPoint("LEFT", word, "LEFT", PAD, 0)
		word:SetWidth(width + PAD * 2)
		word:ClearAllPoints()
		word:SetPoint("LEFT", band, "LEFT", x, 0)
		word:Show()
		x = x + width + PAD * 2
		keys[#keys + 1] = entry.label
		Paint(word)
	end
	for index = #list + 1, #words do
		words[index]:Hide()
		words[index].game = nil
	end
	band:SetWidth(x + FADE - PAD)
	local right, bottom = Corner()
	band:ClearAllPoints()
	if right and bottom then
		band:SetPoint("TOP", UIParent, "BOTTOMLEFT", right, bottom)
	else
		band:SetPoint("TOP", UIParent, "TOP", 0, -20)
	end
	band.rule:SetHeight(ns.Pixel(band))
	band.ruleLeft:SetHeight(ns.Pixel(band))
	band.ruleRight:SetHeight(ns.Pixel(band))
	laidFor = table.concat(keys, ",") .. ("@%d:%d"):format(right or 0, bottom or 0)
end

-- What the band would be laid out for now (the game's shown buttons, where they are).
local function Wanted()
	local keys = {}
	for _, button in ipairs(GameButtons()) do
		local label = Label(button)
		if label and Safe(button.IsShown, button) then keys[#keys + 1] = label end
	end
	keys[#keys + 1] = "Bags"
	local right, bottom = Corner()
	return table.concat(keys, ",") .. ("@%d:%d"):format(right or 0, bottom or 0)
end

local function MakeBand()
	band = CreateFrame("Frame", "SereneMenuBar", UIParent)
	band:SetHeight(HEIGHT)
	band:SetFrameStrata("MEDIUM")
	band:SetFrameLevel(20)
	band:SetClampedToScreen(true)
	local middle = band:CreateTexture(nil, "BACKGROUND")
	middle:SetColorTexture(INK[1], INK[2], INK[3], DARK)
	middle:SetPoint("TOPLEFT", band, "TOPLEFT", FADE, 0)
	middle:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -FADE, 0)
	local left = band:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPRIGHT", middle, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", middle, "BOTTOMLEFT")
	left:SetWidth(FADE)
	Gradient(left, INK, 0, DARK)
	local right = band:CreateTexture(nil, "BACKGROUND")
	right:SetPoint("TOPLEFT", middle, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", middle, "BOTTOMRIGHT")
	right:SetWidth(FADE)
	Gradient(right, INK, DARK, 0)
	-- (a fine gold rule along its bottom, fading at its ends, like the top bar's)
	band.rule = band:CreateTexture(nil, "BORDER")
	band.rule:SetHeight(1)
	band.rule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", FADE, 0)
	band.rule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -FADE, 0)
	band.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], RULE)
	band.ruleLeft = band:CreateTexture(nil, "BORDER")
	band.ruleLeft:SetHeight(1)
	band.ruleLeft:SetPoint("RIGHT", band.rule, "LEFT")
	band.ruleLeft:SetWidth(FADE)
	Gradient(band.ruleLeft, GOLD, 0, RULE)
	band.ruleRight = band:CreateTexture(nil, "BORDER")
	band.ruleRight:SetHeight(1)
	band.ruleRight:SetPoint("LEFT", band.rule, "RIGHT")
	band.ruleRight:SetWidth(FADE)
	Gradient(band.ruleRight, GOLD, RULE, 0)
	-- (the bags, where the game has no backpack button: opened as B opens them)
	local bags = CreateFrame("Button", "SereneMenuBags", UIParent)
	bags:Hide()
	bags:SetScript("OnClick", function()
		if _G.ToggleAllBags then Safe(_G.ToggleAllBags) end
	end)
end

local function Init()
	if not ns.On("menuBar") then return end
	MakeBand()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED",
		"DISPLAY_SIZE_CHANGED", "BAG_UPDATE_DELAYED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" then
			for _, word in ipairs(words) do if word.bags then Paint(word) end end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
		C_Timer.After(0, Layout)
	end)
	local manager = _G.EditModeManagerFrame
	if type(manager) == "table" and manager.HookScript then
		manager:HookScript("OnHide", function() C_Timer.After(0, Layout) end)
	end
	-- (the words' states a few times a second; the layout again when the game's buttons change or move)
	local since, sinceLayout = 0, 0
	events:SetScript("OnUpdate", function(_, elapsed)
		since, sinceLayout = since + elapsed, sinceLayout + elapsed
		if since < EVERY then return end
		since = 0
		for _, word in ipairs(words) do
			if word:IsShown() then pcall(Paint, word) end
		end
		if sinceLayout >= 1 and not InCombatLockdown() then
			sinceLayout = 0
			if Wanted() ~= laidFor then pcall(Layout) end
		end
	end)
	Layout()
end

function ns.MenuDebug()
	local names = {}
	for _, button in ipairs(GameButtons()) do
		names[#names + 1] = (button:GetName() or "?") .. "=" .. tostring(Label(button))
			.. (Safe(button.IsShown, button) and "" or "(hidden)") .. ":" .. tostring(Safe(button.GetButtonState, button))
	end
	ns.Print(("menu: %s, band %s, laid out for %s%s"):format(tostring(ns.On("menuBar")), band and "made" or "none",
		laidFor, waiting and " (waiting for the fight's end)" or ""))
	ns.Print("   " .. table.concat(names, " "))
end

table.insert(ns.modules, { init = Init })
