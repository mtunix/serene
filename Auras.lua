local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Buffs and debuffs made calm: the game's own aura buttons (yours at the top of the screen, your weapons' enchants,
-- the small ones on your target's and focus's frames, and your debuffs on enemies' nameplates), nothing new beside
-- them. Edit Mode still places them, sizes them and sets how they wrap; the game still fills them, counts them down,
-- sorts them; a right click still cancels one of yours. Only looks change:
--   - the icon round, like the unit frames' portraits, or square (its baked-in edge trimmed away either way);
--   - around it a hairline (one pixel, or two or three): the game's gold, soft, for a buff; for a debuff the game's
--     own border made that line, in a quieter shade of its colour for what it is (magic blue, curse violet, disease
--     ochre, poison green, the rest soft red) or the game's own colours; a weapon's enchant in soft violet. Or only
--     the debuffs', or none. A target's aura's swirl takes the icon's shape;
--   - the time left small and muted, a soft white once it runs low (the game says when), readable over a bright sky:
--     outlined thinly (the quieter), or on a little pill of dark glass, or not shown; under the icon (the game's
--     place) or on its lower edge; its size chosen or the game's; the count in Serene's warm white;
--   - the arrow that folds your buffs away (the game's) only under the mouse.
-- Your own buffs and debuffs go to Serene's own frame instead (AuraFrame.lua) unless the game's is chosen; otherwise
-- this dresses only the others' (target, focus, nameplates).
-- Each look is chosen on Serene's page ("Buffs") and applied at once.
-- Nothing protected is touched (no frame moved, nothing written into the game's tables): all of it is safe in a fight,
-- and it reads nothing the game keeps secret there (it passes the game's colours on without looking at them when it
-- can't). Fade.lua still fades them.
--   /serene auras on|off      (a reload to switch)
--   /serene auraunits on|off  the target's and focus's too (a reload to switch)
--   /serene auratime outline|plate|none  the time left outlined, on a pill of glass, or not shown (at once)

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8X8" -- (the square's line)
local DISC = MEDIA .. "AuraDisc"  -- (one soft-edged circle: the icon's mask, its ring a pixel wider behind it, its
local MASK = DISC                  -- edge, the swirls; all lined up, smooth at small sizes)
local DIM = 0.55                   -- how dark the icon's elapsed part turns

-- Every swirl's timing, as the game gave it (secret or not), kept from the moment Serene loads: an aura's swirl
-- dressed after the game set it (a nameplate's debuff, there before Serene saw it) can still be followed at once.
-- Hooked on all swirls alike, as OmniCC does. Not only the calls Serene knows by name: every one of the swirl's that
-- sets a time (its name says cooldown, duration, expiration, aura or time), each one's last kept in the order they
-- came, to be played again on Serene's own swirl the same way. A few values per swirl, let go with it.
local TIMING = {}       -- the swirls' timing calls on this game (names)
local lastTiming = setmetatable({}, { __mode = "k" }) -- swirl -> { [name] = { name, n = .., args... }, order = {...} }
local seenCalls = setmetatable({}, { __mode = "k" })  -- swirl -> name -> times called (for /serene debug plates)
local function IsTimingCall(name)
	if type(name) ~= "string" or not name:find("^Set") or name:find("Countdown") or name:find("Swipe")
		or name:find("Edge") or name:find("Bling") or name:find("Point") then
		return false
	end
	return name:find("Cooldown") or name:find("Duration") or name:find("Expiration") or name:find("Aura")
		or name:find("Time") or name:find("Paused") or false
end
do
	local probe = CreateFrame("Cooldown")
	local methods = probe and getmetatable(probe)
	methods = methods and methods.__index
	if type(methods) == "table" then
		for name, fn in pairs(methods) do
			if type(fn) == "function" and IsTimingCall(name) then TIMING[#TIMING + 1] = name end
		end
		table.sort(TIMING)
		for _, name in ipairs(TIMING) do
			hooksecurefunc(methods, name, function(self, ...)
				local kept = lastTiming[self]
				if not kept then
					kept = { order = {} }
					lastTiming[self] = kept
				end
				if not kept[name] then kept.order[#kept.order + 1] = name end
				kept[name] = { name, n = select("#", ...) + 1, ... } -- (n: nil arguments kept, # would drop them)
				local seen = seenCalls[self] or {}
				seenCalls[self] = seen
				seen[name] = (seen[name] or 0) + 1
			end)
		end
		for _, name in ipairs({ "Clear", "Pause", "Resume" }) do
			if type(methods[name]) == "function" then
				hooksecurefunc(methods, name, function(self)
					-- (a cleared swirl's timing forgotten, so Replay can't bring it back)
					if name == "Clear" then lastTiming[self] = nil end
					local seen = seenCalls[self] or {}
					seenCalls[self] = seen
					seen[name] = (seen[name] or 0) + 1
				end)
			end
		end
	end
end

-- The game's timing on a swirl played again on another (Serene's): each kind of call's last, in the order they came.
-- True when any took.
local function Replay(from, to)
	local kept = lastTiming[from]
	if not kept then return false end
	local any = false
	for _, name in ipairs(kept.order) do
		local call = kept[name]
		if call and type(to[name]) == "function" and pcall(to[name], to, unpack(call, 2, call.n)) then any = true end
	end
	return any
end

-- A texture set smooth, not snapped to pixels.
-- (never a "TRILINEAR" filter here: it crashes this client on login)
local function Smooth(texture, file)
	if not pcall(texture.SetTexture, texture, file, "CLAMP", "CLAMP") then
		pcall(texture.SetTexture, texture, file)
	end
	if texture.SetSnapToPixelGrid then pcall(texture.SetSnapToPixelGrid, texture, false) end
	if texture.SetTexelSnappingBias then pcall(texture.SetTexelSnappingBias, texture, 0) end
end
local PILL = MEDIA .. "Pill"      -- (a small piece of glass under the time left)
local INK = ns.INK
local PLATE_ALPHA = 0.72
local PLATE_X, PLATE_Y = 4, 1     -- the glass beyond the words
local SOFT = ns.SOFT_RGB
local MUTED = ns.MUTED_RGB
local LINE = ns.LINE
local TRIM = 0.08          -- the icon's edge trimmed away, on each side
local BORDER_ALPHA = 0.95  -- a debuff's hairline (over the gold one, which it hides)
local TRACK_ALPHA = 0.22   -- the line under the ring while it drains
local EDGE = { 0, 0, 0, 0.85 } -- a dark hairline outside it all: it stands out on bright ground
local GOLD = { 1, 0.82, 0.35 }
local DURATION_SHRINK = 1  -- the time left this much smaller than the game's
local DURATION_LEAST = 8
ns.AURA_FONT_AUTO = 6      -- (the time's size at or below this: the game's, a little smaller)
local ON_EDGE = 1          -- the time on the icon: this far above its lower edge
-- A debuff's kind, in a quieter shade (the game's own are full and bright).
local DEBUFF = { 0.82, 0.34, 0.3 }
local KINDS = {
	magic = { 0.36, 0.6, 0.92 },
	curse = { 0.66, 0.42, 0.9 },
	disease = { 0.78, 0.6, 0.3 },
	poison = { 0.42, 0.7, 0.36 },
	bleed = DEBUFF,
	none = DEBUFF,
}
local ENCHANT = { 0.7, 0.5, 0.92 }
-- Where the aura buttons live: the game's frames, and the older global names.
local PLAYER_HOLDERS = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }
local PLAYER_GLOBALS = { { "BuffButton", 40 }, { "DebuffButton", 16 }, { "TempEnchant", 3 } }
local UNIT_FRAMES = { "TargetFrame", "FocusFrame" }
local UNIT_GLOBALS = { { "TargetFrameBuff", 32 }, { "TargetFrameDebuff", 16 }, { "FocusFrameBuff", 32 },
	{ "FocusFrameDebuff", 16 } }
-- The methods after which the game has (re)filled its buttons.
local UPDATES = { "Update", "UpdateAuraButtons", "UpdateAuras", "UpdateGridLayout", "RefreshAuras" }

local dressed = {}    -- button -> its parts (kept here, never on the game's button)
local count = { player = 0, unit = 0, plate = 0, borders = 0 } -- buttons dressed, by kind (for /serene debug)
local holding = false -- (Serene's own calls, not heard by its hooks)
local pending = false -- (a scan already asked for on the next frame)
local active, onUnits, onPlayer, onPlates = false, false, true, false
local hookedObjects = {} -- (hooks can't be removed: each object hooked once)

local function IsRegion(value)
	return type(value) == "table" and type(value.GetObjectType) == "function" and type(value.SetAlpha) == "function"
end

local function IsTexture(region)
	return IsRegion(region) and Safe(region.IsObjectType, region, "Texture") == true
end

local function IsFontString(region)
	return IsRegion(region) and Safe(region.IsObjectType, region, "FontString") == true
end

-- A part of a button, by its key or the older global name.
-- (rawget: some of the game's frames have an __index metatable)
local function Part(button, keys, suffix, check)
	for _, key in ipairs(keys) do
		local part = rawget(button, key)
		if check(part) then return part end
	end
	local name = Clean(Safe(button.GetName, button))
	if type(name) == "string" and suffix then
		local part = _G[name .. suffix]
		if check(part) then return part end
	end
end

-- (a key holding a part, by a word in it, when the usual keys aren't there: newer games name them otherwise)
local NOT_ICON = { "Border", "Highlight", "Overlay", "Raid", "Leader", "Pvp", "PvP", "Quest", "Prestige", "Role",
	"Guide", "Ready", "Portrait", "Corner", "Status", "Battle" }
local function KeyWith(button, word, check, avoid)
	for key, value in pairs(button) do
		if type(key) == "string" and key:find(word, 1, true) and check(value) then
			local bad = false
			for _, no in ipairs(avoid or {}) do bad = bad or key:find(no, 1, true) ~= nil end
			if not bad then return value end
		end
	end
end

local function IconOf(button)
	return Part(button, { "Icon", "icon" }, "Icon", IsTexture) or KeyWith(button, "Icon", IsTexture, NOT_ICON)
end
local function CountOf(button)
	return Part(button, { "Count", "count", "Stack", "Applications" }, "Count", IsFontString)
		or KeyWith(button, "Count", IsFontString)
end
local function DurationOf(button) return Part(button, { "Duration", "duration" }, "Duration", IsFontString) end

local function IsCooldown(value)
	return IsRegion(value) and Safe(value.IsObjectType, value, "Cooldown") == true
end

-- The game's swirl over an aura (a target's): by its key, or a child that is one.
local function CooldownOf(button)
	local found = Part(button, { "Cooldown", "cooldown" }, "Cooldown", IsCooldown)
	if found then return found end
	for _, child in ipairs({ Safe(button.GetChildren, button) }) do
		if IsCooldown(child) then return child end
	end
end

-- Its borders: the game's (a debuff's, a weapon enchant's), whatever their key.
local function BordersOf(button)
	local found, seen = {}, {}
	local function Add(texture, kind)
		if IsTexture(texture) and not seen[texture] then
			seen[texture] = true
			found[#found + 1] = { texture = texture, kind = kind }
		end
	end
	for key, value in pairs(button) do
		if type(key) == "string" and key:find("Border") and not key:find("Highlight") then
			Add(value, key:find("Enchant") and "enchant" or "debuff")
		end
	end
	local name = Clean(Safe(button.GetName, button))
	if type(name) == "string" then
		Add(_G[name .. "Border"], name:find("TempEnchant") and "enchant" or "debuff")
	end
	return found
end

local function IsAuraButton(frame)
	if not IsRegion(frame) or dressed[frame] then return false end
	if Safe(frame.IsObjectType, frame, "StatusBar") == true then return false end
	if not IconOf(frame) then return false end
	return CountOf(frame) ~= nil or DurationOf(frame) ~= nil or CooldownOf(frame) ~= nil
end

-- Inside a frame the game keys "Auras" (the newer unit frames) anything is an aura: its parts found by their shape when
-- their keys say nothing. The icon: its largest square texture (its own, or one frame down); the count: a number.
-- (a size kept secret, in a fight, counts as no area at all)
local function Area(region)
	local width, height = Clean(Safe(region.GetWidth, region)), Clean(Safe(region.GetHeight, region))
	if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return 0, false end
	return width * height, math.abs(width - height) <= math.max(width, height) * 0.2
end

local function LooseIcon(button)
	local best, bestArea
	local function Look(frame)
		for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
			if IsTexture(region) and Safe(region.IsObjectType, region, "MaskTexture") ~= true then
				local area, square = Area(region)
				if square and (not bestArea or area > bestArea) then best, bestArea = region, area end
			end
		end
	end
	Look(button)
	if not best then
		for _, child in ipairs({ Safe(button.GetChildren, button) }) do
			if not IsCooldown(child) then Look(child) end
		end
	end
	return best
end

local function LooseCount(button)
	for _, region in ipairs({ Safe(button.GetRegions, button) }) do
		if IsFontString(region) then return region end
	end
end

-- The newer game's unit auras, wherever they hang: a small square texture whose picture the game keeps secret (it sets
-- auras' icons that way; no frame art is). Frames with a portrait are left alone.
local function SecretIcon(frame)
	for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
		if IsTexture(region) and ns.IsSecret(Safe(region.GetTexture, region)) then
			local _, square = Area(region)
			local width = Clean(Safe(region.GetWidth, region))
			if square and type(width) == "number" and width <= 48 then return region end
		end
	end
end

local function HasPortrait(frame)
	for key in pairs(frame) do
		if type(key) == "string" and key:find("Portrait", 1, true) then return true end
	end
	return false
end

local function IsLooseAura(frame)
	if not IsRegion(frame) or dressed[frame] then return false end
	if Safe(frame.IsObjectType, frame, "StatusBar") == true or IsCooldown(frame) then return false end
	return (IconOf(frame) or LooseIcon(frame)) ~= nil
end

local function Font(text, shrink, color)
	local font, size, flags = Safe(text.GetFont, text)
	font, size = Clean(font), Clean(size)
	holding = true
	if font and type(size) == "number" and shrink and shrink > 0 then
		pcall(text.SetFont, text, font, math.max(DURATION_LEAST, size - shrink), Clean(flags) or "")
	end
	if color then pcall(text.SetTextColor, text, color[1], color[2], color[3]) end
	pcall(text.SetShadowColor, text, 0, 0, 0, 0.85)
	pcall(text.SetShadowOffset, text, 1, -1)
	holding = false
end

-- The look chosen -----------------------------------------------------------------------------------------------------

local function Setting(key, fallback)
	local value = ns.db and ns.db[key]
	if value == nil then return fallback end
	return value
end

local function Look()
	local size = math.floor(tonumber(Setting("auraRingSize", 1)) or 1)
	local time = Setting("auraTime", "outline")
	return {
		round = Setting("auraShape", "round") ~= "square",
		ring = Setting("auraRing", "all"),                 -- "all", "debuffs" or "none"
		width = math.max(1, math.min(3, size)),
		quiet = Setting("auraColors", "quiet") ~= "game",
		time = (time == "plate" or time == "none") and time or "outline",
		on = Setting("auraTimeAt", "under") == "on",
		font = math.floor(tonumber(Setting("auraTimeSize", 0)) or 0),
		drain = Setting("auraDrain", true) ~= false,
		edge = Setting("auraEdge", true) ~= false,
		dim = Setting("auraDim", true) ~= false,
	}
end

-- Laying a hairline around the icon -------------------------------------------------------------------------------

-- (below the icon, the icon a pixel or so smaller on each side shows it as a hairline)
local function Around(texture, icon, px, sublevel)
	local layer = Clean(Safe(icon.GetDrawLayer, icon)) or "BACKGROUND"
	pcall(texture.SetDrawLayer, texture, layer, sublevel)
	pcall(texture.ClearAllPoints, texture)
	pcall(texture.SetPoint, texture, "TOPLEFT", icon, "TOPLEFT", -px, px)
	pcall(texture.SetPoint, texture, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", px, -px)
end

local function Thickness(a, look)
	return (a.px or 1) * look.width
end

-- A debuff's colour, the game's own made quieter (when it can be read: in a fight it may not, and is kept).
local function Quieter(r, g, b)
	r, g, b = Clean(r), Clean(g), Clean(b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
	local colors = _G.DebuffTypeColor
	if type(colors) ~= "table" then return nil end
	for kind, color in pairs(colors) do
		if type(color) == "table" and type(kind) == "string" then
			local cr, cg, cb = Clean(color.r), Clean(color.g), Clean(color.b)
			if type(cr) == "number" and math.abs(cr - r) < 0.02 and math.abs(cg - g) < 0.02 and math.abs(cb - b) < 0.02 then
				return KINDS[kind:lower()] or (kind == "" and DEBUFF) or nil
			end
		end
	end
end

-- An atlas or a file named for a kind of debuff.
local function KindOfName(name)
	name = Clean(name)
	if type(name) ~= "string" then return nil end
	name = name:lower()
	for kind, color in pairs(KINDS) do
		if kind ~= "none" and name:find(kind, 1, true) then return color end
	end
end

local function Tint(texture, color)
	holding = true
	pcall(texture.SetVertexColor, texture, color[1], color[2], color[3])
	holding = false
end

-- The game's border made the hairline: the icon's shape, the thickness chosen (unseen with no line chosen).
local function Flatten(a, border, look)
	look = look or Look()
	local texture = border.texture
	holding = true
	pcall(Smooth, texture, look.round and DISC or FLAT)
	pcall(texture.SetTexCoord, texture, 0, 1, 0, 1)
	pcall(texture.SetAlpha, texture, look.ring == "none" and 0 or BORDER_ALPHA)
	pcall(Around, texture, a.icon, Thickness(a, look), -6)
	holding = false
end

-- The ring draining over the line (the game's swirl, made a ring): the line's colour, brighter.
local function SwipeColor(a, r, g, b)
	a.swipe = { r, g, b }
	local cooldown = a.cooldown
	if not cooldown or a.gameDims then return end
	holding = true
	pcall(cooldown.SetSwipeColor, cooldown, r, g, b, 0.9)
	holding = false
end

-- Its colour: the kind's quieter shade, or the game's own as it gave it.
local function Colour(a, border, look)
	local texture = border.texture
	if border.kind == "enchant" then
		Tint(texture, ENCHANT)
		return SwipeColor(a, ENCHANT[1], ENCHANT[2], ENCHANT[3])
	end
	local raw = a.raw[texture]
	if raw then
		local quiet = look.quiet and Quieter(raw[1], raw[2], raw[3])
		if quiet then
			Tint(texture, quiet)
			return SwipeColor(a, quiet[1], quiet[2], quiet[3])
		end
		-- (secret, or the game's colours chosen: its values handed back unread)
		holding = true
		pcall(texture.SetVertexColor, texture, raw[1], raw[2], raw[3])
		holding = false
		SwipeColor(a, raw[1], raw[2], raw[3])
	elseif a.named[texture] then
		Tint(texture, a.named[texture])
		SwipeColor(a, a.named[texture][1], a.named[texture][2], a.named[texture][3])
	end
end

local function HookBorder(a, border)
	local texture = border.texture
	if hookedObjects[texture] then return end
	hookedObjects[texture] = true
	-- (the game draws its border art anew: the hairline again, coloured by what its name says)
	local function Again(_, name)
		if holding then return end
		Flatten(a, border)
		a.raw[texture] = nil
		if border.kind == "enchant" then
			Tint(texture, ENCHANT)
		else
			a.named[texture] = KindOfName(name) or DEBUFF
			Tint(texture, a.named[texture])
			SwipeColor(a, a.named[texture][1], a.named[texture][2], a.named[texture][3])
		end
	end
	for _, method in ipairs({ "SetTexture", "SetAtlas" }) do
		if texture[method] then hooksecurefunc(texture, method, Again) end
	end
	-- (moved or sized by the game: back around the icon)
	for _, method in ipairs({ "SetPoint", "SetSize", "SetAllPoints" }) do
		if texture[method] then
			hooksecurefunc(texture, method, function()
				if holding then return end
				holding = true
				pcall(Around, texture, a.icon, Thickness(a, Look()), -6)
				holding = false
			end)
		end
	end
	-- (the game's colour for the kind: kept as it gave it (it may be secret: never looked at then), and made a
	-- quieter shade when it can be read and that is chosen)
	hooksecurefunc(texture, "SetVertexColor", function(_, r, g, b)
		if holding then return end
		if border.kind == "enchant" then return Tint(texture, ENCHANT) end
		a.raw[texture] = { r, g, b }
		local quiet = Look().quiet and Quieter(r, g, b)
		if quiet then
			Tint(texture, quiet)
			SwipeColor(a, quiet[1], quiet[2], quiet[3])
		else
			SwipeColor(a, r, g, b)
		end
	end)
end

-- The game's swirl made the ring: as large as the line around the icon, under the icon (lifted above it), draining
-- (not filling) in the line's colour; the line itself dim beneath while it drains. Its timing stays the game's (in a
-- fight too). Off: no swirl, the line alone.
-- (a nameplate's: the game times its swirl where Serene can't follow it, so the swirl itself is the darkening, over
-- the icon and its line, as on Serene's own buff frame)
local function GameDim(a, look)
	local cooldown = a.cooldown
	local thick = look.ring == "none" and 0 or Thickness(a, look)
	holding = true
	pcall(cooldown.ClearAllPoints, cooldown)
	pcall(cooldown.SetPoint, cooldown, "TOPLEFT", a.icon, "TOPLEFT", -thick, thick)
	pcall(cooldown.SetPoint, cooldown, "BOTTOMRIGHT", a.icon, "BOTTOMRIGHT", thick, -thick)
	pcall(cooldown.SetSwipeTexture, cooldown, look.round and DISC or FLAT)
	pcall(cooldown.SetUseCircularEdge, cooldown, look.round)
	pcall(cooldown.SetReverse, cooldown, true)
	pcall(cooldown.SetDrawEdge, cooldown, false)
	pcall(cooldown.SetDrawBling, cooldown, false)
	pcall(cooldown.SetDrawSwipe, cooldown, look.dim and true or false)
	pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, DIM)
	-- (the icon under it, the words above)
	local level = Clean(Safe(a.button.GetFrameLevel, a.button)) or 1
	pcall(a.face.SetFrameLevel, a.face, level + 1)
	pcall(cooldown.SetFrameLevel, cooldown, level + 2)
	pcall(a.top.SetFrameLevel, a.top, level + 3)
	local countFrame = rawget(a.button, "CountFrame")
	if type(countFrame) == "table" and countFrame.SetFrameLevel then
		pcall(countFrame.SetFrameLevel, countFrame, level + 3)
	end
	holding = false
end

local function Ring(a, look)
	local cooldown = a.cooldown
	if not cooldown then return end
	if a.gameDims then return GameDim(a, look) end
	local thick = Thickness(a, look)
	local drains = look.drain and look.ring ~= "none"
	holding = true
	pcall(cooldown.ClearAllPoints, cooldown)
	pcall(cooldown.SetPoint, cooldown, "TOPLEFT", a.icon, "TOPLEFT", -thick, thick)
	pcall(cooldown.SetPoint, cooldown, "BOTTOMRIGHT", a.icon, "BOTTOMRIGHT", thick, -thick)
	pcall(cooldown.SetSwipeTexture, cooldown, look.round and DISC or FLAT)
	pcall(cooldown.SetUseCircularEdge, cooldown, look.round)
	pcall(cooldown.SetReverse, cooldown, false)
	pcall(cooldown.SetDrawEdge, cooldown, false)
	pcall(cooldown.SetDrawBling, cooldown, false)
	pcall(cooldown.SetDrawSwipe, cooldown, drains)
	local swipe = a.swipe or GOLD
	pcall(cooldown.SetSwipeColor, cooldown, swipe[1], swipe[2], swipe[3], 0.9)
	holding = false
	-- (the icon and its words above the ring)
	local level = Clean(Safe(cooldown.GetFrameLevel, cooldown)) or 1
	pcall(a.face.SetFrameLevel, a.face, level + 1)
	pcall(a.dim.SetFrameLevel, a.dim, level + 2)
	pcall(a.top.SetFrameLevel, a.top, level + 3)
	local countFrame = rawget(a.button, "CountFrame")
	if type(countFrame) == "table" and countFrame.SetFrameLevel then
		pcall(countFrame.SetFrameLevel, countFrame, level + 3)
	end
end

-- The icon's elapsed part darkened: a swirl of Serene's over it, timed as the game times its own (each call of the
-- game's on its swirl replayed on this one: its values passed on as they are, secret or not).
local function Dim(a, look)
	look = look or Look()
	local on = false
	pcall(a.dim.SetSwipeTexture, a.dim, look.round and DISC or FLAT)
	pcall(a.dim.SetUseCircularEdge, a.dim, look.round)
	-- (the game's timing on its swirl, all of it, kept from before Serene dressed it too)
	if look.dim and a.cooldown and not a.gameDims then on = Replay(a.cooldown, a.dim) end
	if not on then pcall(a.dim.Clear, a.dim) end
	pcall(a.dim.SetDrawSwipe, a.dim, on and true or false)
end

-- The line under the ring: full when steady, dim while the ring drains over it.
local function Track(a, look)
	local drains = a.cooldown and a.timed and look.drain and look.ring ~= "none" and not a.gameDims
	a.rim:SetAlpha(drains and TRACK_ALPHA / LINE[4] or 1) -- (its colour already holds LINE's alpha)
	for _, border in ipairs(a.borders) do
		pcall(border.texture.SetAlpha, border.texture, look.ring == "none" and 0 or drains and TRACK_ALPHA or BORDER_ALPHA)
	end
end

local function HookRing(a)
	local cooldown = a.cooldown
	if not cooldown or hookedObjects[cooldown] then return end
	hookedObjects[cooldown] = true
	local function Again()
		if holding then return end
		Ring(a, Look())
	end
	for _, method in ipairs({ "SetPoint", "SetAllPoints", "SetReverse", "SetDrawSwipe", "SetSwipeColor",
		"SetSwipeTexture", "SetDrawEdge", "SetFrameLevel" }) do
		if cooldown[method] then hooksecurefunc(cooldown, method, Again) end
	end
	-- (timed or not: the line beneath dim or full)
	local function Timed(on)
		return function()
			if holding then return end
			a.timed = on
			Track(a, Look())
		end
	end
	for _, method in ipairs({ "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownDuration", "SetCooldownUNIX",
		"Show" }) do
		if cooldown[method] then hooksecurefunc(cooldown, method, Timed(true)) end
	end
	for _, method in ipairs({ "Clear", "Hide" }) do
		if cooldown[method] then hooksecurefunc(cooldown, method, Timed(false)) end
	end
	-- (its timing played again on the swirl darkening the icon, each time the game sets it; these hooks wrap the
	-- shared ones at file load, so the call is already kept when they run)
	for _, method in ipairs(TIMING) do
		if cooldown[method] then hooksecurefunc(cooldown, method, function() pcall(Dim, a) end) end
	end
	if cooldown.Clear then hooksecurefunc(cooldown, "Clear", function() pcall(Dim, a) end) end
end

-- The icon's shape: round (masked like the portraits) or square; the dark edge, the gold line around it; the
-- borders; the ring.
local function Shape(a, look)
	local icon = a.icon
	if a.mask then
		if look.round and not a.masked then
			a.masked = pcall(icon.AddMaskTexture, icon, a.mask)
		elseif not look.round and a.masked then
			pcall(icon.RemoveMaskTexture, icon, a.mask)
			a.masked = false
		end
	end
	local thick = Thickness(a, look)
	local shape = look.round and DISC or FLAT
	Smooth(a.rim, shape)
	a.rim:SetVertexColor(LINE[1], LINE[2], LINE[3], LINE[4])
	a.rim:SetShown(look.ring == "all")
	Smooth(a.edge, shape)
	a.edge:SetVertexColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	a.edge:SetShown(look.edge)
	-- (sublevels: the game's border at -6 over the gold line at -7 over the dark edge at -8)
	holding = true
	pcall(Around, a.rim, icon, thick, -7)
	pcall(Around, a.edge, icon, (look.ring == "none" and 0 or thick) + (a.px or 1), -8)
	holding = false
	for _, border in ipairs(a.borders) do
		Flatten(a, border, look)
		Colour(a, border, look)
	end
	Ring(a, look)
	Track(a, look)
	pcall(Dim, a, look)
end

-- The time left -------------------------------------------------------------------------------------------------------

-- Muted, a soft white once the game says it runs low (it turns it white then; gold otherwise). Given back by the same
-- method the game used (a text's colour and its vertex colour may multiply).
local function HookDuration(text)
	if hookedObjects[text] then return end
	hookedObjects[text] = true
	local function Recolour(method, r, g, b)
		if holding then return end
		if type(r) == "table" then r, g, b = r.r, r.g, r.b end
		r, g, b = Clean(r), Clean(g), Clean(b)
		local low = type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.95 and g > 0.95
			and b > 0.95
		local color = low and SOFT or MUTED
		holding = true
		pcall(text[method], text, color[1], color[2], color[3])
		holding = false
	end
	for _, method in ipairs({ "SetTextColor", "SetVertexColor" }) do
		if text[method] then
			hooksecurefunc(text, method, function(_, ...) Recolour(method, ...) end)
		end
	end
end

-- Where the game put the words (to give them back).
local function Points(region)
	local points = {}
	for index = 1, (Clean(Safe(region.GetNumPoints, region)) or 0) do
		local point = { Safe(region.GetPoint, region, index) }
		if point[1] then points[#points + 1] = point end
	end
	return points
end

-- A pill of glass under the time left: as wide as its words, shown with them (when that look is chosen).
local function Plate(a)
	local text = a.duration
	local plate = (a.top or a.face or a.button):CreateTexture(nil, "OVERLAY")
	plate:SetTexture(PILL)
	plate:SetVertexColor(INK[1], INK[2], INK[3], PLATE_ALPHA)
	plate:SetPoint("TOPLEFT", text, "TOPLEFT", -PLATE_X, PLATE_Y)
	plate:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", PLATE_X, -PLATE_Y)
	a.plate = plate
	local function Sync()
		plate:SetShown(Look().time == "plate" and Clean(Safe(text.IsShown, text)) and true or false)
	end
	for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
		if text[method] then hooksecurefunc(text, method, Sync) end
	end
	a.sync = Sync
end

-- The time left in the look chosen: outlined, on its pill or unseen; under the icon or on its lower edge; its size.
local function TimeLook(a, look)
	local text = a.duration
	if not text then return end
	look = look or Look()
	local outline = look.time == "outline"
	local size = look.font > ns.AURA_FONT_AUTO and look.font or a.size
	holding = true
	pcall(text.SetAlpha, text, look.time == "none" and 0 or 1)
	if a.font and size then pcall(text.SetFont, text, a.font, size, outline and "OUTLINE" or a.flags) end
	pcall(text.SetShadowColor, text, 0, 0, 0, outline and 0.4 or 0.85)
	pcall(text.SetShadowOffset, text, 1, -1)
	if look.on then
		pcall(text.ClearAllPoints, text)
		pcall(text.SetPoint, text, "BOTTOM", a.icon, "BOTTOM", 0, ON_EDGE)
		pcall(text.SetDrawLayer, text, "OVERLAY", 6)
		a.moved = true
	elseif a.moved then
		pcall(text.ClearAllPoints, text)
		for _, point in ipairs(a.points) do pcall(text.SetPoint, text, unpack(point)) end
		if a.layer then pcall(text.SetDrawLayer, text, a.layer, a.sublevel or 0) end
		a.moved = false
	end
	holding = false
	local layer, sublevel = Safe(text.GetDrawLayer, text)
	layer, sublevel = Clean(layer) or "OVERLAY", Clean(sublevel)
	-- (the pill just under the words; -8 is the lowest sublevel there is)
	pcall(a.plate.SetDrawLayer, a.plate, layer, math.max(-8, (type(sublevel) == "number" and sublevel or 0) - 1))
	a.sync()
end

local function HookPlace(a)
	local text = a.duration
	hooksecurefunc(text, "SetPoint", function()
		if holding then return end
		-- (the game placed the words anew: its place kept, and ours again if they are on the icon)
		a.points = Points(text)
		if a.moved then
			a.moved = false
			TimeLook(a)
		end
	end)
end

-- Placing again at the current scale (one pixel stays one pixel), in the look chosen.
local function Style(a, look)
	look = look or Look()
	a.px = ns.Pixel(a.button)
	Shape(a, look)
	TimeLook(a, look)
end

local function Fit(a)
	if ns.Pixel(a.button) ~= a.px then Style(a) end
end

-- Dressing one of the game's aura buttons ---------------------------------------------------------------------------

local function Dress(button, kind, loose, found)
	if found then
		if dressed[button] then return end
	elseif loose then
		if not IsLooseAura(button) then return end
	elseif not IsAuraButton(button) then
		return
	end
	local a = { button = button, icon = found or IconOf(button) or (loose and LooseIcon(button)),
		count = CountOf(button) or (loose and LooseCount(button)) or nil, duration = DurationOf(button),
		borders = BordersOf(button), raw = {}, named = {} }
	a.gameDims = kind == "plate" -- (see GameDim)
	dressed[button] = a
	count[kind] = count[kind] + 1
	local icon = a.icon
	a.cooldown = CooldownOf(button)
	-- the icon and its words lifted onto a face of their own, above the game's swirl (made the ring under it)
	a.face = CreateFrame("Frame", nil, button)
	a.face:SetAllPoints(button)
	a.face:EnableMouse(false)
	a.face:SetFrameLevel((Clean(Safe(button.GetFrameLevel, button)) or 1) + 2)
	pcall(icon.SetParent, icon, a.face)
	-- (over the icon, a swirl darkening its elapsed part; over that, its words)
	a.dim = CreateFrame("Cooldown", nil, a.face, "CooldownFrameTemplate")
	a.dim:SetAllPoints(icon)
	a.dim:EnableMouse(false)
	pcall(a.dim.SetDrawEdge, a.dim, false)
	pcall(a.dim.SetDrawBling, a.dim, false)
	pcall(a.dim.SetHideCountdownNumbers, a.dim, true)
	pcall(a.dim.SetReverse, a.dim, true)
	pcall(a.dim.SetSwipeColor, a.dim, 0, 0, 0, DIM)
	pcall(a.dim.SetDrawSwipe, a.dim, false)
	a.top = CreateFrame("Frame", nil, button)
	a.top:SetAllPoints(button)
	a.top:EnableMouse(false)
	a.top:SetFrameLevel(a.face:GetFrameLevel() + 2)
	if a.count then pcall(a.count.SetParent, a.count, a.top) end
	if a.duration then pcall(a.duration.SetParent, a.duration, a.top) end
	-- the icon: trimmed, its own masks off (Serene's round one on, if chosen)
	pcall(icon.SetTexCoord, icon, TRIM, 1 - TRIM, TRIM, 1 - TRIM)
	if icon.GetNumMaskTextures then
		-- (from the last: each removal moves the ones after it down)
		for index = (Clean(Safe(icon.GetNumMaskTextures, icon)) or 0), 1, -1 do
			local mask = Safe(icon.GetMaskTexture, icon, index)
			if mask then pcall(icon.RemoveMaskTexture, icon, mask) end
		end
		a.mask = a.face:CreateMaskTexture()
		if not pcall(a.mask.SetTexture, a.mask, MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
			a.mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		end
		a.mask:SetAllPoints(icon)
	end
	-- the dark edge, then the gold line (a debuff's, laid over it, hides it)
	a.edge = button:CreateTexture(nil, "BACKGROUND")
	a.rim = button:CreateTexture(nil, "BACKGROUND")
	-- the game's borders
	for _, border in ipairs(a.borders) do
		count.borders = count.borders + 1
		if border.kind == "enchant" then Tint(border.texture, ENCHANT) end
		HookBorder(a, border)
	end
	-- the words
	if a.count then Font(a.count, 0, SOFT) end
	if a.duration then
		-- (its colour on the game's next call: it counts down often)
		local text = a.duration
		local font, size, flags = Safe(text.GetFont, text)
		font, size, flags = Clean(font), Clean(size), Clean(flags)
		if font and type(size) == "number" then
			a.font, a.size, a.flags = font, math.max(DURATION_LEAST, size - DURATION_SHRINK), flags or ""
		end
		a.points = Points(text)
		local textLayer, textSublevel = Safe(text.GetDrawLayer, text)
		a.layer, a.sublevel = Clean(textLayer), Clean(textSublevel)
		HookDuration(text)
		Plate(a)
		HookPlace(a)
	end
	-- the game's swirl over a target's aura: made the ring
	if a.cooldown then
		a.timed = Clean(Safe(a.cooldown.IsShown, a.cooldown)) and true or false
		HookRing(a)
	end
	Style(a)
end

-- Finding the buttons -------------------------------------------------------------------------------------------------

local function Walk(frame, kind, depth)
	if type(frame) ~= "table" or not frame.GetChildren or depth > 2 then return end
	for _, child in ipairs({ Safe(frame.GetChildren, frame) }) do
		if rawget(child, "sereneOwn") then
			-- (Serene's own icons: UnitAuras.lua's)
		elseif IsAuraButton(child) then
			pcall(Dress, child, kind)
		elseif not dressed[child] then
			Walk(child, kind, depth + 1)
		end
	end
end

local function Globals(list, kind)
	for _, entry in ipairs(list) do
		for index = 1, entry[2] do
			local button = _G[entry[1] .. index]
			if button then pcall(Dress, button, kind) end
		end
	end
end

local function ScanPlayer()
	for _, name in ipairs(PLAYER_HOLDERS) do
		local holder = _G[name]
		if type(holder) == "table" then
			local list = rawget(holder, "auraFrames")
			if type(list) == "table" then
				for _, button in pairs(list) do pcall(Dress, button, "player") end
			end
			Walk(holder, "player", 0)
		end
	end
	Globals(PLAYER_GLOBALS, "player")
end

-- The newer game's unit auras may hang outside the unit frame, only placed over it: found by where they are. Small
-- square frames over or beside a unit frame (in screen units), with a cooldown swirl (an aura's; no other small
-- thing there has one). Looked for at most every two seconds: it goes through every frame there is.
local function Rect(frame)
	local scale = Clean(Safe(frame.GetEffectiveScale, frame))
	local left, right = Clean(Safe(frame.GetLeft, frame)), Clean(Safe(frame.GetRight, frame))
	local top, bottom = Clean(Safe(frame.GetTop, frame)), Clean(Safe(frame.GetBottom, frame))
	if not (type(scale) == "number" and type(left) == "number" and type(right) == "number" and type(top) == "number"
		and type(bottom) == "number") then return nil end
	return left * scale, right * scale, top * scale, bottom * scale
end

local function Neighbours(around, pad)
	local al, ar, at, ab = Rect(around)
	if not al then return {} end
	local found = {}
	local f = EnumerateFrames and EnumerateFrames()
	while f do
		if not dressed[f] and Clean(Safe(f.IsVisible, f)) and rawget(f, "action") == nil then
			local l, r, t, b = Rect(f)
			if l then
				local w, h = r - l, t - b
				if w >= 8 and h >= 8 and w <= 60 and h <= 60 and math.abs(w - h) <= math.max(w, h) * 0.25
					and l >= al - pad and r <= ar + pad and b >= ab - pad * 2 and t <= at + pad * 2 then
					found[#found + 1] = f
				end
			end
		end
		f = EnumerateFrames(f)
	end
	return found
end

-- Nameplates' auras (the newer game shows your debuffs on an enemy there, not on its unit frame): each a frame with
-- an Icon, a Cooldown and a CountFrame, in the plate's AurasFrame lists. Dressed like the others; the square border
-- art the game lays over them (a texture of no name) put away.
local plateHidden
local function PlateExtras(button)
	plateHidden = plateHidden or CreateFrame("Frame")
	plateHidden:Hide()
	local named = {}
	for key, value in pairs(button) do
		if type(key) == "string" and IsRegion(value) then named[value] = true end
	end
	for _, region in ipairs({ Safe(button.GetRegions, button) }) do
		if IsTexture(region) and not named[region] and Safe(region.IsObjectType, region, "MaskTexture") ~= true then
			pcall(region.SetParent, region, plateHidden)
		end
	end
end

local function ScanPlates()
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and Safe(C_NamePlate.GetNamePlates)
	if type(plates) ~= "table" then return end
	for _, plate in ipairs(plates) do
		local unitFrame = type(plate) == "table" and rawget(plate, "UnitFrame")
		local auras = type(unitFrame) == "table" and rawget(unitFrame, "AurasFrame")
		if type(auras) == "table" and auras.GetChildren then
			for _, list in ipairs({ Safe(auras.GetChildren, auras) }) do
				for _, button in ipairs({ Safe(list.GetChildren, list) }) do
					if not dressed[button] and IsTexture(rawget(button, "Icon")) and CooldownOf(button) then
						pcall(PlateExtras, button)
						pcall(Dress, button, "plate", true)
					end
				end
			end
		end
	end
end

-- The newer game's aura icons (the target's and focus's, as on the nameplates): one build, wherever they hang: an Icon,
-- a Cooldown, a CountFrame and a "useAuraDisplayTime" of their own. Found once by going through every frame (costly:
-- at most every few seconds, and only until some are known); after that, only their parents are looked in, for new
-- ones from the same pool.
local function IsNewAura(f)
	return type(f) == "table" and rawget(f, "useAuraDisplayTime") ~= nil and IsTexture(rawget(f, "Icon"))
		and rawget(f, "Cooldown") ~= nil
end

local auraParents = {} -- frame -> true: holds such auras

-- An aura's look, whatever its build: a square picture with a swirl or a count, no portrait, not a bar.
local function LooksLikeAura(f)
	if type(f) ~= "table" or dressed[f] or HasPortrait(f) or Safe(f.IsObjectType, f, "StatusBar") == true then
		return false
	end
	return (IconOf(f) or LooseIcon(f)) ~= nil and (CooldownOf(f) or CountOf(f) or rawget(f, "CountFrame")) ~= nil
end
local nextSweep, sweeps = 0, 0
local function DressNewAura(f)
	if dressed[f] then return end
	pcall(PlateExtras, f)
	pcall(Dress, f, "unit", true)
	local parent = Safe(f.GetParent, f)
	if parent then auraParents[parent] = true end
end

local function ScanNewAuras()
	for parent in pairs(auraParents) do
		for _, child in ipairs({ Safe(parent.GetChildren, parent) }) do
			if IsNewAura(child) or LooksLikeAura(child) then DressNewAura(child) end
		end
	end
	-- (every frame gone through: when none are known yet, or now and then for other pools)
	local now = GetTime()
	if now < nextSweep then return end
	nextSweep = now + (next(auraParents) and 30 or 3)
	sweeps = sweeps + 1
	local f = EnumerateFrames and EnumerateFrames()
	while f do
		if IsNewAura(f) then DressNewAura(f) end
		f = EnumerateFrames(f)
	end
end

local nextNeighbours = 0
local function DressNeighbours()
	if GetTime() < nextNeighbours then return end
	nextNeighbours = GetTime() + 2
	for _, name in ipairs(UNIT_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and Clean(Safe(frame.IsVisible, frame)) then
			for _, f in ipairs(Neighbours(frame, 40)) do
				if CooldownOf(f) and Safe(f.IsObjectType, f, "StatusBar") ~= true and not HasPortrait(f) then
					pcall(Dress, f, "unit", true)
				end
			end
		end
	end
end
ns.AuraNeighbours = Neighbours

local function ScanUnits()
	for _, name in ipairs(UNIT_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" then
			local pools = rawget(frame, "auraPools")
			if type(pools) == "table" and pools.EnumerateActive then
				local ok, iterate, state, start = pcall(pools.EnumerateActive, pools)
				if ok and type(iterate) == "function" then
					for button in iterate, state, start do pcall(Dress, button, "unit") end
				end
			end
			-- (the auras: the frame's own children, or deeper in the newer game's containers)
			Walk(frame, "unit", -2)
			-- (the newer game's: inside a frame keyed "Auras", parts found by their shape)
			for _, holder in ipairs(ns.AuraContainers(frame)) do
				local function Loose(f, depth)
					for _, child in ipairs({ Safe(f.GetChildren, f) }) do
						if not dressed[child] then
							if IsLooseAura(child) then
								pcall(Dress, child, "unit", true)
							elseif depth < 2 then
								Loose(child, depth + 1)
							end
						end
					end
				end
				Loose(holder, 0)
			end
			-- (and wherever they hang under it: by their secret pictures)
			local function Secret(f, depth)
				for _, child in ipairs({ Safe(f.GetChildren, f) }) do
					if not dressed[child] and not rawget(child, "sereneOwn") and not IsCooldown(child)
						and Safe(child.IsObjectType, child, "StatusBar") ~= true then
						local icon = not HasPortrait(child) and SecretIcon(child)
						if icon then
							pcall(Dress, child, "unit", true, icon)
						elseif depth < 6 then
							Secret(child, depth + 1)
						end
					end
				end
			end
			Secret(frame, 0)
		end
	end
	Globals(UNIT_GLOBALS, "unit")
end

local function Scan()
	pending = false
	if not active then return end
	if onPlayer then pcall(ScanPlayer) end
	if onUnits then pcall(ScanUnits) end
	if onPlates then pcall(ScanPlates) end
	for _, a in pairs(dressed) do pcall(Fit, a) end
end

-- (once, on the next frame: after the game has filled its buttons for the same event)
local function Request()
	if pending or not active then return end
	pending = true
	C_Timer.After(0, Scan)
end

local function HookUpdates(frame)
	if type(frame) ~= "table" then return end
	for _, method in ipairs(UPDATES) do
		if type(frame[method]) == "function" then pcall(hooksecurefunc, frame, method, Request) end
	end
end

-- The arrow folding your buffs away: only under the mouse ---------------------------------------------------------

local function QuietArrow()
	local buffs = _G.BuffFrame
	local arrow = type(buffs) == "table" and rawget(buffs, "CollapseAndExpandButton")
	if not IsRegion(arrow) then return end
	local shown = -1
	-- (nothing says when the mouse comes near: looked at ten times a second)
	local watch = CreateFrame("Frame")
	local wait = 0
	watch:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		local over = ns.Over(buffs, 6, 6, 6, 6) or ns.Over(arrow, 4, 4, 4, 4)
		local alpha = (over or Setting("auraArrow", true) == false) and 1 or 0
		if alpha ~= shown then
			shown = alpha
			pcall(arrow.SetAlpha, arrow, alpha)
		end
	end)
end

local function Init()
	if not ns.On("auras") then return end
	active = true
	onUnits = ns.On("auraUnits")
	-- (your own buffs in Serene's frame instead, AuraFrame.lua: the game's are put away there)
	onPlayer = not ns.SereneAuraFrame()
	if onPlayer then
		for _, name in ipairs(PLAYER_HOLDERS) do HookUpdates(_G[name]) end
	end
	if onUnits then
		for _, name in ipairs(UNIT_FRAMES) do HookUpdates(_G[name]) end
	end
	-- (the older game's functions, if it has them)
	for _, name in ipairs({ "BuffFrame_Update", "AuraButton_Update", "TemporaryEnchantFrame_Update",
		"TargetFrame_UpdateAuras" }) do
		if type(_G[name]) == "function" then pcall(hooksecurefunc, name, Request) end
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
		"UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_INVENTORY_CHANGED", "player") -- (weapon enchants)
	events:SetScript("OnEvent", Request)
	-- (a unit event takes two units at most: the focus on its own)
	local focus = CreateFrame("Frame")
	pcall(focus.RegisterUnitEvent, focus, "UNIT_AURA", "focus")
	focus:SetScript("OnEvent", Request)
	if onPlayer then pcall(QuietArrow) end
	-- (nameplates: when one comes, and twice a second while any is up, for new auras on them)
	onPlates = ns.On("auraPlates")
	if onPlates then
		pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_ADDED")
		C_Timer.NewTicker(0.5, function()
			local plates = C_NamePlate and C_NamePlate.GetNamePlates and Safe(C_NamePlate.GetNamePlates)
			if type(plates) == "table" and #plates > 0 then pcall(ScanPlates) end
		end)
	end
	Scan()
end

local function Refresh()
	if not active then return end
	local look = Look()
	for _, a in pairs(dressed) do pcall(Style, a, look) end
	Request()
end

-- Shared with Serene's own buff frame (AuraFrame.lua): the look chosen, the colours.
function ns.SereneAuraFrame()
	return ns.On("auras") and Setting("auraFrame", "serene") == "serene"
end
ns.AuraStyle = { Look = Look, KINDS = KINDS, DEBUFF = DEBUFF, ENCHANT = ENCHANT, Quieter = Quieter }

-- The frames keyed "Auras" (or holding auras by another such name) under a unit frame.
local CONTAINER_KEYS = { "Auras", "AuraContainer", "AuraFrame", "BuffFrame", "DebuffFrame", "Buffs", "Debuffs" }
function ns.AuraContainers(frame)
	local found, seen = {}, {}
	local function Visit(f, depth)
		if depth > 5 or type(f) ~= "table" then return end
		for _, key in ipairs(CONTAINER_KEYS) do
			local holder = rawget(f, key)
			if IsRegion(holder) and holder.GetChildren and not seen[holder] then
				seen[holder] = true
				found[#found + 1] = holder
			end
		end
		for _, child in ipairs({ Safe(f.GetChildren, f) }) do Visit(child, depth + 1) end
	end
	Visit(frame, 0)
	return found
end

-- What a frame is made of, in one line: its keys, then its regions (unnamed ones too) with their sizes.
local function Describe(f)
	local keyOf = {}
	local keys = {}
	for key, value in pairs(f) do
		if type(key) == "string" then
			if IsRegion(value) then
				keyOf[value] = key
				keys[#keys + 1] = key .. ":" .. (Clean(Safe(value.GetObjectType, value)) or "?")
			elseif type(value) ~= "function" and type(value) ~= "table" then
				keys[#keys + 1] = key .. "=" .. tostring(Clean(value))
			end
		end
	end
	table.sort(keys)
	local regions = {}
	for _, region in ipairs({ Safe(f.GetRegions, f) }) do
		local width, height = Clean(Safe(region.GetWidth, region)), Clean(Safe(region.GetHeight, region))
		local layer = Clean(Safe(region.GetDrawLayer, region))
		regions[#regions + 1] = ("%s%s %s %sx%s%s"):format(Clean(Safe(region.GetObjectType, region)) or "?",
			keyOf[region] and ("(" .. keyOf[region] .. ")") or "", layer or "", type(width) == "number" and
			math.floor(width + 0.5) or "?", type(height) == "number" and math.floor(height + 0.5) or "?",
			Clean(Safe(region.IsShown, region)) and "" or " hidden")
	end
	local children = {}
	for _, child in ipairs({ Safe(f.GetChildren, f) }) do
		children[#children + 1] = Clean(Safe(child.GetObjectType, child)) or "?"
	end
	return ("%s %s; regions: %s; children: %s"):format(Clean(Safe(f.GetObjectType, f)) or "?", table.concat(keys, " "),
		#regions > 0 and table.concat(regions, ", ") or "none", #children > 0 and table.concat(children, ", ") or "none")
end

-- What the target's frame holds for its auras, as lines: each aura holder and everything in it, three levels down.
-- Kept in SereneDB.probeTargetAuras too (read from the saved file: the game writes it on /reload or logout).
local function Snapshot()
	local frame = _G.TargetFrame
	local out = {}
	if type(frame) ~= "table" then return { "no target frame" } end
	out[#out + 1] = ("target: %s, %s"):format(tostring(Clean(Safe(UnitName, "target"))),
		tostring(Clean(Safe(GetTime))))
	-- (where the target's auras really are: any visible texture showing one of their icons, wherever its frame is)
	local icons, list = {}, {}
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		for index = 1, 8 do
			local data = get and Safe(get, "target", index, filter)
			if data == nil then break end
			local icon = Clean(data.icon)
			if icon ~= nil then icons[icon] = true list[#list + 1] = tostring(icon) end
		end
	end
	out[#out + 1] = "target's icons: " .. table.concat(list, ", ")
	local function Ours(f)
		local depth = 0
		while f and depth < 30 do
			local name = Clean(Safe(f.GetName, f))
			if name == "SereneAuras" or name == "SereneDebuffs" or name == "SereneAuraCard" or name == "BuffFrame"
				or name == "DebuffFrame" then return true end
			f = Safe(f.GetParent, f)
			depth = depth + 1
		end
	end
	local function Path(f)
		local parts, depth = {}, 0
		while f and depth < 12 do
			local name = Clean(Safe(f.GetName, f))
			local parent = Safe(f.GetParent, f)
			if not name and parent then
				for key, value in pairs(parent) do
					if value == f and type(key) == "string" then name = "." .. key break end
				end
			end
			if type(name) ~= "string" or ns.IsSecret(name) then name = nil end
			table.insert(parts, 1, name or "?")
			local ok, first = pcall(string.sub, name or "", 1, 1)
			if name and ok and first ~= "." then break end
			f = parent
			depth = depth + 1
		end
		return table.concat(parts, "/")
	end
	local wanted = {}
	for icon in pairs(icons) do wanted[tostring(icon)] = true end
	local matches, frames, secret = 0, 0, 0
	local f = EnumerateFrames and EnumerateFrames()
	while f do
		frames = frames + 1
		if matches < 8 and not Ours(f) and rawget(f, "action") == nil then
			for _, region in ipairs({ Safe(f.GetRegions, f) }) do
				if IsTexture(region) then
					local raw = Safe(region.GetTexture, region)
					if ns.IsSecret(raw) then
						secret = secret + 1
						if secret <= 6 then
							local parent = Safe(f.GetParent, f)
							out[#out + 1] = ("secret picture at %s (%s, %s)"):format(Path(f),
								Clean(Safe(region.IsVisible, region)) and "visible" or "not visible",
								dressed[f] and "dressed" or "not dressed")
							out[#out + 1] = "  it: " .. Describe(f)
							if parent then out[#out + 1] = "  its parent: " .. Describe(parent) end
						end
					end
					local texture = Clean(raw)
					if texture ~= nil and wanted[tostring(texture)] then
						matches = matches + 1
						local parent = Safe(f.GetParent, f)
						out[#out + 1] = ("found %s at %s (%s)"):format(tostring(texture), Path(f),
							Clean(Safe(region.IsVisible, region)) and "visible" or "not visible")
						out[#out + 1] = "  it: " .. Describe(f)
						if parent then out[#out + 1] = "  its parent: " .. Describe(parent) end
						break
					end
				end
			end
		end
		f = EnumerateFrames(f)
	end
	out[#out + 1] = ("%d frame(s) showing the target's icons, of %d frames; %d textures secret"):format(matches,
		frames, secret)
	local near = Neighbours(frame, 40)
	out[#out + 1] = ("%d small square frame(s) over or beside the target's frame"):format(#near)
	for index, f in ipairs(near) do
		if index > 10 then break end
		local okPath, path = pcall(Path, f)
		local okIt, it = pcall(Describe, f)
		out[#out + 1] = ("near: %s%s%s"):format(okPath and path or "?", dressed[f] and " (dressed)" or "",
			CooldownOf(f) and " (swirl)" or "")
		out[#out + 1] = "  it: " .. (okIt and it or "?")
	end
	local holders = ns.AuraContainers(frame)
	out[#out + 1] = ("%d aura holder(s)"):format(#holders)
	for h, holder in ipairs(holders) do
		out[#out + 1] = ("holder %d (%s): %s"):format(h, Clean(Safe(holder.GetName, holder)) or "?", Describe(holder))
		local shown = 0
		local function Inside(f, path, depth)
			for index, child in ipairs({ Safe(f.GetChildren, f) }) do
				if shown >= 30 then return end
				shown = shown + 1
				out[#out + 1] = ("%s/#%d%s%s%s: %s"):format(path, index, dressed[child] and " (dressed)" or "",
					IsLooseAura(child) and " (aura)" or "", Clean(Safe(child.IsShown, child)) and "" or " (hidden)",
					Describe(child))
				if depth < 3 then Inside(child, path .. "/#" .. index, depth + 1) end
			end
		end
		Inside(holder, "  " .. h, 0)
	end
	return out
end

local snapped, waiting = 0, false
local function SnapshotOnce()
	if snapped >= 3 or waiting or not ns.db then return end
	-- (only with a target wearing something, and out of a fight, where it can be read)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get or not Clean(Safe(UnitExists, "target")) or Clean(Safe(UnitIsUnit, "target", "player")) then return end
	if Safe(get, "target", 1, "HELPFUL") == nil and Safe(get, "target", 1, "HARMFUL") == nil then return end
	-- (a moment later: the game draws a new target's auras after Serene first looks)
	waiting = true
	C_Timer.After(1.5, function()
		waiting = false
		if not Clean(Safe(UnitExists, "target")) or Clean(Safe(UnitIsUnit, "target", "player")) then return end
		snapped = snapped + 1
		local ok, lines = pcall(Snapshot)
		lines = ok and lines or { "failed: " .. tostring(lines) }
		ns.db.probeTargetAuras = lines
	end)
end

-- /serene debug targetauras (with a target that has auras): the frames under the target's frame holding an icon,
-- with their keys, and whether they were taken for aura buttons; then what its "Auras" holds, piece by piece.
function ns.AuraTargetDump()
	local frame = _G.TargetFrame
	if type(frame) ~= "table" then return ns.Print("no target frame") end
	local lines = 0
	local function Visit(f, path, depth)
		if depth > 6 or lines >= 25 then return end
		local keys, icon = {}, false
		for key, value in pairs(f) do
			if type(key) == "string" and IsRegion(value) then
				keys[#keys + 1] = key .. ":" .. (Clean(Safe(value.GetObjectType, value)) or "?")
				if key:find("Icon", 1, true) and IsTexture(value) then icon = true end
			end
		end
		local hasCooldown = CooldownOf(f) ~= nil
		if icon or hasCooldown then
			lines = lines + 1
			table.sort(keys)
			ns.Print(("%s%s%s: %s"):format(path, dressed[f] and " (dressed)" or "", IsAuraButton(f) and " (aura)" or "",
				table.concat(keys, " ")))
		end
		for index, child in ipairs({ Safe(f.GetChildren, f) }) do
			local name = Clean(Safe(child.GetName, child))
			Visit(child, path .. "/" .. (name or ("#" .. index)), depth + 1)
		end
	end
	Visit(frame, "TargetFrame", 0)
	if lines == 0 then ns.Print("nothing with an icon or a swirl under the target's frame") end
	local lines = Snapshot()
	ns.db.probeTargetAuras = lines
	for index = 1, math.min(#lines, 12) do ns.Print(lines[index]) end
	ns.Print("(all of it saved for Serene's author: /reload writes it)")
end

ns.SnapshotTargetAuras = SnapshotOnce

-- /serene debug auraholder: the target frame's aura holder (where the game draws the target's auras itself): its
-- type, the methods it has beyond a plain frame's, and what the game offers around it (AuraContainerUtil, the aura
-- enums). Kept in SereneDB.probeHolder.
local function Methods(object)
	local names = {}
	local meta = getmetatable(object)
	local index = type(meta) == "table" and meta.__index
	if type(index) == "table" then
		for key, value in pairs(index) do
			if type(key) == "string" and type(value) == "function" then names[key] = true end
		end
	end
	return names
end

function ns.AuraHolderDump()
	local out = {}
	local plain = Methods(CreateFrame("Frame"))
	local holders = ns.AuraContainers(_G.TargetFrame)
	out[#out + 1] = ("%d holder(s) on the target frame"):format(#holders)
	for h, holder in ipairs(holders) do
		out[#out + 1] = ("holder %d: type %s, shown %s, %d children, %d regions, size %s x %s"):format(h,
			tostring(Clean(Safe(holder.GetObjectType, holder))), tostring(Clean(Safe(holder.IsShown, holder))),
			select("#", Safe(holder.GetChildren, holder)), select("#", Safe(holder.GetRegions, holder)),
			tostring(Clean(Safe(holder.GetWidth, holder))), tostring(Clean(Safe(holder.GetHeight, holder))))
		local extra = {}
		for name in pairs(Methods(holder)) do
			if not plain[name] then extra[#extra + 1] = name end
		end
		table.sort(extra)
		out[#out + 1] = "  its own methods: " .. (#extra > 0 and table.concat(extra, " ") or "none")
		local keys = {}
		for key, value in pairs(holder) do
			if type(key) == "string" then keys[#keys + 1] = key .. ":" .. type(value) end
		end
		table.sort(keys)
		out[#out + 1] = "  its keys: " .. table.concat(keys, " ")
	end
	local util = _G.AuraContainerUtil
	if type(util) == "table" then
		local names = {}
		for key in pairs(util) do names[#names + 1] = tostring(key) end
		table.sort(names)
		out[#out + 1] = "AuraContainerUtil: " .. table.concat(names, " ")
	else
		out[#out + 1] = "AuraContainerUtil: " .. type(util)
	end
	if type(Enum) == "table" then
		for name, values in pairs(Enum) do
			if type(name) == "string" and (name:find("Aura") or name:find("Dispel")) and type(values) == "table" then
				local parts = {}
				for key, value in pairs(values) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(value) end
				table.sort(parts)
				out[#out + 1] = ("Enum.%s: %s"):format(name, table.concat(parts, " "))
			end
		end
	end
	if ns.db then ns.db.probeHolder = out end
	for index = 1, math.min(#out, 4) do ns.Print(out[index]) end
	ns.Print("(all of it saved for Serene's author: /reload writes it)")
end

-- /serene debug plates: each nameplate aura icon, whether Serene dressed it, which of the game's timing calls reached its
-- swirl (and how often), and whether Serene's darkening swirl took them (kept in SereneDB.probePlates too).
function ns.AuraPlatesDump()
	local out = { "timing calls on swirls here: " .. table.concat(TIMING, " ") }
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and Safe(C_NamePlate.GetNamePlates)
	local icons = 0
	for _, plate in ipairs(type(plates) == "table" and plates or {}) do
		local unitFrame = type(plate) == "table" and rawget(plate, "UnitFrame")
		local auras = type(unitFrame) == "table" and rawget(unitFrame, "AurasFrame")
		if type(auras) == "table" and auras.GetChildren then
			for _, list in ipairs({ Safe(auras.GetChildren, auras) }) do
				for _, button in ipairs({ Safe(list.GetChildren, list) }) do
					if Clean(Safe(button.IsShown, button)) then
						icons = icons + 1
						local a = dressed[button]
						local cooldown = (a and a.cooldown) or CooldownOf(button)
						local calls = {}
						for name, times in pairs(cooldown and seenCalls[cooldown] or {}) do
							calls[#calls + 1] = name .. " x" .. times
						end
						table.sort(calls)
						local kept = cooldown and lastTiming[cooldown]
						out[#out + 1] = ("icon %d: %s; swirl %s, shown %s; calls: %s; kept: %s; darkening %s"):format(icons,
							a and "dressed" or "not dressed", cooldown and "found" or "none",
							tostring(cooldown and Clean(Safe(cooldown.IsShown, cooldown))),
							#calls > 0 and table.concat(calls, ", ") or "none",
							kept and table.concat(kept.order, " ") or "nothing",
							a and a.dim and tostring(Clean(Safe(a.dim.GetDrawSwipe, a.dim))) or "-")
					end
				end
			end
		end
	end
	if icons == 0 then out[#out + 1] = "no aura icons on any nameplate now" end
	for _, line in ipairs(out) do ns.Print(line) end
	if ns.db then ns.db.probePlates = out end
end

-- /serene debug targeticons: the target frame's pictures keyed as icons that are showing now: which, its art, its size.
function ns.AuraTargetIcons()
	local frame = _G.TargetFrame
	if type(frame) ~= "table" then return ns.Print("no target frame") end
	local shown = 0
	local function Visit(f, depth)
		if depth > 6 then return end
		for key, value in pairs(f) do
			if type(key) == "string" and key:find("Icon", 1, true) and IsTexture(value)
				and Clean(Safe(value.IsVisible, value)) then
				shown = shown + 1
				local art = Clean(Safe(value.GetAtlas, value)) or Clean(Safe(value.GetTexture, value))
				local width, height = Clean(Safe(value.GetWidth, value)), Clean(Safe(value.GetHeight, value))
				ns.Print(("%s: %s, %sx%s"):format(key, tostring(art), tostring(width and math.floor(width + 0.5)),
					tostring(height and math.floor(height + 0.5))))
			end
		end
		for _, child in ipairs({ Safe(f.GetChildren, f) }) do Visit(child, depth + 1) end
	end
	Visit(frame, 0)
	if shown == 0 then ns.Print("no icon picture showing on the target frame") end
end

-- /serene debug mouse: the frames under the mouse pointer, what they are made of, and their parents up the line (kept
-- in SereneDB.probeMouse too). One that looks like an aura (a square picture with a swirl or a count) is dressed at
-- once, and its parent remembered: others from there are dressed from then on.
function ns.AuraMouseDump()
	local out = {}
	local foci = GetMouseFoci and { Safe(GetMouseFoci) } or {}
	if type(foci[1]) == "table" and not foci[1].GetObjectType then foci = foci[1] end -- (a list, in the newer game)
	if #foci == 0 and GetMouseFocus then foci = { Safe(GetMouseFocus) } end
	out[#out + 1] = ("%d frame(s) under the mouse"):format(#foci)
	for index, f in ipairs(foci) do
		if index > 4 then break end
		local chain, at, depth = {}, f, 0
		while at and depth < 8 do
			local okName, name = pcall(at.GetName, at)
			name = okName and Clean(name) or nil
			local okType, kind = pcall(at.GetObjectType, at)
			chain[#chain + 1] = ((type(name) == "string" and name) or "?") .. ":" .. (okType and tostring(Clean(kind)) or "forbidden")
			local okParent, parent = pcall(at.GetParent, at)
			at = okParent and parent or nil
			depth = depth + 1
		end
		out[#out + 1] = ("%d: %s"):format(index, table.concat(chain, " < "))
		local okIt, it = pcall(Describe, f)
		out[#out + 1] = "  it: " .. (okIt and it or ("can't be read: " .. tostring(it)))
		local okParent, parent = pcall(f.GetParent, f)
		if okParent and parent then
			local okP, p = pcall(Describe, parent)
			out[#out + 1] = "  its parent: " .. (okP and p or "can't be read")
		end
		-- (an aura's look: dressed now, and its parent remembered)
		if LooksLikeAura(f) then
			pcall(PlateExtras, f)
			pcall(Dress, f, "unit", true)
			if dressed[f] then
				out[#out + 1] = "  dressed it"
				if okParent and parent then auraParents[parent] = true end
			end
		end
	end
	if ns.db then ns.db.probeMouse = out end
	for index = 1, math.min(#out, 8) do ns.Print(out[index]) end
	ns.Print("(all of it saved for Serene's author: /reload writes it)")
end

-- /serene debug: what was found.
function ns.AurasDebug()
	if not active then return ns.Print("auras: off") end
	ns.Print(("auras: %d of yours, %d on the target and focus%s, %d on nameplates%s, %d borders made hairlines")
		:format(count.player, count.unit, onUnits and "" or " (off)", count.plate, onPlates and "" or " (off)",
		count.borders))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
