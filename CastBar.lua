local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Your cast bar made calm: the game's own bar (and your pet's, a vehicle's), nothing new beside it. Edit Mode still
-- places and sizes it ("Lock to Player Frame" too), the game still fills it, names the spell, tells the time, fades
-- it out when the cast ends. Only looks change, as on the target's and focus's (below, under their cards):
--   - its art put away: the frame, the shield, the flashes and glows, the dark box under the spell's name;
--   - the fill flat, on a slim slab of glass in a hairline of the game's gold (/serene border none: glass only),
--     coloured by what it is: a cast in soft gold, a channel in green, one that can't be stopped in grey, one that
--     failed or was interrupted in soft red;
--   - the spell's icon square at its start, inside the same glass;
--   - the spell's name in it, quiet, at the left; the time muted at the right, Serene's own words (time left, or
--     left and the whole), whatever Edit Mode's "Show Cast Time" says;
--   - a soft spark at the fill's moving end while the cast goes on;
--   - your lag at the cast's end, a muted strip the fill dims through: once the fill is in it, the next spell can
--     already be pressed (measured from the spell sent to the cast started, else the game's latency);
--   - a channel's ticks, thin dark marks where they land (Drain Life, Blizzard, Arcane Missiles...);
--   - a soft flash as it ends: light when the spell lands, red when it is interrupted or fails;
--   - Serene's rhythm: in softly, away slowly (as the rest of Serene fades), and no shake on an interrupt.
-- Settings (Serene's page, "Cast bar"; each at once, no reload): its height, its width (or Edit Mode's), the icon,
-- the spell's name in the bar, under it (the glass grows to hold it) or none, the words' size, the time, the lag,
-- the ticks, the flash, the fade. Where it sits and its scale stay Edit Mode's.
-- Nothing protected is touched: all of it is safe in a fight.
--   /serene castbar on|off    (a reload to switch)
--   /serene castheight 4-24, /serene castwidth 0|80-400 (0: Edit Mode's)

local FLAT = "Interface\\Buttons\\WHITE8X8"
local INK = ns.INK
local SOFT = ns.SOFT_RGB
local MUTED = ns.MUTED_RGB
local GLASS_ALPHA = 0.6
local PAD = 2          -- the glass beyond the bar
local ICON_GAP = 1     -- between the icon and the bar
local TEXT_INSET = 4   -- the words inside the bar's ends
local TIME_ROOM = 30   -- room kept at the right for the time
local SPARK_WIDTH = 2
local SPARK_RISE = 2   -- the spark this much taller than the bar, at each edge
local UNDER_GAP = 3    -- between the bar and the words under it
local FITS = 9         -- the least height the words fit in (lower: under the bar)
local UNDER_FONT = 10  -- the words under the bar, unless a size is chosen
-- (settings below these: the game's own measure, or the size worked out)
ns.CAST_WIDTH_GAME = 70
ns.CAST_FONT_AUTO = 7
-- (the game's names for its cast bars: retail-style first, the older ones after)
local NAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame", "OverlayPlayerCastingBarFrame" }
-- What a cast is, by its colour: a cast, a channel, one that can't be interrupted, one that failed.
local CASTING = { 0.86, 0.7, 0.36 }
local CHANNELING = { 0.42, 0.68, 0.44 }
local LOCKED = { 0.58, 0.58, 0.6 }
local FAILED = { 0.78, 0.33, 0.3 } -- (Units.lua's hostile red)
local BAR_TYPES = { standard = CASTING, channel = CHANNELING, uninterruptable = LOCKED, interrupted = FAILED,
	empowered = { 1, 0.82, 0.35 } }
local LANDED = { 1, 0.95, 0.82 } -- the flash of a spell that lands (the interrupted one's: FAILED)
local FLASH_PEAK, FLASH_TIME = 0.45, 0.45
local FAILED_PEAK, FAILED_TIME = 0.5, 0.7
local LAG_ALPHA = 0.5
local LAG_MOST = 1       -- (a spell started more than this after it was sent: something else, not lag)
local TICK_ALPHA = 0.75
local IN_TIME = 0.12     -- Serene's way in, from nothing (quicker than Fade's: a cast is news)
local OUT_TIME = 0.9     -- and its way out (Fade's)
-- A channel's ticks, every so many seconds, by its first rank (whose name, in the game's language, names every rank).
local TICKS = {
	[5143] = 1,  -- Arcane Missiles
	[10] = 1,    -- Blizzard
	[12051] = 2, -- Evocation
	[689] = 1,   -- Drain Life
	[5138] = 1,  -- Drain Mana
	[1120] = 3,  -- Drain Soul
	[755] = 1,   -- Health Funnel
	[1949] = 1,  -- Hellfire
	[5740] = 2,  -- Rain of Fire
	[15407] = 1, -- Mind Flay
	[16914] = 1, -- Hurricane
	[740] = 2,   -- Tranquility
	[1510] = 1,  -- Volley
	[746] = 1,   -- First Aid (a bandage)
}

local dressed = {}     -- bar -> its parts
local holding = false  -- (Serene's own calls, not heard by its hooks)
local hidden           -- (where the art goes: a frame never shown, so the game's animations on it show nothing)
local active = false
local sentAt, lag      -- (when your last spell was sent; the lag your last cast measured)
local tickNames        -- a channel's name -> seconds between its ticks (read once the game names the spells)

local IsRegion, IsTexture, IsFontString = ns.IsRegion, ns.IsTexture, ns.IsFontString

local function Place(region, ...)
	holding = true
	pcall(region.ClearAllPoints, region)
	for _, point in ipairs({ ... }) do pcall(region.SetPoint, region, unpack(point)) end
	holding = false
end

local function Size(region, width, height)
	holding = true
	if width then pcall(region.SetWidth, region, width) end
	if height then pcall(region.SetHeight, region, height) end
	holding = false
end

local function FontSize(text)
	local _, size = Safe(text.GetFont, text)
	size = Clean(size)
	return type(size) == "number" and size or nil
end

local function Font(text, size, color)
	local font, _, flags = Safe(text.GetFont, text)
	font = Clean(font)
	holding = true
	if font and FontSize(text) ~= size then pcall(text.SetFont, text, font, size, Clean(flags) or "") end
	pcall(text.SetTextColor, text, color[1], color[2], color[3])
	pcall(text.SetShadowColor, text, 0, 0, 0, 0.8)
	pcall(text.SetShadowOffset, text, 1, -1)
	holding = false
end

-- (the game's art may mask the fill to its rounded shape: taken off)
local function Unmask(bar)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) ~= "table" or not fill.GetNumMaskTextures then return end
	local count = Clean(Safe(fill.GetNumMaskTextures, fill)) or 0
	for index = count, 1, -1 do -- (from the end: taking one off moves the ones after it down)
		local mask = Safe(fill.GetMaskTexture, fill, index)
		if mask then pcall(fill.RemoveMaskTexture, fill, mask) end
	end
end

-- The fill: flat, in the colour of what it shows ------------------------------------------------------------------

-- (the newer cast bars say what they show; the older ones only colour it, and the colour is read)
local function CastColor(c)
	local bar = c.bar
	local kind = Clean(rawget(bar, "barType")) -- (the newer cast bars say what they show)
	if type(kind) == "string" and BAR_TYPES[kind] then return BAR_TYPES[kind] end
	local raw = c.raw -- (the older ones only colour it: orange, green, grey, red)
	if raw then
		local r, g, b = raw[1], raw[2], raw[3]
		if r > 0.85 and g < 0.35 and b < 0.35 then return FAILED end
		if r < 0.9 and math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 then return LOCKED end
		if g > 0.85 and r < 0.35 then return CHANNELING end
	end
	if Clean(rawget(bar, "notInterruptible")) then return LOCKED end
	if Clean(rawget(bar, "channeling")) then return CHANNELING end
	return CASTING
end
local function Paint(c)
	if not active then return end
	local bar = c.bar
	local color = CastColor(c)
	holding = true
	pcall(bar.SetStatusBarTexture, bar, FLAT)
	pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3], 1)
	holding = false
	Unmask(bar)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if fill ~= c.fill and type(fill) == "table" then
		-- (a new fill texture: the spark follows it)
		c.fill = fill
		c.sparkOn = nil
	end
end

-- What the bar shows this frame: whether a cast goes on, a channel or not, where its fill is and its whole length.
-- (the game's own state on the bar, read with rawget: some of its frames have a metatable behind them)
local function Read(c)
	local bar = c.bar
	c.channel = Clean(rawget(bar, "channeling")) and true or false
	c.going = c.channel or Clean(rawget(bar, "casting")) or Clean(rawget(bar, "reverseChanneling")) or false
	local value = Clean(Safe(bar.GetValue, bar))
	local least, most = Safe(bar.GetMinMaxValues, bar)
	least, most = Clean(least), Clean(most)
	local known = type(value) == "number" and type(least) == "number" and type(most) == "number" and most > least
	c.value = known and value - least or nil
	c.most = known and most - least or nil
	c.reverse = Clean(Safe(bar.GetReverseFill, bar)) and true or false
end

-- The spark at the fill's moving end, while the cast goes on.
local function Spark(c)
	local spark, fill = c.spark, c.fill
	local inside = c.value and c.value > 0 and c.value < c.most
	if not (c.going and inside and fill) then
		spark:Hide()
		return
	end
	if c.sparkOn ~= fill or c.sparkReverse ~= c.reverse then
		c.sparkOn, c.sparkReverse = fill, c.reverse
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", fill, c.reverse and "LEFT" or "RIGHT", 0, 0)
	end
	spark:Show()
end

-- The time, in Serene's words: left ("1.4"), or left and the whole ("1.4 / 2.5"). (When the cast ends the last
-- words stay, as the bar fades.)
local function Time(c)
	if not (c.going or Clean(rawget(c.bar, "isInEditMode"))) then return end
	local mode = ns.db and ns.db.castTime or "left"
	local text = ""
	if mode ~= "none" and c.value then
		local left = math.max(0, c.channel and c.value or c.most - c.value)
		text = mode == "both" and ("%.1f / %.1f"):format(left, c.most) or ("%.1f"):format(left)
	end
	if text ~= c.timeText then
		c.timeText = text
		c.time:SetText(text)
	end
end

-- Your lag, as the last cast measured it, else the game's latency (in seconds).
local function Lag()
	if lag then return lag end
	local _, _, home, world = Safe(GetNetStats)
	local ms = Clean(world) or Clean(home)
	return type(ms) == "number" and ms > 0 and ms / 1000 or nil
end

-- Your lag at the cast's end: a cast ends at the fill's far end, a channel (emptying) at its start.
local function Zone(c)
	local zone = c.lag
	local seconds = c.going and c.mine and ns.On("castLatency") and Lag()
	if not (seconds and c.most and c.width) then
		zone:Hide()
		return
	end
	local width = math.max(1, math.min(c.width, c.width * seconds / c.most))
	local side = (c.channel == c.reverse) and "RIGHT" or "LEFT"
	if c.lagSide ~= side or c.lagWidth ~= width or c.lagHeight ~= c.height then
		c.lagSide, c.lagWidth, c.lagHeight = side, width, c.height
		zone:ClearAllPoints()
		zone:SetPoint("TOP" .. side, c.bar, "TOP" .. side, 0, 0)
		zone:SetSize(width, c.height)
	end
	zone:Show()
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return Clean(Safe(C_Spell.GetSpellName, id)) end
	return Clean((Safe(GetSpellInfo, id)))
end

-- Seconds between a channel's ticks, by its name (nil: a channel without ticks, or one Serene doesn't know).
local function TickEvery(name)
	if not name then return nil end
	if not (tickNames and next(tickNames)) then
		tickNames = {}
		for id, every in pairs(TICKS) do
			local spell = SpellName(id)
			if spell then tickNames[spell] = every end
		end
	end
	return tickNames[name]
end

-- A channel's ticks: a thin dark mark where each lands, the ones to come on the fill (the end itself isn't marked).
local function Ticks(c)
	local every
	if c.channel and c.mine and c.most and c.width and ns.On("castTicks") then
		-- (which channel: looked up once for each, by its spell and its length)
		local id = Clean(rawget(c.bar, "spellID"))
		local key = tostring(id) .. ":" .. c.most
		if c.tickKey ~= key then
			c.tickKey = key
			local name = Clean((Safe(UnitChannelInfo, c.unit or "player"))) or (id and SpellName(id))
			c.tickEvery = TickEvery(name)
		end
		every = c.tickEvery
	else
		c.tickKey = nil
	end
	local count = every and math.ceil(c.most / every - 0.001) - 1 or 0
	local placed = every and (c.tickAt ~= c.tickKey or c.tickWidth ~= c.width or c.tickHeight ~= c.height
		or c.tickReverse ~= c.reverse)
	if placed then c.tickAt, c.tickWidth, c.tickHeight, c.tickReverse = c.tickKey, c.width, c.height, c.reverse end
	for index = 1, math.max(count, #c.ticks) do
		local tick = c.ticks[index]
		if index <= count then
			if not tick then
				tick = c.bar:CreateTexture(nil, "OVERLAY", nil, 4)
				tick:SetColorTexture(INK[1], INK[2], INK[3], TICK_ALPHA)
				c.ticks[index] = tick
				placed = true
			end
			if placed then
				-- (the fill counts down: a tick lands where as much is left as its time from the end)
				local x = (c.most - index * every) / c.most * c.width
				tick:ClearAllPoints()
				tick:SetPoint("CENTER", c.bar, c.reverse and "RIGHT" or "LEFT", c.reverse and -x or x, 0)
				tick:SetSize(ns.Pixel(c.bar), c.height)
			end
			tick:Show()
		elseif tick then
			tick:Hide()
		end
	end
end

-- A soft flash over the bar as it ends, fading out.
local function StartFlash(c, color, peak, duration)
	if not (active and ns.On("castFlash")) then return end
	c.flash:SetColorTexture(color[1], color[2], color[3], 1)
	c.flash:SetAlpha(peak)
	c.flashAt, c.flashPeak, c.flashFor = GetTime(), peak, duration
end

local function Flash(c, now)
	if not c.flashAt then return end
	local t = (now - c.flashAt) / c.flashFor
	if t >= 1 then
		c.flashAt = nil
		c.flash:SetAlpha(0)
		return
	end
	c.flash:SetAlpha(c.flashPeak * (1 - t) * (1 - t))
end

-- Serene's way in: the bar's own alpha, from nothing to full.
local function FadeIn(c, now)
	if not c.inAt then return end
	local alpha = math.min(1, (now - c.inAt) / IN_TIME)
	if alpha >= 1 then c.inAt = nil end
	holding = true
	pcall(c.bar.SetAlpha, c.bar, alpha)
	holding = false
end

-- (the game's fades are its own animations on the bar: their fading parts timed anew, the game's times kept for when
-- the setting goes off)
local function Retime(c)
	local serene = active and ns.On("castFade")
	for _, part in ipairs(c.fades) do
		pcall(part.anim.SetDuration, part.anim, serene and OUT_TIME or part.duration)
	end
end

-- Every frame the bar is shown.
local function Tick(c)
	local now = GetTime()
	Read(c)
	Spark(c)
	Time(c)
	Zone(c)
	Ticks(c)
	Flash(c, now)
	FadeIn(c, now)
end

-- The settings, read safely.
local function Setting(key, low, high, fallback)
	local value = tonumber(ns.db and ns.db[key])
	if not value then return fallback end
	return math.max(low, math.min(high, math.floor(value + 0.5)))
end

-- Where everything goes, at the size chosen (the game sets another look and size when the bar is locked to your
-- portrait or set free: laid out again each time).
local function Layout(c)
	if not active then return end
	local bar, box = c.bar, c.box
	-- its size: the height chosen, the width chosen or the game's
	local height = Setting("castHeight", 4, 24, 11)
	local width = Setting("castWidth", 0, 400, 0)
	if width <= ns.CAST_WIDTH_GAME then width = c.gameWidth end
	Size(bar, width, height)
	c.width, c.height = width, height -- (Serene's own measures: the lag and the ticks are placed by them)
	local lined = ns.db and ns.db.unitBorder ~= "none"
	local e = lined and PAD + ns.Pixel(bar) or PAD -- (a pixel more for the hairline, drawn just inside the glass)
	-- the icon
	local icon = c.icon
	local withIcon = false
	if icon then
		withIcon = ns.On("castIcon") and Clean(Safe(icon.GetTexture, icon)) ~= nil
		holding = true
		pcall(withIcon and icon.Show or icon.Hide, icon)
		holding = false
	end
	if withIcon then
		Place(icon, { "TOPRIGHT", bar, "TOPLEFT", -ICON_GAP, 0 })
		Size(icon, height, height)
		pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
		pcall(icon.SetAlpha, icon, 1)
	end
	-- the words: in the bar where they fit, else under it
	local mode = ns.db and ns.db.castText or "in"
	local named = mode ~= "none" and c.text ~= nil
	local timed = (ns.db and ns.db.castTime or "left") ~= "none"
	local under = mode == "under" or height < FITS
	local font = Setting("castFont", 0, 16, 0)
	if font <= ns.CAST_FONT_AUTO then
		font = under and UNDER_FONT or math.max(8, math.min(12, height - 1))
	end
	local row = under and (named or timed) and font + 2 or 0
	-- (the game's time put away: Serene writes its own)
	for _, other in ipairs(c.others) do pcall(other.SetAlpha, other, 0) end
	local time = c.time
	if under then
		Place(time, { "TOPRIGHT", bar, "BOTTOMRIGHT", -1, -UNDER_GAP })
	else
		Place(time, { "RIGHT", bar, "RIGHT", -TEXT_INSET, 0 })
	end
	pcall(time.SetJustifyH, time, "RIGHT")
	pcall(time.SetWordWrap, time, false)
	time:SetShown(timed)
	Font(time, font, MUTED)
	if c.text then
		-- (left and the whole take more room than the time left alone)
		local wide = ns.db and ns.db.castTime == "both"
		local room = timed and -math.max(wide and TIME_ROOM * 2 or TIME_ROOM, font * (wide and 6 or 3))
			or (under and -1 or -TEXT_INSET)
		if under then
			Place(c.text, { "TOPLEFT", bar, "BOTTOMLEFT", 1, -UNDER_GAP }, { "TOPRIGHT", bar, "BOTTOMRIGHT", room, -UNDER_GAP })
		else
			Place(c.text, { "LEFT", bar, "LEFT", TEXT_INSET, 0 }, { "RIGHT", bar, "RIGHT", room, 0 })
		end
		pcall(c.text.SetJustifyH, c.text, "LEFT")
		pcall(c.text.SetJustifyV, c.text, under and "TOP" or "MIDDLE")
		pcall(c.text.SetWordWrap, c.text, false)
		pcall(c.text.SetAlpha, c.text, named and 1 or 0)
		Font(c.text, font, SOFT)
	end
	-- the glass around it all (down over the words under it)
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", withIcon and icon or bar, "TOPLEFT", -e, e)
	box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", e, -e - (row > 0 and row + UNDER_GAP - 1 or 0))
	box.lines:Fit()
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do box.lines[side]:SetShown(lined) end
	pcall(box.SetFrameLevel, box, math.max(0, (Clean(Safe(bar.GetFrameLevel, bar)) or 1) - 1))
	c.spark:SetSize(SPARK_WIDTH, height + SPARK_RISE * 2)
end

-- Dressing one of the game's cast bars ----------------------------------------------------------------------------

local function Dress(bar)
	if dressed[bar] or not IsRegion(bar) or not bar.SetStatusBarTexture or not bar.GetRegions then return end
	local name = Clean(Safe(bar.GetName, bar))
	local c = { bar = bar, others = {} }
	c.icon = rawget(bar, "Icon") or (name and _G[name .. "Icon"])
	c.text = rawget(bar, "Text") or (name and _G[name .. "Text"])
	if not IsTexture(c.icon) then c.icon = nil end
	if not IsFontString(c.text) then c.text = nil end
	hidden = hidden or CreateFrame("Frame")
	hidden:Hide()
	c.fill = Safe(bar.GetStatusBarTexture, bar)
	c.gameWidth = Clean(Safe(bar.GetWidth, bar)) -- (the game's own width, for when none is chosen)
	c.away = {} -- (the art put away: counted for /serene debug)
	-- (the art onto the hidden frame; the fill and the icon stay, the words stay: the name, and any other is a time)
	for _, region in ipairs({ Safe(bar.GetRegions, bar) }) do
		if IsTexture(region) then
			if region ~= c.fill and region ~= c.icon then
				c.away[#c.away + 1] = region
				pcall(region.SetParent, region, hidden)
			end
		elseif region ~= c.text and IsFontString(region) then
			c.others[#c.others + 1] = region
		end
	end
	-- (the time may be its own key, outside the bar's own regions)
	local time = rawget(bar, "CastTimeText")
	if IsFontString(time) then
		local known = false
		for _, other in ipairs(c.others) do known = known or other == time end
		if not known then c.others[#c.others + 1] = time end
	end
	-- (frames inside it, a glow or a shield of the game's: unseen; Edit Mode's outline kept)
	local selection = rawget(bar, "Selection")
	for _, child in ipairs({ Safe(bar.GetChildren, bar) }) do
		if child ~= selection then pcall(child.SetAlpha, child, 0) end
	end
	-- the glass
	c.box = CreateFrame("Frame", nil, bar)
	c.box:EnableMouse(false)
	c.box.ground = c.box:CreateTexture(nil, "BACKGROUND")
	c.box.ground:SetAllPoints()
	c.box.ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS_ALPHA)
	c.box.lines = ns.Hairline(c.box)
	-- the spark (on the bar: above its fill, fading with it)
	c.spark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
	c.spark:SetColorTexture(1, 0.97, 0.88, 0.9)
	c.spark:SetBlendMode("ADD")
	c.spark:Hide()
	-- the time, in Serene's words
	c.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	-- your lag, and a channel's ticks (yours only: the pet's bar is its own)
	local unit = Clean(rawget(bar, "unit"))
	c.unit = type(unit) == "string" and unit or nil
	c.mine = c.unit == nil or c.unit == "player"
	c.lag = bar:CreateTexture(nil, "OVERLAY", nil, 5)
	c.lag:SetColorTexture(MUTED[1], MUTED[2], MUTED[3], LAG_ALPHA)
	c.lag:Hide()
	c.ticks = {}
	-- the flash as it ends
	c.flash = bar:CreateTexture(nil, "OVERLAY", nil, 6)
	c.flash:SetAllPoints(bar)
	c.flash:SetColorTexture(1, 1, 1, 1)
	c.flash:SetBlendMode("ADD")
	c.flash:SetAlpha(0)
	-- the game's fading parts of its fade animations (a short hold before them stays the game's)
	c.fades = {}
	for _, key in ipairs({ "FadeOutAnim", "HoldFadeOutAnim" }) do
		local group = rawget(bar, key)
		if type(group) == "table" and group.GetAnimations then
			for _, anim in ipairs({ Safe(group.GetAnimations, group) }) do
				local to = anim.GetToAlpha and Clean(Safe(anim.GetToAlpha, anim))
				local duration = Clean(Safe(anim.GetDuration, anim))
				if to == 0 and type(duration) == "number" then c.fades[#c.fades + 1] = { anim = anim, duration = duration } end
			end
		end
	end
	dressed[bar] = c

	-- (the game paints it anew for each cast, and on the fill directly too: Serene's colour again, right after)
	hooksecurefunc(bar, "SetStatusBarColor", function(_, r, g, b)
		if holding then return end
		r, g, b = Clean(r), Clean(g), Clean(b)
		-- (the game's own colour kept: CastColor tells from it what an older bar is showing)
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then c.raw = { r, g, b } end
		Paint(c)
	end)
	hooksecurefunc(bar, "SetStatusBarTexture", function()
		if not holding then Paint(c) end
	end)
	if type(c.fill) == "table" then
		for _, method in ipairs({ "SetAtlas", "SetTexture", "SetVertexColor" }) do
			if c.fill[method] then
				hooksecurefunc(c.fill, method, function()
					if not holding then Paint(c) end
				end)
			end
		end
	end
	-- (and lays it out anew: a new look, a new size, the icon shown or hidden, a new spell's icon)
	local function Again()
		if not holding then pcall(Layout, c) end
	end
	-- (the game's own width, kept: given back when no width is chosen)
	hooksecurefunc(bar, "SetSize", function(_, w)
		if holding then return end
		w = Clean(w)
		if type(w) == "number" and w > 0 then c.gameWidth = w end
		Again()
	end)
	hooksecurefunc(bar, "SetWidth", function(_, w)
		if holding then return end
		w = Clean(w)
		if type(w) == "number" and w > 0 then c.gameWidth = w end
		Again()
	end)
	hooksecurefunc(bar, "SetHeight", Again)
	if bar.SetLook then hooksecurefunc(bar, "SetLook", Again) end
	for _, region in ipairs({ c.icon or false, c.text or false }) do
		if region then
			for _, method in ipairs({ "SetPoint", "SetSize", "SetWidth", "SetHeight", "Show", "Hide", "SetShown",
				"SetTexture", "SetFontObject" }) do
				if region[method] then hooksecurefunc(region, method, Again) end
			end
		end
	end
	bar:HookScript("OnShow", function()
		Paint(c)
		Again()
	end)
	bar:HookScript("OnUpdate", function()
		Tick(c)
	end)
	-- (the game ends a cast through these: its fade when the spell lands, its red hold when it is interrupted or fails)
	if bar.PlayFadeAnim then
		hooksecurefunc(bar, "PlayFadeAnim", function() StartFlash(c, LANDED, FLASH_PEAK, FLASH_TIME) end)
	end
	if bar.PlayInterruptAnims then
		hooksecurefunc(bar, "PlayInterruptAnims", function() StartFlash(c, FAILED, FAILED_PEAK, FAILED_TIME) end)
	end
	-- (a cast starting while the bar is away: the game shows it at full at once; Serene's way in instead. Still fading
	-- from the last one, it comes back at once.)
	if bar.ApplyAlpha then
		hooksecurefunc(bar, "ApplyAlpha", function(_, alpha)
			if holding or not active or Clean(alpha) ~= 1 then return end
			-- (a new cast: the last one's flash put out)
			c.flashAt = nil
			c.flash:SetAlpha(0)
			if not ns.On("castFade") or Clean(Safe(bar.IsVisible, bar)) then return end
			c.inAt = GetTime()
			holding = true
			pcall(bar.SetAlpha, bar, 0)
			holding = false
		end)
	end
	-- (no shake on an interrupt)
	local shake = rawget(bar, "InterruptShakeAnim")
	if type(shake) == "table" and shake.Play then
		hooksecurefunc(shake, "Play", function(self)
			if active and ns.On("castFade") then pcall(self.Stop, self) end
		end)
	end
	Retime(c)
	Paint(c)
	pcall(Layout, c)
end

-- The target's and focus's cast bars ----------------------------------------------------------------------------------
-- A slim line on glass under the target's bars (Units.lua dresses the card, and says where the line goes: beside the
-- target's target while that one is shown, the whole width of the bars otherwise), its icon at the outer end, the
-- spell's name in it. The game keeps moving it (under the auras...): placed again each time. With the unit frames
-- (units), whatever castBar says. Not protected: safe in a fight.

local CAST_HEIGHT = 10
local CAST_FONT = 9
local onUnits = false -- (Units.lua dressed one: they are Serene's from then on)


local function PaintCast(c)
	if not onUnits then return end
	local bar, color = c.bar, CastColor(c)
	holding = true
	pcall(bar.SetStatusBarTexture, bar, FLAT)
	pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3], 1)
	holding = false
	Unmask(bar)
end

-- (d: Units.lua's card; narrow: room left at its outer end, for the target's target; y: the row's top, from the bars')
function ns.LayoutUnitCast(d, narrow, y)
	local c = d.cast
	if not onUnits or not c or not d.below then return end
	local bar, below, e = c.bar, d.below, d.e
	local lined = ns.db.unitBorder == "line"
	local right = d.side == "right"
	local icon = c.icon and CAST_HEIGHT + 1 or 0
	if right then
		Place(bar, { "TOPLEFT", below, "BOTTOMLEFT", icon, y }, { "TOPRIGHT", below, "BOTTOMRIGHT", -narrow, y })
	else
		Place(bar, { "TOPLEFT", below, "BOTTOMLEFT", narrow, y }, { "TOPRIGHT", below, "BOTTOMRIGHT", -icon, y })
	end
	Size(bar, nil, CAST_HEIGHT)
	local box = c.box
	box:ClearAllPoints()
	if c.icon then
		if right then
			Place(c.icon, { "TOPRIGHT", bar, "TOPLEFT", -1, 0 })
		else
			Place(c.icon, { "TOPLEFT", bar, "TOPRIGHT", 1, 0 })
		end
		Size(c.icon, CAST_HEIGHT, CAST_HEIGHT)
		pcall(c.icon.SetTexCoord, c.icon, 0.08, 0.92, 0.08, 0.92)
		box:SetPoint("TOPLEFT", right and c.icon or bar, "TOPLEFT", -e, e)
		box:SetPoint("BOTTOMRIGHT", right and bar or c.icon, "BOTTOMRIGHT", e, -e)
	else
		box:SetPoint("TOPLEFT", bar, "TOPLEFT", -e, e)
		box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", e, -e)
	end
	box.lines:Fit()
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do box.lines[side]:SetShown(lined) end
	pcall(box.SetFrameLevel, box, math.max(0, (Clean(Safe(bar.GetFrameLevel, bar)) or 1) - 1))
	if c.text then
		-- (room at the right for a timer, where there is one)
		Place(c.text, { "LEFT", bar, "LEFT", 3, 0 }, { "RIGHT", bar, "RIGHT", #c.others > 0 and -26 or -3, 0 })
		pcall(c.text.SetJustifyH, c.text, "LEFT")
		pcall(c.text.SetWordWrap, c.text, false)
	end
	for _, other in ipairs(c.others) do Place(other, { "RIGHT", bar, "RIGHT", -3, 0 }) end
end

-- (relayout: Units.lua's own placing of it, for when the game moves it)
function ns.DressUnitCast(d, relayout)
	onUnits = true
	local frame = d.frame
	local bar = rawget(frame, "spellbar") or _G[d.name .. "SpellBar"]
	if not IsRegion(bar) or not bar.SetStatusBarTexture or not bar.GetRegions then return end
	local name = Clean(Safe(bar.GetName, bar))
	local c = { bar = bar, others = {} }
	c.icon = rawget(bar, "Icon") or (name and _G[name .. "Icon"])
	c.text = rawget(bar, "Text") or (name and _G[name .. "Text"])
	if not IsTexture(c.icon) then c.icon = nil end
	if not IsFontString(c.text) then c.text = nil end
	hidden = hidden or CreateFrame("Frame")
	hidden:Hide()
	local fill = Safe(bar.GetStatusBarTexture, bar)
	for _, region in ipairs({ Safe(bar.GetRegions, bar) }) do
		if IsTexture(region) then
			if region ~= fill and region ~= c.icon then pcall(region.SetParent, region, hidden) end
		elseif region ~= c.text and IsFontString(region) then
			c.others[#c.others + 1] = region -- (a timer, from the game or an addon)
		end
	end
	for _, text in ipairs({ c.text or false, unpack(c.others) }) do
		if text then Font(text, CAST_FONT, SOFT) end
	end
	if c.icon then pcall(c.icon.Show, c.icon) end
	c.box = CreateFrame("Frame", nil, bar)
	c.box:EnableMouse(false)
	c.box.ground = c.box:CreateTexture(nil, "BACKGROUND")
	c.box.ground:SetAllPoints()
	c.box.ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS_ALPHA)
	c.box.lines = ns.Hairline(c.box)
	d.cast = c
	-- (the game colours it, and moves it, again and again: Serene's colour and place again, right after)
	hooksecurefunc(bar, "SetStatusBarColor", function(_, r, g, b)
		if holding then return end
		r, g, b = Clean(r), Clean(g), Clean(b)
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then c.raw = { r, g, b } end
		PaintCast(c)
	end)
	hooksecurefunc(bar, "SetStatusBarTexture", function()
		if not holding then PaintCast(c) end
	end)
	local function Again()
		if not holding then pcall(relayout) end
	end
	for _, region in ipairs({ bar, c.icon or false, c.text or false }) do
		if region then
			hooksecurefunc(region, "SetPoint", Again)
			if region.SetSize then hooksecurefunc(region, "SetSize", Again) end
			if region.SetHeight then hooksecurefunc(region, "SetHeight", Again) end
		end
	end
	bar:HookScript("OnShow", function()
		PaintCast(c)
		Again()
	end)
	PaintCast(c)
end

local function DressAll()
	for _, name in ipairs(NAMES) do
		local bar = _G[name]
		if bar then pcall(Dress, bar) end
	end
	-- (Edit Mode's own cast bar, whatever its name)
	local manager = _G.EditModeManagerFrame
	local system = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CastBar
	local frames = type(manager) == "table" and manager.registeredSystemFrames
	if system ~= nil and type(frames) == "table" then
		for _, frame in pairs(frames) do
			if type(frame) == "table" and frame.system == system then pcall(Dress, frame) end
		end
	end
end

local function Refresh()
	for _, c in pairs(dressed) do
		pcall(Paint, c)
		pcall(Layout, c)
		pcall(Retime, c)
	end
end

-- Your lag: from your spell sent to its cast (or channel) started.
local function Measure(_, event, unit)
	if Clean(unit) ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		sentAt = GetTime()
	elseif sentAt then
		local took = GetTime() - sentAt
		sentAt = nil
		if took >= 0 and took <= LAG_MOST then lag = took end
	end
end

local function Init()
	if not ns.On("castBar") then return end
	active = true
	DressAll()
	-- (a pet's or a vehicle's bar may come later)
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", DressAll)
	local measure = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
		if not (measure.RegisterUnitEvent and pcall(measure.RegisterUnitEvent, measure, event, "player")) then
			pcall(measure.RegisterEvent, measure, event)
		end
	end
	measure:SetScript("OnEvent", Measure)
end

-- /serene debug: which bars were found, your lag.
function ns.CastDebug()
	local found = {}
	for bar, c in pairs(dressed) do
		found[#found + 1] = ("%s (%d away, icon %s, fades %d)"):format(Clean(Safe(bar.GetName, bar)) or "?", #c.away,
			c.icon and "yes" or "no", #c.fades)
	end
	local seconds = Lag()
	ns.Print("cast bars: " .. (#found > 0 and table.concat(found, ", ") or (active and "none found" or "off"))
		.. (active and ("; lag %s (%s)"):format(seconds and ("%d ms"):format(seconds * 1000) or "?",
			lag and "measured" or "the game's") or ""))
end

ns.CastParts = function(bar) return dressed[bar] end -- (tests)

table.insert(ns.modules, { init = Init, refresh = Refresh })
