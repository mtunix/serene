local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The action buttons and what is on them, worked out in one place for every file about the bars (ActionBars, Ready,
-- Hints, BarCooldowns, BarPing, BarUse, Ranks, Reagents...). Only reading: nothing here changes a button or a slot.
--   ns.Actions.Buttons(all) / Each(fn, all)  the game's action buttons (all: the pet's, stances' and possess' too),
--                                            whether or not Serene's action bars are on
--   BarOf(button), BarButtons(button)        its bar's key ("main", "bar2"... "pet", "stance"), that bar's buttons
--   Slot(button)                             the action slot it shows (nil: none, or not an action button)
--   What(slot)                               what is on a slot, as a word that stays the same while it does
--                                            ("spell:133", "macro:<name>"; saved by BarUse.lua, so never change it)
--   Cast(slot), SpellOn(slot)                what a slot casts ("spell"/"item", id; a macro's own spell or item),
--                                            the spell put there directly
--   Usable, InRange, Current, OnCooldown, Cooldown (slot); Proc(button), Glows(button, fn)
-- The game's calls the new way first and the old one as a fallback. Unknown is never a fact: what can't be read
-- (a secret value in a fight) comes back nil, and callers never dim, glow or count on a nil.

local Actions = {}
ns.Actions = Actions

Actions.SLOTS = 180 -- every action slot (all pages, stances and forms)
local GCD_HOLD = 1.6 -- a cooldown with no word on the global one counts once it lasts longer than this

-- Each family of buttons: how many, the bar it is for the looks (Edit Mode's names, Action Bar 1 to 8), its
-- binding's name and its bar's name as said to the player. The first eight hold action slots.
Actions.FAMILIES = {
	{ prefix = "ActionButton", count = 12, bar = "main", binding = "ACTIONBUTTON", label = "Bar 1", slots = true },
	{ prefix = "MultiBarBottomLeftButton", count = 12, bar = "bar2", binding = "MULTIACTIONBAR1BUTTON", label = "Bar 2", slots = true },
	{ prefix = "MultiBarBottomRightButton", count = 12, bar = "bar3", binding = "MULTIACTIONBAR2BUTTON", label = "Bar 3", slots = true },
	{ prefix = "MultiBarRightButton", count = 12, bar = "bar4", binding = "MULTIACTIONBAR3BUTTON", label = "Bar 4", slots = true },
	{ prefix = "MultiBarLeftButton", count = 12, bar = "bar5", binding = "MULTIACTIONBAR4BUTTON", label = "Bar 5", slots = true },
	{ prefix = "MultiBar5Button", count = 12, bar = "bar6", binding = "MULTIACTIONBAR5BUTTON", label = "Bar 6", slots = true },
	{ prefix = "MultiBar6Button", count = 12, bar = "bar7", binding = "MULTIACTIONBAR6BUTTON", label = "Bar 7", slots = true },
	{ prefix = "MultiBar7Button", count = 12, bar = "bar8", binding = "MULTIACTIONBAR7BUTTON", label = "Bar 8", slots = true },
	{ prefix = "PetActionButton", count = 10, bar = "pet" },
	{ prefix = "StanceButton", count = 10, bar = "stance" },
	{ prefix = "PossessButton", count = 2, bar = "stance" },
}

local CAB = _G.C_ActionBar

-- The buttons -----------------------------------------------------------------------------------------------------

local slotButtons, allButtons -- the lists, once found after login
local barOf = {}     -- button -> its bar's key
local byBar = {}     -- bar key -> its slot buttons, in order
local holdsSlot = {} -- button -> true for the eight families that hold action slots

local function Collect()
	local slots, all = {}, {}
	wipe(byBar)
	for _, family in ipairs(Actions.FAMILIES) do
		for index = 1, family.count do
			local button = _G[family.prefix .. index]
			if type(button) == "table" and button.GetObjectType and button.SetAlpha then
				all[#all + 1] = button
				barOf[button] = family.bar
				if family.slots then
					slots[#slots + 1] = button
					holdsSlot[button] = true
					byBar[family.bar] = byBar[family.bar] or {}
					table.insert(byBar[family.bar], button)
				end
			end
		end
	end
	return slots, all
end

-- The game's action buttons (a list kept and shared: don't change it). all: with the pet's, stances' and possess'.
function Actions.Buttons(all)
	if not allButtons then
		local slots, every = Collect()
		-- (kept once the game has made its bars: before login some may not be there yet)
		if not (IsLoggedIn and IsLoggedIn()) then return all and every or slots end
		slotButtons, allButtons = slots, every
	end
	return all and allButtons or slotButtons
end

function Actions.Each(fn, all)
	for _, button in ipairs(Actions.Buttons(all)) do pcall(fn, button, barOf[button]) end
end

function Actions.BarOf(button)
	if not allButtons then Actions.Buttons() end
	return barOf[button]
end

-- The buttons of the bar this one is on (just this one when it isn't an action bar's).
function Actions.BarButtons(button)
	if not allButtons then Actions.Buttons() end
	return byBar[barOf[button]] or { button }
end

-- One of a button's parts by its key, or by the old global name (ActionButton1Icon).
function Actions.Region(button, key)
	local name = button.GetName and button:GetName()
	return rawget(button, key) or (name and _G[name .. key])
end

-- What is on a slot ------------------------------------------------------------------------------------------------

-- The action slot a button shows. The pet's, stances' and possess' buttons have none.
function Actions.Slot(button)
	if type(button) ~= "table" then return nil end
	local slot = Clean(rawget(button, "action"))
	if type(slot) ~= "number" and holdsSlot[button] then
		-- (where the game keeps no number on the button: asked the ways the button itself knows)
		if button.GetPagedID then slot = Clean(Safe(button.GetPagedID, button)) end
		if type(slot) ~= "number" and button.CalculateAction then slot = Clean(Safe(button.CalculateAction, button)) end
		if type(slot) ~= "number" and button.GetAttribute then slot = Clean(Safe(button.GetAttribute, button, "action")) end
		if type(slot) ~= "number" and _G.ActionButton_GetPagedID then slot = Clean(Safe(_G.ActionButton_GetPagedID, button)) end
	end
	return type(slot) == "number" and slot > 0 and slot or nil
end

-- What a slot holds as a word: "kind:id", a macro by its name (its number moves when macros are added).
-- nil: empty, or can't be read. (BarUse.lua saves these: the form must stay as it is.)
function Actions.What(slot)
	local kind, id = Safe(GetActionInfo, slot)
	kind, id = Clean(kind), Clean(id)
	if not kind then return nil end
	if kind == "macro" then return "macro:" .. tostring(Clean(Safe(GetActionText, slot)) or id) end
	return tostring(kind) .. ":" .. tostring(id)
end

-- The spell put on a slot directly (not by a macro), or nil.
function Actions.SpellOn(slot)
	local kind, id = Safe(GetActionInfo, slot)
	kind, id = Clean(kind), Clean(id)
	if kind == "spell" and type(id) == "number" then return id end
	return nil
end

-- What a slot casts: "item", id or "spell", id; a macro, what it shows.
function Actions.Cast(slot)
	local kind, id, sub = Safe(GetActionInfo, slot)
	kind, id, sub = Clean(kind), Clean(id), Clean(sub)
	if kind == "item" and type(id) == "number" then return "item", id end
	if kind == "spell" and type(id) == "number" then return "spell", id end
	if kind == "macro" and id then
		-- (the newer game names the macro's spell or item itself; the older one, the macro)
		if sub == "spell" and type(id) == "number" then return "spell", id end
		if sub == "item" and type(id) == "number" then return "item", id end
		local _, link = Safe(GetMacroItem, id)
		link = Clean(link)
		local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if item then return "item", item end
		local spell = Clean(Safe(GetMacroSpell, id))
		if type(spell) == "number" then return "spell", spell end
	end
end

-- Its state now ------------------------------------------------------------------------------------------------------

-- Usable now, and if not, for want of mana (rage, energy). Never secret on this client.
function Actions.Usable(slot)
	local fn = CAB and CAB.IsUsableAction or _G.IsUsableAction
	if not fn then return nil end
	local usable, noMana = Safe(fn, slot)
	return Clean(usable), Clean(noMana)
end

-- false only when the game says out of range (nil: no range, or no target).
function Actions.InRange(slot)
	local fn = CAB and CAB.IsActionInRange or _G.IsActionInRange
	if not fn then return nil end
	local inRange = Clean(Safe(fn, slot))
	if inRange == 0 then return false end
	if inRange == 1 then return true end
	return inRange
end

-- In use now: auto attack, a channel, a spell waiting for its target.
function Actions.Current(slot)
	local current = CAB and CAB.IsCurrentAction or _G.IsCurrentAction
	local repeating = CAB and CAB.IsAutoRepeatAction or _G.IsAutoRepeatAction
	return (current and Clean(Safe(current, slot))) or (repeating and Clean(Safe(repeating, slot))) or false
end

-- The cooldown left without the global one, as the game's duration object (handed on to the game's widgets, never
-- read: its numbers are secret in a fight). nil when the game can't give it.
function Actions.Cooldown(slot)
	if not (CAB and CAB.GetActionCooldownDuration) then return nil end
	return Safe(CAB.GetActionCooldownDuration, slot, true)
end

-- On its own cooldown (not the global one)? true, false, or nil when it can't be told. Second: how it was told (for
-- /serene debug).
-- How this client tells (12.x, secret values in fights): the cooldown's startTime/duration are secret, but isActive
-- and isOnGCD are not, and GetActionCooldownDuration(slot, true) leaves the global cooldown out.
local activeSince = {} -- slot -> when its cooldown was first seen without word on the global one
function Actions.OnCooldown(slot)
	-- (a duration that leaves the global cooldown out: zero when nothing else holds the slot)
	local duration = Actions.Cooldown(slot)
	if duration and not Clean(Safe(duration.HasSecretValues, duration)) then
		local zero = Clean(Safe(duration.IsZero, duration))
		if type(zero) == "boolean" then return not zero, "duration" end
	end
	-- (the cooldown's own word: isActive and isOnGCD are never secret)
	if CAB and CAB.GetActionCooldown then
		local info = Safe(CAB.GetActionCooldown, slot)
		local active = info and Clean(Safe(function() return info.isActive end))
		local gcd = info and Clean(Safe(function() return info.isOnGCD end))
		if active == false then
			activeSince[slot] = nil
			return false, "isActive"
		end
		if active == true then
			if gcd == true then return false, "isOnGCD" end
			-- (no word on the global cooldown: it counts once it outlasts one)
			local length = Clean(Safe(function() return info.duration end))
			if type(length) == "number" then return length > GCD_HOLD, "duration (secret-free)" end
			activeSince[slot] = activeSince[slot] or GetTime()
			return GetTime() - activeSince[slot] > GCD_HOLD, "hold"
		end
	end
	-- (the old call: start, duration, enabled)
	if _G.GetActionCooldown then
		local _, length = Safe(_G.GetActionCooldown, slot)
		length = Clean(length)
		if type(length) == "number" then return length > GCD_HOLD, "old call" end
	end
	return nil, "unknown"
end

-- The square glows a button can wear: the game's proc (new and old), its spell highlight, and the glow libraries
-- addons use (LibButtonGlow, LibCustomGlow).
local GLOW_KEYS = { "SpellActivationAlert", "overlay", "Overlay", "SpellHighlightTexture", "__LBGoverlay",
	"_ButtonGlow", "ProcGlow" }

-- Each glow the button has (shown or not): fn(glow, key).
function Actions.Glows(button, fn)
	for _, key in ipairs(GLOW_KEYS) do
		local glow = rawget(button, key)
		if type(glow) == "table" and glow.SetAlpha then fn(glow, key) end
	end
end

-- A proc on the button: the game's alert manager says so, or one of its glows shows (even put out of sight by
-- ActionBars.lua's Glass and Round, which light their own: only its opacity changes, it stays shown).
function Actions.Proc(button)
	local manager = _G.ActionButtonSpellAlertManager
	if type(manager) == "table" and manager.HasAlert and Clean(Safe(manager.HasAlert, manager, button)) then
		return true
	end
	local on = false
	Actions.Glows(button, function(glow)
		if not on and Clean(Safe(glow.IsShown, glow)) then on = true end
	end)
	return on
end
