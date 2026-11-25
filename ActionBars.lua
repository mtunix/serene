local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The action bars made calm: the game's own bars and buttons, close to how the game draws them. Each button keeps
-- its frame and its rounded icon, the whole icon red when its target is out of range; the key that presses it quiet
-- in a corner, macro names away, a soft wash under the mouse and when pressed. The bars' art (the frame, the gryphons, the
-- dividers) gone. An empty slot is see-through (its frame comes back, faintly, while a spell or an item is dragged,
-- to show where it can go).
-- Only looks change: the game still places the bars (Edit Mode), pages them, presses them; Fade.lua still fades them,
-- Hints.lua still lights them. Nothing is moved or dressed in a fight (a /reload in a fight waits for its end).
--   /serene bars on|off    (a reload to switch)
--   /serene keys on|off    the keys on the buttons
--   /serene macros on|off  macro names on the buttons
--   /serene empty on|off   empty slots shown too
-- Three looks, one for every bar or one per bar (Settings > Action bars):
--   classic  the game's button frame and rounded icon (as above)
--   glass    no frame: the icon cut square on a pane of dark glass, a hairline of soft gold around it
--   round    the icon round like the portraits and the buffs, in a thin gold ring (the cooldown drains it, Cooldowns.lua)
-- Out of range is told in every look: the icon red, the key soft red, and the glass's line or the ring soft red too.
-- The game's own cast animations on a button (the fill sweeping across it while casting, the red of an interrupt,
-- the turning light while a spell waits for its ground) are shaped to the look: Glass and Round clip them to their
-- icon, square or round, and leave out the parts drawn as a square frame round the button.
-- Glows: a proc or a hint breathes gently; a class buff running out (Hints.lua) a fainter, still glow.

local GOLD = { 1, 0.82, 0.35 }
local SOFT = ns.SOFT_RGB
local MUTED = ns.MUTED_RGB
local RANGE = { 0.95, 0.42, 0.38 } -- out of range: a soft red, not the game's alarm
local KEY_SIZE = 12
local FAR = { 1, 0.3, 0.3 } -- the icon out of range
local WHITE = { 1, 1, 1 }
local DRAGGING = 0.5 -- an empty slot's frame while something is dragged
local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local DISC = MEDIA .. "AuraDisc" -- (one soft-edged circle: the round icon's mask, its ring, its dark edge)
local LINE = ns.LINE
local INK = ns.INK
local GLASS = 0.8    -- the glass under a glass button: a dark mat showing round the icon
local GLASS_MAT = 2  -- Glass: pixels of mat between the icon and its gold line
local GLASS_LINE = 0.8 -- Glass: the gold line's strength (a frame, not a whisper: the plain hairline read as no
                       -- border at all); a dark pixel outside it keeps it seen on bright ground
local CROP = 0.07    -- the icon's own border cut away (glass, round)
local STYLES = { classic = true, glass = true, round = true }
local INSET = 3 / 45 -- the game's frame covers this much of the icon's edge (its own sweep sits 3 in on 45):
                     -- Glass and Round draw the icon that much smaller, so it shows as large as Classic's
local GLOW_SCALE = 1.6  -- Glass's soft glow (the hints' own, square-ish) over the button's size
local HALO_SCALE = 1.45 -- (Round's fallback halo before the game has GlowRound: a soft disc behind, over the icon)
local RING_AT = 36 / 128 -- GlowRound's bright line, out from its middle, over its whole size (roundglow.py)
local FAINT = 0.4    -- a glow for something running out (a class buff, Hints.lua): still, this strong
local FLAT = "Interface\\Buttons\\WHITE8X8" -- (a square mask: Glass clips the game's cast animations to its icon)
ns.BAR_RIM = 2       -- the round icon's ring and the glass's line, in pixels out from the icon (Cooldowns.lua too)

-- (the buttons and their bars' keys: Actions.lua)
local Actions = ns.Actions
local Region, Glows = Actions.Region, Actions.Glows
ns.BAR_KEYS = { { "main", "Action Bar 1" }, { "bar2", "Action Bar 2" }, { "bar3", "Action Bar 3" },
	{ "bar4", "Action Bar 4" }, { "bar5", "Action Bar 5" }, { "bar6", "Action Bar 6" }, { "bar7", "Action Bar 7" },
	{ "bar8", "Action Bar 8" }, { "pet", "Pet bar" }, { "stance", "Stance bar" } }
local BARS = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
	"MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }
-- The art of the older bar (where the game still has it): textures only, never the frames holding buttons.
local OLD_ART = { "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground", "MainMenuBarLeftEndCap",
	"MainMenuBarRightEndCap", "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2",
	"MainMenuBarTexture3", "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2",
	"MainMenuMaxLevelBar3", "SlidingActionBarTexture0", "SlidingActionBarTexture1", "StanceBarLeft",
	"StanceBarMiddle", "StanceBarRight", "PossessBackground1", "PossessBackground2", "PetActionBarFrame" }
-- What a button wears that Serene takes off (each only where this game has it): the equipped item's green border,
-- the "new" glow, the dividers of the bar's art.
local HIDE = { "Border", "NewActionTexture", "FloatingBG", "RightDivider", "BottomDivider", "LeftDivider", "TopDivider" }
-- The button's frame as the game draws it: kept, except on an empty slot.
local FRAME = { "NormalTexture", "SlotArt", "SlotBackground" }

local dressed = {} -- button -> true
local barOf = {}   -- button -> its bar's key ("main", "bar2"... "pet", "stance")
local parts = {}   -- button -> Serene's parts for the looks { bg, edge, lines, rim, dark, mask, style... }
local hooked = {}  -- object -> true once its hooks are set
local waiting = false -- (dressing waits for the fight's end)
local dragging = false -- a spell, an item, a macro... on the cursor
local rangeHooked = false -- the game's range function itself heard (else its key's red)

local function Hide(region)
	if type(region) == "table" and region.SetAlpha then pcall(region.SetAlpha, region, 0) end
end

-- The look a button wears: the one for every bar, or its bar's own.
local function StyleOf(button)
	local db = ns.db
	if not db then return "classic" end
	local style = db.barStyle
	if db.barStyleSame == false and type(db.barStyles) == "table" then style = db.barStyles[barOf[button]] or style end
	return STYLES[style] and style or "classic"
end
ns.BarStyleOf = StyleOf

-- Something on the button? (an action slot asked directly; the pet's and the stances' by their icon)
local function Filled(button)
	local slot = Actions.Slot(button)
	if slot then return Clean(Safe(HasAction, slot)) and true or false end
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not icon then return true end
	return Clean(Safe(icon.IsShown, icon)) ~= false and Clean(Safe(icon.GetTexture, icon)) ~= nil
end

-- An empty slot see-through: no frame, no key (its frame back, faintly, while something is dragged).
local function Empty(button)
	if not dressed[button] then return end
	local filled = ns.On("barEmpty") or Filled(button)
	local alpha = filled and 1 or (dragging and DRAGGING or 0)
	local classic = StyleOf(button) == "classic"
	-- (the game's frame: Classic's alone; Glass and Round wear Serene's parts instead)
	local frame = classic and alpha or 0
	for _, key in ipairs(FRAME) do
		local part = Region(button, key)
		if type(part) == "table" and part.SetAlpha then pcall(part.SetAlpha, part, frame) end
	end
	local normal = button.GetNormalTexture and Safe(button.GetNormalTexture, button)
	if normal then pcall(normal.SetAlpha, normal, frame) end
	local p = parts[button]
	if p then
		local glass, round = p.style == "glass", p.style == "round"
		p.bg:SetAlpha(glass and alpha or 0)
		p.edge:SetAlpha(glass and alpha or 0)
		p.outline:SetAlpha(glass and alpha or 0)
		p.rim:SetAlpha(round and alpha or 0)
		p.dark:SetAlpha(round and alpha or 0)
	end
	local key = Region(button, "HotKey")
	if key then
		local look = ns.KeyLook and ns.KeyLook(button)
		key:SetAlpha(ns.On("barKeys") and alpha > 0 and look ~= "hidden" and 1 or 0)
	end
end

-- The glass's line and the ring: soft gold, soft red out of range.
local function Edge(button)
	local p = parts[button]
	if not p then return end
	local c = button.sereneFar and RANGE or LINE
	local a = button.sereneFar and 0.9 or GLASS_LINE
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		pcall(p.lines[side].SetColorTexture, p.lines[side], c[1], c[2], c[3], a)
	end
	p.rim:SetVertexColor(c[1], c[2], c[3], button.sereneFar and 0.85 or 0.6)
end

-- Out of range: the whole icon red. The game colours the icon itself (grey when unusable, blue without the mana);
-- the colour it last gave is kept and given back once in range again.
local tinting = false
local function Tint(button)
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not icon then return end
	local color = button.sereneFar and FAR or button.sereneColor or WHITE
	tinting = true
	pcall(icon.SetVertexColor, icon, color[1], color[2], color[3])
	tinting = false
end

local function SetFar(button, far)
	far = far and true or false
	if button.sereneFar == far then return end
	button.sereneFar = far
	Tint(button)
	Edge(button)
end

local function HearIcon(button)
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not icon or hooked[icon] then return end
	hooked[icon] = true
	hooksecurefunc(icon, "SetVertexColor", function(_, r, g, b)
		if tinting then return end
		r, g, b = Clean(r), Clean(g), Clean(b)
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then
			button.sereneColor = { r, g, b }
		end
		if button.sereneFar then Tint(button) end
	end)
end

-- The keys, short: "s-1" -> "S1", "Mouse Button 4" -> "M4", "Num Pad 5" -> "N5"...
local WORDS = {
	{ "Mouse Wheel Up", "WU" }, { "Mouse Wheel Down", "WD" }, { "Middle Mouse", "M3" }, { "Mouse Button ", "M" },
	{ "Num Pad ", "N" }, { "NumPad", "N" }, { "Spacebar", "Sp" }, { "Space", "Sp" }, { "Page Up", "PU" },
	{ "Page Down", "PD" }, { "Insert", "Ins" }, { "Delete", "Del" }, { "Home", "Hm" }, { "Backspace", "Bs" },
	{ "Capslock", "Cp" }, { "Num Lock", "NL" },
}
local function Short(text)
	if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return text end
	if _G.RANGE_INDICATOR and text == _G.RANGE_INDICATOR then return text end
	for _, pair in ipairs(WORDS) do text = text:gsub(pair[1], pair[2]) end
	text = text:gsub("(%a)%-", function(modifier) return modifier:upper() end)
	return text
end

-- The key's text and colour: Serene's, whatever the game writes there.
local function KeyText(button)
	local key = Region(button, "HotKey")
	if not key then return end
	Empty(button)
	if hooked[key] then return end
	hooked[key] = true
	local busy = false
	hooksecurefunc(key, "SetText", function(self, text)
		if busy then return end
		local short = Short(text)
		if short ~= text then
			busy = true
			pcall(self.SetText, self, short)
			busy = false
		end
	end)
	-- (the game turns the key red when out of range, and back: Serene's own red, Serene's own grey)
	hooksecurefunc(key, "SetVertexColor", function(self, r, g, b)
		if busy then return end
		r, g, b = Clean(r), Clean(g), Clean(b)
		if type(r) ~= "number" or type(g) ~= "number" then return end
		local far = r > 0.8 and g < 0.3
		if not rangeHooked then SetFar(button, far) end
		local color = far and RANGE or (ns.KeyLook and ns.KeyLook(button) == "bright" and SOFT) or MUTED
		busy = true
		pcall(self.SetVertexColor, self, color[1], color[2], color[3])
		busy = false
	end)
	busy = true
	pcall(key.SetVertexColor, key, MUTED[1], MUTED[2], MUTED[3])
	busy = false
	pcall(key.SetText, key, (Safe(key.GetText, key)))
end

-- The game's marks off, Serene's soft washes on (again after the game puts its own back).
local function Art(button)
	for _, key in ipairs(HIDE) do Hide(Region(button, key)) end
	local light = button.GetHighlightTexture and Safe(button.GetHighlightTexture, button)
	if light then
		pcall(light.SetColorTexture, light, 1, 1, 1, 0.1)
		pcall(light.SetBlendMode, light, "ADD")
	end
	local pushed = button.GetPushedTexture and Safe(button.GetPushedTexture, button)
	if pushed then pcall(pushed.SetColorTexture, pushed, 1, 1, 1, 0.16) end
	local checked = button.GetCheckedTexture and Safe(button.GetCheckedTexture, button)
	if checked then
		pcall(checked.SetColorTexture, checked, GOLD[1], GOLD[2], GOLD[3], 0.28)
		pcall(checked.SetBlendMode, checked, "ADD")
	end
	local name = Region(button, "Name")
	if name then name:SetAlpha(ns.On("barNames") and 1 or 0) end
	Empty(button)
end

-- The looks ------------------------------------------------------------------------------------------------------

local WASHES = { "HighlightTexture", "PushedTexture", "CheckedTexture" }
local function Washes(button)
	local list = {}
	for _, key in ipairs(WASHES) do
		local get = button["Get" .. key]
		local texture = get and Safe(get, button)
		if texture then list[#list + 1] = texture end
	end
	return list
end

-- Serene's parts for Glass and Round, made once: a pane of glass and its hairline; a ring and a dark edge behind
-- the icon, and a round mask for it.
local function Parts(button, icon)
	local p = parts[button]
	if p then return p end
	p = { gameMasked = true }
	p.bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.bg:SetColorTexture(INK[1], INK[2], INK[3], GLASS)
	p.edge = CreateFrame("Frame", nil, button)
	p.edge:EnableMouse(false)
	p.lines = ns.Hairline(p.edge, LINE, "OVERLAY")
	p.outline = CreateFrame("Frame", nil, button)
	p.outline:EnableMouse(false)
	p.outlineLines = ns.Hairline(p.outline, { INK[1], INK[2], INK[3], 0.85 }, "OVERLAY")
	-- (Round's glow for a proc or a hint: the hints' glow made round, GlowRound.tga, its line on the icon's ring)
	p.ring = CreateFrame("Frame", nil, button)
	p.ring:EnableMouse(false)
	p.ring:SetFrameLevel((Clean(Safe(button.GetFrameLevel, button)) or 1) + 5)
	p.ring.texture = p.ring:CreateTexture(nil, "OVERLAY")
	p.ring.texture:SetAllPoints()
	local found = p.ring.texture:SetTexture(MEDIA .. "GlowRound")
	pcall(p.ring.texture.SetBlendMode, p.ring.texture, "ADD")
	p.ring.texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	-- (a new texture is seen only after the game restarts: until then, a soft gold disc behind the icon)
	p.useHalo = found == false
	-- (no "TRILINEAR" filter on these discs: it crashes this client; their edges are soft in the texture itself)
	p.halo = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.halo:SetTexture(MEDIA .. "DiscSoft", "CLAMP", "CLAMP")
	pcall(p.halo.SetBlendMode, p.halo, "ADD")
	p.halo:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
	p.dark = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	p.dark:SetTexture(DISC, "CLAMP", "CLAMP")
	p.dark:SetVertexColor(INK[1], INK[2], INK[3], 0.7)
	p.rim = button:CreateTexture(nil, "BACKGROUND", nil, -6)
	p.rim:SetTexture(DISC, "CLAMP", "CLAMP")
	for _, texture in ipairs({ p.dark, p.rim, p.halo }) do
		if texture.SetSnapToPixelGrid then
			pcall(texture.SetSnapToPixelGrid, texture, false)
			pcall(texture.SetTexelSnappingBias, texture, 0)
		end
	end
	p.mask = button:CreateMaskTexture()
	p.mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	p.mask:SetAllPoints(icon)
	-- (where the game put the icon, to give it back for Classic)
	p.iconPoints = {}
	for index = 1, Clean(Safe(icon.GetNumPoints, icon)) or 0 do
		p.iconPoints[index] = { icon:GetPoint(index) }
	end
	-- (Glass's glow for a proc or a hint: the hints' soft square-ish glow, over the button)
	p.glow = CreateFrame("Frame", nil, button)
	p.glow:EnableMouse(false)
	p.glow:SetFrameLevel((Clean(Safe(button.GetFrameLevel, button)) or 1) + 5)
	p.glow.texture = p.glow:CreateTexture(nil, "OVERLAY")
	p.glow.texture:SetAllPoints()
	p.glow.texture:SetTexture(MEDIA .. "Glow")
	pcall(p.glow.texture.SetBlendMode, p.glow.texture, "ADD")
	p.glow.texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	-- (their breath: one gentle rise and fall for every glow at once, never started over, BREATH below)
	for _, part in ipairs({ p.glow, p.ring, p.halo }) do part:Hide() end
	parts[button] = p
	return p
end

-- The square glows a button can wear (the game's proc, its spell highlight, the glow libraries addons use:
-- Actions.Glows): Glass and Round put each out of sight and light their own.
-- The game's square glows and the hints' out of sight on Glass and Round (theirs back on Classic). Only what
-- differs is set: nothing fought over with the game's own animations.
local function PutAwayGlows(button, mine)
	local want = mine and 0 or 1
	Glows(button, function(glow)
		if Clean(Safe(glow.GetAlpha, glow)) ~= want then pcall(glow.SetAlpha, glow, want) end
	end)
	-- (the hints' glow breathes by its frame's opacity: its texture is the one put away)
	local hint = ns.HintGlow and ns.HintGlow(button)
	if hint and hint.texture and Clean(Safe(hint.texture.GetAlpha, hint.texture)) ~= want then
		pcall(hint.texture.SetAlpha, hint.texture, want)
	end
end

-- A proc or a hint on a button: Classic keeps the game's glow and the hints'; Glass and Round put those out of
-- sight and light their own (Glass the soft square-ish glow, Round the same glow made round). "faint": something
-- running out (Hints.lua), the same glow fainter and still.
local breathing = {} -- glow part -> true while shown and breathing (breathed by the watcher)
local still = {}     -- glow part -> true while shown faint and still
local function Proc(button, on)
	local p = parts[button]
	local mine = p and p.style ~= "classic"
	PutAwayGlows(button, mine)
	if not p then return end
	local round = on and mine and p.style == "round"
	local faint = on == "faint"
	for part, show in pairs({ [p.glow] = on and mine and p.style == "glass", [p.ring] = round and not p.useHalo,
		[p.halo] = round and p.useHalo }) do
		show = show and true or false
		if show and faint then
			breathing[part] = nil
			if not still[part] then
				still[part] = true
				part:SetAlpha(FAINT)
				part:Show()
			end
		elseif show then
			still[part] = nil
			if not breathing[part] then
				breathing[part] = true
				part:Show()
			end
		elseif breathing[part] or still[part] then
			breathing[part], still[part] = nil, nil
			part:Hide()
		end
	end
end

-- (Hints.lua: Glass and Round light their own glow, so the hints' stays out of sight on them)
function ns.BarsOwnGlow(button)
	local p = parts[button]
	return p ~= nil and p.style ~= "classic"
end

local function Hinted(button)
	for _, lit in ipairs(ns.HintButtons and ns.HintButtons() or {}) do
		if lit == button then return true end
	end
	return false
end

-- true (a proc or a hint), "faint" (a class buff running out, Hints.lua) or false.
local function HasProc(button)
	if Hinted(button) then return true end
	if Actions.Proc(button) then return true end
	if ns.HintSoon and ns.HintSoon(button) then return "faint" end
	return false
end

-- (glows that come by other ways than the game's alert manager, an addon's library among them: looked for on
-- Glass and Round buttons a few times a second, cheap)
local glowLit = {} -- button -> lit at the last look
local function WatchGlows()
	for button, p in pairs(parts) do
		if p.style ~= "classic" then
			local on = HasProc(button)
			if on ~= (glowLit[button] or false) then
				glowLit[button] = on
				pcall(Proc, button, on)
			elseif on == true then
				-- (a glow the game or an addon showed again: back out of sight, only if it isn't already)
				PutAwayGlows(button, true)
			end
		elseif glowLit[button] then
			glowLit[button] = nil
			pcall(Proc, button, false)
		end
	end
end

-- (one breath for every glow: from full to BREATH_LOW and back, a sine, never restarted)
local BREATH_LOW, BREATH_TIME = 0.7, 2.4
local breathClock = 0
local function Breathe(elapsed)
	if not next(breathing) then return end
	breathClock = (breathClock + elapsed) % BREATH_TIME
	local wave = (math.cos(breathClock / BREATH_TIME * 2 * math.pi) + 1) / 2
	local alpha = BREATH_LOW + (1 - BREATH_LOW) * wave
	for part in pairs(breathing) do part:SetAlpha(alpha) end
end

-- (/serene debug glow: what the button under the mouse shows beyond its icon, to name a glow Serene doesn't know)
function ns.BarsGlowDump()
	local foci = _G.GetMouseFoci and Safe(_G.GetMouseFoci)
	local focus = type(foci) == "table" and foci[1] or (_G.GetMouseFocus and Safe(_G.GetMouseFocus))
	local button = focus
	while type(button) == "table" and not dressed[button] and button.GetParent do button = button:GetParent() end
	if not dressed[button] then return ns.Print("glow: put the mouse over an action button, then type this again") end
	local keys = {}
	for key, value in pairs(button) do if type(value) == "table" then keys[value] = tostring(key) end end
	local lines = {}
	local function Note(object, depth)
		local shown = Clean(Safe(object.IsShown, object))
		local alpha = Clean(Safe(object.GetAlpha, object))
		if not shown then return end
		local w, h = Clean(Safe(object.GetWidth, object)), Clean(Safe(object.GetHeight, object))
		local atlas = object.GetAtlas and Clean(Safe(object.GetAtlas, object))
		local texture = object.GetTexture and Clean(Safe(object.GetTexture, object))
		lines[#lines + 1] = ("%s%s %s %sx%s a%.2f %s"):format(("  "):rep(depth), keys[object] or (object.GetName and
			object:GetName()) or "?", tostring(Clean(Safe(object.GetObjectType, object))),
			type(w) == "number" and ("%.0f"):format(w) or "?", type(h) == "number" and ("%.0f"):format(h) or "?",
			type(alpha) == "number" and alpha or -1, tostring(atlas or texture or ""))
	end
	for _, region in ipairs({ button:GetRegions() }) do Note(region, 0) end
	for _, child in ipairs({ button:GetChildren() }) do
		Note(child, 0)
		for _, region in ipairs({ child:GetRegions() }) do Note(region, 1) end
	end
	ns.db.probeGlow = lines
	ns.Print(("glow: %s, %d shown parts (all in SereneDB.probeGlow after a /reload)"):format(
		tostring(button:GetName()), #lines))
	for index = 1, math.min(#lines, 14) do ns.Print("   " .. lines[index]) end
end

-- The game's cast animations shaped to the look. Each: the texture, the game's own mask on it (nil: none), the
-- frame holding it (a mask of Serene's is made in that same frame). Away on Glass and Round: what the game draws as
-- a square frame round the button (the interrupt's red frame, the reticle's base) and the burst at a cast's end.
local function CastParts(button)
	local cast, interrupt, reticle = rawget(button, "SpellCastAnimFrame"), rawget(button, "InterruptDisplay"),
		rawget(button, "TargetReticleAnimFrame")
	local clip, away = {}, {}
	local function Add(texture, mask, holder)
		if type(texture) == "table" and texture.AddMaskTexture and type(holder) == "table" and holder.CreateMaskTexture then
			clip[#clip + 1] = { texture = texture, mask = type(mask) == "table" and mask or nil, holder = holder }
		end
	end
	local fill = type(cast) == "table" and rawget(cast, "Fill")
	if type(fill) == "table" then
		Add(rawget(fill, "CastFill"), rawget(fill, "FillMask"), fill)
		Add(rawget(fill, "InnerGlowTexture"), nil, fill)
	end
	if type(cast) == "table" then away[#away + 1] = rawget(cast, "EndBurst") end
	local light = type(interrupt) == "table" and rawget(interrupt, "Highlight")
	if type(light) == "table" then Add(rawget(light, "HighlightTexture"), rawget(light, "Mask"), light) end
	if type(interrupt) == "table" then away[#away + 1] = rawget(interrupt, "Base") end
	if type(reticle) == "table" then
		Add(rawget(reticle, "Highlight"), rawget(reticle, "Mask"), reticle)
		away[#away + 1] = rawget(reticle, "Base")
	end
	return clip, away
end

local function CastShape(button, p, icon, style)
	if not p.cast then
		local clip, away = CastParts(button)
		p.cast = { clip = clip, away = away, masks = {} }
	end
	local mine = style ~= "classic"
	for _, entry in ipairs(p.cast.clip) do
		local mask = p.cast.masks[entry.holder]
		if not mask and mine then
			mask = entry.holder:CreateMaskTexture()
			p.cast.masks[entry.holder] = mask
		end
		if mask then
			pcall(entry.texture.RemoveMaskTexture, entry.texture, mask)
			if mine then
				if style == "round" then
					mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				else
					mask:SetTexture(FLAT, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				end
				mask:ClearAllPoints()
				mask:SetAllPoints(icon)
			end
		end
		if entry.mask then pcall(entry.texture.RemoveMaskTexture, entry.texture, entry.mask) end
		if mine then
			if mask then pcall(entry.texture.AddMaskTexture, entry.texture, mask) end
		elseif entry.mask then
			pcall(entry.texture.AddMaskTexture, entry.texture, entry.mask)
		end
	end
	for _, part in ipairs(p.cast.away) do
		if type(part) == "table" and part.SetAlpha then pcall(part.SetAlpha, part, mine and 0 or 1) end
	end
end

-- The look put on (out of a fight: masks and points). Classic gives back what the game had.
local function Look(button)
	local icon = Region(button, "icon") or Region(button, "Icon")
	if not icon then return end
	local style = StyleOf(button)
	local p = parts[button]
	if style == "classic" and not p then return end -- (never dressed otherwise: nothing to give back)
	p = Parts(button, icon)
	if p.style == style then return end
	p.style = style
	local gameMask = Region(button, "IconMask")
	local regions = Washes(button)
	table.insert(regions, 1, icon)
	local round = style == "round"
	for _, region in ipairs(regions) do
		if region.RemoveMaskTexture then
			-- (the game's rounded square: Classic's; the disc: Round's; Glass is square)
			if gameMask then pcall(region.RemoveMaskTexture, region, gameMask) end
			pcall(region.RemoveMaskTexture, region, p.mask)
			if style == "classic" and gameMask then pcall(region.AddMaskTexture, region, gameMask) end
			if round then pcall(region.AddMaskTexture, region, p.mask) end
		end
	end
	-- (Classic: the icon where the game had it, whole; Glass and Round: drawn in by the frame's width, its own
	-- border cut away, so the picture is as large as Classic's inside its frame)
	pcall(icon.ClearAllPoints, icon)
	if style == "classic" then
		if #p.iconPoints > 0 then
			for _, point in ipairs(p.iconPoints) do pcall(icon.SetPoint, icon, unpack(point)) end
		else
			pcall(icon.SetAllPoints, icon, button)
		end
		pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
	else
		local inset = (Clean(Safe(button.GetWidth, button)) or 45) * INSET
		pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", inset, -inset)
		pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
		pcall(icon.SetTexCoord, icon, CROP, 1 - CROP, CROP, 1 - CROP)
	end
	local px = ns.Pixel(button)
	local rim = ns.BAR_RIM * px
	local width = Clean(Safe(button.GetWidth, button)) or 45
	p.glow:ClearAllPoints()
	p.glow:SetPoint("CENTER", button, "CENTER")
	p.glow:SetSize(width * GLOW_SCALE, width * GLOW_SCALE)
	-- (the glow's bright line on the ring: the ring's radius over where the line sits in the texture)
	local ringSize = (width * (1 - 2 * INSET) / 2 + rim) / RING_AT
	p.ring:ClearAllPoints()
	p.ring:SetPoint("CENTER", icon, "CENTER")
	p.ring:SetSize(ringSize, ringSize)
	local halo = width * (1 - 2 * INSET) * HALO_SCALE
	p.halo:ClearAllPoints()
	p.halo:SetPoint("CENTER", icon, "CENTER")
	p.halo:SetSize(halo, halo)
	-- (Glass: the icon on a dark mat, the gold line round the mat, a dark pixel round the line)
	local mat = GLASS_MAT * px
	p.bg:ClearAllPoints()
	p.bg:SetPoint("TOPLEFT", icon, "TOPLEFT", -mat, mat)
	p.bg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", mat, -mat)
	p.edge:ClearAllPoints()
	p.edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -mat - px, mat + px)
	p.edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", mat + px, -mat - px)
	p.lines:Fit()
	p.outline:ClearAllPoints()
	p.outline:SetPoint("TOPLEFT", icon, "TOPLEFT", -mat - 2 * px, mat + 2 * px)
	p.outline:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", mat + 2 * px, -mat - 2 * px)
	p.outlineLines:Fit()
	p.rim:ClearAllPoints()
	p.rim:SetPoint("TOPLEFT", icon, "TOPLEFT", -rim, rim)
	p.rim:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", rim, -rim)
	p.dark:ClearAllPoints()
	p.dark:SetPoint("TOPLEFT", icon, "TOPLEFT", -rim - px, rim + px)
	p.dark:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", rim + px, -rim - px)
	pcall(CastShape, button, p, icon, style)
	Edge(button)
	Empty(button)
	glowLit[button] = HasProc(button)
	Proc(button, glowLit[button])
	if ns.CooldownLook then ns.CooldownLook(button) end
end

local function Dress(button)
	if dressed[button] then return end
	dressed[button] = true
	-- (the washes over the icon only, rounded like it where the game rounds its icons)
	local icon = Region(button, "icon") or Region(button, "Icon")
	local mask = Region(button, "IconMask")
	for _, key in ipairs({ "HighlightTexture", "PushedTexture", "CheckedTexture" }) do
		local get = button["Get" .. key]
		local texture = get and Safe(get, button)
		if texture and icon then
			texture:ClearAllPoints()
			texture:SetAllPoints(icon)
			if mask and texture.AddMaskTexture then pcall(texture.AddMaskTexture, texture, mask) end
		end
	end

	local key = Region(button, "HotKey")
	if key then
		local font, _, flags = key:GetFont()
		if font then pcall(key.SetFont, key, font, KEY_SIZE, flags ~= "" and flags or "OUTLINE") end
		key:ClearAllPoints()
		key:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -3)
		key:SetJustifyH("RIGHT")
	end
	local count = Region(button, "Count")
	if count then
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
		count:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
	end
	local name = Region(button, "Name")
	if name then
		name:ClearAllPoints()
		name:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 3)
		name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
		name:SetTextColor(SOFT[1], SOFT[2], SOFT[3], 0.8)
	end

	Art(button)
	Look(button)
	HearIcon(button)
	KeyText(button)
	-- (the game dresses its buttons again when the bar's art or the page changes)
	for _, method in ipairs({ "UpdateButtonArt", "UpdateHotkeys", "Update" }) do
		if type(button[method]) == "function" then
			hooksecurefunc(button, method, function(self) Art(self) end)
		end
	end
end

-- The bars' own art: their textures out of sight, never the buttons. A bar's children that are not buttons
-- (its end caps, its dividers) lose their textures too; the page arrows and the buttons are left alone.
local function Strip(frame)
	if type(frame) ~= "table" then return end
	if frame.GetObjectType and Safe(frame.GetObjectType, frame) == "Texture" then return Hide(frame) end
	if not frame.GetRegions then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then Hide(region) end
	end
end

local function StripBar(bar)
	if type(bar) ~= "table" or not bar.GetRegions then return end
	Strip(bar)
	for _, key in ipairs({ "BorderArt", "EndCaps", "Background", "BackgroundArt" }) do
		local part = bar[key]
		Strip(part)
		if type(part) == "table" and part.GetChildren then
			for _, child in ipairs({ part:GetChildren() }) do Strip(child) end
		end
	end
	for _, child in ipairs({ bar:GetChildren() }) do
		local kind = child.GetObjectType and child:GetObjectType()
		-- (the mouse's frames stay: Edit Mode's selection, the page arrows)
		if kind == "Frame" and not dressed[child] and child ~= bar.ActionBarPageNumber and child ~= bar.Selection
			and not (child.IsMouseEnabled and child:IsMouseEnabled())
			and not (child.GetNumChildren and child:GetNumChildren() > 0) then
			Strip(child)
		end
	end
end

local function Bars()
	for _, name in ipairs(BARS) do
		local bar = _G[name]
		if type(bar) == "table" then
			StripBar(bar)
			if not hooked[bar] then
				hooked[bar] = true
				-- (dividers come and go with the bar's layout)
				for _, method in ipairs({ "UpdateDividers", "UpdateGridLayout", "UpdateEndCaps", "UpdateVisibility" }) do
					if type(bar[method]) == "function" then
						hooksecurefunc(bar, method, function(self) StripBar(self) end)
					end
				end
			end
		end
	end
	for _, name in ipairs(OLD_ART) do Strip(_G[name]) end
end

local function Buttons()
	local list = {}
	for _, button in ipairs(Actions.Buttons(true)) do
		if button.CreateTexture then
			list[#list + 1] = button
			barOf[button] = Actions.BarOf(button)
		end
	end
	return list
end

local function DressAll()
	if InCombatLockdown() then
		waiting = true
		return
	end
	waiting = false
	for _, button in ipairs(Buttons()) do
		pcall(Dress, button)
		pcall(Look, button)
	end
	pcall(Bars)
end

-- Switches that change at once: the keys and the macro names.
local function Refresh()
	if not ns.db or not ns.db.actionBars then return end
	local fighting = InCombatLockdown()
	for button in pairs(dressed) do
		local name = Region(button, "Name")
		if name then name:SetAlpha(ns.On("barNames") and 1 or 0) end
		-- (a new look waits for the fight's end)
		if fighting then waiting = true else pcall(Look, button) end
		Empty(button)
	end
end

-- The key on a button again (BarKeys.lua: learnt, or being learnt): its colour and whether it shows.
function ns.BarsKey(button)
	if not dressed[button] then return end
	Empty(button)
	local key = Region(button, "HotKey")
	if key then
		-- (through the key's own hook, which picks Serene's colour: the game's red when far, else grey)
		if button.sereneFar then
			pcall(key.SetVertexColor, key, 1, 0.1, 0.1)
		else
			pcall(key.SetVertexColor, key, MUTED[1], MUTED[2], MUTED[3])
		end
	end
end

function ns.BarsEach(fn)
	for button in pairs(dressed) do pcall(fn, button, barOf[button]) end
end

-- Slots filled or emptied, a page turned, something picked up or put down: the empty slots looked at again
-- (a moment later, once the game has updated its buttons).
local function Slots()
	dragging = Clean(Safe(GetCursorInfo)) ~= nil
	for button in pairs(dressed) do pcall(Empty, button) end
end
local slotsQueued = false
local function QueueSlots()
	if slotsQueued then return end
	slotsQueued = true
	C_Timer.After(0, function()
		slotsQueued = false
		Slots()
	end)
end
local SLOT_EVENTS = { ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
	ACTIONBAR_SHOWGRID = true, ACTIONBAR_HIDEGRID = true, CURSOR_CHANGED = true, PET_BAR_UPDATE = true,
	UPDATE_SHAPESHIFT_FORMS = true, UPDATE_POSSESS_BAR = true, UPDATE_OVERRIDE_ACTIONBAR = true,
	PLAYER_ENTERING_WORLD = true }

local function Init()
	if not ns.On("actionBars") then return end
	-- (the game's own word on range, where it has the function: in range, out of range, or no range at all)
	if type(_G.ActionButton_UpdateRangeIndicator) == "function" then
		hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
			if not dressed[button] then return end
			checksRange, inRange = Clean(checksRange), Clean(inRange)
			SetFar(button, checksRange and inRange == false)
		end)
		rangeHooked = true
	end
	-- (procs: the game's glow shown or hidden on a button; Glass and Round light their own instead)
	local since = 0
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnUpdate", function(_, elapsed)
		Breathe(elapsed)
		since = since + elapsed
		if since < 0.2 then return end
		since = 0
		WatchGlows()
	end)
	local alerts = _G.ActionButtonSpellAlertManager
	if type(alerts) == "table" and type(alerts.ShowAlert) == "function" then
		hooksecurefunc(alerts, "ShowAlert", function(_, button) if dressed[button] then pcall(Proc, button, true) end end)
		hooksecurefunc(alerts, "HideAlert", function(_, button) if dressed[button] then pcall(Proc, button, false) end end)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "PET_BAR_UPDATE",
		"UPDATE_SHAPESHIFT_FORMS", "UPDATE_MULTI_CAST_ACTIONBAR" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for event in pairs(SLOT_EVENTS) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event)
		if SLOT_EVENTS[event] then QueueSlots() end
		if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
		if SLOT_EVENTS[event] and event ~= "PLAYER_ENTERING_WORLD" and event ~= "PET_BAR_UPDATE"
			and event ~= "UPDATE_SHAPESHIFT_FORMS" then return end
		DressAll()
	end)
	-- (Edit Mode moves and shows bars: dressed again once it closes)
	local manager = _G.EditModeManagerFrame
	if type(manager) == "table" and manager.HookScript then
		manager:HookScript("OnHide", function() C_Timer.After(0, DressAll) end)
	end
	DressAll()
end

function ns.BarsDebug()
	local count, missing = 0, {}
	for _ in pairs(dressed) do count = count + 1 end
	for _, name in ipairs(BARS) do
		if type(_G[name]) ~= "table" then missing[#missing + 1] = name end
	end
	ns.Print(("action bars: %s, %d buttons dressed%s"):format(tostring(ns.On("actionBars")), count,
		waiting and " (waiting for the fight's end)" or ""))
	if #missing > 0 then ns.Print("   bars not in this game: " .. table.concat(missing, ", ")) end
	local sample = _G.ActionButton1
	if type(sample) == "table" then
		local parts = {}
		for _, key in ipairs({ "icon", "IconMask", "NormalTexture", "SlotArt", "SlotBackground", "Border", "HotKey",
			"Name", "Count", "cooldown" }) do
			parts[#parts + 1] = key .. (Region(sample, key) and "+" or "-")
		end
		ns.Print("   ActionButton1: " .. table.concat(parts, " "))
	end
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
