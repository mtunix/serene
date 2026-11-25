local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Ready ping: a long cooldown coming back says so, once. When a button's own cooldown (not the global one) that ran
-- for at least the setting's while (30 seconds by default) ends, one soft ring of gold goes out from the button and
-- fades: round on a round button, the hints' soft square-ish glow on the others. Seen even while the bar is faded
-- (readiness, or the interface resting): then the spell's icon shows with it for a moment, so you know what is back
-- without looking for it. Never repeated, nothing to dismiss.
-- How long a cooldown ran is measured, not read (its numbers are secret in a fight): from the moment it is first
-- seen running to its end. A cooldown already running at a /reload counts from then (it may stay quiet once).
--   (Settings > Action bars > Cooldowns)

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local GOLD = { 1, 0.82, 0.35 }
local CHECK_EVERY = 0.1
local GLOW_SCALE = 1.6       -- Glow.tga over the button (its line sits on the button's edge)
local RING_AT = 36 / 128     -- GlowRound.tga's line, out from its middle, over its size
local INSET = 3 / 45         -- (Glass and Round draw the icon this much in, ActionBars.lua)
local FAINT_BELOW = 0.6      -- the button this faint or fainter: its icon shown with the ring
local SEEN_GAP = 0.5         -- a cooldown not seen on a button for longer (a page turned away): no ping at its end

local Actions = ns.Actions
local Slot, What, Region = Actions.Slot, Actions.What, Actions.Region
local running = {} -- slot -> { at = first seen running, seen = last seen on a button, what = the action }
local pings = {}   -- button -> its ping frame
local played = 0   -- (for /serene debug)

-- The ping frame: the ring and the icon, one animation played from the start each time (a one-off, never a loop).
local function Frame(button)
	local f = pings[button]
	if f then return f end
	f = CreateFrame("Frame", nil, button)
	f:EnableMouse(false)
	-- (above the button's glows, ActionBars' and Hints', which sit 5 over it)
	f:SetFrameLevel((Clean(Safe(button.GetFrameLevel, button)) or 1) + 7)
	-- (seen on a faded bar too)
	pcall(f.SetIgnoreParentAlpha, f, true)
	f.ring = f:CreateTexture(nil, "OVERLAY")
	f.ring:SetAllPoints()
	pcall(f.ring.SetBlendMode, f.ring, "ADD")
	f.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.mask = f:CreateMaskTexture()
	f.mask:SetTexture(MEDIA .. "AuraDisc", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	f.mask:SetAllPoints(f.icon)
	f:SetAlpha(0)
	f:Hide()
	local group = f:CreateAnimationGroup()
	local grow = group:CreateAnimation("Scale")
	grow:SetTarget(f.ring)
	if grow.SetScaleFrom then
		grow:SetScaleFrom(0.85, 0.85)
		grow:SetScaleTo(1.25, 1.25)
	else
		pcall(grow.SetFromScale, grow, 0.85, 0.85)
		pcall(grow.SetToScale, grow, 1.25, 1.25)
	end
	grow:SetDuration(0.9)
	if grow.SetSmoothing then grow:SetSmoothing("OUT") end
	local come = group:CreateAnimation("Alpha")
	come:SetFromAlpha(0)
	come:SetToAlpha(1)
	come:SetDuration(0.12)
	come:SetOrder(1)
	local go = group:CreateAnimation("Alpha")
	go:SetFromAlpha(1)
	go:SetToAlpha(0)
	go:SetStartDelay(0.15)
	go:SetDuration(0.75)
	go:SetOrder(2)
	if go.SetSmoothing then go:SetSmoothing("IN") end
	group:SetScript("OnFinished", function() f:SetAlpha(0) f:Hide() end)
	f.group = group
	pings[button] = f
	return f
end

local function Play(button)
	if not ns.On("barPing") then return end
	if not Clean(Safe(button.IsVisible, button)) then return end
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not icon then return end
	local f = Frame(button)
	local style = ns.BarStyleOf and ns.BarStyleOf(button) or "classic"
	local width = Clean(Safe(button.GetWidth, button)) or 45
	f:ClearAllPoints()
	f:SetPoint("CENTER", icon, "CENTER")
	if style == "round" then
		-- (the round glow's line on the ring, as ActionBars.lua places it)
		local size = (width * (1 - 2 * INSET) / 2 + ns.BAR_RIM * ns.Pixel(button)) / RING_AT
		f:SetSize(size, size)
		f.ring:SetTexture(MEDIA .. "GlowRound")
	else
		f:SetSize(width * GLOW_SCALE, width * GLOW_SCALE)
		f.ring:SetTexture(MEDIA .. "Glow")
	end
	-- (the button faint or its bar away: the icon too, so you see what came back)
	local shown = Clean(Safe(button.GetEffectiveAlpha, button))
	local ghost = type(shown) == "number" and shown < FAINT_BELOW
	f.icon:ClearAllPoints()
	f.icon:SetAllPoints(icon)
	f.icon:SetTexture(Clean(Safe(icon.GetTexture, icon)))
	pcall(f.icon.SetTexCoord, f.icon, Safe(icon.GetTexCoord, icon))
	-- (the mask taken off first: the button's look may have changed since its last ping)
	pcall(f.icon.RemoveMaskTexture, f.icon, f.mask)
	if style == "round" then pcall(f.icon.AddMaskTexture, f.icon, f.mask) end
	f.icon:SetShown(ghost and true or false)
	f.group:Stop()
	f:SetAlpha(1)
	f:Show()
	f.group:Play()
	played = played + 1
end

-- Each look: the cooldowns on the buttons, those that just ended after a long run pinged.
local function Look()
	if not ns.On("barPing") then
		if next(running) then wipe(running) end
		return
	end
	local now = GetTime()
	local least = tonumber(ns.db.barPingMin) or 30
	Actions.Each(function(button)
		local slot = Slot(button)
		if not slot or not Clean(Safe(button.IsVisible, button)) then return end
		local on = Actions.OnCooldown(slot)
		local r = running[slot]
		if on == true then
			if not r or r.what ~= What(slot) then
				running[slot] = { at = now, seen = now, what = What(slot) }
			else
				r.seen = now
			end
		-- (nil, unknown: the record kept as it is, never taken for an end)
		elseif on == false and r then
			running[slot] = nil
			if now - r.at >= least and now - r.seen <= SEEN_GAP and r.what == What(slot) then Play(button) end
		end
	end)
end

local function Init()
	if not ns.On("actionBars") then return end
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "ACTIONBAR_SLOT_CHANGED")
	events:SetScript("OnEvent", function(_, _, slot)
		-- (another action in the slot: its old cooldown forgotten)
		slot = Clean(slot)
		if type(slot) == "number" then running[slot] = nil end
	end)
	local since = 0
	events:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < CHECK_EVERY then return end
		since = 0
		Look()
	end)
end

-- (/serene ping: a ping on Action Bar 1's first button, to see it)
function ns.PingTest()
	local button = _G.ActionButton1
	if type(button) ~= "table" then return end
	local was = ns.db.barPing
	ns.db.barPing = true
	Play(button)
	ns.db.barPing = was
end

function ns.PingDebug()
	local count = 0
	for _ in pairs(running) do count = count + 1 end
	ns.Print(("ready ping: %s, from %s s; %d cooldowns followed, %d pings so far"):format(tostring(ns.On("barPing")),
		tostring(ns.db.barPingMin), count, played))
end

table.insert(ns.modules, { init = Init })
