local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- New ranks onto the bars. When you learn a spell's next rank, every action button holding the rank that was your
-- highest until then takes the new one (out of a fight; after it otherwise). Off ("by itself" in the settings):
-- those buttons wear a small gold mark instead, and a quiet button over Action Bar 1 puts the new ranks on with a
-- click.
-- A lower rank put on a bar on purpose (a small heal, kept for its mana) is never touched: only the rank that was
-- the highest when the new one came. Each character remembers its highest ranks, so ranks learnt while Serene was
-- off are seen at the next login too.
--   (Settings > Action bars > Ranks and reagents)

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local GOLD = { 1, 0.82, 0.35 }
local INK = ns.INK
local MARK_SIZE = 6

local CAB = _G.C_ActionBar
local Actions = ns.Actions
local SpellOn = Actions.SpellOn
local store                  -- this character's: { seen = { name -> spellID }, pending = { old spellID -> name } }
local highest = {}           -- name -> { id = spellID, slot = spellbook slot } (the last look at the spellbook)
local waiting = {}           -- { slot, id, name, book } on the bars, not yet at their new rank
local marks = {}             -- button -> its mark
local pill
local queued, fightWaits = false, false
local settled = false        -- a few seconds after entering the world: the spellbook read whole by then

local function Bank() return Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0 end

-- The spellbook's spells at their highest rank known.
local function ReadBook()
	local book = C_SpellBook
	if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo) then
		return nil
	end
	local found = {}
	local bank = Bank()
	local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
	for line = 1, Clean(Safe(book.GetNumSpellBookSkillLines)) or 0 do
		local info = Safe(book.GetSpellBookSkillLineInfo, line)
		local offset = info and Clean(info.itemIndexOffset) or 0
		local count = info and Clean(info.numSpellBookItems) or 0
		for slot = offset + 1, offset + count do
			local item = Safe(book.GetSpellBookItemInfo, slot, bank)
			-- (the base spell, not one standing in for it now: a form or a talent swapping it is not a new rank)
			local id = item and (Clean(item.actionID) or Clean(item.spellID))
			local name = item and Clean(item.name)
			if id and type(name) == "string" and name ~= "" and not Clean(item.isPassive)
				and (not spellType or Clean(item.itemType) == spellType)
				and Clean(Safe(book.IsSpellBookItemLowRank, slot, bank)) ~= true then
				found[name] = { id = id, slot = slot }
			end
		end
	end
	return found
end

-- Marks and the button ----------------------------------------------------------------------------------------------

local function Mark(button)
	local mark = marks[button]
	if mark then return mark end
	mark = button:CreateTexture(nil, "OVERLAY", nil, 7)
	-- (no "TRILINEAR" filter: it crashes this client; the disc's edge is soft in the texture, and snapping is off)
	mark:SetTexture(MEDIA .. "AuraDisc", "CLAMP", "CLAMP")
	if mark.SetSnapToPixelGrid then
		pcall(mark.SetSnapToPixelGrid, mark, false)
		pcall(mark.SetTexelSnappingBias, mark, 0)
	end
	mark:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	mark:SetSize(MARK_SIZE, MARK_SIZE)
	mark:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
	mark:Hide()
	marks[button] = mark
	return mark
end

local function Names()
	local seen, list = {}, {}
	for _, w in ipairs(waiting) do
		if not seen[w.name] then
			seen[w.name] = true
			list[#list + 1] = w.name
		end
	end
	return list
end

local Upgrade -- (below)

local function Pill()
	if pill then return pill end
	local first = _G.ActionButton1
	if type(first) ~= "table" then return nil end
	pill = CreateFrame("Button", "SereneRankButton", UIParent)
	pill:SetFrameStrata("MEDIUM")
	pill:SetHeight(20)
	pill:SetPoint("BOTTOMLEFT", first, "TOPLEFT", 0, 8)
	pill.bg = pill:CreateTexture(nil, "BACKGROUND")
	pill.bg:SetAllPoints()
	pill.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.85)
	pill.lines = ns.Hairline(pill)
	pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pill.text:SetPoint("CENTER")
	pill:SetScript("OnClick", function() Upgrade() end)
	pill:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("New ranks learnt", GOLD[1], GOLD[2], GOLD[3])
		for _, name in ipairs(Names()) do GameTooltip:AddLine(name, 0.91, 0.894, 0.855) end
		GameTooltip:AddLine("Click: onto your bars", 0.56, 0.56, 0.56)
		GameTooltip:Show()
		self.text:SetTextColor(1, 1, 1)
	end)
	pill:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end)
	pill.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	pill:Hide()
	return pill
end

local function Show()
	local manual = ns.On("barRanks") and not ns.On("barRanksAuto")
	local bySlot = {}
	for _, w in ipairs(waiting) do bySlot[w.slot] = true end
	-- (every action button, Serene's action bars on or not)
	Actions.Each(function(button)
		local slot = Actions.Slot(button)
		local on = manual and slot and bySlot[slot] or false
		if on then Mark(button):Show() elseif marks[button] then marks[button]:Hide() end
	end)
	local button = Pill()
	if not button then return end
	local count = #Names()
	-- (nothing can be put on the bars in a fight: the button waits for its end)
	if manual and count > 0 and not InCombatLockdown() then
		button.text:SetText(count == 1 and "A new rank: put it on your bars"
			or ("New ranks for %d spells: put them on your bars"):format(count))
		button:SetWidth((Clean(Safe(button.text.GetStringWidth, button.text)) or 200) + 20)
		button.lines:Fit()
		button:Show()
	else
		button:Hide()
	end
end

-- Looking and upgrading ----------------------------------------------------------------------------------------------

local function Look()
	queued = false
	if not ns.On("barRanks") or not store then
		wipe(waiting)
		return Show()
	end
	if InCombatLockdown() then
		fightWaits = true
		return
	end
	local found = ReadBook()
	if not found then return end
	highest = found
	-- (a highest rank that changed since the last look: the old one waits on the bars for the new)
	-- (a character's first look only learns what it has: nothing counts as new)
	local firstLook = next(store.seen) == nil
	for name, h in pairs(found) do
		local old = store.seen[name]
		if not firstLook and old and old ~= h.id then store.pending[old] = name end
		store.seen[name] = h.id
	end
	wipe(waiting)
	local still = {}
	for slot = 1, Actions.SLOTS do
		local id = SpellOn(slot)
		local name = id and store.pending[id]
		local h = name and found[name]
		if h and h.id ~= id then
			-- (the game's own word, where it has it: already the highest, nothing to do)
			local top = CAB and CAB.IsHighestSpellRank and Clean(Safe(CAB.IsHighestSpellRank, slot))
			if top ~= true then
				waiting[#waiting + 1] = { slot = slot, id = id, name = name, book = h.slot, new = h.id }
				still[id] = name
			end
		end
	end
	-- (an old rank on no bar any more: nothing waits for it)
	store.pending = still
	if ns.On("barRanksAuto") and #waiting > 0 then return Upgrade() end
	Show()
end

local function Queue()
	if queued or not settled then return end
	queued = true
	-- (the spellbook's events come in bursts: one look after them)
	C_Timer.After(0.5, Look)
end

-- The new ranks onto the bars: each picked up from the spellbook and put in its button's slot, the old rank let go.
Upgrade = function()
	if InCombatLockdown() then
		fightWaits = true
		return
	end
	-- (something held on the cursor: yours, left alone; tried again in a moment)
	if Clean(Safe(GetCursorInfo)) ~= nil then
		C_Timer.After(2, Queue)
		return
	end
	local done, names = 0, {}
	for _, w in ipairs(waiting) do
		-- (only a slot still holding the old rank: it may have changed since the look)
		if SpellOn(w.slot) == w.id then
			if C_SpellBook and C_SpellBook.PickupSpellBookItem then
				Safe(C_SpellBook.PickupSpellBookItem, w.book, Bank())
			elseif C_Spell and C_Spell.PickupSpell then
				Safe(C_Spell.PickupSpell, w.new)
			end
			-- (only a spell is put down: a failed pickup never drops something else on the bar)
			if Clean(Safe(GetCursorInfo)) == "spell" then
				if CAB and CAB.PutActionInSlot then Safe(CAB.PutActionInSlot, w.slot) else Safe(_G.PlaceAction, w.slot) end
			end
			Safe(ClearCursor)
			if SpellOn(w.slot) == w.new then
				done = done + 1
				store.pending[w.id] = nil
				names[w.name] = true
			end
		end
	end
	wipe(waiting)
	Show()
	if done > 0 then
		local list = {}
		for name in pairs(names) do list[#list + 1] = name end
		table.sort(list)
		ns.Print(("new rank on your bars: %s"):format(table.concat(list, ", ")))
	end
end

local function Init()
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	ns.db.ranks = ns.db.ranks or {}
	ns.db.ranks[who] = ns.db.ranks[who] or { seen = {}, pending = {} }
	store = ns.db.ranks[who]
	store.seen, store.pending = store.seen or {}, store.pending or {}
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB",
		"PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			if not settled then C_Timer.After(3, function() settled = true Queue() end) end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			if pill then pill:Hide() end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if not fightWaits then return Show() end -- (the button back, hidden for the fight)
			fightWaits = false
		end
		Queue()
	end)
end

local function Refresh()
	if store then Queue() end
end

function ns.RanksDebug()
	local known = 0
	for _ in pairs(highest) do known = known + 1 end
	local pending = 0
	for _ in pairs(store and store.pending or {}) do pending = pending + 1 end
	ns.Print(("ranks: %s (by itself %s); %d spells known at their top rank, %d old ranks waiting on %d buttons"):format(
		tostring(ns.On("barRanks")), tostring(ns.On("barRanksAuto")), known, pending, #waiting))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
