local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Readiness: an action button as present as it is ready. What can be pressed now stays at full; what can't (on its
-- cooldown, short of mana, rage or energy, unusable now, an attack with no enemy targeted, out of range) steps back to a faint shade, and comes back
-- the moment it is ready again. In a fight the eye finds what can be pressed without reading the bar.
-- Always at full, whatever its state: a proc (the game's glow), a button Serene's hints light, the one in use (auto
-- attack, a channel), every button while a spell or item is on the cursor, in Edit Mode or while peeking, and (a
-- setting) the whole bar the mouse is on.
-- The global cooldown is not a cooldown here: every button would blink with each cast.
-- Only the buttons' opacity changes (allowed in a fight); the game still draws, presses and colours them, Fade.lua
-- still fades their bars (the two multiply). Works with the game's own look as well as Serene's.
--   /serene ready on|off      (the rest: Settings > Action bars)
--
-- What a slot's state is comes from Actions.lua (secret values in fights: how this client tells is written there).
-- Unknown is never a fact: a state that can't be read never dims a button.

local CHECK_EVERY = 0.5    -- the safety look (a cooldown's end, a mana tick no event told of)
local HOVER_EVERY = 0.1    -- the mouse over a bar
local FADE_IN, FADE_OUT = 0.12, 0.35 -- seconds: back quickly, away gently

local Actions = ns.Actions
local buttons = {}     -- the action buttons found
local alphaNow = {}    -- button -> the opacity Serene gave it
local alphaWant = {}   -- button -> the opacity it is going to
local reasonOf = {}    -- button -> why it is faint ("cooldown", "power", "unusable", "target", "range", "unused")
local touched = false  -- Serene changed some button's opacity (given back at full once off)
local dirty = true
local driver
local lastHover = {}   -- bar -> under the mouse at the last look
local cooldownBy = "?" -- how the last cooldown was read (for /serene debug)

local CAB = _G.C_ActionBar

-- An attack with nothing to attack: a harmful action while the target is you, a friend, dead, or there is none.
-- (IsUsableAction says yes to these whoever is targeted, and the range check has no answer for a friend.)
-- A secret answer on the target counts as an enemy, as everywhere in Serene: unknown never dims.
local function WrongTarget(slot)
	local harmful = CAB and CAB.IsHarmfulAction or _G.IsHarmfulAction
	if not harmful or Clean(Safe(harmful, slot, false)) ~= true then return false end
	if not Clean(Safe(UnitExists, "target")) then return true end
	if Clean(Safe(UnitIsDeadOrGhost, "target")) == true then return true end
	return Clean(Safe(UnitCanAttack, "player", "target")) == false
end

local function EditMode()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and manager.IsEditModeActive and Clean(Safe(manager.IsEditModeActive, manager))
		and true or false
end

local function Fighting()
	return InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player")) and true or false
end

-- Why a button is faint now (nil: it is ready, or it can't be told).
local function Reason(slot)
	local db = ns.db
	-- (a button you chose to fade, unused for long: BarUse.lua)
	if ns.BarUseFaded and ns.BarUseFaded(slot) then return "unused" end
	if db.barReadyCooldown then
		local on, how = Actions.OnCooldown(slot)
		cooldownBy = how
		if on == true then return "cooldown" end
	end
	local usable, noMana = Actions.Usable(slot)
	if usable == false then
		if noMana then
			if db.barReadyPower then return "power" end
		elseif db.barReadyUnusable then
			return "unusable"
		end
	end
	if db.barReadyTarget and WrongTarget(slot) then return "target" end
	if db.barReadyRange and Actions.InRange(slot) == false then return "range" end
	return nil
end

-- Looking at every button -----------------------------------------------------------------------------------------

local function Collect()
	buttons = Actions.Buttons()
end

local function Enabled()
	return ns.db and ns.On("barReady") and (ns.db.barReadyWhen ~= "fight" or Fighting())
end

local function Look()
	dirty = false
	local enabled = Enabled()
	local faint = math.max(0, math.min(100, tonumber(ns.db and ns.db.barReadyDim) or 30)) / 100
	local all = not enabled or EditMode() or (ns.IsPeeking and ns.IsPeeking()) or Clean(Safe(GetCursorInfo)) ~= nil
	local lit = {}
	if enabled and ns.HintButtons then
		for _, button in ipairs(ns.HintButtons() or {}) do lit[button] = true end
	end
	local hover = enabled and ns.On("barReadyHover")
	for _, button in ipairs(buttons) do
		local want, reason = 1, nil
		local slot = Actions.Slot(button)
		if not all and slot and Clean(Safe(HasAction, slot)) then
			local bar = button.GetParent and button:GetParent()
			if not lit[button] and not (hover and lastHover[bar]) and not Actions.Current(slot)
				and not Actions.Proc(button) then
				reason = Reason(slot)
				if reason then want = faint end
			end
		end
		reasonOf[button] = reason
		alphaWant[button] = want
	end
end

local function Step(elapsed)
	local moving = false
	for _, button in ipairs(buttons) do
		local want = alphaWant[button] or 1
		local now = alphaNow[button] or 1
		if now ~= want then
			now = ns.Approach(now, want, elapsed, FADE_IN, FADE_OUT)
			alphaNow[button] = now
			pcall(button.SetAlpha, button, now)
			touched = true
			if now ~= want then moving = true end
		end
	end
	return moving
end

-- Everything back at full (switched off).
local function Restore()
	for _, button in ipairs(buttons) do
		if touched then pcall(button.SetAlpha, button, 1) end
		alphaNow[button], alphaWant[button], reasonOf[button] = nil, nil, nil
	end
	touched = false
end

-- The mouse over a bar: a look only when it changes.
local function Hover()
	if not ns.On("barReadyHover") then
		if next(lastHover) then wipe(lastHover) dirty = true end
		return
	end
	for _, button in ipairs(buttons) do
		local bar = button.GetParent and button:GetParent()
		if bar and lastHover[bar] == nil then lastHover[bar] = false end
	end
	for bar, was in pairs(lastHover) do
		local over = ns.Over(bar)
		if over ~= was then
			lastHover[bar] = over
			dirty = true
		end
	end
end

local function Dirty() dirty = true end

local function Init()
	Collect()
	driver = CreateFrame("Frame")
	local sinceCheck, sinceHover = 0, 0
	driver:SetScript("OnUpdate", function(_, elapsed)
		if not ns.On("barReady") then
			if touched then Restore() end
			return
		end
		sinceCheck, sinceHover = sinceCheck + elapsed, sinceHover + elapsed
		if sinceHover >= HOVER_EVERY then
			sinceHover = 0
			Hover()
		end
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			dirty = true
		end
		if dirty then Look() end
		Step(elapsed)
	end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "ACTION_USABLE_CHANGED",
		"ACTIONBAR_UPDATE_USABLE", "ACTION_RANGE_CHECK_UPDATE", "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_SLOT_CHANGED",
		"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "PLAYER_TARGET_CHANGED",
		"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "CURSOR_CHANGED",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_FACTION", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	-- (a moment later: the game updates its buttons after the same event)
	events:SetScript("OnEvent", function() C_Timer.After(0, Dirty) end)
	-- (a cooldown that ends fires nothing for that button: the safety look catches it within CHECK_EVERY)
end

local function Refresh()
	if not driver then return end
	if not ns.On("barReady") then
		Restore()
	else
		dirty = true
	end
end

function ns.ReadyDebug()
	local counts, faint = {}, 0
	for _, button in ipairs(buttons) do
		local reason = reasonOf[button]
		if reason then
			counts[reason] = (counts[reason] or 0) + 1
			faint = faint + 1
		end
	end
	local parts = {}
	for reason, count in pairs(counts) do parts[#parts + 1] = reason .. " " .. count end
	ns.Print(("readiness: %s (%s), %d buttons, %d faint%s; cooldowns read by %s; fighting %s"):format(
		tostring(ns.On("barReady")), tostring(ns.db.barReadyWhen), #buttons, faint,
		#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "", cooldownBy, tostring(Fighting())))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
