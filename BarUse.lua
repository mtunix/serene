local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- How you use your bars, learnt from your presses (by key and by mouse, BarKeys.lua). Each action slot counts its
-- presses and remembers the last, in hours of play (time logged in, not away). Then:
--   unused   buttons on your bars not pressed for a long while of play (10 hours by default, counted from when the
--            action was put there): one quiet line in the chat when there are new ones, and a review to go through
--            them: keep it (never asked again), fade it (readiness keeps it faint, Ready.lua), or clear the slot.
--   keys     your most pressed actions sitting on hard keys (none, a modifier, far from the hand) while rarely
--            pressed ones have easy keys (1 to 5, Q, E, R, F, the side mouse buttons): a swap suggested, done in a
--            click (the two actions trade slots; their counts go with them).
-- For each character. Nothing changes on your bars without a click.
--   /serene review
--   (Settings > Action bars > How you use them)

local TICK = 10               -- seconds of play counted at a time
local NOTICE_AFTER = 60       -- seconds into a session before the quiet line
local LEAST_HOURS = 1         -- an action's presses counted for keys only after this much play with it
local BUSY_RATE = 5           -- presses an hour: an action worth an easy key
local SWAPS = 3
local ROWS = 10
local INK = ns.INK
local GOLD = { 1, 0.82, 0.35 }
local TEXT = { 0.92, 0.91, 0.88 }
local MUTED = ns.MUTED_RGB
local MEDIA = "Interface\\AddOns\\Serene\\Media\\"

local Actions = ns.Actions
local What = Actions.What -- (saved in each slot's entry, and in keep and faded: its form never changes)

local store   -- this character's: { played, slots = { slot -> { what, since, last, n } }, keep = {}, faded = {}, told }
local panel
local settled = false

local function Hours(seconds) return seconds / 3600 end

-- The slots as they are: an action new in a slot starts counting from now.
local function Look(slot)
	if not store then return end
	local what = What(slot)
	local entry = store.slots[slot]
	if not what then
		store.slots[slot] = nil
	elseif not entry or entry.what ~= what then
		store.slots[slot] = { what = what, since = store.played, n = 0 }
	end
end

local function LookAll()
	for slot = 1, Actions.SLOTS do Look(slot) end
end

local function Pressed(button)
	if not store or not ns.On("barUse") then return end
	local slot = Actions.Slot(button)
	if not slot then return end
	Look(slot)
	local entry = store.slots[slot]
	if entry then
		entry.n = (entry.n or 0) + 1
		entry.last = store.played
	end
end

-- The buttons on screen now: slot -> { button, bar's name, index, binding }.
local function OnScreen()
	local out = {}
	for _, family in ipairs(Actions.FAMILIES) do
		if family.slots then
			for index = 1, family.count do
				local button = _G[family.prefix .. index]
				local slot = type(button) == "table" and Actions.Slot(button)
				if slot and Clean(Safe(button.IsVisible, button)) and not out[slot] then
					local key = Clean(Safe(GetBindingKey, family.binding .. index))
					out[slot] = { button = button, bar = family.label, index = index, key = key }
				end
			end
		end
	end
	return out
end

-- How easy a key is to reach (0: no key at all).
local EASY = { ["1"] = 6, ["2"] = 6, ["3"] = 6, ["4"] = 6, ["5"] = 5, Q = 5, E = 5, R = 5, F = 5, BUTTON4 = 5,
	BUTTON5 = 5, T = 4, G = 4, Z = 4, X = 4, C = 4, V = 4, ["6"] = 3, MOUSEWHEELUP = 4, MOUSEWHEELDOWN = 4,
	["7"] = 2, ["8"] = 2, ["9"] = 2, ["0"] = 2, ["-"] = 2, ["="] = 2 }
local function Ease(key)
	if type(key) ~= "string" or key == "" then return 0 end
	local score = 0
	if key:find("SHIFT%-") then score = score - 1 end
	if key:find("CTRL%-") then score = score - 2 end
	if key:find("ALT%-") then score = score - 2 end
	local base = key:match("([^%-]+)$") or key
	if base:match("^F%d+$") then score = score + 1 else score = score + (EASY[base] or 3) end
	return math.max(1, score)
end

local function Since(entry) return store.played - (entry.last or entry.since or store.played) end

-- The unused buttons on screen, longest unused first.
local function Unused()
	local list = {}
	if not store then return list end
	local limit = (tonumber(ns.db.barUseHours) or 10) * 3600
	for slot, where in pairs(OnScreen()) do
		local entry = store.slots[slot]
		if entry and not store.keep[entry.what] and Since(entry) >= limit then
			list[#list + 1] = { slot = slot, entry = entry, where = where }
		end
	end
	table.sort(list, function(a, b) return Since(a.entry) > Since(b.entry) end)
	return list
end

-- Swaps worth making: a busy action on a hard key with a quiet one on an easy key.
local function Swaps()
	local hard, easy = {}, {}
	if not store then return {} end
	for slot, where in pairs(OnScreen()) do
		local entry = store.slots[slot]
		local hours = entry and Hours(store.played - (entry.since or store.played))
		if entry and hours >= LEAST_HOURS then
			local item = { slot = slot, entry = entry, where = where, rate = (entry.n or 0) / hours, ease = Ease(where.key) }
			if item.ease <= 2 and item.rate >= BUSY_RATE then hard[#hard + 1] = item end
			if item.ease >= 4 then easy[#easy + 1] = item end
		end
	end
	table.sort(hard, function(a, b) return a.rate > b.rate end)
	table.sort(easy, function(a, b) return a.rate < b.rate end)
	local out = {}
	for index = 1, math.min(#hard, #easy, SWAPS) do
		local busy, quiet = hard[index], easy[index]
		if busy.rate >= quiet.rate * 3 + 1 then out[#out + 1] = { busy = busy, quiet = quiet } end
	end
	return out
end

-- Changes ------------------------------------------------------------------------------------------------------------

local function Mine(fn)
	if ns.BarSetsMine then ns.BarSetsMine(fn) else pcall(fn) end
end

local function Clear(slot)
	if InCombatLockdown() then return ns.Print("bars: not in a fight") end
	Mine(function()
		-- (the cursor emptied first: a pickup while holding something would put that in the slot)
		Safe(ClearCursor)
		Safe(PickupAction, slot)
		Safe(ClearCursor)
	end)
	store.slots[slot] = nil
end

local CAB = _G.C_ActionBar
local function Put(slot)
	if CAB and CAB.PutActionInSlot then Safe(CAB.PutActionInSlot, slot) else Safe(_G.PlaceAction, slot) end
end

local function Swap(a, b)
	if InCombatLockdown() then return ns.Print("bars: not in a fight") end
	if Clean(Safe(GetCursorInfo)) ~= nil then return ns.Print("bars: put down what you hold first") end
	-- (the counts go with their actions)
	store.slots[a], store.slots[b] = store.slots[b], store.slots[a]
	-- (a's action into b hands back b's on the cursor, which then goes into a)
	Mine(function()
		Safe(PickupAction, a)
		Put(b)
		Put(a)
		Safe(ClearCursor)
	end)
end

-- The review ---------------------------------------------------------------------------------------------------------

local function Icon(slot)
	local get = CAB and CAB.GetActionTexture or _G.GetActionTexture
	return Clean(Safe(get, slot))
end

local function ActionName(slot)
	local kind, id = Safe(GetActionInfo, slot)
	kind, id = Clean(kind), Clean(id)
	if kind == "spell" and C_Spell and C_Spell.GetSpellName then return Clean(Safe(C_Spell.GetSpellName, id)) end
	if kind == "item" and C_Item and C_Item.GetItemNameByID then return Clean(Safe(C_Item.GetItemNameByID, id)) end
	return Clean(Safe(GetActionText, slot)) or tostring(kind)
end

local function KeyText(key)
	if not key then return "no key" end
	return (GetBindingText and Clean(Safe(GetBindingText, key, "KEY_"))) or key
end

local function Chip(parent, text, onClick)
	local chip = CreateFrame("Button", nil, parent)
	chip.ground = chip:CreateTexture(nil, "BACKGROUND")
	chip.ground:SetTexture(MEDIA .. "Pill")
	chip.ground:SetAllPoints()
	chip.text = chip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	chip.text:SetPoint("CENTER")
	function chip:Set(label, on)
		self.text:SetText(label)
		self.on = on
		self:SetSize(math.floor((Clean(Safe(self.text.GetStringWidth, self.text)) or 40) + 16 + 0.5), 18)
		if on then
			self.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
			self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			self.ground:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.06)
			self.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
		end
	end
	chip:Set(text)
	chip:SetScript("OnClick", onClick)
	chip:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
	chip:SetScript("OnLeave", function(self) self:Set(self.text:GetText(), self.on) end)
	return chip
end

local Fill -- (below)

local function Row(parent, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
	row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
	row:SetHeight(26)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT")
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetJustifyH("LEFT")
	row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
	row.detail:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	row.detail:SetJustifyH("LEFT")
	return row
end

local function Panel()
	if panel then return panel end
	panel = CreateFrame("Frame", "SereneBarReview", UIParent)
	panel:SetSize(460, 200)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel.bg = panel:CreateTexture(nil, "BACKGROUND")
	panel.bg:SetAllPoints()
	panel.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.92)
	panel.lines = ns.Hairline(panel)
	panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 14, -12)
	panel.title:SetText("Your bars")
	panel.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	panel.close = Chip(panel, "Close", function() panel:Hide() end)
	panel.close:SetPoint("TOPRIGHT", -10, -10)
	panel.rows = {}
	panel.heads = {}
	tinsert(UISpecialFrames, "SereneBarReview")
	panel:Hide()
	return panel
end

local function Head(index, text, y)
	local head = panel.heads[index]
	if not head then
		head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		panel.heads[index] = head
	end
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
	head:SetText(text:upper())
	head:Show()
end

local function Where(where)
	return ("%s, button %d, %s"):format(where.bar, where.index, KeyText(where.key))
end

Fill = function()
	if not panel or not panel:IsShown() then return end
	for _, row in ipairs(panel.rows) do
		row:Hide()
		for _, chip in ipairs(row.chips or {}) do chip:Hide() end
	end
	for _, head in ipairs(panel.heads) do head:Hide() end
	local y, used = -40, 0
	local function NextRow()
		used = used + 1
		local row = panel.rows[used]
		if not row then
			row = Row(panel, 0)
			row.chips = {}
			panel.rows[used] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
		row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, y)
		row:Show()
		y = y - 30
		return row
	end
	local function Chips(row, list)
		local x = 0
		for index, def in ipairs(list) do
			local chip = row.chips[index]
			if not chip then
				chip = Chip(row, def[1])
				row.chips[index] = chip
			end
			chip:Set(def[1], def[3])
			-- (drawn again a moment later, once the bars have changed)
			chip:SetScript("OnClick", function() def[2]() C_Timer.After(0.6, Fill) end)
			chip:ClearAllPoints()
			chip:SetPoint("RIGHT", row, "RIGHT", -x, 0)
			x = x + chip:GetWidth() + 4
			chip:Show()
		end
	end
	local hours = tonumber(ns.db.barUseHours) or 10
	local unused = Unused()
	Head(1, ("Not pressed in %d h of play"):format(hours), y)
	y = y - 18
	if #unused == 0 then
		local row = NextRow()
		row.icon:SetTexture(nil)
		row.name:SetText("Every button on your bars is in use.")
		row.detail:SetText("")
	end
	for index = 1, math.min(#unused, ROWS) do
		local u = unused[index]
		local row = NextRow()
		row.icon:SetTexture(Icon(u.slot))
		row.name:SetText(ActionName(u.slot) or "?")
		row.detail:SetText(("%s  ·  %d h unused"):format(Where(u.where), math.floor(Hours(Since(u.entry)))))
		local faded = store.faded[u.entry.what]
		Chips(row, {
			{ "Clear", function() Clear(u.slot) end },
			{ faded and "Faded" or "Fade", function() store.faded[u.entry.what] = not faded or nil end, faded },
			{ "Keep", function() store.keep[u.entry.what] = true store.faded[u.entry.what] = nil end },
		})
	end
	if #unused > ROWS then
		local row = NextRow()
		row.icon:SetTexture(nil)
		row.name:SetText(("and %d more"):format(#unused - ROWS))
		row.detail:SetText("")
	end
	local swaps = Swaps()
	y = y - 8
	Head(2, "Easier keys", y)
	y = y - 18
	if #swaps == 0 then
		local row = NextRow()
		row.icon:SetTexture(nil)
		row.name:SetText("Your busiest actions have good keys.")
		row.detail:SetText("Learnt from your presses; more play, better advice.")
	end
	for _, s in ipairs(swaps) do
		local row = NextRow()
		row.icon:SetTexture(Icon(s.busy.slot))
		row.name:SetText(("%s  (%d an hour, %s)"):format(ActionName(s.busy.slot) or "?", math.floor(s.busy.rate + 0.5),
			KeyText(s.busy.where.key)))
		row.detail:SetText(("trade with %s  (%d an hour, %s)"):format(ActionName(s.quiet.slot) or "?",
			math.floor(s.quiet.rate + 0.5), KeyText(s.quiet.where.key)))
		Chips(row, { { "Swap", function() Swap(s.busy.slot, s.quiet.slot) end } })
	end
	panel:SetHeight(-y + 12)
end

function ns.BarUseUnkeep()
	if store then wipe(store.keep) ns.Print("bars: kept buttons will be asked about again") end
end

function ns.BarReview()
	if not store then return end
	LookAll()
	Panel():Show()
	Fill()
end

-- (Ready.lua: a button you chose to fade)
function ns.BarUseFaded(slot)
	if not store or not ns.On("barUse") then return false end
	local entry = store.slots[slot]
	return entry ~= nil and store.faded[entry.what] == true
end

-- The quiet line: new unused buttons since the last time it was said.
local function Notice()
	if not store or not ns.On("barUse") or InCombatLockdown() then return end
	local list = Unused()
	local keys = {}
	for _, u in ipairs(list) do keys[#keys + 1] = u.entry.what end
	table.sort(keys)
	local said = table.concat(keys, ",")
	if #list == 0 or said == store.told then return end
	store.told = said
	ns.Print(("%d button%s on your bars not pressed in %d h of play  -  /serene review"):format(#list,
		#list == 1 and "" or "s", tonumber(ns.db.barUseHours) or 10))
end

local function Init()
	if not ns.On("actionBars") then return end
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	-- (per character in barUseBy: barUse itself is the on/off setting, a boolean)
	if type(ns.db.barUseBy) ~= "table" then ns.db.barUseBy = {} end
	ns.db.barUseBy[who] = ns.db.barUseBy[who] or {}
	store = ns.db.barUseBy[who]
	store.played = store.played or 0
	store.slots = store.slots or {}
	store.keep = store.keep or {}
	store.faded = store.faded or {}
	if ns.OnBarPress then ns.OnBarPress(Pressed) end
	-- (hours of play: time logged in and not away)
	C_Timer.NewTicker(TICK, function()
		if settled and not Clean(Safe(UnitIsAFK, "player")) then store.played = store.played + TICK end
	end)
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "ACTIONBAR_SLOT_CHANGED")
	pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, slot)
		if event == "PLAYER_ENTERING_WORLD" then
			if not settled then
				-- (the bars read a few seconds in: before, a slot may only be one not loaded yet)
				C_Timer.After(3, function()
					settled = true
					LookAll()
				end)
				C_Timer.After(NOTICE_AFTER, Notice)
			end
			return
		end
		slot = Clean(slot)
		-- (slot 0 means every slot: left to the review's own LookAll)
		if settled and type(slot) == "number" and slot > 0 then
			Look(slot)
			if panel and panel:IsShown() then C_Timer.After(0.3, Fill) end
		end
	end)
end

function ns.BarUseDebug()
	if not store then return ns.Print("bar use: not started (Serene's action bars off)") end
	local count = 0
	for _ in pairs(store.slots) do count = count + 1 end
	ns.Print(("bar use: %s; %.1f h of play, %d slots followed, %d unused now, %d swaps suggested"):format(
		tostring(ns.On("barUse")), Hours(store.played), count, #Unused(), #Swaps()))
end

table.insert(ns.modules, { init = Init, refresh = function() if panel and panel:IsShown() then Fill() end end })
