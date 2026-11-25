local _, ns = ...
local Safe, Clean, Over = ns.Safe, ns.Clean, ns.Over

-- The compass: the minimap made calm and modern.
-- * The game's own sharp round map (its engine cannot draw a half-seen edge), wrapped in a thin pale-gold ring
--   with fine degree ticks, a soft shadow around it and a quiet vignette on its rim.
-- * N, E, S and W just outside the ring (N in gold); with the game's "Rotate Minimap" option they turn with it.
-- * Under it, on a dark band fading at both ends: the zone in its color, where you stand and the time.
-- * No ring art, zone plate or clutter of the game's (its zoom, clocks, world map button...). Three small round
--   buttons on the ring, in the compass's look, under the mouse: the calendar (today's date, a gold dot for an
--   invitation), tracking, and every addon's minimap icon gathered in one panel (opened by a click; the button sits on the side of
--   the ring facing the middle of the screen and the panel slides out from under the ring beside it, its side toward
--   the compass an arc around it). The game's own
--   tracking button lies unseen over ours: its menu is the game's. The day and night and the game's calendar go. The mouse wheel zooms; the band tells
--   the time (a click on it: the game's clock and alarm; right click: the calendar). The mail, the queue and the
--   instance's difficulty stay where the game puts them (the queue's eye comes and goes with the compass; the top
--   bar tells of the queue meanwhile).
-- * Square instead of round: /serene edge square.
-- /serene minimap on|off (a reload to switch). When it shows (under the mouse; with /serene compass world, always
-- outside cities and towns) is Fade.lua's.

local RING = "Interface\\AddOns\\Serene\\Media\\CompassRing"
local SHADOW = "Interface\\AddOns\\Serene\\Media\\CompassShadow"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a round edge (only when coming back from square)
local SQUARE = "Interface\\Buttons\\WHITE8X8"
local SCALE = 1.16           -- the ring's texture, compared to the map
local LETTER_AT = 0.975      -- the letters' distance, in the ring texture's radii
local RING_COLOR = { 1, 0.88, 0.62, 0.9 }
local NORTH_COLOR = { 1, 0.82, 0.35 }
local LETTER_COLOR = { 0.88, 0.87, 0.84 }
local INK = { 0.035, 0.04, 0.05 }
local HOVER_IN, HOVER_OUT, LINGER = 0.15, 0.4, 0.8 -- seconds: the round buttons coming, going, staying after the mouse
local INFO_EVERY = 0.25 -- seconds between the band's words written again
local AGAIN = 2 -- seconds: buttons added by addons meanwhile, pieces the game showed again

local ZONE_COLORS = {
	sanctuary = { 0.55, 0.85, 1 }, friendly = { 0.55, 0.92, 0.55 }, hostile = { 1, 0.5, 0.45 },
	contested = { 1, 0.78, 0.4 }, arena = { 1, 0.5, 0.45 }, combat = { 1, 0.5, 0.45 },
}
local DEFAULT_ZONE = { 1, 0.92, 0.75 }
local LETTERS = { { "N", 0 }, { "E", 90 }, { "S", 180 }, { "W", 270 } }

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local BADGE = 22                                  -- the round buttons on the ring
local SATELLITES = { calendar = 45, addons = 135, tracking = 315 } -- their place, degrees clockwise from north
local ADDONS_LEFT = 225                           -- the addons' button when the panel opens to the left
local FLY_SIZE, FLY_GAP, FLY_COLUMNS, FLY_PAD = 24, 6, 6, 8       -- the addons' panel (at most 6 a row)
local FLY_ROWS = 4                                -- at most (more icons: wider rows)
local FLY_AWAY = 7                                -- the panel's arc: its distance outside the round buttons
local FLY_TIP = 10                                -- where the arc meets the panel's end: cut this far back
local HOLE_AT, DISC_AT = 80 / 512, 126 / 256      -- HoleMask's hole and DiscMask's disc: radius over size
local FLY_IN, FLY_OUT = 0.22, 0.14                -- seconds: the panel sliding out, and back
local FLY_SLIDE, FLY_RISE, FLY_STAGGER = 10, 4, 0.35 -- pixels it slides; each icon rising; the icons' delays
local FLY_LINGER = 2                              -- seconds the panel stays once the mouse left it

local hidden = CreateFrame("Frame")
hidden:Hide()
local deco, info, driver
local badges = {}          -- key -> our round button
local targets = {}         -- key -> the game's button lying unseen over ours
local fly, flyOpen, flyLast = nil, false, -math.huge
local flySlots, flyList = {}, {} -- the panel's slots; the icons in them, in order
local flyShow = 0                -- the panel's opening, 0 (closed) to 1 (open)
local flyH = -1                  -- the side it opens to: -1 left, 1 right (it grows up from its button)
local hover, lastNear = 0, -math.huge -- the round buttons' opacity; when the mouse was last near the compass
local letters = {}
local laidWidth, laidFacing, laidSquare, laidH, laidV -- (what Layout last placed for: unchanged, it does nothing)

local function Part(owner, key)
	local value = type(owner) == "table" and owner[key] or nil
	return type(value) == "table" and value or nil
end

local function Tuck(region)
	if type(region) == "table" and region.SetParent and region:GetParent() ~= hidden then
		pcall(region.SetParent, region, hidden)
	end
end

-- A list of what exists (a missing piece would end an ipairs early).
local function List(...)
	local list = {}
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if type(value) == "table" then list[#list + 1] = value end
	end
	return list
end

-- The game's ring, band and zone plate: away for good.
local function Borders()
	local cluster = MinimapCluster
	return List(_G.MinimapCompassTexture, _G.MinimapBorder, _G.MinimapBorderTop, Part(cluster, "BorderTop"),
		Part(cluster, "ZoneTextButton"), _G.MinimapZoneTextButton, _G.MinimapToggleButton, _G.MinimapNorthTag)
end

-- Gone for good: the zoom (the wheel zooms), the clock (the band tells the time), the world map button (M).
local function Unwanted()
	local map = Minimap
	return List(Part(map, "ZoomIn"), Part(map, "ZoomOut"), _G.MinimapZoomIn, _G.MinimapZoomOut, Part(map, "ZoomHitArea"),
		_G.TimeManagerClockButton, _G.MiniMapWorldMapButton, _G.ExpansionLandingPageMinimapButton, _G.GameTimeFrame)
end

-- What stays where the game puts it: the mail, the queue, the instance's difficulty (they tell you something).
local STAYS = { "Mail", "Difficulty", "Battlefield", "LFG", "Queue", "Challenge", "Voice", "Indicator", "Instance" }
local function Stays(frame)
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" then return false end
	for _, word in ipairs(STAYS) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

-- The queue's eye (group finder, battlegrounds): where the game puts it, but it comes and goes with the compass
-- (Fade.lua), wherever the game hangs it; the top bar tells of the queue while the compass is away (TopBar.lua).
local QUEUE_NAMES = { "QueueStatusButton", "QueueStatusMinimapButton", "MiniMapLFGFrame", "LFGMinimapFrame",
	"MiniMapBattlefieldFrame", "LFGListMinimapFrame" }
local QUEUE_WORDS = { "Queue", "LFG", "Battlefield" }
local queueFrames, queueSeen, queueLooked = {}, {}, -math.huge
function ns.QueueFrames()
	local now = GetTime()
	if now - queueLooked < 2 then return queueFrames end -- (the top bar asks twice a second)
	queueLooked = now
	wipe(queueFrames)
	wipe(queueSeen)
	local function Add(frame)
		if type(frame) == "table" and frame.SetAlpha and frame ~= Minimap and not queueSeen[frame] then
			queueSeen[frame] = true
			queueFrames[#queueFrames + 1] = frame
		end
	end
	for _, name in ipairs(QUEUE_NAMES) do Add(_G[name]) end
	for _, holder in ipairs(List(Minimap, MinimapCluster, _G.MinimapBackdrop)) do
		for _, child in ipairs({ holder:GetChildren() }) do
			local name = child.GetName and child:GetName()
			if type(name) == "string" then
				for _, word in ipairs(QUEUE_WORDS) do
					if name:find(word, 1, true) then Add(child) break end
				end
			end
		end
	end
	return queueFrames
end

-- The eye shown now (the game shows it while you queue), and which one.
function ns.QueueShown()
	for _, frame in ipairs(ns.QueueFrames()) do
		if Safe(frame.IsShown, frame) then return frame end
	end
end

-- The game's buttons that ours stand for.
local function FindTargets()
	local cluster = MinimapCluster
	local tracking = Part(cluster, "Tracking") or _G.MiniMapTracking
	targets.tracking = Part(tracking, "Button") or _G.MiniMapTrackingButton or tracking
	-- (its holder too: kept unseen, and out of the clutter Gather tucks away)
	targets.trackingHolder = targets.tracking ~= tracking and tracking or nil
end

-- Every addon's minimap icon (LibDBIcon's, and any button an addon named after the minimap), and the game's addon
-- compartment: into the panel. Never the game's own pieces, nor the quest pins Questie draws on the map.
local hiddenByUs = setmetatable({}, { __mode = "k" }) -- an addon's icon Serene hid while the panel is closed
local NOT_ADDON = { "^Minimap", "^MiniMap", "^Questie", "HereBeDragons", "^HBD", "^GameTime", "^TimeManager", "Pin%d" }
local function IsAddonButton(frame)
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" or frame == fly or frame == deco or frame == info then return false end
	if name:find("^LibDBIcon10_") then return true end
	if not name:lower():find("minimap", 1, true) then return false end
	for _, pattern in ipairs(NOT_ADDON) do
		if name:find(pattern) then return false end
	end
	local kind = frame.GetObjectType and frame:GetObjectType()
	return kind == "Button" or kind == "Frame" or kind == "CheckButton"
end

local function AddonButtons()
	local list, seen = {}, {}
	local compartment = _G.AddonCompartmentFrame
	if type(compartment) == "table" and (Safe(compartment.IsShown, compartment) or hiddenByUs[compartment]) then
		list[#list + 1] = compartment
		seen[compartment] = true
	end
	local found = {}
	-- (LibDBIcon's own list first: every icon it made, wherever it sits and whatever it is called; one its addon
	-- set to hidden stays out)
	local ldb = LibStub and LibStub("LibDBIcon-1.0", true)
	if ldb and type(ldb.objects) == "table" then
		for _, button in pairs(ldb.objects) do
			local hide = type(button) == "table" and type(button.db) == "table" and button.db.hide
			if type(button) == "table" and button.SetPoint and not seen[button] and not hide then
				seen[button] = true
				found[#found + 1] = button
			end
		end
	end
	for _, holder in ipairs(List(Minimap, MinimapCluster, _G.MinimapBackdrop)) do
		for _, child in ipairs({ holder:GetChildren() }) do
			-- (an icon its addon hid stays hidden; one Serene hid is still the panel's)
			if not seen[child] and IsAddonButton(child) and (Safe(child.IsShown, child) or hiddenByUs[child]) then
				seen[child] = true
				found[#found + 1] = child
			end
		end
	end
	table.sort(found, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
	for _, child in ipairs(found) do list[#list + 1] = child end
	return list
end

-- /serene debug: the addons' icons the panel gathers, and LibDBIcon's own list.
function ns.MinimapDebug()
	local names = {}
	for _, button in ipairs(AddonButtons()) do names[#names + 1] = (button.GetName and button:GetName()) or "?" end
	ns.Print(("|cffffd100addons panel|r (%d): %s"):format(#names, #names > 0 and table.concat(names, ", ") or "nothing"))
	local ldb = LibStub and LibStub("LibDBIcon-1.0", true)
	if not ldb then return ns.Print("   LibDBIcon: not loaded") end
	local listed = {}
	for name, button in pairs(ldb.objects or {}) do
		local hide = type(button.db) == "table" and button.db.hide
		local parent = button.GetParent and button:GetParent()
		listed[#listed + 1] = ("%s%s (in %s)"):format(name, hide and " [hidden by its addon]" or "",
			parent and parent.GetName and parent:GetName() or "?")
	end
	for name in pairs(ldb.notCreated or {}) do listed[#listed + 1] = name .. " [never made: hidden by its addon]" end
	table.sort(listed)
	ns.Print("   LibDBIcon: " .. (#listed > 0 and table.concat(listed, ", ") or "nothing registered"))
	local eyes = {}
	for _, frame in ipairs(ns.QueueFrames()) do
		local parent = frame.GetParent and frame:GetParent()
		eyes[#eyes + 1] = ("%s (%s, in %s)"):format((frame.GetName and frame:GetName()) or "?",
			Safe(frame.IsShown, frame) and "shown" or "hidden", parent and parent.GetName and parent:GetName() or "?")
	end
	ns.Print("   queue's eye: " .. (#eyes > 0 and table.concat(eyes, ", ") or "none found"))
end

-- Any other named button of the game's around the map (a second calendar, a day and night...): gone too.
local function Clutter()
	local list, keep = {}, {}
	for _, frame in pairs(targets) do keep[frame] = true end
	for _, holder in ipairs(List(MinimapCluster, _G.MinimapBackdrop)) do
		for _, child in ipairs({ holder:GetChildren() }) do
			local name = child.GetName and child:GetName()
			local kind = child.GetObjectType and child:GetObjectType()
			if type(name) == "string" and kind == "Button" and child ~= Minimap and not keep[child] and not Stays(child)
				and not IsAddonButton(child) then
				list[#list + 1] = child
			end
		end
	end
	return list
end

-- The game's own coordinates (this game writes them around the minimap): found by what they say, kept unseen.
local COORDS = "^%s*%-?%d+[%.,]?%d*%s*[,;/]%s*%-?%d+[%.,]?%d*%s*$"
local gameCoords
local function FindCoords(frame, depth)
	if type(frame) ~= "table" or depth > 4 or frame == info or frame == deco then return nil end
	for _, region in ipairs({ frame:GetRegions() }) do
		local text = region.GetText and Clean(Safe(region.GetText, region))
		if type(text) == "string" and text:match(COORDS) then return region end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = FindCoords(child, depth + 1)
		if found then return found end
	end
end

local function KeepCoordsUnseen()
	if gameCoords and Safe(gameCoords.GetAlpha, gameCoords) ~= 0 then pcall(gameCoords.SetAlpha, gameCoords, 0) end
end

-- A clock written somewhere around the map by the game ("12:23", "12:23 PM"): its button goes.
local CLOCK = "^%s*%d%d?:%d%d%s*[AaPp]?%.?[Mm]?%.?%s*$"
local function FindClocks(frame, depth, found)
	if type(frame) ~= "table" or depth > 3 or frame == info or frame == deco or frame == fly then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		local text = region.GetText and Clean(Safe(region.GetText, region))
		if type(text) == "string" and text:match(CLOCK) then found[#found + 1] = frame end
	end
	for _, child in ipairs({ frame:GetChildren() }) do FindClocks(child, depth + 1, found) end
end

local function Gather()
	if not gameCoords then gameCoords = FindCoords(MinimapCluster, 1) or FindCoords(Minimap, 1) end
	KeepCoordsUnseen()
	FindTargets()
	for _, region in ipairs(Borders()) do Tuck(region) end
	for _, region in ipairs(Unwanted()) do Tuck(region) end
	for _, region in ipairs(Clutter()) do Tuck(region) end
	local clocks = {}
	for _, holder in ipairs(List(MinimapCluster, _G.MinimapBackdrop)) do
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= Minimap and not Stays(child) then FindClocks(child, 1, clocks) end
		end
	end
	for _, clock in ipairs(clocks) do
		-- (the button holding it, right under the map's frame)
		local frame = clock
		for _ = 1, 3 do
			local parent = frame.GetParent and frame:GetParent()
			if parent == MinimapCluster or parent == _G.MinimapBackdrop or parent == Minimap or type(parent) ~= "table" then break end
			frame = parent
		end
		local isTarget = false
		for _, target in pairs(targets) do isTarget = isTarget or target == frame end
		if not isTarget then Tuck(frame) end
	end
	if ns.PlaceSatellites then ns.PlaceSatellites() end
	if ns.PlaceFly then ns.PlaceFly() end
end

-- The edge: the game's own round one (never touched at login), or square. Addons placing pins and buttons on the
-- edge (LibDBIcon, HereBeDragons) ask GetMinimapShape.
local squared = false
function ns.MinimapEdge(atLogin)
	if not (Minimap and Minimap.SetMaskTexture and ns.On("minimap")) then return end
	if ns.db.edge == "square" then
		pcall(Minimap.SetMaskTexture, Minimap, SQUARE)
		_G.GetMinimapShape = function() return "SQUARE" end
		squared = true
	elseif squared or not atLogin then
		if squared then pcall(Minimap.SetMaskTexture, Minimap, ROUND) end
		_G.GetMinimapShape = function() return "ROUND" end
		squared = false
	end
	laidWidth = nil -- (drawn again in its new shape)
end

-- The ring --------------------------------------------------------------------------------------------------------

local function Text(parent, size, color)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
	text:SetTextColor(color[1], color[2], color[3])
	return text
end

local function MakeDeco()
	deco = CreateFrame("Frame", nil, Minimap)
	deco:SetPoint("CENTER", Minimap, "CENTER")
	deco:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 1)
	deco:EnableMouse(false)
	deco.shadow = deco:CreateTexture(nil, "ARTWORK", nil, 0)
	deco.shadow:SetTexture(SHADOW)
	deco.shadow:SetAllPoints(deco)
	deco.ring = deco:CreateTexture(nil, "ARTWORK", nil, 1)
	deco.ring:SetTexture(RING)
	deco.ring:SetAllPoints(deco)
	deco.ring:SetVertexColor(RING_COLOR[1], RING_COLOR[2], RING_COLOR[3], RING_COLOR[4])
	-- (square: a thin frame of four lines and a dark line outside it)
	deco.lines = {}
	for index = 1, 8 do
		local line = deco:CreateTexture(nil, "ARTWORK", nil, index <= 4 and 1 or 0)
		if index <= 4 then
			line:SetColorTexture(RING_COLOR[1], RING_COLOR[2], RING_COLOR[3], RING_COLOR[4])
		else
			line:SetColorTexture(0, 0, 0, 0.6)
		end
		line:Hide()
		deco.lines[index] = line
	end
	for _, each in ipairs(LETTERS) do
		local north = each[1] == "N"
		local text = Text(deco, north and 14 or 11, north and NORTH_COLOR or LETTER_COLOR)
		text:SetText(each[1])
		letters[#letters + 1] = { text = text, angle = math.rad(each[2]) }
	end
end

local function SquareLines(width, show)
	local lines = deco.lines
	for _, line in ipairs(lines) do
		line:SetShown(show)
		line:ClearAllPoints()
	end
	if not show then return end
	local half = width / 2
	local function Edge(line, thickness, out)
		return line, thickness, out
	end
	-- (inner: the pale frame on the map's edge; outer: a dark line just outside it; each { thickness, gap outside })
	for index, spec in ipairs({ { 2, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 }, { 1, 2 }, { 1, 2 }, { 1, 2 }, { 1, 2 } }) do
		local line, thickness, out = Edge(lines[index], spec[1], spec[2])
		local side = (index - 1) % 4
		local reach = half + out + thickness
		if side == 0 then -- top
			line:SetPoint("BOTTOMLEFT", Minimap, "CENTER", -reach, half + out)
			line:SetPoint("TOPRIGHT", Minimap, "CENTER", reach, half + out + thickness)
		elseif side == 1 then -- bottom
			line:SetPoint("TOPLEFT", Minimap, "CENTER", -reach, -half - out)
			line:SetPoint("BOTTOMRIGHT", Minimap, "CENTER", reach, -half - out - thickness)
		elseif side == 2 then -- left
			line:SetPoint("TOPRIGHT", Minimap, "CENTER", -half - out, reach)
			line:SetPoint("BOTTOMLEFT", Minimap, "CENTER", -half - out - thickness, -reach)
		else -- right
			line:SetPoint("TOPLEFT", Minimap, "CENTER", half + out, reach)
			line:SetPoint("BOTTOMRIGHT", Minimap, "CENTER", half + out + thickness, -reach)
		end
	end
end

-- Where the compass sits on the screen: the side the addons' panel opens to (toward the middle), and up or down.
local function Side()
	local mx, my = Safe(Minimap.GetCenter, Minimap)
	local ux, uy = Safe(UIParent.GetCenter, UIParent)
	local ms = Clean(Safe(Minimap.GetEffectiveScale, Minimap))
	local us = Clean(Safe(UIParent.GetEffectiveScale, UIParent))
	mx, my, ux, uy = Clean(mx), Clean(my), Clean(ux), Clean(uy)
	if not (mx and my and ux and uy and ms and us) then return -1, -1 end -- (unknown: top right, the game's corner)
	return (mx * ms > ux * us) and -1 or 1, (my * ms > uy * us) and -1 or 1
end

-- Placed again when the map's size, its shape, its side of the screen or (rotating) your facing changes.
local function Layout()
	local width = Clean(Safe(Minimap.GetWidth, Minimap))
	if type(width) ~= "number" or width <= 0 then width = laidWidth or 140 end
	local square = ns.db.edge == "square"
	local facing = 0
	if Clean(Safe(GetCVar, "rotateMinimap")) == "1" then
		facing = Clean(Safe(GetPlayerFacing)) or 0
	end
	facing = math.floor(facing * 200 + 0.5) / 200 -- (in 1/200 radian, under a third of a degree: no work for nothing)
	local h, v = Side()
	if width == laidWidth and facing == laidFacing and square == laidSquare and h == laidH and v == laidV then return end
	local resized = width ~= laidWidth or square ~= laidSquare or h ~= laidH or v ~= laidV
	laidWidth, laidFacing, laidSquare, laidH, laidV = width, facing, square, h, v
	flyH = h
	if resized then
		deco:SetSize(width * SCALE, width * SCALE)
		deco.ring:SetShown(not square)
		deco.shadow:SetShown(not square)
		SquareLines(width, square)
		info:ClearAllPoints()
		-- (just under the letters' circle, clear of the S)
		info:SetPoint("TOP", Minimap, "BOTTOM", 0, -(width * (SCALE * LETTER_AT - 1) / 2 + 14))
		if ns.PlaceSatellites then ns.PlaceSatellites() end
		if ns.PlaceFly and not InCombatLockdown() then ns.PlaceFly() end
	end
	-- (the ring turns with the map: north where the map's north is)
	if deco.ring.SetRotation then pcall(deco.ring.SetRotation, deco.ring, -facing) end
	local radius = width * SCALE * LETTER_AT / 2
	for _, letter in ipairs(letters) do
		local angle = letter.angle + facing
		local x, y = math.sin(angle) * radius, math.cos(angle) * radius
		if square then
			-- (on a square: just outside its edge, wherever the angle points)
			local most = math.max(math.abs(math.sin(angle)), math.abs(math.cos(angle)))
			local out = width / 2 + 12
			x, y = math.sin(angle) / most * out, math.cos(angle) / most * out
		end
		letter.text:ClearAllPoints()
		letter.text:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end
end

-- Under the map: the zone, where you stand and the time -------------------------------------------------------------

local function Coordinates()
	local map = C_Map and Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	if not map then return nil end
	local position = Safe(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local x, y = Safe(position.GetXY, position)
	x, y = Clean(x), Clean(y)
	if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local function Clock()
	-- (the game's own clock, in its 12 or 24 hour setting; else the computer's)
	if GameTime_GetTime then
		local text = Clean(Safe(GameTime_GetTime, true))
		if type(text) == "string" and text ~= "" then return text end
	end
	return date("%H:%M")
end

local function UpdateInfo()
	local zone = Clean(Safe(GetMinimapZoneText)) or Clean(Safe(GetZoneText)) or ""
	local kind = Clean(Safe(GetZonePVPInfo))
	local c = ZONE_COLORS[kind or ""] or DEFAULT_ZONE
	info.zone:SetText(zone)
	info.zone:SetTextColor(c[1], c[2], c[3])
	local where = Coordinates()
	info.line:SetText(where and (where .. "  ·  " .. Clock()) or Clock())
end

local function Gradient(texture, fromAlpha, toAlpha)
	if texture.SetGradient and CreateColor then
		texture:SetColorTexture(1, 1, 1, 1)
		texture:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], fromAlpha), CreateColor(INK[1], INK[2], INK[3], toAlpha))
	else
		texture:SetColorTexture(INK[1], INK[2], INK[3], (fromAlpha + toAlpha) / 2)
	end
end

local function MakeInfo()
	info = CreateFrame("Frame", nil, Minimap)
	info:SetSize(200, 36)
	info:SetPoint("TOP", Minimap, "BOTTOM", 0, -20)
	info:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 2)
	info:EnableMouse(false)
	local DARK, FADE = 0.6, 32
	local middle = info:CreateTexture(nil, "BACKGROUND")
	middle:SetColorTexture(INK[1], INK[2], INK[3], DARK)
	middle:SetPoint("TOPLEFT", info, "TOPLEFT", FADE, 0)
	middle:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT", -FADE, 0)
	local left = info:CreateTexture(nil, "BACKGROUND")
	left:SetPoint("TOPRIGHT", middle, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", middle, "BOTTOMLEFT")
	left:SetWidth(FADE)
	Gradient(left, 0, DARK)
	local right = info:CreateTexture(nil, "BACKGROUND")
	right:SetPoint("TOPLEFT", middle, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", middle, "BOTTOMRIGHT")
	right:SetWidth(FADE)
	Gradient(right, DARK, 0)
	-- (a fine gold rule over the band, fading at its ends)
	local rule = info:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", info, "TOPLEFT", FADE, 0)
	rule:SetPoint("TOPRIGHT", info, "TOPRIGHT", -FADE, 0)
	rule:SetColorTexture(NORTH_COLOR[1], NORTH_COLOR[2], NORTH_COLOR[3], 0.45)
	-- (a click: the game's clock and alarm; a right click: the calendar)
	info:EnableMouse(true)
	info:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			if ns.OpenCalendar then ns.OpenCalendar() end
		elseif _G.TimeManager_Toggle then
			Safe(_G.TimeManager_Toggle)
		end
	end)
	info:SetScript("OnEnter", function(self)
		ns.ShowTip(self, function(tip)
			tip:AddLine(Clean(Safe(GetZoneText)) or "", 1, 0.82, 0.35)
			local sub = Clean(Safe(GetSubZoneText))
			if sub and sub ~= "" then tip:AddLine(ns.SOFT .. sub .. "|r") end
			ns.TipHint(tip, "Click: clock and alarm")
			ns.TipHint(tip, "Right click: calendar")
		end, "ANCHOR_BOTTOM")
	end)
	info:SetScript("OnLeave", function() ns.HideTip() end)
	info.zone = Text(info, 13, DEFAULT_ZONE)
	info.zone:SetPoint("TOP", info, "TOP", 0, -5)
	info.line = Text(info, 11, LETTER_COLOR)
	info.line:SetPoint("TOP", info.zone, "BOTTOM", 0, -3)
end

-- The round buttons on the ring -------------------------------------------------------------------------------

local LABELS = { calendar = "Calendar", tracking = "Tracking", addons = "Addons" }

-- The game's calendar (its window loads when first asked for).
local function OpenCalendar()
	if _G.ToggleCalendar then return Safe(_G.ToggleCalendar) end
	local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
	if load then pcall(load, "Blizzard_Calendar") end
	if _G.Calendar_Toggle then return Safe(_G.Calendar_Toggle) end
	local button = _G.GameTimeFrame
	if type(button) == "table" and button.Click then Safe(button.Click, button) end
end
ns.OpenCalendar = OpenCalendar

local function Badge(key)
	local badge = CreateFrame("Button", nil, Minimap)
	badge:SetSize(BADGE, BADGE)
	badge:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 4)
	badge:EnableMouse(false)
	badge:SetAlpha(0) -- (the driver brings it with the mouse)
	badge.disc = badge:CreateTexture(nil, "BACKGROUND")
	badge.disc:SetTexture(MEDIA .. "BadgeDisc")
	badge.disc:SetAllPoints()
	badge.disc:SetVertexColor(INK[1], INK[2], INK[3], 0.88)
	badge.rim = badge:CreateTexture(nil, "BORDER")
	badge.rim:SetTexture(MEDIA .. "BadgeRim")
	badge.rim:SetAllPoints()
	if key == "calendar" then
		badge.day = Text(badge, 10, NORTH_COLOR)
		badge.day:SetPoint("CENTER", badge, "CENTER", 0, 0)
		badge.dot = badge:CreateTexture(nil, "OVERLAY")
		badge.dot:SetTexture(MEDIA .. "BadgeDisc")
		badge.dot:SetSize(7, 7)
		badge.dot:SetPoint("CENTER", badge, "TOPRIGHT", -3, -3)
		badge.dot:SetVertexColor(NORTH_COLOR[1], NORTH_COLOR[2], NORTH_COLOR[3], 1)
		badge.dot:Hide()
		badge:EnableMouse(true)
		badge:RegisterForClicks("AnyUp")
		badge:SetScript("OnClick", OpenCalendar)
		badge:SetScript("OnEnter", function(self)
			ns.ShowTip(self, function(tip)
				tip:SetText(LABELS.calendar)
				local invites = C_Calendar and Clean(Safe(C_Calendar.GetNumPendingInvites))
				if type(invites) == "number" and invites > 0 then
					tip:AddLine(invites == 1 and "1 invitation" or (invites .. " invitations"), NORTH_COLOR[1], NORTH_COLOR[2], NORTH_COLOR[3])
				end
			end, "ANCHOR_LEFT")
		end)
		badge:SetScript("OnLeave", function() ns.HideTip() end)
	else
		badge.icon = badge:CreateTexture(nil, "ARTWORK")
		badge.icon:SetTexture(MEDIA .. (key == "tracking" and "IconTracking" or "IconAddons"))
		badge.icon:SetPoint("CENTER")
		badge.icon:SetSize(BADGE * 0.55, BADGE * 0.55)
	end
	badge.key = key
	badges[key] = badge
	return badge
end

-- Lit under the mouse: the rim and the icon brighter. Open (its panel out): the icon in gold.
local WHITE = { 1, 1, 1 }
local function Light(badge, lit, open)
	local state = open and 2 or lit and 1 or 0
	if badge.state == state then return end
	badge.state = state
	badge.rim:SetVertexColor(RING_COLOR[1], RING_COLOR[2], RING_COLOR[3], state > 0 and 1 or 0.75)
	if badge.icon then
		local c = open and NORTH_COLOR or lit and WHITE or LETTER_COLOR
		badge.icon:SetVertexColor(c[1], c[2], c[3], state > 0 and 1 or 0.9)
	end
end

-- The game's button lying over ours, unseen: its clicks, its menu; our own words in its tooltip.
local hooked = {}
local function Overlay(key)
	local target, badge = targets[key], badges[key]
	if type(target) ~= "table" or not badge or InCombatLockdown() then return end
	local width = Clean(Safe(target.GetWidth, target)) or BADGE
	local height = Clean(Safe(target.GetHeight, target)) or BADGE
	local scale = (BADGE + 2) / math.max(width, height, 1) -- (a touch larger than ours: its clicks cover the badge)
	local now = Clean(Safe(target.GetScale, target)) or 1
	if math.abs(now - scale) > 0.01 then pcall(target.SetScale, target, scale) end
	pcall(target.ClearAllPoints, target)
	pcall(target.SetPoint, target, "CENTER", badge, "CENTER", 0, 0)
	pcall(target.SetFrameLevel, target, (badge:GetFrameLevel() or 1) + 2)
	if not hooked[target] and target.HookScript then
		hooked[target] = true
		target:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(LABELS[key] or "")
			GameTooltip:Show()
		end)
		-- (the game writes its tooltip again while it is shown, the time with it: our words kept)
		target:HookScript("OnUpdate", function(self)
			if not GameTooltip:IsOwned(self) then return end
			local first = _G.GameTooltipTextLeft1
			local said = first and Clean(Safe(first.GetText, first))
			if said ~= LABELS[key] or GameTooltip:NumLines() > 1 then
				GameTooltip:SetText(LABELS[key] or "")
				GameTooltip:Show()
			end
		end)
	end
end

local function KeepTargetsUnseen()
	for _, frame in pairs(targets) do
		if type(frame) == "table" and Safe(frame.GetAlpha, frame) ~= 0 then pcall(frame.SetAlpha, frame, 0) end
	end
end

-- A round button's place from the map's middle (screen-fixed: they do not turn with a rotating map).
local function SatellitePoint(key)
	local width = laidWidth or Clean(Safe(Minimap.GetWidth, Minimap)) or 140
	local degrees = SATELLITES[key]
	if key == "addons" and flyH < 0 then degrees = ADDONS_LEFT end
	local angle = math.rad(degrees)
	local radius = width / 2 + 2
	local x, y = math.sin(angle) * radius, math.cos(angle) * radius
	if ns.db.edge == "square" then
		local most = math.max(math.abs(math.sin(angle)), math.abs(math.cos(angle)))
		x, y = x / most, y / most
	end
	return x, y
end

function ns.PlaceSatellites()
	if not deco then return end
	for key in pairs(SATELLITES) do
		local badge = badges[key]
		if badge then
			local x, y = SatellitePoint(key)
			badge:ClearAllPoints()
			badge:SetPoint("CENTER", Minimap, "CENTER", x, y)
			Overlay(key)
		end
	end
end

local function UpdateCalendar()
	local badge = badges.calendar
	if not badge then return end
	badge.day:SetText(tonumber(date("%d")) or "") -- (no leading zero)
	local invites = C_Calendar and Clean(Safe(C_Calendar.GetNumPendingInvites)) or Clean(Safe(_G.CalendarGetNumPendingInvites))
	badge.dot:SetShown(type(invites) == "number" and invites > 0)
end

-- The addons' panel ------------------------------------------------------------------------------------------------
-- Dark glass in a quiet gold hairline, beside its button on the side facing the screen's middle, growing up from the
-- button's row. Its side toward the compass is an arc around the compass's middle, just outside the round buttons
-- and the letters (HoleMask carves it, DiscMask with it draws the arc's hairline): the rows follow the arc, the
-- panel a wing of the compass. It slides out from under the ring and fades in, the icons rising one after another;
-- it slides back quicker. The button's icon turns a quarter of the way (its four squares a diamond) and goes gold
-- while it is out. A square compass: a straight side instead of the arc.

local function Ease(t) return 1 - (1 - t) ^ 3 end

local function FlyTip(self)
	ns.ShowTip(self, function(tip)
		tip:SetText(LABELS.addons)
		local count = #flyList
		if count == 0 then
			tip:AddLine("No addon icons", ns.MUTED_RGB[1], ns.MUTED_RGB[2], ns.MUTED_RGB[3])
		else
			tip:AddLine(count == 1 and "1 icon" or (count .. " icons"), ns.SOFT_RGB[1], ns.SOFT_RGB[2], ns.SOFT_RGB[3])
			if InCombatLockdown() then
				ns.TipHint(tip, "Not in a fight")
			else
				ns.TipHint(tip, flyOpen and "Click: put them away" or "Click: show them")
			end
		end
	end, flyH < 0 and "ANCHOR_RIGHT" or "ANCHOR_LEFT") -- (away from the panel)
end

local function MakeFly()
	fly = CreateFrame("Frame", nil, Minimap)
	fly:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	fly:EnableMouse(true)
	fly:SetAlpha(0)
	fly:Hide()
	-- (a dark pixel outside, the glass, a soft gold hairline just inside it)
	local line = { ns.LINE[1], ns.LINE[2], ns.LINE[3], 0.6 }
	fly.edge = fly:CreateTexture(nil, "BACKGROUND", nil, -1)
	fly.edge:SetColorTexture(0, 0, 0, 0.55)
	fly.ground = fly:CreateTexture(nil, "BACKGROUND", nil, 0)
	fly.ground:SetAllPoints()
	fly.ground:SetColorTexture(INK[1], INK[2], INK[3], 0.9)
	fly.lines = ns.Hairline(fly, line)
	fly.arc = fly:CreateTexture(nil, "BORDER")
	fly.arc:SetAllPoints()
	fly.arc:SetColorTexture(line[1], line[2], line[3], line[4])
	-- (the masks sit on the compass's middle, still while the panel slides: it comes out from under the ring)
	fly.hole = fly:CreateMaskTexture()
	fly.hole:SetTexture(MEDIA .. "HoleMask", "CLAMP", "CLAMP")
	fly.hole:SetPoint("CENTER", Minimap, "CENTER")
	fly.holeEdge = fly:CreateMaskTexture()
	fly.holeEdge:SetTexture(MEDIA .. "HoleMask", "CLAMP", "CLAMP")
	fly.holeEdge:SetPoint("CENTER", Minimap, "CENTER")
	fly.disc = fly:CreateMaskTexture()
	fly.disc:SetTexture(MEDIA .. "DiscMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	fly.disc:SetPoint("CENTER", Minimap, "CENTER")

	local badge = badges.addons
	-- (a soft gold halo behind the button while its panel is out)
	badge.halo = badge:CreateTexture(nil, "BACKGROUND", nil, -1)
	badge.halo:SetTexture(MEDIA .. "DiscSoft")
	badge.halo:SetPoint("CENTER")
	badge.halo:SetSize(BADGE * 1.7, BADGE * 1.7)
	badge.halo:SetVertexColor(NORTH_COLOR[1], NORTH_COLOR[2], NORTH_COLOR[3], 1)
	badge.halo:SetAlpha(0)
	badge:EnableMouse(true)
	badge:RegisterForClicks("LeftButtonUp")
	badge:SetScript("OnClick", function(self)
		-- (other addons' buttons are moved and shown: not in a fight)
		if InCombatLockdown() then return end
		flyOpen = not flyOpen and #AddonButtons() > 0
		flyLast = GetTime()
		if ns.PlaceFly then ns.PlaceFly() end
		FlyTip(self)
	end)
	-- (pressed: the icon a touch smaller)
	badge:SetScript("OnMouseDown", function(self) self.icon:SetSize(BADGE * 0.47, BADGE * 0.47) end)
	badge:SetScript("OnMouseUp", function(self) self.icon:SetSize(BADGE * 0.55, BADGE * 0.55) end)
	badge:SetScript("OnEnter", FlyTip)
	badge:SetScript("OnLeave", function(self)
		self.icon:SetSize(BADGE * 0.55, BADGE * 0.55)
		ns.HideTip()
	end)
end

-- The slot under an icon: a soft gold glow behind it under the mouse.
local function Slot(index)
	local slot = flySlots[index]
	if slot then return slot end
	slot = CreateFrame("Frame", nil, fly)
	slot:SetSize(FLY_SIZE, FLY_SIZE)
	slot.glow = slot:CreateTexture(nil, "BORDER")
	slot.glow:SetTexture(MEDIA .. "DiscSoft")
	slot.glow:SetPoint("CENTER")
	slot.glow:SetSize(FLY_SIZE + 10, FLY_SIZE + 10)
	slot.glow:SetVertexColor(NORTH_COLOR[1], NORTH_COLOR[2], NORTH_COLOR[3], 1)
	slot.glow:SetAlpha(0)
	slot.lit = 0
	flySlots[index] = slot
	return slot
end

-- The arc's masks on (a round compass) or off (square): the glass, its lines and its dark pixel carved by them.
local function MaskFly(round)
	if fly.round == round then return end
	fly.round = round
	local function Mask(texture, mask)
		if round then pcall(texture.AddMaskTexture, texture, mask) else pcall(texture.RemoveMaskTexture, texture, mask) end
	end
	Mask(fly.ground, fly.hole)
	Mask(fly.arc, fly.hole)
	Mask(fly.arc, fly.disc)
	Mask(fly.edge, fly.holeEdge)
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do Mask(fly.lines[side], fly.hole) end
	fly.arc:SetShown(round)
end

-- The panel in its place, slid back toward the compass by `back` (0: in place, 1: all the way, under the ring).
local function AnchorFly(back)
	if not fly.left then return end
	fly:ClearAllPoints()
	fly:SetPoint("BOTTOMLEFT", Minimap, "CENTER", fly.left - flyH * back * FLY_SLIDE, fly.bottom)
end

-- An icon's own share of the opening: each a moment after the one before (all together on the way back).
local function IconShare(index, count, opening)
	local eased = Ease(flyShow)
	if not opening or count <= 1 then return eased end
	local delay = FLY_STAGGER * (index - 1) / (count - 1)
	local t = (flyShow - delay) / (1 - FLY_STAGGER)
	return Ease(math.max(0, math.min(1, t)))
end

-- One step of the panel's motion (every pass of the driver; force: draw it even when nothing moves).
local lastShow
local function AnimateFly(elapsed, force)
	if not fly then return end
	local opening = flyOpen
	flyShow = ns.Approach(flyShow, opening and 1 or 0, elapsed, FLY_IN, FLY_OUT)
	local moving = flyShow ~= lastShow
	lastShow = flyShow
	local count = #flyList
	local shown = flyShow > 0 and count > 0
	if fly:IsShown() ~= shown then fly:SetShown(shown) end
	local badge = badges.addons
	local eased = Ease(flyShow)
	-- (the button: its icon turned, its halo, lit while open or under the mouse)
	if moving or force then
		if badge.icon.SetRotation then badge.icon:SetRotation(-eased * math.pi / 4) end
		badge.halo:SetAlpha(0.22 * eased)
	end
	Light(badge, Over(badge), flyOpen)
	if moving or force then
		fly:SetAlpha(eased)
		AnchorFly(1 - eased)
	end
	local fighting = InCombatLockdown()
	for index, button in ipairs(flyList) do
		local slot = flySlots[index]
		if shown then
			local share = IconShare(index, count, opening)
			if moving or force or Safe(button.GetAlpha, button) ~= share then pcall(button.SetAlpha, button, share) end
			if hiddenByUs[button] then
				hiddenByUs[button] = nil
				pcall(button.Show, button)
			end
			if (moving or force) and slot and not fighting then
				pcall(button.ClearAllPoints, button)
				pcall(button.SetPoint, button, "CENTER", slot, "CENTER", 0, -FLY_RISE * (1 - share))
			end
			-- (the glow under the mouse, once the panel is out)
			if slot then
				local want = (flyShow == 1 and Over(button)) and 1 or 0
				if slot.lit ~= want then
					slot.lit = ns.Approach(slot.lit, want, elapsed, 0.12, 0.25)
					slot.glow:SetAlpha(0.16 * slot.lit)
				end
			end
		else
			if slot and slot.lit ~= 0 then
				slot.lit = 0
				slot.glow:SetAlpha(0)
			end
			if Safe(button.IsShown, button) then
				-- (hidden while closed: no tooltip, no click where nothing is seen)
				hiddenByUs[button] = true
				pcall(button.Hide, button)
			end
		end
	end
end

-- The icons in their slots (out of combat): the panel sized to them; hidden away while it is closed.
function ns.PlaceFly()
	if not fly or InCombatLockdown() then return end
	local list = AddonButtons()
	-- (an icon gone from the list: no longer the panel's to hide or fade)
	local keep = {}
	for _, button in ipairs(list) do keep[button] = true end
	for _, button in ipairs(flyList) do
		if not keep[button] then hiddenByUs[button] = nil end
	end
	wipe(flyList)
	local count = #list
	if count == 0 then flyOpen = false end
	-- (one row up to four; then two rows, at most six a row; past that, wider rows)
	local columns = count <= 4 and math.max(1, count) or math.min(FLY_COLUMNS, math.ceil(count / 2))
	if math.ceil(count / columns) > FLY_ROWS then columns = math.ceil(count / FLY_ROWS) end
	local rows = math.max(1, math.ceil(count / columns))
	local step = FLY_SIZE + FLY_GAP
	-- (the arc: around the compass's middle, outside the round buttons and the letters; square: a straight side)
	local half = (laidWidth or 140) / 2
	local round = ns.db.edge ~= "square"
	local reach = half + 2 + BADGE / 2 + FLY_AWAY
	if round then reach = math.max(reach, half * SCALE * LETTER_AT + 12) end
	local function Inner(y) -- the arc's distance from the middle, sideways, at a height
		if not round then return reach end
		y = math.min(math.abs(y), reach - 1)
		return math.sqrt(reach * reach - y * y)
	end
	-- (the rows from the button's up, each as near the arc as it lets them)
	local _, badgeY = SatellitePoint("addons")
	local bottom = badgeY - FLY_PAD - FLY_SIZE / 2
	local top = bottom + FLY_PAD * 2 + rows * FLY_SIZE + (rows - 1) * FLY_GAP
	local rowIn, outer, nearest = {}, 0, math.huge
	for line = 0, rows - 1 do
		local y0 = bottom + FLY_PAD + line * step
		local y1 = y0 + FLY_SIZE
		local near = (y0 <= 0 and y1 >= 0) and 0 or math.min(math.abs(y0), math.abs(y1))
		rowIn[line] = Inner(near) + FLY_PAD
		local inRow = math.min(columns, count - line * columns)
		outer = math.max(outer, rowIn[line] + inRow * step - FLY_GAP)
		nearest = math.min(nearest, rowIn[line])
	end
	outer = outer + FLY_PAD
	-- (the glass from a little inside where the arc reaches furthest out, so it ends in a short straight side and not
	-- a sharp point; the arc carves the rest)
	local inner = math.min(Inner(math.max(math.abs(bottom), math.abs(top))) + FLY_TIP, nearest - FLY_PAD)
	fly.left = flyH < 0 and -outer or inner
	fly.bottom = bottom
	fly:SetSize(outer - inner, top - bottom)
	-- (no clicks caught over the compass, where the arc carved the glass away)
	local carved = math.max(0, nearest - FLY_PAD / 2 - inner)
	if flyH < 0 then fly:SetHitRectInsets(0, carved, 0, 0) else fly:SetHitRectInsets(carved, 0, 0, 0) end
	local px = ns.Pixel(fly)
	fly.edge:ClearAllPoints()
	fly.edge:SetPoint("TOPLEFT", fly, "TOPLEFT", -px, px)
	fly.edge:SetPoint("BOTTOMRIGHT", fly, "BOTTOMRIGHT", px, -px)
	fly.lines:Fit()
	MaskFly(round)
	-- (radii: the hole at reach, its dark edge a pixel inside, the disc 1.5 px out: the hairline between)
	if round then
		fly.hole:SetSize(reach / HOLE_AT, reach / HOLE_AT)
		fly.holeEdge:SetSize((reach - px) / HOLE_AT, (reach - px) / HOLE_AT)
		fly.disc:SetSize((reach + 1.5 * px) / DISC_AT, (reach + 1.5 * px) / DISC_AT)
	end
	for index, button in ipairs(list) do
		flyList[index] = button
		local slot = Slot(index)
		-- (filled from the button's row up, the first icon of each row nearest the compass)
		local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
		local x = flyH * (rowIn[line] + column * step + FLY_SIZE / 2)
		local y = bottom + FLY_PAD + line * step + FLY_SIZE / 2
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", fly, "BOTTOMLEFT", x - fly.left, y - bottom)
		slot:Show()
		local width = Clean(Safe(button.GetWidth, button)) or FLY_SIZE
		local height = Clean(Safe(button.GetHeight, button)) or FLY_SIZE
		local scale = FLY_SIZE / math.max(width, height, 1)
		local now = Clean(Safe(button.GetScale, button)) or 1
		if math.abs(now - scale) > 0.01 then pcall(button.SetScale, button, scale) end
		pcall(button.SetFrameLevel, button, (fly:GetFrameLevel() or 1) + 2)
		-- (before it is first seen: unseen, so it fades in rather than flashing)
		if flyShow == 0 then pcall(button.SetAlpha, button, 0) end
	end
	for index = count + 1, #flySlots do flySlots[index]:Hide() end
	AnimateFly(0, true)
end

-- Under the mouse ------------------------------------------------------------------------------------------------

local function Near()
	-- (24 px all round the map: IsMouseOver's offsets move each edge up or right)
	if Over(Minimap, 24, -24, -24, 24) or Over(MinimapCluster) or Over(info) then return true end
	for _, badge in pairs(badges) do if Over(badge) then return true end end
	return fly ~= nil and fly:IsShown() and Over(fly)
end

-- Our round buttons at the hover's opacity; each lit under the mouse.
local function SetBadges(alpha)
	for key, badge in pairs(badges) do
		if badge:GetAlpha() ~= alpha then badge:SetAlpha(alpha) end
		if key ~= "addons" then Light(badge, Over(badge)) end -- (the addons' button: AnimateFly's)
	end
end

local function Init()
	if not ns.On("minimap") or not (Minimap and MinimapCluster) then return end
	MakeInfo()
	MakeDeco()
	for key in pairs(SATELLITES) do Light(Badge(key), false) end
	MakeFly()
	Gather()
	UpdateCalendar()
	ns.MinimapEdge(true)
	-- (the zoom by the wheel, when the game has none of its own)
	if Minimap.EnableMouseWheel and not Minimap:GetScript("OnMouseWheel") then
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", function(self, delta)
			local zoom = self:GetZoom() or 0
			local most = (self.GetZoomLevels and self:GetZoomLevels() or 6) - 1
			self:SetZoom(math.max(0, math.min(most, zoom + (delta > 0 and 1 or -1))))
		end)
	end
	SetBadges(0)
	Layout()
	UpdateInfo()
	local sinceInfo, sinceAgain = 0, 0
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		local now = GetTime()
		if Near() then lastNear = now end
		local want = (now - lastNear < LINGER) and 1 or 0
		-- (coming into view: tidied first, so nothing the game showed again flashes; reparenting waits out a fight)
		if want == 1 and hover == 0 and not InCombatLockdown() then Gather() end
		hover = ns.Approach(hover, want, elapsed, HOVER_IN, HOVER_OUT)
		-- (every pass: the game shows some of its pieces again on its own)
		SetBadges(hover)
		KeepCoordsUnseen()
		KeepTargetsUnseen()
		Layout()
		AnimateFly(elapsed)
		-- (the addons' panel closes a moment after the mouse left it)
		if flyOpen then
			if Over(fly) or Over(badges.addons) then flyLast = now end
			if now - flyLast > FLY_LINGER and not InCombatLockdown() then
				flyOpen = false
				ns.PlaceFly()
			end
		end
		sinceInfo = sinceInfo + elapsed
		if sinceInfo >= INFO_EVERY then
			sinceInfo = 0
			UpdateInfo()
			UpdateCalendar()
		end
		sinceAgain = sinceAgain + elapsed
		if sinceAgain >= AGAIN and not InCombatLockdown() then
			sinceAgain = 0
			Gather()
		end
	end)
end

table.insert(ns.modules, { init = Init })

-- (Fade.lua: the compass's parts outside its frame count as the compass under the mouse; the addons panel open
-- keeps it shown)
local parts = {}
function ns.CompassParts()
	wipe(parts)
	if info then parts[#parts + 1] = info end
	if fly and (flyOpen or flyShow > 0) then parts[#parts + 1] = fly end
	for _, badge in pairs(badges) do parts[#parts + 1] = badge end
	return parts
end
function ns.CompassOpen() return flyOpen and true or false end

-- (Fade.lua: the ring, the letters and the band fade as the compass comes and goes; the map itself never does)
local decorAlpha
function ns.CompassDecor(alpha)
	alpha = math.floor(alpha * 100 + 0.5) / 100 -- (hundredths: no work for nothing)
	if alpha == decorAlpha then return end
	decorAlpha = alpha
	if deco then pcall(deco.SetAlpha, deco, alpha) end
	if info then pcall(info.SetAlpha, info, alpha) end
end
