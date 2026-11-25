-- Picking up and placing actions as the game does, for the bar specs (dofile'd at a spec's top, after wow.lua).
-- What is on the cursor is wow.held (the whole action: { kind, id, subType, text }), shown by GetCursorInfo.
-- Placing an action fires ACTIONBAR_SLOT_CHANGED, like the game: after the code that placed it has run (the game's
-- events come between frames, never in the middle of a script).

wow.actions = wow.actions or {}
wow.macroList = wow.macroList or {} -- index -> name
wow.book = wow.book or {}           -- spellbook slot -> { id = , name = , lowRank = }

local function Hold(record)
	wow.held = record
	wow.cursor = record and { record.kind, record.id } or nil
end

function GetCursorInfo() if wow.held then return wow.held.kind, wow.held.id end end
function ClearCursor() Hold(nil) end
function CursorHasItem() return wow.held ~= nil and wow.held.kind == "item" end

function PickupAction(slot)
	local had = wow.actions[slot]
	wow.actions[slot] = nil
	Hold(had)
	C_Timer.After(0, function() wow.fire("ACTIONBAR_SLOT_CHANGED", slot) end)
end

function PlaceAction(slot)
	if not wow.held then return end
	local old = wow.actions[slot]
	wow.actions[slot] = wow.held
	Hold(old)
	C_Timer.After(0, function() wow.fire("ACTIONBAR_SLOT_CHANGED", slot) end)
end

C_Spell.PickupSpell = function(id) if IsSpellKnown(id) then Hold({ kind = "spell", id = id }) end end
PickupSpell = C_Spell.PickupSpell
C_Item.PickupItem = function(id) Hold({ kind = "item", id = id }) end
PickupItem = C_Item.PickupItem

function GetMacroIndexByName(name)
	for index, macro in pairs(wow.macroList) do if macro == name then return index end end
	return 0
end
function PickupMacro(index)
	local name = wow.macroList[index]
	if name then Hold({ kind = "macro", id = index, text = name }) end
end

-- The spellbook (C_SpellBook, one skill line holding wow.book's slots).
C_SpellBook = C_SpellBook or {}
C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #wow.book } end
C_SpellBook.GetSpellBookItemInfo = function(slot)
	local s = wow.book[slot]
	if s then return { actionID = s.id, spellID = s.id, name = s.name, isPassive = s.passive or false, itemType = 1 } end
end
C_SpellBook.IsSpellBookItemLowRank = function(slot) local s = wow.book[slot] return s and s.lowRank or false end
C_SpellBook.PickupSpellBookItem = function(slot)
	local s = wow.book[slot]
	if s then Hold({ kind = "spell", id = s.id }) end
end

-- Put an action on a slot directly (as if it was always there).
function wow.put(slot, kind, id, text)
	wow.actions[slot] = { kind = kind, id = id, text = text }
end
