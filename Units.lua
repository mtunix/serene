local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The unit frames made calm: the game's own frames (you, your pet, your target and its target, your focus and its
-- target), nothing new beside them. Edit Mode still places and sizes them, a click still targets, the right click
-- still opens the game's menu, the game still fills their bars (in a fight it alone may read the numbers) and still
-- shows their auras, cast bars and icons. Only looks change:
--   - the ornate frame, its flashes and the target's reputation band put away;
--   - the bars flat, on a slab of glass, squared (the art's mask taken off), coloured quietly: a player by class,
--     a creature by how it feels about you (soft red, gold, green), grey once someone else has tapped it or it died;
--     power by its kind (mana, rage, energy...);
--   - the name in Serene's warm white, the level in the game's difficulty colour, a small mark for elites and rares;
--     the game's own dragon (gold: elite, silver: rare) around the round portrait, fitted to it (/serene elite off:
--     gone with the frame);
--   - one card: a single piece of glass, rounded at the portrait's end (a capsule), holding the portrait (round,
--     flush beside the bars, as tall as the name row and the bars together), the name above the bars and the level
--     at the end of its row; the game's level badge put away. Or no portrait (/serene portraits off).
--   - the target's target (and the focus's): a small sibling of its card, tucked under it on the portrait's side, its
--     little portrait under the big one;
--   - the game's heal prediction flat and as tall as the bar, growing from the fill's end whichever way the bar fills;
--     a bright hairline at the bar's full end while a heal of yours is coming and would overflow it (an overheal)
--     (UnitHeals.lua);
--   - the target's cast bar (and the focus's): a slim line on glass under the target's bars, beside the target's
--     target, its icon at the outer end; the colour says what it is (a cast, a channel, one that can't be stopped,
--     one that failed) (drawn by CastBar.lua, placed from here).
-- Nothing protected is touched in a fight: all of it is safe there. The one protected move, the target's target's
-- frame under the target's card, is made out of a fight only (one starting first: once it is over). Fade.lua still
-- fades your portrait and your pet's.
--   /serene units on|off      (a reload to switch)
--   /serene portraits on|off
--   /serene elite on|off       the game's dragon around an elite's or a rare's portrait
--   /serene border line|none   line: the card in a hairline of the game's gold (one pixel, soft), the portrait in a
--                hairline rim, the bars (flat) coming out of it; none: the glass capsule alone

local FLAT = "Interface\\Buttons\\WHITE8X8"
local RING_EXTRA = 6  -- the hairline look: the portrait this much taller than the box (the box's corners behind it)
local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local INK = ns.INK
local SOFT = ns.SOFT_RGB
local GOLD = { 1, 0.82, 0.35 }
local SILVER = { 0.78, 0.8, 0.84 }
local GLASS_ALPHA = 0.6
local PAD = 2         -- the glass beyond the card's parts
local HOLE = MEDIA .. "HoleMask"
local HOLE_AT = 80 / 512 -- HoleMask's hole: its radius over its size
local INNER = 2       -- between the portrait and the bars
local NAME_GAP = 3    -- between the name row and the bars
local BADGE = 64      -- the largest texture around the level or the portrait taken for the level's badge
local EVERY = 0.25    -- seconds between two looks at colours (a target of a target changes without telling)

-- How a creature feels about you, quiet.
local HOSTILE = { 0.78, 0.33, 0.3 }
local NEUTRAL = { 0.86, 0.7, 0.36 }
local FRIENDLY = { 0.42, 0.68, 0.44 }
local GREY = { 0.45, 0.45, 0.45 }
local POWER = {
	MANA = { 0.33, 0.52, 0.86 }, RAGE = { 0.8, 0.3, 0.28 }, ENERGY = { 0.9, 0.78, 0.38 },
	FOCUS = { 0.86, 0.56, 0.3 }, RUNIC_POWER = { 0.36, 0.74, 0.9 }, HAPPINESS = { 0.42, 0.68, 0.44 },
}

-- The game's unit frames, by name, and what each holds (looked for under these keys, or the global names the
-- older frames used). Each frame found is dressed; those this game doesn't have are skipped.
local FRAMES = { "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" }
-- (the parts holding the others, walked into)
local HOLDERS = { "PlayerFrameContainer", "PlayerFrameContent", "PlayerFrameContentMain", "PlayerFrameContentContextual",
	"TargetFrameContainer", "TargetFrameContent", "TargetFrameContentMain", "TargetFrameContentContextual",
	"HealthBarsContainer", "ManaBarArea", "textureFrame" }
-- The art put away.
local ART = { "FrameTexture", "FrameFlash", "Flash", "StatusTexture", "VehicleFrameTexture",
	"AlternatePowerFrameTexture", "BossPortraitFrameTexture", "ReputationColor", "Background", "NameBackground",
	"PlayerPortraitCornerIcon" }
-- (the older frames' art, by its global name)
local OLD_ART = { "PlayerFrameTexture", "PlayerFrameVehicleTexture", "PlayerFrameFlash", "PlayerStatusTexture",
	"PlayerFrameBackground", "PetFrameTexture", "PetFrameFlash", "PetAttackModeTexture",
	"TargetFrameTextureFrameTexture", "TargetFrameFlash", "TargetFrameBackground", "TargetFrameNameBackground",
	"TargetFrameToTTextureFrameTexture", "TargetFrameToTBackground", "FocusFrameTextureFrameTexture", "FocusFrameFlash",
	"FocusFrameBackground", "FocusFrameNameBackground", "FocusFrameToTTextureFrameTexture", "FocusFrameToTBackground" }
local PORTRAITS = { "PlayerPortrait", "Portrait", "portrait" }
local CLASSIFIED = { TargetFrame = true, FocusFrame = true }

-- The target's target, a small sibling placed from the target's card (and the focus's from the focus's).
local TOT_OF = { TargetFrame = "TargetFrameToT", FocusFrame = "FocusFrameToT" }
local PARENT_OF = { TargetFrameToT = "TargetFrame", FocusFrameToT = "FocusFrame" }
local TOT_WIDTH, TOT_HEALTH, TOT_POWER = 64, 6, 2
local TOT_FONT = 9
local TOT_NAME_GAP = 2
local TOT_RING = 2    -- (its portrait only a little taller than its box)
local ROW_GAP = 3     -- between a card and the row under it (the target's target, the cast bar)

local dressed = {}   -- unit frame -> { health, power, glass, mark, art = {}, name }
local away = {}      -- region -> true while put away
local holding = false -- (Serene's own calls, not heard by its hooks)
local hooked = {}     -- region -> true once hooked (hooks can't be taken off: never twice)
local active = false

-- Finding the parts ------------------------------------------------------------------------------------------------

local IsRegion, IsTexture = ns.IsRegion, ns.IsTexture

-- A key looked for in the frame and in the parts holding the others.
local function Each(frame, keys, found, depth)
	found = found or {}
	depth = depth or 0
	if depth > 4 or type(frame) ~= "table" then return found end
	for _, key in ipairs(keys) do
		local part = rawget(frame, key)
		if IsRegion(part) then found[#found + 1] = part end
	end
	for _, key in ipairs(HOLDERS) do
		local holder = rawget(frame, key)
		if type(holder) == "table" and holder ~= frame then Each(holder, keys, found, depth + 1) end
	end
	return found
end

local function First(frame, keys)
	return Each(frame, keys)[1]
end

local function HealthBar(frame)
	return frame.healthbar or frame.HealthBar or First(frame, { "HealthBar" })
		or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "HealthBar"])
end

local function PowerBar(frame)
	return frame.manabar or frame.ManaBar or First(frame, { "ManaBar" })
		or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "ManaBar"])
end

-- (the player's power bar, for the five-second rule's line under it: Regen.lua; found with the cards off too)
function ns.PlayerPowerBar()
	local frame = _G.PlayerFrame
	if type(frame) ~= "table" then return nil end
	return PowerBar(frame)
end

-- (and its round portrait, where Serene shows one: the line starts at its rim)
function ns.PlayerPortrait()
	local d = dressed[_G.PlayerFrame or false]
	if d and d.portrait and d.size and ns.On("unitPortraits") then return d.portrait end
end

local function UnitOf(frame, bar)
	local unit = Clean(bar and bar.unit) or Clean(frame.unit)
	if type(unit) == "string" then return unit end
end

-- Putting away, kept away ------------------------------------------------------------------------------------------
-- The game shows its art again (a vehicle, an elite, a flash in a fight): it goes again at once.

local function Hold(region)
	holding = true
	pcall(region.SetAlpha, region, 0)
	holding = false
end

local function PutAway(region)
	if not IsRegion(region) then return end
	away[region] = true
	Hold(region)
	if hooked[region] then return end
	hooked[region] = true
	local function Again()
		if holding or not away[region] then return end
		Hold(region)
	end
	hooksecurefunc(region, "SetAlpha", Again)
	if region.Show then hooksecurefunc(region, "Show", Again) end
	if region.SetShown then hooksecurefunc(region, "SetShown", Again) end
end

local function GiveBack(region)
	if not away[region] then return end
	away[region] = nil
	holding = true
	pcall(region.SetAlpha, region, 1)
	holding = false
end

-- Colours ------------------------------------------------------------------------------------------------------------

local classColors = {} -- class -> its colour, quieter (made once: a colour unchanged is never painted again)
local function ClassColor(unit)
	local _, file = Safe(UnitClass, unit)
	file = Clean(file)
	if not file then return nil end
	if classColors[file] then return classColors[file] end
	-- (another addon's class colours, where one sets them)
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local c = colors and colors[file]
	if not c then return nil end
	-- (a little quieter than the game's own)
	classColors[file] = { c.r * 0.82 + 0.06, c.g * 0.82 + 0.06, c.b * 0.82 + 0.06 }
	return classColors[file]
end

local function HealthColor(unit)
	if not unit or not Clean(Safe(UnitExists, unit)) then return GREY end
	if Clean(Safe(UnitIsDeadOrGhost, unit)) then return GREY end
	if Clean(Safe(UnitIsPlayer, unit)) then return ClassColor(unit) or FRIENDLY end
	if Clean(Safe(UnitIsTapDenied, unit)) then return GREY end
	local reaction = Clean(Safe(UnitReaction, unit, "player"))
	if type(reaction) == "number" then -- (1 to 3 hostile, 4 neutral, 5 to 8 friendly)
		if reaction <= 3 then return HOSTILE end
		if reaction == 4 then return NEUTRAL end
		return FRIENDLY
	end
	if Clean(Safe(UnitCanAttack, "player", unit)) then return HOSTILE end
	return FRIENDLY
end

local function PowerColor(unit)
	if not unit then return POWER.MANA end
	local _, token = Safe(UnitPowerType, unit)
	token = Clean(token)
	if token and POWER[token] then return POWER[token] end
	local game = token and _G.PowerBarColor and _G.PowerBarColor[token]
	if type(game) == "table" and type(game.r) == "number" then
		POWER[token] = { game.r * 0.8 + 0.08, game.g * 0.8 + 0.08, game.b * 0.8 + 0.08 }
		return POWER[token]
	end
	return POWER.MANA
end

-- The bars -----------------------------------------------------------------------------------------------------------

-- The art's mask off the fill (its slanted, rounded ends), squared.
local function Unmask(bar)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) ~= "table" or not fill.GetNumMaskTextures then return end
	local count = Clean(Safe(fill.GetNumMaskTextures, fill)) or 0
	for index = count, 1, -1 do -- (from the end: taking one off moves the ones after it down)
		local mask = Safe(fill.GetMaskTexture, fill, index)
		if mask then pcall(fill.RemoveMaskTexture, fill, mask) end
	end
end

local Paint -- (below)
local FitDragon -- (below)

-- The fill itself: the game also sets its art on the fill directly, not through the bar (the target's, on every new
-- target: its atlas back, gradient and all, while Serene's colour, unchanged, is never painted again). Serene's again.
local function HookFill(bar)
	local fill = Safe(bar.GetStatusBarTexture, bar)
	if type(fill) ~= "table" or hooked[fill] then return end
	hooked[fill] = true
	local function Again()
		-- (a fill the bar has since replaced: its hooks stay, but it is no longer Serene's to paint)
		if holding or not active or Safe(bar.GetStatusBarTexture, bar) ~= fill then return end
		Paint(bar)
	end
	for _, method in ipairs({ "SetAtlas", "SetTexture", "SetColorTexture", "SetVertexColor" }) do
		if type(fill[method]) == "function" then hooksecurefunc(fill, method, Again) end
	end
end

Paint = function(bar)
	local color = bar.sereneColor
	if not color then return end
	holding = true
	pcall(bar.SetStatusBarTexture, bar, FLAT)
	pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3], 1)
	holding = false
	Unmask(bar)
	HookFill(bar) -- (the fill may be a new one)
end

local function HookBar(bar)
	if hooked[bar] then return end
	hooked[bar] = true
	-- (the game sets its own texture and colour on updates: Serene's again, right after)
	local function Again()
		if holding or not active then return end
		Paint(bar)
	end
	hooksecurefunc(bar, "SetStatusBarTexture", Again)
	hooksecurefunc(bar, "SetStatusBarColor", Again)
	HookFill(bar)
end

local function Quiet(text)
	if type(text) ~= "table" or not text.SetTextColor then return end
	pcall(text.SetTextColor, text, SOFT[1], SOFT[2], SOFT[3])
	pcall(text.SetShadowColor, text, 0, 0, 0, 0.8)
	pcall(text.SetShadowOffset, text, 1, -1)
end

local function QuietTexts(bar)
	for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do Quiet(bar and bar[key]) end
	local name = bar and bar.GetName and bar:GetName()
	if name then Quiet(_G[name .. "Text"]) end
end


-- The card ------------------------------------------------------------------------------------------------------------
-- One piece of glass holds it all, a capsule: rounded around the portrait (round, flush beside the bars and as tall
-- as the name row and the bars together), straight behind the name and the bars, the level at the end of the name's
-- row. The glass is two parts meeting at the portrait's middle, never overlapping (no darker seam): half a disc
-- around the portrait, a slab from there to the bars' end. Everything is anchored
-- to the game's own health bar, so the card follows it wherever Edit Mode or the game puts it. (The target's portrait
-- stays on the side the game draws it.)

local function Shown(region)
	return region and Clean(Safe(region.IsShown, region)) and (Clean(Safe(region.GetHeight, region)) or 0) > 1
end

-- The portrait round in its new place: the game's mask stays where the game's frame had it, so it is taken off and
-- Serene's own disc, held by the portrait itself, put on instead.
local function Round(d)
	local portrait = d.portrait
	if not portrait then return end
	local count = Clean(Safe(portrait.GetNumMaskTextures, portrait)) or 0
	for index = count, 1, -1 do
		local mask = Safe(portrait.GetMaskTexture, portrait, index)
		if mask and mask ~= d.mask then pcall(portrait.RemoveMaskTexture, portrait, mask) end
	end
	if d.mask == nil then
		d.mask = false -- (tried once: false where this client can't)
		local parent = Safe(portrait.GetParent, portrait)
		if parent and parent.CreateMaskTexture and portrait.AddMaskTexture then
			local mask = parent:CreateMaskTexture()
			mask:SetTexture(MEDIA .. "BadgeDisc", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(portrait)
			if pcall(portrait.AddMaskTexture, portrait, mask) then d.mask = mask end
		end
	end
end

-- Textures of the frame (not its bars, not its portrait), walked into its children.
local function Textures(frame, found, depth, skip)
	found, depth = found or {}, depth or 0
	if depth > 6 or type(frame) ~= "table" or skip[frame] then return found end
	for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
		if IsTexture(region) and not skip[region] then found[#found + 1] = region end
	end
	for _, child in ipairs({ Safe(frame.GetChildren, frame) }) do Textures(child, found, depth + 1, skip) end
	return found
end

-- What the game draws around the level (a badge, a disc and its ring): small textures under the level's middle.
-- (the game's icons that matter, kept whatever their place: leader, PvP, rest, combat, raid mark, role...)
local KEEP = { "Icon", "PVP", "Pvp", "Prestige", "Leader", "Guide", "Role", "Rest", "Attack", "Raid", "Quest",
	"Threat", "Group", "Selection", "Highlight", "HighLevel", "Skull", "Aura", "Buff", "Debuff", "Spell", "Cast" }

local function KeyOf(region)
	return Clean(Safe(region.GetParentKey, region)) or Clean(Safe(region.GetName, region)) or ""
end

local function Kept(texture)
	-- (its own key, and its holder's: the level's badge may be a frame of its own holding a disc and a ring)
	for _, key in ipairs({ KeyOf(texture), KeyOf(Safe(texture.GetParent, texture) or texture) }) do
		if key:find("Level") and not key:find("HighLevel") then return false end
	end
	local key = KeyOf(texture)
	for _, word in ipairs(KEEP) do
		if key:find(word) then return true end
	end
	return false
end

-- Anchored to the portrait (or to something anchored to it): moves with it, as the level's badge did.
local function OnPortrait(region, portrait, depth)
	depth = depth or 0
	if depth > 3 or not portrait then return false end
	local count = Clean(Safe(region.GetNumPoints, region)) or 0
	for index = 1, count do
		local _, relative = Safe(region.GetPoint, region, index)
		if relative == portrait then return true end
		if type(relative) == "table" and relative ~= region and relative.GetNumPoints
			and OnPortrait(relative, portrait, depth + 1) then return true end
	end
	return false
end

-- What the game draws around the level (its round badge, empty once the level moves to the name's row): looked at
-- once, as the game laid the frame out. A texture named for the level, or a small round-ish one under the level or
-- close around the portrait.
local function FindBadges(d)
	local lx, ly
	if d.levelText then
		lx, ly = Safe(d.levelText.GetCenter, d.levelText)
		lx, ly = Clean(lx), Clean(ly)
	end
	local px, py, radius
	if d.portrait then
		px, py = Safe(d.portrait.GetCenter, d.portrait)
		px, py = Clean(px), Clean(py)
		radius = (Clean(Safe(d.portrait.GetWidth, d.portrait)) or 0) / 2
	end
	local skip = { [d.health] = true, [d.glass] = true, [d.ringFrame] = true }
	if d.power then skip[d.power] = true end
	for _, portrait in ipairs(d.portraits) do skip[portrait] = true end
	if d.frame.Selection then skip[d.frame.Selection] = true end
	if d.ring then skip[d.ring] = true end
	if d.dragon then skip[d.dragon] = true end
	for _, texture in ipairs(Textures(d.frame, nil, 0, skip)) do
		if not Kept(texture) then
			local art = Clean(Safe(texture.GetAtlas, texture)) or Clean(Safe(texture.GetTexture, texture))
			local named = type(art) == "string" and art:lower():find("level") and true or false
			local left, bottom, width, height = Safe(texture.GetRect, texture)
			left, bottom, width, height = Clean(left), Clean(bottom), Clean(width), Clean(height)
			local round, under, near = false, false, false
			local anchored = OnPortrait(texture, d.portrait) or OnPortrait(Safe(texture.GetParent, texture) or texture, d.portrait)
			if left and width and height then
				round = width <= BADGE and height <= BADGE and math.abs(width - height) <= 4
				local cx, cy = left + width / 2, bottom + height / 2
				under = lx and lx >= left and lx <= left + width and ly >= bottom and ly <= bottom + height
				near = px and radius > 0 and math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2) <= radius + 12
			end
			if named or (round and (under or near or anchored)) then
				d.badges[#d.badges + 1] = texture
				PutAway(texture)
			end
		end
	end
end

local function FontSize(text)
	local _, size = Safe(text and text.GetFont, text)
	size = Clean(size)
	return type(size) == "number" and size or nil
end

-- The name row: as tall as its taller text (the level in the name's own font, so it never stands out over the edge).
local function RowHeight(d)
	if d.nameText and d.levelText then
		local font, size, flags = Safe(d.nameText.GetFont, d.nameText)
		font, size = Clean(font), Clean(size)
		if font and size and FontSize(d.levelText) ~= size then
			holding = true
			pcall(d.levelText.SetFont, d.levelText, font, size, Clean(flags) or "")
			holding = false
		end
	end
	return math.ceil(math.max(FontSize(d.nameText) or 0, FontSize(d.levelText) or 0, 10) + 1)
end

-- A part the game protects (the target's target's bars, hanging from its secure frame) can't be moved in a fight:
-- left where it is, and the card laid out again once the fight is over (`blocked`, read at the end of Layout).
local blocked = false
local function Movable(region)
	if not InCombatLockdown() or not Clean(Safe(region.IsProtected, region)) then return true end
	blocked = true
	return false
end

local function Place(region, ...)
	if not Movable(region) then return end
	holding = true
	pcall(region.ClearAllPoints, region)
	local points = { ... }
	for _, point in ipairs(points) do pcall(region.SetPoint, region, unpack(point)) end
	holding = false
end

local function Size(region, width, height)
	if not Movable(region) then return end
	holding = true
	if width then pcall(region.SetWidth, region, width) end
	if height then pcall(region.SetHeight, region, height) end
	holding = false
end

-- The portrait for a card this tall (its name row and its bars), an even size so its middle falls on a whole pixel.
local function PortraitSize(content, e, lined, ringExtra)
	if lined then return math.floor((content + 2 * e + ringExtra) / 2 + 0.5) * 2 end
	return math.floor(content / 2 + 0.5) * 2
end

local function SmallFont(text, size)
	local font, _, flags = Safe(text and text.GetFont, text)
	font = Clean(font)
	if font and FontSize(text) ~= size then pcall(text.SetFont, text, font, size, Clean(flags) or "") end
end

-- The cast bar under the card (CastBar.lua dresses and draws it): beside the target's target while that one is shown
-- (on the same row, up to its box's edge), the whole width of the bars otherwise; its glass level with the target's
-- target's.
local function LayoutCast(d)
	if not active or not d.cast or not d.below or not d.spine then return end
	local e = d.e
	local tot = TOT_OF[d.name] and dressed[_G[TOT_OF[d.name]] or false]
	local beside = tot and tot.spine and Clean(Safe(tot.frame.IsShown, tot.frame))
	local narrow = beside and (TOT_WIDTH + (tot.e or e) + ROW_GAP + e - (d.spine - tot.spine)) or 0
	local rise = (ns.db.unitBorder == "line" and ns.On("unitPortraits")) and TOT_RING / 2 + 1 or 0
	ns.LayoutUnitCast(d, narrow, -(d.floor + ROW_GAP + rise + e))
end

-- The target's target: its frame under the target's card (protected: moved out of a fight only; in one, once it is
-- over). x, y: where its top corner on the portrait's side goes, from the bottom corner of the target's bars.
local function MoveCompact(d, pd, x, y, width, height)
	if InCombatLockdown() then
		d.later = true
		return
	end
	local frame, parent, below = d.frame, pd.frame, pd.below
	local right = d.side == "right"
	-- (anchored to the target's own frame, not to its bars: nothing Serene moves in a fight holds it)
	local bx = Clean(Safe(right and below.GetRight or below.GetLeft, below))
	local by = Clean(Safe(below.GetBottom, below))
	local fx, fy = Clean(Safe(parent.GetLeft, parent)), Clean(Safe(parent.GetBottom, parent))
	if not (bx and by and fx and fy) then
		d.dirty = true -- (not laid out yet: at the next look)
		return
	end
	d.later = false
	holding = true
	pcall(frame.ClearAllPoints, frame)
	pcall(frame.SetPoint, frame, right and "TOPRIGHT" or "TOPLEFT", parent, "BOTTOMLEFT",
		bx - fx + (right and x or -x), by - fy + y)
	pcall(frame.SetSize, frame, width, height)
	holding = false
end

-- The target's target laid out small: its frame placed from the target's card (its portrait's middle under the
-- target's portrait's, or its box's edge under the target's box's), its bars inside it. Returns how tall its bars are.
local function PlaceCompact(d, pd, lined, e, px, portrait, top)
	local bars = TOT_HEALTH + (Shown(d.power) and d.barGap + TOT_POWER or 0)
	local size = portrait and PortraitSize(top + bars, e, lined, TOT_RING) or 0
	local rise = (lined and portrait) and TOT_RING / 2 + 1 or 0 -- (the portrait over its box's edge)
	local spine = portrait and (lined and size / 2 or INNER + size / 2) or e
	local outer = portrait and (lined and size + px or INNER + size + PAD) or e
	local ceil, floor = top + e + rise, e + rise
	MoveCompact(d, pd, pd.spine - spine + outer, -(pd.floor + ROW_GAP), e + TOT_WIDTH + outer, ceil + bars + floor)
	Size(d.health, TOT_WIDTH, TOT_HEALTH)
	if d.power then Size(d.power, nil, TOT_POWER) end
	if d.side == "right" then
		Place(d.health, { "TOPRIGHT", d.frame, "TOPRIGHT", -outer, -ceil })
	else
		Place(d.health, { "TOPLEFT", d.frame, "TOPLEFT", outer, -ceil })
	end
	d.spine = spine
	return bars
end

-- The PvP emblem (the faction's crest, or the prestige portrait and its badge): the game keeps it where its own,
-- larger portrait was, out beside Serene's. Pinned to the portrait's rim instead, up on its outer side, a little
-- smaller; at the card's outer top corner without a portrait.
local EMBLEM = 0.42 -- (its height, of the portrait's)
local function EmblemSize(region, height)
	local atlas = Clean(Safe(region.GetAtlas, region))
	local info = atlas and C_Texture and C_Texture.GetAtlasInfo and Safe(C_Texture.GetAtlasInfo, atlas)
	local w, h = info and Clean(info.width), info and Clean(info.height)
	if not (type(w) == "number" and type(h) == "number" and w > 0 and h > 0) then w, h = 1, 1 end
	return height * w / h, height
end

local function PlaceEmblems(d)
	if #d.emblems == 0 or not d.side or not d.e then return end
	local portrait = ns.On("unitPortraits") and d.portrait and d.size and d.portrait or nil
	local outer = d.side == "right" and 1 or -1
	local anchor, point, x, y, height
	if portrait then
		local r = d.size / 2 * 0.7071 -- (its middle on the rim, 45 degrees up)
		anchor, point, x, y = portrait, "CENTER", outer * r, r
		height = math.max(12, math.floor(d.size * EMBLEM + 0.5))
	else
		anchor, point = d.health, d.side == "right" and "TOPRIGHT" or "TOPLEFT"
		x, y = outer * d.e, (d.top or 0) + d.e
		height = 14
	end
	for _, region in ipairs(d.emblems) do
		local w, h = EmblemSize(region, height)
		Place(region, { "CENTER", anchor, point, x, y })
		Size(region, w, h)
	end
	if d.prestigeBadge then
		local around = d.prestigePortrait or d.emblems[1]
		Place(d.prestigeBadge, { "CENTER", around, "CENTER", 0, 0 })
		Size(d.prestigeBadge, math.floor(height * 0.6 + 0.5), math.floor(height * 0.6 + 0.5))
	end
end

-- A crest taken in: on the rim now, and again each time the game sets it again (at its own size) or moves it.
local function AddEmblem(d, region, badge)
	if not IsTexture(region) or away[region] or d.emblemOf[region] then return end
	d.emblemOf[region] = true
	if badge then
		d.prestigeBadge = region
	else
		d.emblems[#d.emblems + 1] = region
		if KeyOf(region):find("Prestige") or KeyOf(region):find("prestige") then d.prestigePortrait = region end
	end
	local function Again()
		if not holding and active then pcall(PlaceEmblems, d) end
	end
	for _, method in ipairs({ "SetAtlas", "SetTexture", "SetPoint", "SetSize", "Show" }) do
		if type(region[method]) == "function" then hooksecurefunc(region, method, Again) end
	end
	pcall(PlaceEmblems, d)
end

-- The crest found by its art, whatever this game calls it: the faction's, PvP's or prestige's, anywhere in the frame.
local CREST = { "pvp", "alliance", "horde", "prestige", "honorsystem" }
local function FindEmblems(d)
	for _, texture in ipairs(Textures(d.frame, nil, 0, d.emblemSkip)) do
		if not d.emblemOf[texture] and not away[texture] and texture ~= d.portrait then
			local art = Clean(Safe(texture.GetAtlas, texture))
			if type(art) ~= "string" then art = Clean(Safe(texture.GetTexture, texture)) end
			if type(art) == "string" then
				art = art:lower()
				for _, word in ipairs(CREST) do
					if art:find(word, 1, true) then
						AddEmblem(d, texture, art:find("badge", 1, true) ~= nil)
						break
					end
				end
			end
		end
	end
end

-- What lies behind the portrait carved away under it. A card fading draws each of its parts at that opacity on its own,
-- so whatever the face hid (the glass and its hairline reaching to the face's middle, the bars' stubs, the gold disc
-- of the ring) would show through it, and the card would come apart as it fades. Carved, nothing lies under the face
-- (but its soft edge), and the card fades as one.
local function Carve(d, portrait, size, px)
	local want = (portrait and type(size) == "number" and size > 0) and true or false
	for _, hole in ipairs(d.holes) do
		if want then
			-- (the mask sized so its hole's radius is a pixel under the face's)
			local side = math.max(1, size / 2 - px) / HOLE_AT
			hole.mask:ClearAllPoints()
			hole.mask:SetPoint("CENTER", portrait, "CENTER", 0, 0)
			hole.mask:SetSize(side, side)
		end
		if want ~= hole.on then
			for _, texture in ipairs(hole.textures) do
				pcall(want and texture.AddMaskTexture or texture.RemoveMaskTexture, texture, hole.mask)
			end
			hole.on = want
		end
	end
end

local function Layout(d)
	local health = d.health
	local hx = Clean(Safe(health.GetCenter, health))
	if not hx then return end -- (not laid out by the game yet: later)
	local pd = d.compact and dressed[_G[PARENT_OF[d.name]] or false]
	if d.compact and not (pd and pd.spine and pd.below) then return end -- (placed from the target's card: that first)
	d.dirty = false
	d.later = false
	blocked = false
	-- (first, as the game drew it: which side the portrait is on, what sits around the level)
	if not d.measured then
		d.measured = true
		local px = d.portrait and Clean(Safe(d.portrait.GetCenter, d.portrait))
		d.side = (px and px > hx) and "right" or "left"
		FindBadges(d)
		-- (the gap the game leaves between the bars, kept: 0 to 3)
		local healthBottom = Clean(Safe(health.GetBottom, health))
		local powerTop = d.power and Clean(Safe(d.power.GetTop, d.power))
		d.barGap = (healthBottom and powerTop) and math.max(0, math.min(3, healthBottom - powerTop)) or 1
		if d.compact then
			d.side = pd.side -- (the same side as the target's: its little portrait under the big one)
			d.barGap = 1
		end
	end
	-- The portrait is about to be placed from the bars: bars still hanging from it (as the pet's do) would make a
	-- loop, and the game would leave the portrait nowhere (and the bars, the name and the glass with it). The bars
	-- hung from the frame instead, where the game drew them (looked at once, before the portrait first moves).
	if d.portrait and OnPortrait(health, d.portrait) then
		if not d.healthAt then
			local fl, ft = Clean(Safe(d.frame.GetLeft, d.frame)), Clean(Safe(d.frame.GetTop, d.frame))
			local hl, ht = Clean(Safe(health.GetLeft, health)), Clean(Safe(health.GetTop, health))
			if fl and ft and hl and ht then d.healthAt = { hl - fl, ht - ft } end
		end
		if d.healthAt then Place(health, { "TOPLEFT", d.frame, "TOPLEFT", d.healthAt[1], d.healthAt[2] }) end
	end
	local lined = ns.db.unitBorder == "line"
	local px = ns.Pixel(health)
	local e = lined and PAD + px or PAD -- (the glass beyond the bars)
	local portrait = ns.On("unitPortraits") and d.portrait or nil
	local ringExtra = d.compact and TOT_RING or RING_EXTRA
	if d.compact then SmallFont(d.nameText, TOT_FONT) end
	local nameGap = d.compact and TOT_NAME_GAP or NAME_GAP
	local row = RowHeight(d)
	local top = row + nameGap -- (the name row above the bars)
	local compactBars = d.compact and PlaceCompact(d, pd, lined, e, px, portrait, top)
	-- The power bar exactly under the health bar, as wide (the game draws the target's a little longer, to the left).
	if d.power then
		Place(d.power, { "TOPLEFT", health, "BOTTOMLEFT", 0, -d.barGap }, { "TOPRIGHT", health, "BOTTOMRIGHT", 0, -d.barGap })
	end
	local below = Shown(d.power) and d.power or health

	-- the name row
	if d.levelText then
		Place(d.levelText, { "BOTTOMRIGHT", health, "TOPRIGHT", -1, nameGap })
		pcall(d.levelText.SetJustifyH, d.levelText, "RIGHT")
	end
	if d.nameText then
		local right = d.levelText and { "BOTTOMRIGHT", d.levelText, "BOTTOMLEFT", d.mark and -12 or -4, 0 }
			or { "BOTTOMRIGHT", health, "TOPRIGHT", -1, nameGap }
		Place(d.nameText, { "BOTTOMLEFT", health, "TOPLEFT", 1, nameGap }, right)
		pcall(d.nameText.SetJustifyH, d.nameText, "LEFT")
		pcall(d.nameText.SetWordWrap, d.nameText, false)
	end

	-- the portrait and the glass
	local barTop, healthBottom, barBottom
	if compactBars then
		-- (just placed: measured from its own numbers, not from where the game has drawn it so far)
		barTop, healthBottom, barBottom = 0, -TOT_HEALTH, -compactBars
	else
		barTop = Clean(Safe(health.GetTop, health))
		healthBottom = Clean(Safe(health.GetBottom, health))
		barBottom = Clean(Safe(below.GetBottom, below))
	end
	local content = (barTop and barBottom) and (barTop - barBottom + top) or (top + 30) -- (the name row and the bars)
	local glass, slab, cap, box, ring = d.glass, d.glass.slab, d.glass.cap, d.box, d.ring
	slab:ClearAllPoints()
	cap:ClearAllPoints()
	box:ClearAllPoints()
	if ring then ring:ClearAllPoints() end
	if lined then
		-- The hairline look: the box of glass around the name and the bars in a pixel of soft gold; the portrait a
		-- little taller, its middle on the box's end (the box's corners behind it), in a pixel-thin rim of the same.
		box.lines:Fit()
		slab:Hide()
		cap:Hide()
		box:Show()
		if portrait then
			local size = PortraitSize(content, e, lined, ringExtra)
			d.size = size
			local gap = 0 -- (the bars from the portrait's edge: they come out of it)
			-- (its middle level with the middle of the name row and the bars)
			local dy = (barTop and barBottom and healthBottom)
				and ((barTop + top + barBottom) / 2 - (barTop + healthBottom) / 2) or 0
			holding = true
			pcall(portrait.ClearAllPoints, portrait)
			pcall(portrait.SetSize, portrait, size, size)
			if d.side == "right" then
				pcall(portrait.SetPoint, portrait, "LEFT", health, "RIGHT", gap, dy)
			else
				pcall(portrait.SetPoint, portrait, "RIGHT", health, "LEFT", -gap, dy)
			end
			holding = false
			Round(d)
			if d.side == "right" then
				box:SetPoint("TOPLEFT", health, "TOPLEFT", -e, top + e)
				box:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", gap + size / 2, -e)
			else
				box:SetPoint("TOPLEFT", health, "TOPLEFT", -(gap + size / 2), top + e)
				box:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", e, -e)
			end
			if ring then
				ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
				ring:SetSize(size + 2 * px, size + 2 * px)
				ring:Show()
			end
			-- (each bar reaches on behind the portrait to its middle: where the circle curves away from the bar's
			-- end, the bar seems to come out of it)
			for _, bar in ipairs({ health, Shown(d.power) and d.power or false }) do
				local stub = bar and d.stubs[bar]
				if stub then
					stub:ClearAllPoints()
					if d.side == "right" then
						stub:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
						stub:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
					else
						stub:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
						stub:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
					end
					stub:SetWidth(gap + size / 2)
					stub.placed = true
					if d.side == "right" and bar.SetReverseFill then
						-- (the target's bars fill toward its portrait, on the right, and empty away from it: a mirror
						-- of yours)
						pcall(bar.SetReverseFill, bar, true)
						d.reversed = true
					end
				end
			end
			if d.reversed then d:Segments() end -- (its heal prediction mirrored with it)
		else
			box:SetPoint("TOPLEFT", health, "TOPLEFT", -e, top + e)
			box:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", e, -e)
			if ring then ring:Hide() end
			d:Unreverse()
		end
	else
		-- The glass capsule: the portrait flush beside the bars, as tall as the name row and the bars; the glass
		-- rounded around it.
		d:Unreverse()
		box:Hide()
		if ring then ring:Hide() end
		slab:Show()
		if portrait then
			local size = PortraitSize(content, e, lined, ringExtra)
			d.size = size
			if d.side == "right" then
				Place(portrait, { "TOPLEFT", health, "TOPRIGHT", INNER, top }, { "BOTTOMLEFT", below, "BOTTOMRIGHT", INNER, 0 })
			else
				Place(portrait, { "TOPRIGHT", health, "TOPLEFT", -INNER, top }, { "BOTTOMRIGHT", below, "BOTTOMLEFT", -INNER, 0 })
			end
			holding = true
			pcall(portrait.SetWidth, portrait, size)
			holding = false
			Round(d)
			cap:SetWidth(size / 2 + PAD)
			if d.side == "left" then
				slab:SetPoint("TOPLEFT", portrait, "TOP", 0, PAD)
				slab:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", PAD, -PAD)
				cap:SetPoint("TOPRIGHT", portrait, "TOP", 0, PAD)
				cap:SetPoint("BOTTOMRIGHT", portrait, "BOTTOM", 0, -PAD)
				cap:SetTexCoord(0, 0.5, 0, 1)
			else
				slab:SetPoint("TOPLEFT", health, "TOPLEFT", -PAD, top + PAD)
				slab:SetPoint("BOTTOMRIGHT", portrait, "BOTTOM", 0, -PAD)
				cap:SetPoint("TOPLEFT", portrait, "TOP", 0, PAD)
				cap:SetPoint("BOTTOMLEFT", portrait, "BOTTOM", 0, -PAD)
				cap:SetTexCoord(0.5, 1, 0, 1)
			end
			cap:Show()
		else
			slab:SetPoint("TOPLEFT", health, "TOPLEFT", -PAD, top + PAD)
			slab:SetPoint("BOTTOMRIGHT", below, "BOTTOMRIGHT", PAD, -PAD)
			cap:Hide()
		end
	end
	-- (the glass under the bars and under the portrait both; the ring over the portrait)
	local level = Clean(Safe(health.GetFrameLevel, health)) or 2
	local holder = portrait and Safe(portrait.GetParent, portrait)
	local portraitLevel = holder and Clean(Safe(holder.GetFrameLevel, holder))
	for _, other in ipairs({ d.power and Clean(Safe(d.power.GetFrameLevel, d.power)) or false, portraitLevel or false }) do
		if other and other < level then level = other end
	end
	pcall(glass.SetFrameLevel, glass, math.max(0, level - 1))
	pcall(box.SetFrameLevel, box, math.max(0, level - 1))
	pcall(d.ringFrame.SetFrameLevel, d.ringFrame, (portraitLevel or level) + 2)
	d.below = below
	-- (what the rows under the card are placed from: how far its lowest edge is under its bars, where its portrait's
	-- middle is from the bars' end)
	d.e = e
	d.top = top
	if not portrait then d.size = nil end
	Carve(d, portrait, d.size, px)
	PlaceEmblems(d)
	FitDragon(d)
	d.floor = e + ((lined and portrait) and ringExtra / 2 + 1 or 0)
	if not d.compact then
		d.spine = portrait and d.size and (lined and d.size / 2 or INNER + d.size / 2) or e
		local tot = TOT_OF[d.name] and dressed[_G[TOT_OF[d.name]] or false]
		if tot then tot.dirty = true end
	end
	local owner = d.compact and pd or d
	if owner.cast then pcall(LayoutCast, owner) end
	if blocked then d.later = true end
end

-- The game moving a part, or the bars changing size or showing the power bar: laid out again at the next look.
local watched = {}
local function Watch(d, region)
	if not IsRegion(region) or watched[region] then return end
	watched[region] = true
	local function Dirty()
		if holding then return end
		d.dirty = true
		-- (laid out again on the next frame, once the game is done moving its parts)
		if d.pending or not C_Timer then return end -- (one already waiting: many moves, one layout)
		d.pending = true
		C_Timer.After(0, function()
			d.pending = false
			if d.dirty then pcall(Layout, d) end
		end)
	end
	hooksecurefunc(region, "SetPoint", Dirty)
	if region.SetSize then hooksecurefunc(region, "SetSize", Dirty) end
	if region.SetHeight then hooksecurefunc(region, "SetHeight", Dirty) end
	if region.SetWidth then hooksecurefunc(region, "SetWidth", Dirty) end
	if region.HookScript and region.GetScript and region:HasScript("OnShow") then
		region:HookScript("OnShow", Dirty)
		region:HookScript("OnHide", Dirty)
	end
end

-- Elites and rares: a small mark beside the level (gold: elite or boss, silver: rare).
local function Mark(d)
	if not d.levelText then return end
	local mark = d.ringFrame:CreateTexture(nil, "OVERLAY")
	mark:SetTexture(MEDIA .. "Disc")
	mark:SetSize(6, 6)
	mark:SetPoint("RIGHT", d.levelText, "LEFT", -4, 0)
	mark:Hide()
	d.mark = mark
end

local function PaintMark(d)
	if not d.mark then return end
	local unit = UnitOf(d.frame, d.health)
	local kind = unit and Clean(Safe(UnitClassification, unit))
	local color = (kind == "elite" or kind == "worldboss" or kind == "rareelite") and GOLD
		or kind == "rare" and SILVER
	if color then
		d.mark:SetVertexColor(color[1], color[2], color[3], 0.95)
		d.mark:Show()
	else
		d.mark:Hide()
	end
end

-- Elites and rares: the game's own dragon around the portrait (gold for an elite or a boss, silver for a rare, as the
-- game picks it), if wanted. The game draws it around its own, larger portrait where its frame had it; Serene's
-- portrait has moved and shrunk, so the dragon is fitted to it: its middle as far from the portrait's middle as the
-- game had it, and its size, both scaled by how much smaller the portrait now is. The game still decides when it shows
-- and which art it wears; each time it sets it again (another kind, another place), fitted again.

-- Where a point lies on a box this size, from its bottom left corner.
local function PointOn(point, width, height)
	point = type(point) == "string" and point:upper() or "CENTER"
	local x = point:find("LEFT") and 0 or point:find("RIGHT") and width or width / 2
	local y = point:find("BOTTOM") and 0 or point:find("TOP") and height or height / 2
	return x, y
end

-- A region's anchor as the game set it (not one to Serene's portrait).
local function GameAnchor(region, portrait)
	local count = Clean(Safe(region.GetNumPoints, region)) or 0
	for index = 1, count do
		local point, relative, relPoint, x, y = Safe(region.GetPoint, region, index)
		point, relPoint, x, y = Clean(point), Clean(relPoint), Clean(x), Clean(y)
		relative = relative or Safe(region.GetParent, region)
		if type(point) == "string" and relative and relative ~= portrait then
			return { point = point, relative = relative, relPoint = relPoint or point, x = x or 0, y = y or 0 }
		end
	end
end

-- The middle of a box this size anchored so, from its relative's bottom left corner.
local function MiddleOf(at, width, height)
	local rw = Clean(Safe(at.relative.GetWidth, at.relative)) or 0
	local rh = Clean(Safe(at.relative.GetHeight, at.relative)) or 0
	local ax, ay = PointOn(at.relPoint, rw, rh)
	local px, py = PointOn(at.point, width, height)
	return ax + at.x - px + width / 2, ay + at.y - py + height / 2
end

FitDragon = function(d)
	local dragon = d.dragon
	if not dragon then return end
	-- (only on the right, the side the game draws it for)
	if not (ns.On("unitElite") and ns.On("unitPortraits") and d.portrait and d.size and d.side == "right") then
		PutAway(dragon)
		return
	end
	GiveBack(dragon)
	-- (its own size: the atlas's, or as the game last sized it)
	local atlas = Clean(Safe(dragon.GetAtlas, dragon))
	local info = type(atlas) == "string" and C_Texture and C_Texture.GetAtlasInfo and Safe(C_Texture.GetAtlasInfo, atlas)
	local width = type(info) == "table" and Clean(info.width) or d.dragonSize and d.dragonSize[1]
	local height = type(info) == "table" and Clean(info.height) or d.dragonSize and d.dragonSize[2]
	if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
	local was = d.portraitSize or { 58, 58 } -- (the game's portrait, as its frame drew it)
	local scale = d.size / was[1]
	local dx, dy = 0, 0
	local pa, da = d.portraitAt, d.dragonAt
	if pa and da and pa.relative == da.relative then
		local px, py = MiddleOf(pa, was[1], was[2])
		local mx, my = MiddleOf(da, width, height)
		dx, dy = mx - px, my - py
	end
	holding = true
	pcall(dragon.ClearAllPoints, dragon)
	pcall(dragon.SetPoint, dragon, "CENTER", d.portrait, "CENTER", dx * scale, dy * scale)
	pcall(dragon.SetSize, dragon, width * scale, height * scale)
	holding = false
end

local function Dragon(d)
	local dragon = First(d.frame, { "BossPortraitFrameTexture" })
	if not IsTexture(dragon) or not d.portrait then return end
	d.dragon = dragon
	-- (looked at before anything moves: the game's portrait, its place and size; the dragon's place)
	d.portraitAt = GameAnchor(d.portrait)
	local width, height = Clean(Safe(d.portrait.GetWidth, d.portrait)), Clean(Safe(d.portrait.GetHeight, d.portrait))
	if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
		d.portraitSize = { width, height }
	end
	d.dragonAt = GameAnchor(dragon, d.portrait)
	-- (over the portrait, and over its rim)
	local layer = Safe(d.portrait.GetDrawLayer, d.portrait)
	if Safe(dragon.GetParent, dragon) == Safe(d.portrait.GetParent, d.portrait) and Clean(layer) ~= "OVERLAY" then
		pcall(dragon.SetDrawLayer, dragon, "OVERLAY", 6)
	end
	local function Again()
		if holding or not active then return end
		d.dragonAt = GameAnchor(dragon, d.portrait) or d.dragonAt
		pcall(FitDragon, d)
	end
	hooksecurefunc(dragon, "SetAtlas", function()
		if holding then return end
		-- (the game's own size for this art, before it is fitted)
		local w, h = Clean(Safe(dragon.GetWidth, dragon)), Clean(Safe(dragon.GetHeight, dragon))
		if type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then d.dragonSize = { w, h } end
		Again()
	end)
	hooksecurefunc(dragon, "SetPoint", Again)
	if dragon.SetSize then hooksecurefunc(dragon, "SetSize", Again) end
end

-- A frame ------------------------------------------------------------------------------------------------------------

local function Portraits(d)
	local show = ns.On("unitPortraits")
	for _, portrait in ipairs(d.portraits) do
		if show then GiveBack(portrait) else PutAway(portrait) end
	end
	d.dirty = true
end

-- The art put away, kept away: back to nothing if anything showed it again past the hooks.
local function KeepAway(d)
	for _, list in ipairs({ d.art, d.badges }) do
		for _, region in ipairs(list) do
			if away[region] and (Clean(Safe(region.GetAlpha, region)) or 0) > 0 then Hold(region) end
		end
	end
end

local function Colour(d)
	KeepAway(d)
	-- (a new unit: its crest looked for by its art, now and at the next look, once the game has set it)
	if d.lookFor and d.lookFor > 0 then
		d.lookFor = d.lookFor - 1
		FindEmblems(d)
	end
	local unit = UnitOf(d.frame, d.health)
	local health = HealthColor(unit)
	if d.health.sereneColor ~= health then
		d.health.sereneColor = health
		Paint(d.health)
	end
	if d.power then
		local power = PowerColor(UnitOf(d.frame, d.power) or unit)
		if d.power.sereneColor ~= power then
			d.power.sereneColor = power
			Paint(d.power)
		end
	end
	if d.dirty or d.below ~= (Shown(d.power) and d.power or d.health) then Layout(d) end
	-- (the game may put its own mask back: Serene's disc again)
	if d.portrait and ns.On("unitPortraits") then Round(d) end
	PaintMark(d)
	d:Stubs()
	ns.UnitHeals.Overheal(d, unit) -- (the game's own update heard too, below; this the look that catches the rest)
end

local function Dress(frame, name)
	local health = HealthBar(frame)
	if not IsRegion(health) or not health.SetStatusBarTexture then return end
	local d = { frame = frame, name = name, health = health, power = PowerBar(frame), art = {}, portraits = {},
		badges = {}, dirty = true, compact = PARENT_OF[name] ~= nil }
	if d.power and not d.power.SetStatusBarTexture then d.power = nil end
	for _, region in ipairs(Each(frame, ART)) do d.art[#d.art + 1] = region end
	for _, global in ipairs(OLD_ART) do
		local region = _G[global]
		if IsRegion(region) and global:find("^" .. name) then d.art[#d.art + 1] = region end
	end
	-- (the band behind the name also found by its key wherever it hangs, or by its art: the reaction colour's
	-- "...-Type" strip; not in the target's target, a child of the target's frame, nor the cast bar)
	local listed = {}
	for _, region in ipairs(d.art) do listed[region] = true end
	local skip = { [health] = true }
	if d.power then skip[d.power] = true end
	for _, other in ipairs({ TOT_OF[name] and _G[TOT_OF[name]] or false, rawget(frame, "spellbar") or false,
		_G[name .. "SpellBar"] or false }) do
		if other then skip[other] = true end
	end
	for _, texture in ipairs(Textures(frame, nil, 0, skip)) do
		local key = KeyOf(texture)
		local art = Clean(Safe(texture.GetAtlas, texture))
		art = type(art) == "string" and art:lower() or ""
		if not listed[texture] and (key:find("Reputation") or key:find("NameBackground") or art:find("%-type$")) then
			listed[texture] = true
			d.art[#d.art + 1] = texture
		end
	end
	for _, region in ipairs(d.art) do PutAway(region) end
	-- The PvP emblem, moved onto the portrait's rim (not the target's target's: it has none).
	d.emblems, d.emblemOf, d.emblemSkip = {}, {}, skip
	if not d.compact then
		for _, region in ipairs(Each(frame, { "PvpIcon", "PVPIcon", "PrestigePortrait" })) do AddEmblem(d, region) end
		for _, global in ipairs({ name .. "TextureFramePVPIcon", name == "PlayerFrame" and "PlayerPVPIcon" or false }) do
			if global then AddEmblem(d, _G[global]) end
		end
		AddEmblem(d, First(frame, { "PrestigeBadge" }), true)
		d.lookFor = 2
	end
	local seen = {}
	for _, portrait in ipairs(Each(frame, PORTRAITS)) do
		if not seen[portrait] then
			seen[portrait] = true
			d.portraits[#d.portraits + 1] = portrait
		end
	end
	if #d.portraits == 0 and IsRegion(_G[name .. "Portrait"]) then d.portraits[1] = _G[name .. "Portrait"] end
	for _, portrait in ipairs(d.portraits) do
		if IsTexture(portrait) then d.portrait = portrait break end
	end
	d.nameText = frame.name or First(frame, { "Name", "PlayerName" }) or _G[name .. "Name"]
		or (name == "PlayerFrame" and _G.PlayerName) or nil
	d.levelText = frame.levelText or First(frame, { "LevelText", "PlayerLevelText" })
		or (name == "PlayerFrame" and _G.PlayerLevelText) or _G[name .. "TextureFrameLevelText"] or nil
	if not IsRegion(d.nameText) then d.nameText = nil end
	if not IsRegion(d.levelText) then d.levelText = nil end
	HookBar(health)
	QuietTexts(health)
	if d.power then
		HookBar(d.power)
		QuietTexts(d.power)
	end
	Quiet(d.nameText)
	local glass = CreateFrame("Frame", nil, frame)
	glass:SetAllPoints(frame) -- (only a holder: its two parts are anchored to the card's)
	glass:EnableMouse(false)
	glass.slab = glass:CreateTexture(nil, "BACKGROUND")
	glass.slab:SetColorTexture(INK[1], INK[2], INK[3], GLASS_ALPHA)
	glass.cap = glass:CreateTexture(nil, "BACKGROUND")
	glass.cap:SetTexture(MEDIA .. "Disc")
	glass.cap:SetVertexColor(INK[1], INK[2], INK[3], GLASS_ALPHA)
	d.glass = glass
	-- (the hairline look: a box of glass in a pixel of gold; a rim behind the portrait, a pixel larger all round,
	-- drawn in the portrait's own layer just under it, so only its edge shows)
	d.box = CreateFrame("Frame", nil, glass)
	d.box:EnableMouse(false)
	d.box.ground = d.box:CreateTexture(nil, "BACKGROUND")
	d.box.ground:SetAllPoints()
	d.box.ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS_ALPHA)
	d.box.lines = ns.Hairline(d.box)
	d.box:Hide()
	d.stubs = {}
	for _, bar in ipairs({ health, d.power or false }) do
		if bar then
			d.stubs[bar] = d.box:CreateTexture(nil, "ARTWORK")
			d.stubs[bar]:SetTexture(FLAT)
			d.stubs[bar]:Hide()
			-- (an empty bar loses its stub, a filling one gets it back)
			bar:HookScript("OnValueChanged", function() if d.Stubs then d:Stubs() end end)
		end
	end
	function d:Unreverse()
		if not self.reversed then return end
		for _, bar in ipairs({ self.health, self.power or false }) do
			if bar and bar.SetReverseFill then pcall(bar.SetReverseFill, bar, false) end
		end
		self.reversed = false
		self:Segments()
	end
	ns.UnitHeals.Dress(d)
	-- The stubs in the bar's colour while the bar is filled at the portrait's end (the target's bars fill toward it).
	function d:Stubs()
		local lined = ns.db.unitBorder == "line" and ns.On("unitPortraits") and self.portrait
		for bar, stub in pairs(self.stubs) do
			local show = lined and stub.placed and Shown(bar) and bar.sereneColor
			if show then
				local fill = Safe(bar.GetStatusBarTexture, bar)
				local width = fill and Clean(Safe(fill.GetWidth, fill))
				local shownFill = fill and Clean(Safe(fill.IsShown, fill)) ~= false
				if type(width) == "number" then -- (unreadable in a fight: taken as filled)
					show = shownFill and width > 0.5
				end
			end
			if show then
				local c = bar.sereneColor
				stub:SetVertexColor(c[1], c[2], c[3], 1)
				stub:Show()
			else
				stub:Hide()
			end
		end
	end
	d.ringFrame = CreateFrame("Frame", nil, frame) -- (above the portrait: the elite mark)
	d.ringFrame:SetAllPoints(frame)
	d.ringFrame:EnableMouse(false)
	local holder = d.portrait and Safe(d.portrait.GetParent, d.portrait)
	if holder and holder.CreateTexture then
		local layer, sublevel = Safe(d.portrait.GetDrawLayer, d.portrait)
		layer, sublevel = Clean(layer) or "ARTWORK", Clean(sublevel) or 0
		d.ring = holder:CreateTexture(nil, layer, nil, math.max(-8, sublevel - 1))
		d.ring:SetTexture(MEDIA .. "Disc")
		d.ring:SetVertexColor(ns.LINE[1], ns.LINE[2], ns.LINE[3], ns.LINE[4])
		d.ring:Hide()
	end
	-- (the holes under the portrait, one per frame the carved parts belong to: placed by Carve)
	d.holes = {}
	local function Hole(owner, textures)
		if not (owner and owner.CreateMaskTexture) then return end
		local mask = owner:CreateMaskTexture()
		mask:SetTexture(HOLE, "CLAMP", "CLAMP")
		d.holes[#d.holes + 1] = { mask = mask, textures = textures, on = false }
	end
	Hole(glass, { glass.slab, glass.cap })
	local inBox = { d.box.ground, d.box.lines.top, d.box.lines.bottom, d.box.lines.left, d.box.lines.right }
	for _, stub in pairs(d.stubs) do inBox[#inBox + 1] = stub end
	Hole(d.box, inBox)
	if d.ring then Hole(holder, { d.ring }) end
	if CLASSIFIED[name] then
		Mark(d)
		Dragon(d)
	end
	for _, region in ipairs({ health, d.power or false, d.portrait or false, d.nameText or false, d.levelText or false,
		d.compact and frame or false }) do
		if region then Watch(d, region) end
	end
	if TOT_OF[name] and ns.DressUnitCast then ns.DressUnitCast(d, function() LayoutCast(d) end) end
	if d.compact then
		-- (the target's target shown or gone: the cast bar beside it, or the whole width)
		local function Beside()
			local pd = dressed[_G[PARENT_OF[name]] or false]
			if pd then pcall(LayoutCast, pd) end
		end
		frame:HookScript("OnShow", Beside)
		frame:HookScript("OnHide", Beside)
	end
	dressed[frame] = d
	Portraits(d)
	Colour(d)
end

local function DressAll()
	for _, name in ipairs(FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and not dressed[frame] then
			local ok, problem = pcall(Dress, frame, name)
			if not ok then ns.Print("|cffff6060units (" .. name .. "): " .. tostring(problem) .. "|r") end
		end
	end
end

local function ColourAll()
	for _, d in pairs(dressed) do pcall(Colour, d) end
end

local function Refresh()
	if not active then return end
	for _, d in pairs(dressed) do
		Portraits(d)
		-- (the look may have changed: the bars painted again, the card laid out again)
		d.health.sereneColor = nil
		if d.power then d.power.sereneColor = nil end
		d.dirty = true
	end
	ColourAll()
end

local function Init()
	ns.db.unitsDump = nil -- (a dump is kept until the next load: read from the saved variables after a /reload)
	if not ns.On("units") then return end
	active = true
	DressAll()
	-- (the game placing its heal prediction anew: the overheal mark looked at with it, at once)
	if type(UnitFrameHealPredictionBars_Update) == "function" then
		hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
			local d = frame and dressed[frame]
			if d then pcall(ns.UnitHeals.Overheal, d, UnitOf(d.frame, d.health)) end
		end)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET",
		"UNIT_FACTION", "UNIT_DISPLAYPOWER", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_CLASSIFICATION_CHANGED",
		"UNIT_PORTRAIT_UPDATE", "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		-- (a frame that comes later, with another of the game's addons or a new world: dressed then)
		if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then DressAll() end
		if event == "PLAYER_REGEN_ENABLED" then
			-- (the target's target's frame, waiting for the fight to end: placed now)
			for _, d in pairs(dressed) do
				if d.later then d.dirty = true end
			end
		end
		if event ~= "PLAYER_REGEN_ENABLED" and event ~= "UNIT_DISPLAYPOWER" then
			-- (a new unit, or its side changed: its crest looked for again)
			for _, d in pairs(dressed) do
				if not d.compact then d.lookFor = 2 end
			end
		end
		ColourAll()
	end)
	-- (tapped by someone else, dead, a target's target changed: a quiet look four times a second)
	local since = 0
	events:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < EVERY then return end
		since = 0
		ColourAll()
	end)
end

-- /serene debug: each frame, what was found in it.
function ns.UnitsDebug()
	local list = {}
	for _, name in ipairs(FRAMES) do
		local frame = _G[name]
		local d = type(frame) == "table" and dressed[frame]
		if not frame then
			list[#list + 1] = name .. " |cff8f8f8f(not in this game)|r"
		elseif not d then
			list[#list + 1] = name .. " |cffff8080not dressed|r"
		else
			list[#list + 1] = ("%s (art %d, badges %d, emblems %s, portrait %s, name %s, level %s, power %s, side %s, unit %s)"):format(
				name, #d.art, #d.badges, d.emblems and #d.emblems > 0 and (function()
					local names = {}
					for _, region in ipairs(d.emblems) do
						local _, relative = Safe(region.GetPoint, region, 1)
						names[#names + 1] = KeyOf(region) .. (relative == d.portrait and " on the rim" or " elsewhere")
					end
					return table.concat(names, "/")
				end)() or "none", d.portrait and "yes" or "no", d.nameText and "yes" or "no",
				d.levelText and "yes" or "no", d.power and "yes" or "no", tostring(d.side), tostring(UnitOf(frame, d.health)))
		end
	end
	ns.Print(("units: %s, portraits %s - %s"):format(tostring(ns.On("units")), tostring(ns.On("unitPortraits")),
		table.concat(list, ", ")))
end

-- /serene debug units [frame]: every texture and text in a frame, and everything drawn around its portrait from any
-- frame at all (where the game, or another addon, draws art Serene doesn't know). Kept in SereneDB.unitsDump too, so
-- it can be read from the saved variables after a /reload.
local function NameOf(region)
	if type(region) ~= "table" then return tostring(region) end
	return Clean(Safe(region.GetDebugName, region)) or Clean(Safe(region.GetName, region)) or KeyOf(region)
end

local function Describe(region)
	local kind = Clean(Safe(region.GetObjectType, region)) or "?"
	local w, h = Clean(Safe(region.GetWidth, region)), Clean(Safe(region.GetHeight, region))
	local what = ""
	if kind == "Texture" then
		what = tostring(Clean(Safe(region.GetAtlas, region)) or Clean(Safe(region.GetTexture, region)) or "")
	elseif kind == "FontString" then
		what = '"' .. tostring(Clean(Safe(region.GetText, region)) or "") .. '"'
	end
	local point, relative, relPoint, x, y = Safe(region.GetPoint, region, 1)
	local anchor = point and ("%s>%s:%s %.0f,%.0f"):format(tostring(point), NameOf(relative), tostring(relPoint),
		Clean(x) or 0, Clean(y) or 0) or "-"
	-- (where it is on the screen, how it is drawn: its layer, or its strata and level; seen after its parents' opacity)
	local left, bottom = Clean(Safe(region.GetLeft, region)), Clean(Safe(region.GetBottom, region))
	local rect = left and bottom and ("@%.0f,%.0f"):format(left, bottom) or "@?"
	local drawn
	if kind == "Texture" or kind == "FontString" then
		local layer, sub = Safe(region.GetDrawLayer, region)
		drawn = ("%s%s"):format(tostring(Clean(layer) or "?"), Clean(sub) and (" " .. Clean(sub)) or "")
	else
		drawn = ("%s %s"):format(tostring(Clean(Safe(region.GetFrameStrata, region)) or "?"),
			tostring(Clean(Safe(region.GetFrameLevel, region)) or "?"))
	end
	local effective = Clean(Safe(region.GetEffectiveAlpha, region))
	return ("%s | %s %dx%d %s %s a%.2f%s%s | %s | %s | at %s"):format(NameOf(region), kind, math.floor(w or 0),
		math.floor(h or 0), rect, Clean(Safe(region.IsVisible, region)) and "visible"
			or (Clean(Safe(region.IsShown, region)) and "shown" or "hidden"),
		Clean(Safe(region.GetAlpha, region)) or -1, effective and ("/%.2f"):format(effective) or "",
		away[region] and " (put away)" or "", drawn, what, anchor)
end

function ns.UnitsDump(which)
	local frame = _G[which or "PlayerFrame"]
	for _, name in ipairs(FRAMES) do
		if which and name:lower() == which:lower() then frame = _G[name] end
	end
	if type(frame) ~= "table" then return ns.Print("units: no such frame") end
	local lines = {}
	local function Line(text) lines[#lines + 1] = text end
	local function Walk(f, depth)
		if depth > 7 then return end
		for _, region in ipairs({ Safe(f.GetRegions, f) }) do Line(("  "):rep(depth) .. Describe(region)) end
		for _, child in ipairs({ Safe(f.GetChildren, f) }) do
			Line(("  "):rep(depth) .. "[" .. Describe(child) .. "]")
			Walk(child, depth + 1)
		end
	end
	Line("== " .. Describe(frame) .. " | in " .. NameOf(Safe(frame.GetParent, frame)))
	Walk(frame, 0)
	-- (and Serene's card for it: its glass and its box, children of the frame, listed above; the player's card too,
	-- which a frame inside the player's may sit under)
	local player = dressed[_G.PlayerFrame]
	if player and frame ~= _G.PlayerFrame then
		Line("== the player's card")
		for _, region in ipairs({ player.health, player.power or false, player.box, player.box.ground, player.glass }) do
			if region then Line(Describe(region)) end
		end
	end
	-- (around the portrait, from any frame)
	local d = dressed[frame]
	local portrait = d and d.portrait
	local px, py = portrait and Safe(portrait.GetCenter, portrait)
	px, py = Clean(px), Clean(py)
	if px and py and EnumerateFrames then
		local reach = (Clean(Safe(portrait.GetWidth, portrait)) or 40) / 2 + 30
		Line("== around the portrait (any frame), within " .. math.floor(reach))
		local f = EnumerateFrames()
		while f do
			if Clean(Safe(f.IsVisible, f)) then
				for _, region in ipairs({ Safe(f.GetRegions, f) }) do
					if Clean(Safe(region.IsVisible, region)) then
						local cx, cy = Safe(region.GetCenter, region)
						cx, cy = Clean(cx), Clean(cy)
						if cx and cy and math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2) <= reach then
							Line(Describe(region))
						end
					end
				end
			end
			f = EnumerateFrames(f)
		end
	end
	ns.db.unitsDump = lines
	for index = 1, math.min(#lines, 40) do ns.Print(lines[index]) end
	ns.Print(("units: %d lines kept in the saved variables (a /reload writes them)"):format(#lines))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
