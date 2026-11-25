local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Your bars kept safe. Serene keeps a copy of every action slot (all bars, all pages, stances and forms), taken again
-- each time you change them. When actions leave your bars by themselves (a talent reset unlearning spells, three or
-- more gone at once), a quiet button over Action Bar 1 says how many: a click puts back what can be put back, each
-- into its old slot if that slot is still empty, and the rest (spells not learnt again yet) come back by themselves
-- the moment you learn them, while their slot stays empty. Right-click: forget them. Nothing you put on a slot since
-- is ever replaced.
-- Sets: the bars as they are now, saved under a name ("solo", "raid"...) and put on again later, exactly: each slot as
-- it was saved (a spell you don't know, an item or a macro that is gone: that slot left as it is). Putting a set on
-- first saves the bars as they were ("undo"). For each character.
--   /serene sets                     the saved sets
--   /serene sets save|load|delete <name>
--   (Settings > Action bars > Your bars kept)

local SLOTS = ns.Actions.SLOTS
local WIPE_AT = 3          -- this many gone at once, not by your hand: "left your bars"
local SETTLE = 1           -- seconds after the last change before the bars are looked at
local UNDO = "undo"        -- the set saved before one is put on
local INK = ns.INK
local GOLD = { 1, 0.82, 0.35 }

local CAB = _G.C_ActionBar
local store   -- this character's: { copy = { slot -> record }, lost = { slot -> record }, armed = bool, sets = {} }
local pill
local settled = false
local placing = false
local queued = false
local fightWaits = false

-- What a slot holds, as can be put back: { kind, id, name }; nil for an empty slot (or one that can't be read).
local function Read(slot)
	local kind, id, sub = Safe(GetActionInfo, slot)
	kind, id, sub = Clean(kind), Clean(id), Clean(sub)
	if not kind then return nil end
	if kind == "macro" then
		-- (the macro by its name: its number moves when macros are added)
		local name = Clean(Safe(GetActionText, slot))
		return { kind = "macro", name = name, id = id }
	end
	-- (an equipment set's id is its name)
	if kind == "equipmentset" then return { kind = kind, name = type(id) == "string" and id or nil, id = id } end
	return { kind = kind, id = id }
end

local function Key(record)
	if not record then return "" end
	if record.kind == "macro" or record.kind == "equipmentset" then return record.kind .. ":" .. tostring(record.name) end
	return record.kind .. ":" .. tostring(record.id)
end

local function ReadAll()
	local bars, count = {}, 0
	for slot = 1, SLOTS do
		local record = Read(slot)
		if record then
			bars[slot] = record
			count = count + 1
		end
	end
	return bars, count
end

local function Count(list)
	local count = 0
	for _ in pairs(list or {}) do count = count + 1 end
	return count
end

local function Known(id)
	return Clean(Safe(IsPlayerSpell, id)) or Clean(Safe(IsSpellKnown, id)) or false
end

local function Name(record)
	if record.kind == "spell" then
		return C_Spell and C_Spell.GetSpellName and Clean(Safe(C_Spell.GetSpellName, record.id)) or tostring(record.id)
	elseif record.kind == "item" then
		return C_Item and C_Item.GetItemNameByID and Clean(Safe(C_Item.GetItemNameByID, record.id)) or tostring(record.id)
	end
	return record.name or tostring(record.id)
end

-- Picked up, ready to be put in a slot (false: it can't be, now).
local function Pickup(record)
	if record.kind == "spell" then
		if not Known(record.id) then return false end
		if C_Spell and C_Spell.PickupSpell then Safe(C_Spell.PickupSpell, record.id) else Safe(_G.PickupSpell, record.id) end
	elseif record.kind == "item" then
		if C_Item and C_Item.PickupItem then Safe(C_Item.PickupItem, record.id) else Safe(_G.PickupItem, record.id) end
	elseif record.kind == "macro" then
		local index = record.name and Clean(Safe(GetMacroIndexByName, record.name))
		if type(index) ~= "number" or index <= 0 then return false end
		Safe(PickupMacro, index)
	elseif record.kind == "equipmentset" then
		local set = C_EquipmentSet and record.name and Clean(Safe(C_EquipmentSet.GetEquipmentSetID, record.name))
		if not set then return false end
		Safe(C_EquipmentSet.PickupEquipmentSet, set)
	else
		return false
	end
	return Clean(Safe(GetCursorInfo)) ~= nil
end

local function Put(slot)
	if CAB and CAB.PutActionInSlot then Safe(CAB.PutActionInSlot, slot) else Safe(_G.PlaceAction, slot) end
end

-- One record into one slot (whatever was there let go). true when it is there now.
local function Place(slot, record)
	if not Pickup(record) then
		Safe(ClearCursor)
		return false
	end
	Put(slot)
	Safe(ClearCursor)
	return Key(Read(slot)) == Key(record)
end

local function Clear(slot)
	if not Read(slot) then return end
	Safe(_G.PickupAction, slot)
	Safe(ClearCursor)
end

local function Busy()
	return InCombatLockdown() or Clean(Safe(GetCursorInfo)) ~= nil
end

local Snapshot, Show -- (below)

-- Serene's own placing: its changes not taken for yours, the copy taken once it is done.
local function Placing(fn)
	placing = true
	-- (in pcall: placing always ends, even if fn fails)
	local ok, a, b = pcall(fn)
	-- (past SETTLE, so the slot changes it caused have all come and been muted)
	C_Timer.After(SETTLE + 0.2, function()
		placing = false
		-- (what Serene itself changed is no loss: the bars as they are now become the copy, nothing compared)
		if store then store.stale = true end
		Snapshot()
	end)
	if ok then return a, b end
end

-- What left your bars back where it was (each slot still empty); the rest waits for its spell.
local function Restore(quiet)
	if not store or not store.lost then return end
	if Busy() then
		fightWaits = InCombatLockdown()
		return
	end
	local back = 0
	Placing(function()
		for slot, record in pairs(store.lost) do
			if Read(slot) then
				-- (the slot used since: yours, and the old one not waited for any more)
				store.lost[slot] = nil
			elseif Place(slot, record) then
				store.lost[slot] = nil
				back = back + 1
			end
		end
	end)
	store.armed = true
	if not next(store.lost) then store.lost, store.armed = nil, nil end
	if back > 0 then ns.Print(("bars: %d back in their place%s"):format(back, quiet and " (learnt again)" or "")) end
	Show()
end

local function Forget()
	if not store then return end
	store.lost, store.armed = nil, nil
	Show()
end

-- The quiet button -------------------------------------------------------------------------------------------------

local function Pill()
	if pill then return pill end
	local last = _G.ActionButton12
	if type(last) ~= "table" then return nil end
	-- (on UIParent, not the bar: seen while the bars are faded)
	pill = CreateFrame("Button", "SereneBarSetsButton", UIParent)
	pill:SetFrameStrata("MEDIUM")
	pill:SetHeight(20)
	pill:SetPoint("BOTTOMRIGHT", last, "TOPRIGHT", 0, 8)
	pill.bg = pill:CreateTexture(nil, "BACKGROUND")
	pill.bg:SetAllPoints()
	pill.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.85)
	pill.lines = ns.Hairline(pill)
	pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pill.text:SetPoint("CENTER")
	pill.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	pill:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pill:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then Forget() else Restore() end
	end)
	pill:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Left your bars", GOLD[1], GOLD[2], GOLD[3])
		local shown = 0
		for _, record in pairs(store and store.lost or {}) do
			shown = shown + 1
			if shown <= 12 then
				local waits = record.kind == "spell" and not Known(record.id)
				GameTooltip:AddDoubleLine(Name(record), waits and "not learnt yet" or "", 0.91, 0.894, 0.855, 0.56, 0.56, 0.56)
			end
		end
		if shown > 12 then GameTooltip:AddLine(("and %d more"):format(shown - 12), 0.56, 0.56, 0.56) end
		GameTooltip:AddLine("Click: back in their place (the rest as you learn them)", 0.56, 0.56, 0.56)
		GameTooltip:AddLine("Right-click: forget them", 0.56, 0.56, 0.56)
		GameTooltip:Show()
		self.text:SetTextColor(1, 1, 1)
	end)
	pill:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end)
	pill:Hide()
	return pill
end

Show = function()
	local button = Pill()
	if not button then return end
	local lost = store and Count(store.lost) or 0
	-- (nothing can be put back in a fight)
	if not ns.On("barSets") or lost == 0 or InCombatLockdown() then return button:Hide() end
	local waiting = 0
	for _, record in pairs(store.lost) do
		if record.kind == "spell" and not Known(record.id) then waiting = waiting + 1 end
	end
	if store.armed and waiting == lost then
		button.text:SetText(lost == 1 and "1 action waits for its spell" or ("%d actions wait for their spells"):format(lost))
	else
		button.text:SetText(lost == 1 and "An action left your bars: put it back"
			or ("%d actions left your bars: put them back"):format(lost))
	end
	button:SetWidth((Clean(Safe(button.text.GetStringWidth, button.text)) or 200) + 20)
	button.lines:Fit()
	button:Show()
end

-- Looking at the bars ------------------------------------------------------------------------------------------------

-- The copy taken again; actions that left by themselves noted first.
Snapshot = function()
	queued = false
	if store and not ns.On("barSets") then store.stale = true end
	if not store or not settled or placing or not ns.On("barSets") then return end
	if Busy() then
		-- (a fight: looked at again when it ends; something on the cursor: again in a moment)
		fightWaits = fightWaits or InCombatLockdown()
		if not InCombatLockdown() then C_Timer.After(SETTLE, Snapshot) end
		return
	end
	local now, count = ReadAll()
	-- (nothing at all: the bars not read yet, not a wipe)
	if count == 0 and next(store.copy) then return end
	-- (switched off for a while: the bars as they are now are the copy, nothing taken as lost)
	if store.stale then
		store.copy, store.stale = now, nil
		return Show()
	end
	local gone, unlearnt = {}, 0
	for slot, record in pairs(store.copy) do
		if not now[slot] then
			gone[slot] = record
			if record.kind == "spell" and not Known(record.id) then unlearnt = unlearnt + 1 end
		end
	end
	if Count(gone) >= WIPE_AT or unlearnt > 0 then
		store.lost = store.lost or {}
		for slot, record in pairs(gone) do store.lost[slot] = record end
	end
	-- (a slot waited for and used since: yours now)
	for slot in pairs(store.lost or {}) do
		if now[slot] then store.lost[slot] = nil end
	end
	if store.lost and not next(store.lost) then store.lost, store.armed = nil, nil end
	store.copy = now
	Show()
end

local function Queue()
	if queued or placing then return end
	queued = true
	C_Timer.After(SETTLE, Snapshot)
end

-- Learnt again: what waits for it back in its slot (after the first click, or at once when nothing else waits).
local function Learnt()
	if not store or not store.lost or not store.armed then return Show() end
	for _, record in pairs(store.lost) do
		if record.kind ~= "spell" or Known(record.id) then
			C_Timer.After(0.5, function() Restore(true) end)
			return
		end
	end
	Show()
end

-- Sets ---------------------------------------------------------------------------------------------------------------

local function Copy(bars)
	local out = {}
	for slot, record in pairs(bars) do
		out[slot] = { kind = record.kind, id = record.id, name = record.name }
	end
	return out
end

function ns.BarSetSave(name)
	if not store or type(name) ~= "string" or name == "" then return end
	store.sets[name] = Copy((ReadAll()))
	ns.Print(("bars saved as \"%s\" (%d actions)"):format(name, Count(store.sets[name])))
end

function ns.BarSetLoad(name)
	local set = store and store.sets[name or ""]
	if not set then return ns.Print(("no set called \"%s\" (/serene sets)"):format(tostring(name))) end
	if InCombatLockdown() then return ns.Print("bars: not in a fight") end
	if Clean(Safe(GetCursorInfo)) ~= nil then return ns.Print("bars: put down what you hold first") end
	if name ~= UNDO then store.sets[UNDO] = Copy((ReadAll())) end
	local missed = {}
	Placing(function()
		for slot = 1, SLOTS do
			local want, now = set[slot], Read(slot)
			if Key(want) ~= Key(now) then
				if not want then
					Clear(slot)
				elseif not Place(slot, want) then
					missed[#missed + 1] = Name(want)
				end
			end
		end
	end)
	ns.Print(("bars: \"%s\" put on%s"):format(name, #missed > 0 and (" (not placed: " .. table.concat(missed, ", ") .. ")") or ""))
end

function ns.BarSetDelete(name)
	if not store or not store.sets[name or ""] then return ns.Print(("no set called \"%s\""):format(tostring(name))) end
	store.sets[name] = nil
	ns.Print(("set \"%s\" deleted"):format(name))
end

function ns.BarSetList()
	if not store then return end
	local names = {}
	for name, set in pairs(store.sets) do names[#names + 1] = ("%s (%d)"):format(name, Count(set)) end
	table.sort(names)
	ns.Print("sets: " .. (#names > 0 and table.concat(names, ", ") or "none yet")
		.. "  -  /serene sets save|load|delete <name>")
end

-- (BarUse.lua: changes of its own, a clear or a swap, never taken for actions leaving by themselves)
function ns.BarSetsMine(fn) return Placing(fn) end
function ns.BarSetHas(name) return store and store.sets[name] ~= nil or false end
function ns.BarSetsRestore() Restore() end
function ns.BarSetsLost() return store and Count(store.lost) or 0 end

-- Wiring ---------------------------------------------------------------------------------------------------------------

local function Init()
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	ns.db.barSetsBy = ns.db.barSetsBy or {}
	ns.db.barSetsBy[who] = ns.db.barSetsBy[who] or {}
	store = ns.db.barSetsBy[who]
	store.copy = store.copy or {}
	store.sets = store.sets or {}
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			-- (the bars read whole a few seconds in: before, an empty slot may only be one not loaded yet)
			if not settled then C_Timer.After(3, function() settled = true Snapshot() end) end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			if pill then pill:Hide() end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if fightWaits then
				fightWaits = false
				Queue()
			end
			return Show()
		end
		if event == "ACTIONBAR_SLOT_CHANGED" then return Queue() end
		-- (a spell learnt: the copy looked at again, and what waits for it brought back once that copy is taken)
		Queue()
		C_Timer.After(SETTLE + 0.5, Learnt)
	end)
end

local function Refresh()
	if not store then return end
	if not ns.On("barSets") then store.stale = true elseif store.stale then Queue() end
	Show()
end

function ns.BarSetsDebug()
	local sets = store and Count(store.sets) or 0
	ns.Print(("bars kept: %s; copy of %d actions, %d left the bars%s, %d sets"):format(tostring(ns.On("barSets")),
		store and Count(store.copy) or 0, store and Count(store.lost) or 0,
		store and store.armed and " (back as learnt)" or "", sets))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
