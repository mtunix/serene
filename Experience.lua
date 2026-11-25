local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Experience gained: the game's experience bar comes back for a moment (Fade.lua asks ns.XPGained), and what was just
-- earned shows on it: a gold fill runs from where the bar was to where it is now, its tip glowing; a moment later the
-- bar's own colour sweeps in over the gold, and once it is there the tip's glow fades away. Kills one after another
-- carry on from where the fills have got to; a level gained starts again from the left.
-- /serene xpgain on|off

local SHOW = 5                          -- seconds the bar stays after experience is gained
local GOLD_IN, HOLD, SWEEP = 0.9, 0.6, 1.2 -- seconds: the gold running in, staying, the bar's colour sweeping over it
local GLOW_OUT = 1.1                    -- seconds: the tip's glow (and any gold still showing) fading once the bar is there
local GOLD = { 1, 0.82, 0.35 }
local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
	"StatusTrackingBarManager", "MainMenuExpBar" }

local lastXP, lastMax, lastLevel
local gainedAt = -math.huge
-- { from, gfrom, gain, to, start, levelled, mode, last, moved, now, gold, fading, done } (experience points, as the
-- game's bar counts them)
local anim
local bar, overlay
local lastMode -- (/serene debug: how the last gain was shown)
local lastFade -- (/serene debug: { frames, seconds, placed } of the last fade away)

-- The game's experience bar: a status bar whose most is the experience a level needs ----------------------------------

local function Most(statusbar)
	local _, most = Safe(statusbar.GetMinMaxValues, statusbar)
	return Clean(most)
end

local function IsXP(frame, need)
	if type(frame) ~= "table" or not frame.GetObjectType or Safe(frame.GetObjectType, frame) ~= "StatusBar" then return false end
	if not Clean(Safe(frame.IsVisible, frame)) then return false end
	-- (the reputation and honour bars share the containers: told apart by their most)
	return Most(frame) == need
end

local function Search(frame, need, depth)
	if IsXP(frame, need) then return frame end
	if depth <= 0 or type(frame) ~= "table" or not frame.GetChildren then return nil end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = Search(child, need, depth - 1)
		if found then return found end
	end
end

local function FindBar()
	local need = Clean(Safe(UnitXPMax, "player"))
	if type(need) ~= "number" or need <= 0 then return nil end
	if bar and IsXP(bar, need) then return bar end
	bar = nil
	for _, name in ipairs(CONTAINERS) do
		local found = Search(_G[name], need, 5)
		if found then
			bar = found
			return bar
		end
	end
end

-- The fill moving in -------------------------------------------------------------------------------------------------
-- The game's bar itself is never written to (its value, its range: the newer bars keep their own count of them).
-- Where it jumps at once to the new value, Serene's own copy of its fill (its texture and colour, laid over it) stands
-- in while the game's waits unseen: the gold runs ahead, the copy follows over it, and once there the game's fill is
-- back (the same pixels) and the copy gone. Where the game moves its bar itself, the gold runs ahead of the game's
-- own fill, which then moves in over it.

local function ease(p) return 1 - (1 - p) ^ 3 end

local hidden -- the game's fill texture while Serene's copy stands in for it

local function Reveal()
	if hidden then
		pcall(hidden.SetAlpha, hidden, 1)
		hidden = nil
	end
	if overlay then overlay.fill:Hide() end
end

local function Value(target)
	return Clean(Safe(target.GetValue, target))
end

local function X(target, value)
	local low, high = Safe(target.GetMinMaxValues, target)
	low, high = Clean(low), Clean(high)
	if type(low) ~= "number" or type(high) ~= "number" or high <= low or type(value) ~= "number" then return nil end
	return (overlay:GetWidth() or 0) * math.max(0, math.min(1, (value - low) / (high - low)))
end

-- Serene's copy of the game's fill: its atlas (or file), its colour. The game's fill texture once it has one.
local function Dress(target)
	local game = Safe(target.GetStatusBarTexture, target)
	if type(game) ~= "table" then return nil end
	local fill = overlay.fill
	local atlas = Clean(Safe(game.GetAtlas, game))
	local done = false
	if type(atlas) == "string" and atlas ~= "" then
		done = pcall(fill.SetAtlas, fill, atlas, false) and Clean(Safe(fill.GetAtlas, fill)) ~= nil
	end
	if not done then
		local file = Clean(Safe(game.GetTexture, game))
		if file then
			done = pcall(fill.SetTexture, fill, file) and Clean(Safe(fill.GetTexture, fill)) ~= nil
			if done then
				local coords = { Safe(game.GetTexCoord, game) }
				if #coords >= 4 then pcall(fill.SetTexCoord, fill, unpack(coords)) end
			end
		end
	end
	if not done then return nil end
	local r, g, b, a = Safe(game.GetVertexColor, game)
	r, g, b, a = Clean(r), Clean(g), Clean(b), Clean(a)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		pcall(fill.SetVertexColor, fill, r, g, b, type(a) == "number" and a or 1)
	end
	local blend = Clean(Safe(game.GetBlendMode, game))
	if blend then pcall(fill.SetBlendMode, fill, blend) end
	return game
end

-- Where everything stands: the bar's colour up to `purple`, gold from there to `gold`, the glow lighting what was just
-- gained (from `gained` to the gold's edge), brightest at the tip (`glow`: 1, down to 0 as they fade away).
local function Place(purple, gold, glow, gained)
	local o = overlay
	if o.fill:IsShown() then
		o.fill:SetWidth(math.max(0.01, purple))
		o.fill:SetAlpha(purple >= 0.5 and 1 or 0)
	end
	local span = gold - purple
	o.gold:SetShown(span >= 0.5 and glow > 0)
	o.gold:ClearAllPoints()
	o.gold:SetPoint("TOPLEFT", o, "TOPLEFT", purple, 0)
	o.gold:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", purple, 0)
	o.gold:SetWidth(math.max(0.5, span))
	local length = gold - math.max(0, math.min(gained, gold))
	o.glow:SetShown(length >= 1 and glow > 0)
	o.glow:ClearAllPoints()
	o.glow:SetPoint("TOPRIGHT", o, "TOPLEFT", gold, 0)
	o.glow:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", gold, 0)
	o.glow:SetWidth(math.max(1, length))
	o.tip:SetShown(gold >= 1 and glow > 0)
	o.tip:ClearAllPoints()
	o.tip:SetPoint("TOPRIGHT", o, "TOPLEFT", gold, 0)
	o.tip:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", gold, 0)
end

-- How lit the gold and the tip are, wherever they stand (set every frame, even one the bar's numbers can't be read).
local function Light(glow)
	local o = overlay
	o.lit:SetAlpha(glow)
	o.gold:SetAlpha(glow)
	o.glow:SetAlpha(glow)
	o.tip:SetAlpha(glow)
	-- (fading: the game's own fill is back underneath, and Serene's copy of it fades away over it, so nothing the
	-- copy draws differently from the game's pops out of sight at the end)
	if anim and anim.fading and o.fill:IsShown() then o.fill:SetAlpha(glow) end
	if glow <= 0 then
		o.glow:Hide()
		o.tip:Hide()
		o.gold:Hide()
	end
end

local function Paint()
	if not anim or not overlay then return end
	local target = overlay:GetParent()
	local now = GetTime()
	local since = now - anim.start
	-- (the first look, after the game has dealt with the same news: already at the end? Serene's copy stands in;
	-- else the game is moving its bar itself)
	if not anim.mode then
		local v = Value(target)
		anim.mode = "follow"
		if type(v) == "number" and v >= anim.to - 0.5 then
			local game = Dress(target)
			if game then
				anim.mode = "cover"
				if hidden ~= game then
					Reveal()
					if pcall(game.SetAlpha, game, 0) then hidden = game end
				end
				overlay.fill:Show()
			end
		elseif type(v) == "number" then
			anim.from = math.min(v, anim.to)
		end
		lastMode = anim.mode
		anim.last, anim.moved = v, now
	end
	local gold = anim.gfrom + (anim.to - anim.gfrom) * ease(math.min(1, since / GOLD_IN))
	local purple
	if anim.mode == "cover" then
		local sweep = math.max(0, since - GOLD_IN - HOLD)
		local p = math.min(1, sweep / SWEEP)
		purple = anim.from + (anim.to - anim.from) * ease(p)
		if p >= 1 and not anim.fading then
			anim.fading = now
			if hidden then
				pcall(hidden.SetAlpha, hidden, 1)
				hidden = nil
			end
		end
	else
		purple = Value(target) or anim.from
		if purple ~= anim.last then anim.last, anim.moved = purple, now end
		-- (the game's bar there and still for a moment, or five seconds at most: the glow fades)
		if not anim.fading and ((now - anim.moved > 0.2 and purple >= anim.to - 0.5 and since > GOLD_IN) or since > 5) then
			anim.fading = now
		end
	end
	-- (the bar there: the tip's glow, and whatever gold is still showing, fade away rather than vanish; quickest at
	-- first, as the tip is laid on brightly enough that the first part of a gentler fade wouldn't show)
	local glow = 1
	if anim.fading then
		local t = math.min(1, (now - anim.fading) / GLOW_OUT)
		glow = (1 - t) ^ 2
		if t >= 1 then anim.done = now end
	end
	anim.now, anim.gold = purple, gold
	local px, gx = X(target, purple), X(target, gold)
	local nx = X(target, anim.gain)
	if px and gx then Place(px, math.max(px, gx), glow, nx or px) end
	Light(glow)
	if anim.fading then
		lastFade = lastFade or { frames = 0, placed = 0 }
		lastFade.frames = lastFade.frames + 1
		lastFade.placed = lastFade.placed + ((px and gx) and 1 or 0)
		lastFade.seconds = now - anim.fading
	end
	if anim.done then
		-- (there: the game's own fill, the same pixels, back in place of the copy)
		anim = nil
		overlay:Hide()
	end
end

local function Overlay(target)
	if not overlay then
		overlay = CreateFrame("Frame")
		overlay.gold = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
		overlay.gold:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
		overlay.gold:Hide()
		overlay.fill = overlay:CreateTexture(nil, "ARTWORK", nil, 2)
		overlay.fill:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
		overlay.fill:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
		overlay.fill:Hide()
		-- (the tip: a soft light toward the gold's edge, and the edge itself brighter)
		local r, g, b = 1, 0.92, 0.7
		-- (on a frame of their own above the rest: its opacity is what fades them)
		overlay.lit = CreateFrame("Frame", nil, overlay)
		overlay.lit:SetAllPoints(overlay)
		overlay.glow = overlay.lit:CreateTexture(nil, "OVERLAY", nil, 6)
		overlay.glow:SetColorTexture(1, 1, 1, 1)
		overlay.glow:SetBlendMode("ADD")
		if overlay.glow.SetGradient and CreateColor then
			pcall(overlay.glow.SetGradient, overlay.glow, "HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.8))
		elseif overlay.glow.SetGradientAlpha then
			pcall(overlay.glow.SetGradientAlpha, overlay.glow, "HORIZONTAL", r, g, b, 0, r, g, b, 0.8)
		end
		overlay.tip = overlay.lit:CreateTexture(nil, "OVERLAY", nil, 7)
		overlay.tip:SetColorTexture(1, 0.95, 0.8, 1)
		overlay.tip:SetBlendMode("ADD")
		overlay.tip:SetWidth(2)
		overlay:SetScript("OnUpdate", Paint)
		overlay:SetScript("OnHide", Reveal) -- (hidden with the game's bar too: its fill never left unseen)
	end
	-- (a child of the game's bar: it fades with it)
	if overlay:GetParent() ~= target then
		Reveal()
		overlay:SetParent(target)
		overlay:ClearAllPoints()
		overlay:SetAllPoints(target)
	end
	overlay:SetFrameLevel((target:GetFrameLevel() or 1) + 1)
	return overlay
end

local function Start()
	if not anim then return end
	local target = FindBar()
	if not target then
		anim = nil
		return
	end
	Overlay(target):Show()
end

-- Experience coming in -------------------------------------------------------------------------------------------------

local function Read()
	return Clean(Safe(UnitXP, "player")), Clean(Safe(UnitXPMax, "player")), Clean(Safe(UnitLevel, "player"))
end

local function OnXP()
	local xp, most, level = Read()
	if type(xp) ~= "number" or type(most) ~= "number" or most <= 0 or type(level) ~= "number" then return end
	if lastXP then
		-- (the level's number may come after its experience: a drop with a new most is a level too)
		local levelled = level > lastLevel or (xp < lastXP and most ~= lastMax)
		if (levelled or xp > lastXP) and ns.On("xpGain") then
			local now = GetTime()
			gainedAt = now
			local from, gfrom = lastXP, lastXP
			if levelled then
				from, gfrom = 0, 0
			elseif anim and type(anim.now) == "number" and anim.now <= xp then
				-- (still moving: on from where the fills have got to)
				from = anim.now
				gfrom = type(anim.gold) == "number" and math.max(from, math.min(anim.gold, xp)) or from
			end
			-- (`gain`: where this gain starts, the part the glow lights)
			anim = { from = from, gfrom = gfrom, gain = levelled and 0 or lastXP, to = xp, start = now, levelled = levelled }
			lastFade = nil
			-- (its first look on this frame's update, after the game has dealt with the same news)
			Start()
		end
	end
	lastXP, lastMax, lastLevel = xp, most, level
end

-- Fade.lua: the experience bar wanted now.
function ns.XPGained()
	return ns.On("xpGain") and GetTime() - gainedAt < SHOW
end

local function Init()
	lastXP, lastMax, lastLevel = Read()
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "PLAYER_XP_UPDATE")
	pcall(events.RegisterEvent, events, "PLAYER_LEVEL_UP")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LEVEL_UP" then
			C_Timer.After(0.2, OnXP) -- (the new level's numbers a moment later)
		else
			OnXP()
		end
	end)
end

function ns.XPDebug()
	local target = FindBar()
	local name = target and target.GetName and target:GetName()
	ns.Print(("experience: %s, bar %s, shown for a gain %s, last gain %s"):format(tostring(ns.On("xpGain")),
		target and (name or ("inside " .. tostring(target:GetParent() and target:GetParent():GetName()))) or "not found",
		tostring(ns.XPGained()), lastMode == "cover" and "Serene's fill moving in over the game's" or lastMode == "follow"
			and "moved by the game, Serene's glow following" or "none yet"))
	ns.Print(lastFade and ("experience: last fade away %d frames over %.2fs (%d placed), %s"):format(lastFade.frames,
		lastFade.seconds or 0, lastFade.placed, tostring(lastMode)) or "experience: no fade away seen for the last gain")
end

table.insert(ns.modules, { init = Init })
