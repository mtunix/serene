local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Rest mode, the whole interface away (its opacity only: nothing hidden, nothing moved, safe in a fight).
-- Away (the game's AFK), or nothing done for a while (no mouse, no walking, no cast, no typing): all of it
-- fades away; the mouse moved, a step, a key in the chat, and it is back at once.           (/serene idle on|off,
-- /serene idle 30-1800: the seconds before it rests)
-- Never in a fight, never in Edit Mode.

local AWAY_AFTER = 8                 -- seconds still, once the game says you are away
local FADE_OUT, FADE_IN = 1.2, 0.25
local CHECK_EVERY = 0.1

local alpha = 1                      -- the interface's opacity as Serene holds it
local touched = false                -- Serene wrote UIParent's opacity (given back at full once done)
local lastActive = GetTime()
local lastX, lastY
local fighting = false

local function Typing()
	local get = _G.ChatEdit_GetActiveWindow or (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow)
	local box = get and Safe(get)
	return type(box) == "table" and Safe(box.HasFocus, box) and true or false
end

-- Anything you do now: the mouse moved, walking, casting, typing.
local function Active()
	local x, y = GetCursorPosition()
	local moved = lastX ~= nil and (math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2)
	lastX, lastY = x, y
	if moved then return true end
	local speed = Clean(Safe(GetUnitSpeed, "player"))
	if type(speed) == "number" and speed > 0 then return true end
	if Clean(Safe(UnitCastingInfo, "player")) or Clean(Safe(UnitChannelInfo, "player")) then return true end
	return Typing()
end

local function EditMode()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and manager.IsEditModeActive and Safe(manager.IsEditModeActive, manager) and true or false
end

-- What the interface should be now: "rest" or nil (all of it).
local function Mode(now)
	if fighting or EditMode() or (ns.IsPeeking and ns.IsPeeking()) then return nil end
	if ns.On("idle") then
		local still = now - lastActive
		local away = Clean(Safe(UnitIsAFK, "player"))
		if still >= (ns.db.idleAfter or 120) or (away and still >= AWAY_AFTER) then return "rest" end
	end
	return nil
end
ns.ModesMode = Mode -- (tests)

local mode
-- The mode now: "rest" or nil.
function ns.ModeNow() return mode end
local function Step(elapsed)
	local want = mode and 0 or 1
	if alpha == want and not (want == 1 and touched) then return end
	alpha = ns.Approach(alpha, want, elapsed, FADE_IN, FADE_OUT)
	pcall(UIParent.SetAlpha, UIParent, alpha)
	touched = alpha < 1
end

local function Init()
	local since = 0
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= CHECK_EVERY then
			since = 0
			local now = GetTime()
			if Active() then lastActive = now end
			local new = Mode(now)
			-- (resting: anything done brings it all back at once)
			if new == "rest" and now - lastActive < CHECK_EVERY * 2 then new = nil end
			if new ~= mode then
				mode = new
				if ns.HintsDirty then ns.HintsDirty() end
			end
		end
		Step(elapsed)
	end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_STARTED_MOVING",
		"MODIFIER_STATE_CHANGED", "PLAYER_CONTROL_GAINED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then fighting = true
		elseif event == "PLAYER_REGEN_ENABLED" then fighting = false end
		-- (anything happening to you: awake; a fight brings the interface back at once)
		lastActive = GetTime()
		if fighting and mode then mode = nil end
	end)
	fighting = InCombatLockdown() and true or false
end

table.insert(ns.modules, { init = Init })
