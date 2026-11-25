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
--   - the spell's name in it, quiet, at the left; the time left (Edit Mode: "Show Cast Time") muted at the right;
--   - a soft spark at the fill's moving end while the cast goes on.
-- Settings (Serene's page, "Cast bar"; each at once, no reload): its height, its width (or Edit Mode's), the icon,
-- the spell's name in the bar, under it (the glass grows to hold it) or none, the words' size. Where it sits and its
-- scale stay Edit Mode's; whether the time shows too (its "Show Cast Time").
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

local dressed = {}     -- bar -> its parts
local holding = false  -- (Serene's own calls, not heard by its hooks)
local hidden           -- (where the art goes: a frame never shown, so the game's animations on it show nothing)
local active = false

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

-- The spark at the fill's moving end, while the cast goes on.
local function Spark(c)
	local bar, spark, fill = c.bar, c.spark, c.fill
	-- (the game's own state on the bar, read with rawget: some of its frames have a metatable behind them)
	local going = Clean(rawget(bar, "casting")) or Clean(rawget(bar, "channeling")) or Clean(rawget(bar, "reverseChanneling"))
	local value = Clean(Safe(bar.GetValue, bar))
	local least, most = Safe(bar.GetMinMaxValues, bar)
	least, most = Clean(least), Clean(most)
	local inside = type(value) == "number" and type(least) == "number" and type(most) == "number" and most > least
		and value > least and value < most
	if not (going and inside and fill) then
		spark:Hide()
		return
	end
	local reverse = Clean(Safe(bar.GetReverseFill, bar)) and true or false
	if c.sparkOn ~= fill or c.sparkReverse ~= reverse then
		c.sparkOn, c.sparkReverse = fill, reverse
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", fill, reverse and "LEFT" or "RIGHT", 0, 0)
	end
	spark:Show()
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
	local timed = false
	for _, other in ipairs(c.others) do
		if Clean(Safe(other.IsShown, other)) then timed = true end
	end
	local under = mode == "under" or height < FITS
	local font = Setting("castFont", 0, 16, 0)
	if font <= ns.CAST_FONT_AUTO then
		font = under and UNDER_FONT or math.max(8, math.min(12, height - 1))
	end
	local row = under and (named or timed) and font + 2 or 0
	for _, other in ipairs(c.others) do
		if under then
			Place(other, { "TOPRIGHT", bar, "BOTTOMRIGHT", -1, -UNDER_GAP })
		else
			Place(other, { "RIGHT", bar, "RIGHT", -TEXT_INSET, 0 })
		end
		pcall(other.SetJustifyH, other, "RIGHT")
		Font(other, font, MUTED)
	end
	if c.text then
		local room = timed and -math.max(TIME_ROOM, font * 3) or (under and -1 or -TEXT_INSET)
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
	for _, region in ipairs({ c.icon or false, c.text or false, unpack(c.others) }) do
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
		Spark(c)
	end)
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
end

-- /serene debug: which bars were found.
function ns.CastDebug()
	local found = {}
	for bar, c in pairs(dressed) do
		found[#found + 1] = ("%s (%d away, icon %s, time %s)"):format(Clean(Safe(bar.GetName, bar)) or "?", #c.away,
			c.icon and "yes" or "no", #c.others > 0 and "yes" or "no")
	end
	ns.Print("cast bars: " .. (#found > 0 and table.concat(found, ", ") or (active and "none found" or "off")))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
