local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The action buttons' cooldowns, in the look of their bar (ActionBars.lua):
--   sweep  the game's dark sweep over the icon (square, or round on a round icon)
--   line   no sweep: a thin gold line filling along the icon's foot until it is ready (Glass's own)
--   ring   the round icon's gold ring darkened and given back as the cooldown runs (Round's own)
--   none   nothing over the icon (readiness, Ready.lua, can still say it)
-- "The look's own" picks: Classic the sweep, Glass the line, Round the ring.
-- Its numbers: the game's setting, only in the last seconds, always, or never.
-- One global cooldown line: the global cooldown left off every button and drawn once instead, a gold hairline under
-- Action Bar 1 filling with it.
-- Timing is never read (secret in a fight): the game's duration objects are handed to the game's own widgets
-- (a cooldown frame, a status bar's timer), and the last seconds are found by a curve the game samples.
-- With Serene's action bars only (/serene bars).

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local DISC = MEDIA .. "AuraDisc"
local RING = MEDIA .. "Ring"
local INK = ns.INK
local GOLD = { 1, 0.82, 0.35 }
local GCD_SPELL = 61304       -- the game's own spell for the global cooldown
local SOON = 3                -- the last seconds, when the numbers show only then
local CHECK_EVERY = 0.1       -- the lines and the last seconds' numbers looked at again
local LINE_PX = 2             -- the cooldown line and the global cooldown line, in pixels
local FRAME_IN = 3 / 45       -- Classic: the game's frame covers this much of the icon (its sweep sits 3 in on 45)

local CAB = _G.C_ActionBar
local Actions = ns.Actions
local Region, Slot, Duration = Actions.Region, Actions.Slot, Actions.Cooldown
local looked = {}  -- button -> the cooldown look it wears ("sweep", "line", "ring", "none")
local lines = {}   -- button -> its cooldown line (a status bar)
local hooked = {}  -- cooldown frame -> true
local holding = false -- (Serene's own calls on a cooldown frame, not heard by its hooks)
local gcdBar
local curve

local function Zero(duration)
	if not duration then return nil end
	return Clean(Safe(duration.IsZero, duration))
end

local function Timer(bar, duration)
	local interpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	-- (filling with the time gone: full when ready)
	local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
	return pcall(bar.SetTimerDuration, bar, duration, interpolation, direction)
end

-- Which look a button's cooldown wears.
local function Mode(button)
	local style = ns.BarStyleOf and ns.BarStyleOf(button) or "classic"
	local want = ns.db and ns.db.barCooldown or "style"
	if want == "style" then
		want = style == "glass" and "line" or style == "round" and "ring" or "sweep"
	end
	if want == "ring" and style ~= "round" then want = "sweep" end
	-- (the pet's and the stances' have no slot to ask for a duration: the sweep)
	if want == "line" and not Slot(button) then want = "sweep" end
	return want, style
end

-- The cooldown line under the icon --------------------------------------------------------------------------------

local function Line(button, icon)
	local line = lines[button]
	if line then return line end
	line = CreateFrame("StatusBar", nil, button)
	line:SetStatusBarTexture(FLAT)
	line:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	line:SetMinMaxValues(0, 1)
	line.track = line:CreateTexture(nil, "BACKGROUND")
	line.track:SetAllPoints()
	line.track:SetColorTexture(INK[1], INK[2], INK[3], 0.75)
	line:EnableMouse(false)
	line:Hide()
	lines[button] = line
	return line
end

local function PlaceLine(button)
	local line, icon = lines[button], Region(button, "icon") or Region(button, "Icon")
	if not line or not icon then return end
	local px = ns.Pixel(button)
	-- (inside Classic's frame; Glass's and Round's icons are drawn in already)
	local inset = px
	if ns.BarStyleOf and ns.BarStyleOf(button) == "classic" then
		inset = (Clean(Safe(button.GetWidth, button)) or 45) * FRAME_IN
	end
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
	line:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
	line:SetHeight(LINE_PX * px)
	local cooldown = button.cooldown
	local level = cooldown and Clean(Safe(cooldown.GetFrameLevel, cooldown)) or Clean(Safe(button.GetFrameLevel, button))
	if type(level) == "number" then line:SetFrameLevel(level + 2) end -- (over the cooldown's sweep)
end

-- The line shown and timed while a cooldown (not the global one) runs.
local function UpdateLine(button)
	local line = lines[button]
	if not line then return end
	local slot = Slot(button)
	if looked[button] ~= "line" or not slot then return line:Hide() end
	local duration = Duration(slot)
	-- (a secret answer hides it: unknown never shows a cooldown)
	if Zero(duration) == false then
		Timer(line, duration)
		line:Show()
	else
		line:Hide()
	end
end

-- The cooldown frame's look ---------------------------------------------------------------------------------------

local function Paint(button, mode, style)
	local cooldown = button.cooldown
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not cooldown or not icon then return end
	-- (points only out of a fight: nothing on a secure button is moved in one)
	local place = not InCombatLockdown()
	holding = true
	if mode == "ring" then
		local rim = ns.BAR_RIM * ns.Pixel(button)
		if place then
			pcall(cooldown.ClearAllPoints, cooldown)
			pcall(cooldown.SetPoint, cooldown, "TOPLEFT", icon, "TOPLEFT", -rim, rim)
			pcall(cooldown.SetPoint, cooldown, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", rim, -rim)
		end
		pcall(cooldown.SetSwipeTexture, cooldown, RING)
		pcall(cooldown.SetUseCircularEdge, cooldown, true)
		-- (the part still to wait over the ring in the glass's dark: the gold comes back as it runs)
		pcall(cooldown.SetSwipeColor, cooldown, INK[1], INK[2], INK[3], 0.9)
		pcall(cooldown.SetDrawSwipe, cooldown, true)
		pcall(cooldown.SetDrawEdge, cooldown, false)
		pcall(cooldown.SetDrawBling, cooldown, false)
	else
		if place then
			-- (Classic: inside the game's frame, where the game puts it; Glass, Round: the icon, drawn in already)
			local inset = style == "classic" and (Clean(Safe(button.GetWidth, button)) or 45) * FRAME_IN or 0
			pcall(cooldown.ClearAllPoints, cooldown)
			pcall(cooldown.SetPoint, cooldown, "TOPLEFT", icon, "TOPLEFT", inset, -inset)
			pcall(cooldown.SetPoint, cooldown, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
		end
		local round = style == "round"
		pcall(cooldown.SetSwipeTexture, cooldown, round and DISC or FLAT)
		pcall(cooldown.SetUseCircularEdge, cooldown, round)
		pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, style == "classic" and 0.8 or 0.7)
		pcall(cooldown.SetDrawSwipe, cooldown, mode == "sweep")
		pcall(cooldown.SetDrawEdge, cooldown, false)
		pcall(cooldown.SetDrawBling, cooldown, mode == "sweep" and style == "classic")
	end
	holding = false
end

-- (the game paints the sweep again now and then: its colour while casting, its points with the bar's art)
local function Hear(button)
	local cooldown = button.cooldown
	if not cooldown or hooked[cooldown] then return end
	hooked[cooldown] = true
	local function Again()
		if holding or not looked[button] then return end
		-- (a frame later, once the game is done setting it)
		C_Timer.After(0, function() if looked[button] then Paint(button, looked[button], ns.BarStyleOf(button)) end end)
	end
	for _, method in ipairs({ "SetSwipeColor", "SetDrawSwipe", "SetSwipeTexture" }) do
		if cooldown[method] then hooksecurefunc(cooldown, method, Again) end
	end
end

-- Its numbers -------------------------------------------------------------------------------------------------------

local function GameNumbers()
	local value = Safe(GetCVar, "countdownForCooldowns")
	return value == "1"
end

local function Numbers(button)
	local cooldown = button.cooldown
	if not cooldown or not cooldown.SetHideCountdownNumbers then return end
	local want = ns.db and ns.db.barCooldownText or "game"
	local hide
	if want == "never" then hide = true
	elseif want == "always" or want == "soon" then hide = false
	else hide = not GameNumbers() end
	pcall(cooldown.SetHideCountdownNumbers, cooldown, hide)
	if want ~= "soon" then
		local text = cooldown.GetCountdownFontString and Safe(cooldown.GetCountdownFontString, cooldown)
		if text then pcall(text.SetAlpha, text, 1) end
	end
end

-- (the last seconds: a step the game samples on the duration, 1 under SOON seconds left, 0 above)
local function Curve()
	if curve ~= nil then return curve or nil end -- (false: tried, and this client can't make one)
	curve = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local ok, made = pcall(C_CurveUtil.CreateCurve)
	if not ok or not made then return nil end
	if Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(made.SetType, made, Enum.LuaCurveType.Step) end
	pcall(made.AddPoint, made, 0, 1)
	pcall(made.AddPoint, made, SOON + 0.05, 0)
	curve = made
	return curve
end

local function Soon(button)
	local cooldown, slot = button.cooldown, Slot(button)
	if not cooldown or not slot then return end
	-- (only a cooldown running: the frame shows while it does)
	if not Clean(Safe(cooldown.IsShown, cooldown)) then return end
	local text = cooldown.GetCountdownFontString and Safe(cooldown.GetCountdownFontString, cooldown)
	local duration = Duration(slot)
	local shape = Curve()
	if not text or not duration or not shape then return end
	local alpha = Safe(duration.EvaluateRemainingDuration, duration, shape)
	-- (handed on as it comes, secret or not)
	if alpha ~= nil then pcall(text.SetAlpha, text, alpha) end
end

-- A button dressed -----------------------------------------------------------------------------------------------

local function Active()
	return ns.On("actionBars")
end

function ns.CooldownLook(button)
	if not Active() or InCombatLockdown() then return end
	local mode, style = Mode(button)
	if looked[button] == nil and mode == "sweep" and style == "classic" then
		-- (Classic with the game's sweep: the game's own, untouched; once given another look, it is painted back)
		Numbers(button)
		return
	end
	looked[button] = mode
	Hear(button)
	if mode == "line" then
		Line(button)
		PlaceLine(button)
	end
	Paint(button, mode, style)
	UpdateLine(button)
	Numbers(button)
end

-- The global cooldown off the buttons: the game's cooldown set again without it.
local function StripGcd(button)
	if not ns.On("barGcd") then return end
	local slot, cooldown = Slot(button), button.cooldown
	if not slot or not cooldown or not cooldown.SetCooldownFromDurationObject then return end
	-- (a loss of control shown in the cooldown's place: the game's)
	if CAB and CAB.GetActionLossOfControlCooldownInfo then
		local info = Safe(CAB.GetActionLossOfControlCooldownInfo, slot)
		-- (read inside a closure: the table itself may be secret)
		if info and Clean(Safe(function() return info.shouldReplaceNormalCooldown end)) then return end
	end
	local duration = Duration(slot)
	if duration then
		holding = true
		pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
		holding = false
	end
end

-- The global cooldown line ------------------------------------------------------------------------------------------

local function GcdBar()
	if gcdBar then return gcdBar end
	local bar = _G.MainActionBar or _G.MainMenuBar
	local first, last = _G.ActionButton1, _G.ActionButton12
	if type(first) ~= "table" then return nil end
	-- (on the main bar, so Fade fades it with the bar)
	gcdBar = CreateFrame("StatusBar", "SereneGlobalCooldown", type(bar) == "table" and bar or UIParent)
	gcdBar:SetStatusBarTexture(FLAT)
	gcdBar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
	gcdBar:SetMinMaxValues(0, 1)
	gcdBar.track = gcdBar:CreateTexture(nil, "BACKGROUND")
	gcdBar.track:SetAllPoints()
	gcdBar.track:SetColorTexture(INK[1], INK[2], INK[3], 0.5)
	gcdBar:EnableMouse(false)
	gcdBar:SetAlpha(0)
	gcdBar.alpha = 0
	local px = ns.Pixel(first)
	gcdBar:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -3 * px)
	gcdBar:SetPoint("TOPRIGHT", type(last) == "table" and last or first, "BOTTOMRIGHT", 0, -3 * px)
	gcdBar:SetHeight(LINE_PX * px)
	return gcdBar
end

local function GcdActive()
	if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
	local info = Safe(C_Spell.GetSpellCooldown, GCD_SPELL)
	return info and Clean(Safe(function() return info.isActive end)) == true or false
end

local function UpdateGcd()
	local bar = ns.On("barGcd") and Active() and GcdBar()
	if not bar then
		if gcdBar then gcdBar:SetAlpha(0) gcdBar.alpha = 0 gcdBar.want = 0 end
		return
	end
	if GcdActive() then
		local duration = C_Spell.GetSpellCooldownDuration and Safe(C_Spell.GetSpellCooldownDuration, GCD_SPELL, false)
		if duration and Zero(duration) ~= true then
			-- (timed again only for a new duration: restarting the timer would make the line jump)
			if bar.want ~= 1 or bar.duration ~= duration then
				Timer(bar, duration)
				bar.duration = duration
			end
			bar.want = 1
			return
		end
	end
	bar.duration = nil
	bar.want = 0
end

-- Wiring --------------------------------------------------------------------------------------------------------------

local Refresh -- (below)

local function Init()
	if not Active() then return end
	-- (each time the game sets a button's cooldown: the global one left off, the line timed)
	if type(_G.ActionButton_UpdateCooldown) == "function" then
		hooksecurefunc("ActionButton_UpdateCooldown", function(button)
			if not looked[button] and not ns.On("barGcd") then return end
			StripGcd(button)
			UpdateLine(button)
		end)
	end
	-- (the game's own word on the numbers, followed by Serene's)
	if type(_G.ActionButton_UpdateCooldownNumberHidden) == "function" then
		hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", function(button) pcall(Numbers, button) end)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD",
		"UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		-- (the looks put on once the bars are dressed, and again after a fight held them back)
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
			C_Timer.After(0, Refresh)
		end
		if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
			for button in pairs(lines) do PlaceLine(button) end
			return
		end
		UpdateGcd()
	end)
	local since = 0
	events:SetScript("OnUpdate", function(_, elapsed)
		if gcdBar then
			local want = gcdBar.want or 0
			if gcdBar.alpha ~= want then
				gcdBar.alpha = ns.Approach(gcdBar.alpha, want, elapsed, 0.08, 0.2)
				gcdBar:SetAlpha(gcdBar.alpha)
			end
		end
		since = since + elapsed
		if since < CHECK_EVERY then return end
		since = 0
		-- (its end, in case no event told of it)
		if gcdBar and gcdBar.want == 1 and not GcdActive() then gcdBar.want = 0 end
		local soon = ns.db and ns.db.barCooldownText == "soon"
		for button in pairs(lines) do UpdateLine(button) end
		if soon and ns.BarsEach then ns.BarsEach(Soon) end
	end)
end

Refresh = function()
	if not Active() or not ns.BarsEach then return end
	if not InCombatLockdown() then ns.BarsEach(ns.CooldownLook) end
	ns.BarsEach(Numbers)
	UpdateGcd()
end

function ns.CooldownsDebug()
	local counts = {}
	for _, mode in pairs(looked) do counts[mode] = (counts[mode] or 0) + 1 end
	local parts = {}
	for mode, count in pairs(counts) do parts[#parts + 1] = mode .. " " .. count end
	ns.Print(("cooldowns: %s, numbers %s, global line %s (%s)%s"):format(tostring(ns.db.barCooldown),
		tostring(ns.db.barCooldownText), tostring(ns.On("barGcd")), gcdBar and "made" or "not made",
		#parts > 0 and ("; " .. table.concat(parts, ", ")) or ""))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
