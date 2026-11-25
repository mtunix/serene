local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- The game's toasts made calm. The "New Recipe Learned!" toast is the game's own frame, kept (its click still opens
-- the profession, its fade in and out still play); only its art is put away (the parchment box, the ornate ring, the
-- glow and the shine) and it is drawn again in Serene's way: a slim card of glass in a hairline of gold, the
-- profession's icon round at its left end (framed by a hairline of its own, the card coming out of it), "New Recipe
-- Learned!" said quietly above the recipe's name in gold.
-- The achievement toasts the same way (Forever's "Legacy Challenge Earned" is the game's achievement toast, its
-- title worded so; "Achievement Progress" too): the game's frames kept (a click still opens the achievements), the
-- parchment, the ornate icon frame, the shield and its banner put away; the achievement's icon round at the left
-- end, what was earned said quietly above its name in gold, its points (when it has any) a quiet number at the right.
-- Where the toasts appear: the game stacks every toast (recipes, achievements, loot won...) upward from one anchor
-- of its own (AlertFrame). Placed, that anchor is moved and kept there; the toasts stack from it as before.
-- /serene toasts on|off (a reload to switch), /serene toasts move (a sample to drag), /serene toasts reset,
-- /serene toasts test (a real recipe toast and a real achievement toast)

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local WIDTH, HEIGHT = 270, 40 -- the toast (the icon's round end included)
local ICON = 40               -- the icon's size with its rim: as tall as the card
local PAD = 10                -- between the icon and the words, and at the card's right end
local GAP = 10                -- between the anchor and the lowest toast (as the game stacks them)
local GLASS_ALPHA = 0.75
local GOLD = { 1, 0.82, 0.35 }
local INK = ns.INK
local MUTED = ns.MUTED_RGB
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_Food_15"
local ROUND = MEDIA .. "RoundMask"

-- (a round shape scaled smoothly, not snapped to the screen's pixel grid, which leaves its edge stepped)
local function Smooth(region)
	if region.SetSnapToPixelGrid then pcall(region.SetSnapToPixelGrid, region, false) end
	if region.SetTexelSnappingBias then pcall(region.SetTexelSnappingBias, region, 0) end
end

local dressed = {}   -- toast -> Serene's parts for it
local attic          -- a hidden frame holding the game's art put away
local original       -- the anchor's own place, before Serene moved it
local seen = {}      -- toast -> how it was drawn when last up (/serene debug)
local placing = false -- (Serene's own SetPoint on the anchor, not heard by its hook)
local mover          -- the sample toast /serene toasts move shows

local function IsTexture(region)
	return type(region) == "table" and region.IsObjectType and Safe(region.IsObjectType, region, "Texture") == true
end

local function IsText(region)
	return type(region) == "table" and region.IsObjectType and Safe(region.IsObjectType, region, "FontString") == true
end

-- The game's toast and its parts -----------------------------------------------------------------------------------

local RECIPE_TITLES = {}
for _, key in ipairs({ "NEW_RECIPE_LEARNED_TITLE", "UPGRADED_RECIPE_LEARNED_TITLE" }) do
	if type(_G[key]) == "string" then RECIPE_TITLES[_G[key]] = true end
end

-- The game's toast systems Serene dresses (each with a pool of frames it shows from).
local SYSTEMS = { "NewRecipeLearnedAlertSystem", "AchievementAlertSystem", "CriteriaAlertSystem" }

local function RecipeSystem()
	return type(_G.NewRecipeLearnedAlertSystem) == "table" and _G.NewRecipeLearnedAlertSystem or nil
end

local function InPool(system, frame)
	local pool = type(system) == "table" and system.alertFramePool
	if not pool then return false end
	if type(pool.activeObjects) == "table" and pool.activeObjects[frame] ~= nil then return true end
	return pool.IsActive and Clean(Safe(pool.IsActive, pool, frame)) and true or false
end

-- (a toast of one of those systems: one of their pools' frames, or one whose title says it is a recipe's; the
-- achievement toasts by their template's parts too: an icon frame with its texture, the shield, "Unlocked")
local function IsServed(frame)
	if type(frame) ~= "table" then return false end
	for _, key in ipairs(SYSTEMS) do
		if InPool(_G[key], frame) then return true end
	end
	local title = IsText(frame.Title) and Clean(Safe(frame.Title.GetText, frame.Title))
	if title and RECIPE_TITLES[title] then return true end
	return type(frame.Icon) == "table" and IsTexture(frame.Icon.Texture) and IsText(frame.Unlocked) and IsText(frame.Name)
		and true or false
end

-- The icon: the game's key for it (a texture, or the achievement's icon frame holding one), else a square texture
-- of icon size that isn't atlas art.
local function FindIcon(frame)
	if IsTexture(frame.Icon) then return frame.Icon end
	if type(frame.Icon) == "table" and IsTexture(frame.Icon.Texture) then return frame.Icon.Texture end
	for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
		if IsTexture(region) and not Clean(Safe(region.GetAtlas, region)) then
			local w, h = Clean(Safe(region.GetWidth, region)), Clean(Safe(region.GetHeight, region))
			if type(w) == "number" and type(h) == "number" and w >= 24 and w <= 72 and math.abs(w - h) < 2 then
				return region
			end
		end
	end
end

-- The two lines of words: the game's keys (an achievement's title is its "Unlocked"), else its font strings from the
-- top down.
local function FindTexts(frame)
	local title, name = frame.Title, frame.Name
	if not IsText(title) and IsText(frame.Unlocked) then title = frame.Unlocked end
	if IsText(title) and IsText(name) then return title, name end
	local texts = {}
	for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
		if IsText(region) and region ~= title and region ~= name then texts[#texts + 1] = region end
	end
	table.sort(texts, function(a, b) return (Clean(Safe(a.GetTop, a)) or 0) > (Clean(Safe(b.GetTop, b)) or 0) end)
	if not IsText(title) then title = table.remove(texts, 1) end
	if not IsText(name) then name = table.remove(texts, 1) end
	return title, name
end

-- The game's art put away: every texture of the toast and of its plain child frames, but the icon.
local function PutAway(frame, d, depth)
	if depth > 2 then return end
	attic = attic or CreateFrame("Frame")
	attic:Hide()
	for _, region in ipairs({ Safe(frame.GetRegions, frame) }) do
		if IsTexture(region) and region ~= d.icon and not d.own[region] then pcall(region.SetParent, region, attic) end
	end
	for _, child in ipairs({ Safe(frame.GetChildren, frame) }) do
		-- (a child that takes the mouse is the toast's click area: left where it is)
		if child ~= d.card and not Clean(Safe(child.IsMouseEnabled, child)) then PutAway(child, d, depth + 1) end
	end
end

-- Dressing a toast --------------------------------------------------------------------------------------------------

-- (a toast as drawn, for /serene debug: its parts, its icon (file, crop, size, layer, masks), the game's art left
-- showing)
local function Describe(frame, d)
	local title = d.title and Clean(Safe(d.title.GetText, d.title))
	local line = ("  %s: icon %s, title %s, name %s, points %s"):format(tostring(title), tostring(d.icon ~= nil),
		tostring(d.title ~= nil), tostring(d.name ~= nil), tostring(d.points ~= nil))
	local icon = d.icon
	if icon then
		local coords = { Safe(icon.GetTexCoord, icon) }
		for i, v in ipairs(coords) do coords[i] = type(v) == "number" and ("%.2f"):format(v) or tostring(v) end
		local w, h = Safe(icon.GetSize, icon)
		local layer, sub = Safe(icon.GetDrawLayer, icon)
		local holder = Safe(icon.GetParent, icon)
		line = line .. ("\n    icon: %s, crop %s, %sx%s, %s %s, masks %s (ours %s), parent %s"):format(
			tostring(Safe(icon.GetTexture, icon)), table.concat(coords, " "),
			tostring(w and math.floor(w + 0.5)), tostring(h and math.floor(h + 0.5)), tostring(layer), tostring(sub),
			tostring(Safe(icon.GetNumMaskTextures, icon)), tostring(d.mask ~= nil),
			tostring(holder and (Safe(holder.GetDebugName, holder) or "?")))
	end
	local left = {}
	local function Look(f, depth)
		if depth > 3 then return end
		for _, region in ipairs({ Safe(f.GetRegions, f) }) do
			if region ~= icon and not d.own[region] and Safe(region.IsVisible, region)
				and (IsTexture(region) or Safe(region.IsObjectType, region, "MaskTexture")) then
				local rw, rh = Safe(region.GetSize, region)
				left[#left + 1] = ("%s %s %sx%s"):format(tostring(Safe(region.GetObjectType, region)),
					tostring(Safe(region.GetAtlas, region) or Safe(region.GetTexture, region)),
					tostring(rw and math.floor(rw + 0.5)), tostring(rh and math.floor(rh + 0.5)))
			end
		end
		for _, child in ipairs({ Safe(f.GetChildren, f) }) do
			if child ~= d.card then Look(child, depth + 1) end
		end
	end
	Look(frame, 0)
	return line .. "\n    art still showing: " .. (#left > 0 and table.concat(left, ", ") or "none")
end

local function Layout(frame, d)
	pcall(frame.SetSize, frame, WIDTH, HEIGHT)
	local level = Clean(Safe(frame.GetFrameLevel, frame)) or 1
	pcall(d.card.SetFrameLevel, d.card, math.max(0, level - 1)) -- (under the toast's own icon and words)
	local px = ns.Pixel(frame)
	d.card:ClearAllPoints()
	d.card:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON / 2, 0)
	d.card:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	d.card.lines:Fit()
	local ground, notch = d.card.ground, d.card.notch
	ground:ClearAllPoints()
	ground:SetPoint("BOTTOMRIGHT", d.card, "BOTTOMRIGHT")
	if d.icon then
		notch:ClearAllPoints()
		notch:SetPoint("TOPLEFT", d.card, "TOPLEFT")
		notch:SetPoint("BOTTOMLEFT", d.card, "BOTTOMLEFT")
		notch:SetWidth(ICON / 2)
		notch:Show()
		ground:SetPoint("TOPLEFT", d.card, "TOPLEFT", ICON / 2, 0)
		d.card.lines.left:Hide() -- (the rim closes the card at the icon)
		-- (the top and bottom lines begin where they meet the rim's curve, never crossing into the round)
		local r, edge = ICON / 2, ICON / 2 - px
		local from = math.floor(math.sqrt(math.max(0, r * r - edge * edge)))
		local lines = d.card.lines
		lines.top:SetPoint("TOPLEFT", d.card, "TOPLEFT", from, 0)
		lines.bottom:SetPoint("BOTTOMLEFT", d.card, "BOTTOMLEFT", from, 0)
	else
		notch:Hide()
		ground:SetPoint("TOPLEFT", d.card, "TOPLEFT")
		d.card.lines.left:Show()
	end

	local icon = d.icon
	if icon then
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetPoint, icon, "CENTER", frame, "LEFT", ICON / 2, 0)
		Smooth(icon)
		pcall(icon.SetSize, icon, ICON - 2 * px, ICON - 2 * px)
		pcall(icon.SetTexCoord, icon, 0.1, 0.9, 0.1, 0.9) -- (past the light bevel round the game's icons)
		if not d.mask then pcall(icon.SetMask, icon, ROUND) end -- (no mask object on this client: the old way)
		pcall(icon.SetAlpha, icon, 1)
		pcall(icon.Show, icon)
		-- (round it, a pixel larger: a hollow rim of gold, only its edge outside the icon; rim and icon kept within
		-- the toast's own height, as the game's recipe toast cuts away whatever reaches outside it)
		d.ring:ClearAllPoints()
		d.ring:SetPoint("CENTER", frame, "LEFT", ICON / 2, 0)
		d.ring:SetSize(ICON, ICON)
		d.ring:Show()
	else
		d.ring:Hide()
	end

	local left = icon and ICON + PAD or PAD
	local right = PAD
	-- an achievement's points: a quiet number at the right end (none: nothing there, the words reach the end)
	local points = d.points
	if points then
		local text = Clean(Safe(points.GetText, points))
		local shown = Clean(Safe(points.IsShown, points))
		if type(text) == "string" and text ~= "" and text ~= "0" and shown ~= false then
			pcall(points.SetFontObject, points, "GameFontHighlightSmall")
			pcall(points.SetTextColor, points, MUTED[1], MUTED[2], MUTED[3])
			pcall(points.SetShadowOffset, points, 0, 0)
			pcall(points.SetJustifyH, points, "RIGHT")
			pcall(points.ClearAllPoints, points)
			pcall(points.SetPoint, points, "RIGHT", frame, "RIGHT", -PAD, 0)
			pcall(points.SetAlpha, points, 1)
			local w = Clean(Safe(points.GetStringWidth, points))
			right = PAD + (type(w) == "number" and math.ceil(w) or 14) + 8
		else
			pcall(points.SetAlpha, points, 0)
		end
	end
	for _, text in ipairs(d.hush) do pcall(text.SetAlpha, text, 0) end
	local title, name = d.title, d.name
	if title then
		pcall(title.SetFontObject, title, "GameFontHighlightSmall")
		pcall(title.SetTextColor, title, MUTED[1], MUTED[2], MUTED[3])
		pcall(title.SetJustifyH, title, "LEFT")
		pcall(title.SetShadowOffset, title, 0, 0)
		pcall(title.ClearAllPoints, title)
		pcall(title.SetPoint, title, "TOPLEFT", frame, "TOPLEFT", left, -7)
		pcall(title.SetPoint, title, "TOPRIGHT", frame, "TOPRIGHT", -right, -7)
		pcall(title.SetHeight, title, 12)
		pcall(title.SetAlpha, title, 1)
	end
	if name then
		pcall(name.SetFontObject, name, "GameFontNormal")
		pcall(name.SetTextColor, name, GOLD[1], GOLD[2], GOLD[3])
		pcall(name.SetJustifyH, name, "LEFT")
		pcall(name.SetJustifyV, name, "MIDDLE")
		if name.SetMaxLines then pcall(name.SetMaxLines, name, 1) end
		if name.SetWordWrap then pcall(name.SetWordWrap, name, false) end
		pcall(name.ClearAllPoints, name)
		pcall(name.SetPoint, name, "BOTTOMLEFT", frame, "BOTTOMLEFT", left, 7)
		pcall(name.SetPoint, name, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -right, 7)
		pcall(name.SetHeight, name, 14)
		pcall(name.SetAlpha, name, 1)
		-- (a long achievement's name a size smaller rather than cut)
		if Clean(Safe(name.IsTruncated, name)) then pcall(name.SetFontObject, name, "GameFontNormalSmall") end
	end
	PutAway(frame, d, 0) -- (again: art a toast only makes when shown)
	-- (a snapshot for /serene debug: a toast is gone before a command can be typed)
	if frame ~= mover and C_Timer and C_Timer.After then
		C_Timer.After(0.5, function()
			if Safe(frame.IsVisible, frame) then seen[frame] = Describe(frame, d) end
		end)
	end
end

local function Dress(frame)
	local d = dressed[frame]
	if not d then
		d = { own = {} }
		d.icon = FindIcon(frame)
		d.title, d.name = FindTexts(frame)
		-- an achievement's points (on its shield), and words of its art that would float on the card (a guild's name)
		local shield = type(frame.Shield) == "table" and frame.Shield
		d.points = shield and IsText(shield.Points) and shield.Points or nil
		d.hush = {}
		for _, key in ipairs({ "GuildName" }) do
			if IsText(frame[key]) and frame[key] ~= d.title and frame[key] ~= d.name then d.hush[#d.hush + 1] = frame[key] end
		end
		-- the card: glass in a hairline of gold, under the toast's own icon and words
		d.card = CreateFrame("Frame", nil, frame)
		d.card:EnableMouse(false)
		d.card.ground = d.card:CreateTexture(nil, "BACKGROUND")
		d.card.ground:SetColorTexture(INK[1], INK[2], INK[3], GLASS_ALPHA)
		-- (its left end, under the icon's right half: glass cut round, so nothing lies under the icon and its rim, and
		-- a fading toast stays one thing rather than showing its layers through each other)
		d.card.notch = d.card:CreateTexture(nil, "BACKGROUND")
		d.card.notch:SetTexture(MEDIA .. "ToastNotch")
		d.card.notch:SetVertexColor(INK[1], INK[2], INK[3], GLASS_ALPHA)
		Smooth(d.card.notch)
		d.card.lines = ns.Hairline(d.card)
		-- the rim round the icon, in the icon's own layer just under it
		local layer, sublevel = "ARTWORK", 0
		if d.icon then
			local l, s = Safe(d.icon.GetDrawLayer, d.icon)
			layer, sublevel = Clean(l) or layer, Clean(s) or sublevel
		end
		d.ring = frame:CreateTexture(nil, layer, nil, math.max(-8, sublevel - 1)) -- (-8: the lowest sublevel there is)
		d.ring:SetTexture(MEDIA .. "Ring")
		Smooth(d.ring)
		d.ring:SetVertexColor(ns.LINE[1], ns.LINE[2], ns.LINE[3], ns.LINE[4])
		d.own[d.ring] = true
		-- the icon made round by a mask of the icon's own frame, laid over it (the game's way for round portraits)
		local holder = d.icon and Safe(d.icon.GetParent, d.icon)
		if holder and holder.CreateMaskTexture and d.icon.AddMaskTexture then
			local ok, mask = pcall(holder.CreateMaskTexture, holder)
			if ok and mask then
				mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				mask:SetAllPoints(d.icon)
				Smooth(mask)
				if pcall(d.icon.AddMaskTexture, d.icon, mask) then d.mask = mask end
				d.own[mask] = true
			end
		end
		dressed[frame] = d
		-- (pooled: the same frame comes back for a later toast, its parts set up anew by the game)
		if frame.HookScript then
			frame:HookScript("OnShow", function(self) if dressed[self] then pcall(Layout, self, dressed[self]) end end)
		end
	end
	Layout(frame, d)
	return d
end

local function Sweep()
	if not ns.On("toast") then return end
	for _, key in ipairs(SYSTEMS) do
		local system = _G[key]
		local pool = type(system) == "table" and system.alertFramePool
		if pool and pool.EnumerateActive then
			for frame in pool:EnumerateActive() do pcall(Dress, frame) end
		end
	end
end

-- Where the toasts appear --------------------------------------------------------------------------------------------

local function Anchor() return type(_G.AlertFrame) == "table" and _G.AlertFrame or nil end

-- (a place in UIParent's units -> in the anchor's own)
local function Ratio(frame)
	local outer = Clean(Safe(UIParent.GetEffectiveScale, UIParent)) or 1
	local own = Clean(Safe(frame.GetEffectiveScale, frame)) or outer
	return own > 0 and outer / own or 1
end

local function Place()
	local anchor, at = Anchor(), ns.db and ns.db.toastAt
	if not anchor then return end
	if type(at) ~= "table" or type(at.x) ~= "number" or type(at.y) ~= "number" then
		if original and original.moved then -- (placed and then reset: the game's own place back)
			placing = true
			pcall(anchor.ClearAllPoints, anchor)
			for _, point in ipairs(original) do pcall(anchor.SetPoint, anchor, unpack(point)) end
			placing = false
			original.moved = false
		end
		return
	end
	if not original then
		original = {}
		for i = 1, (Clean(Safe(anchor.GetNumPoints, anchor)) or 0) do
			original[#original + 1] = { Safe(anchor.GetPoint, anchor, i) }
		end
	end
	local ratio = Ratio(anchor)
	placing = true
	pcall(anchor.ClearAllPoints, anchor)
	pcall(anchor.SetPoint, anchor, "TOP", UIParent, "BOTTOM", at.x * ratio, (at.y - GAP) * ratio)
	placing = false
	original.moved = true
end

-- (where the lowest toast sits now, in UIParent's units: { x from the middle, y from the bottom })
local function Current()
	local at = ns.db.toastAt
	if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number" then return at.x, at.y end
	local anchor = Anchor()
	local top = anchor and Clean(Safe(anchor.GetTop, anchor))
	local cx = anchor and Clean(Safe(anchor.GetCenter, anchor))
	if type(top) == "number" and type(cx) == "number" then
		local scale = 1 / Ratio(anchor)
		return cx * scale - UIParent:GetWidth() / 2, top * scale + GAP
	end
	return 0, UIParent:GetHeight() * 0.25
end

local function Mover()
	if mover then return mover end
	mover = CreateFrame("Button", nil, UIParent)
	mover:SetFrameStrata("DIALOG")
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:RegisterForClicks("RightButtonUp")
	mover.Icon = mover:CreateTexture(nil, "ARTWORK")
	mover.Icon:SetTexture(SAMPLE_ICON)
	mover.Title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mover.Title:SetText(type(NEW_RECIPE_LEARNED_TITLE) == "string" and NEW_RECIPE_LEARNED_TITLE or "New Recipe Learned!")
	mover.Name = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mover.Name:SetText("Where toasts appear")
	mover.hint = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mover.hint:SetPoint("TOP", mover, "BOTTOM", ICON / 4, -6) -- (under the card, which begins at the icon's middle)
	mover.hint:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
	mover.hint:SetText("Drag: move.  Right click: done.")
	Dress(mover)
	local d = dressed[mover]
	-- (a soft pulse of its hairline while it waits to be placed)
	local t = 0
	mover:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		local a = ns.LINE[4] + (0.9 - ns.LINE[4]) * (0.5 + 0.5 * math.sin(t * 3))
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			d.card.lines[side]:SetColorTexture(ns.LINE[1], ns.LINE[2], ns.LINE[3], a)
		end
		d.ring:SetVertexColor(ns.LINE[1], ns.LINE[2], ns.LINE[3], a)
	end)
	mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
	mover:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- (its place kept in toastAt, not in the game's own layout cache)
		if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
		local cx, bottom = self:GetCenter(), self:GetBottom()
		if cx and bottom then
			ns.db.toastAt = { x = math.floor(cx - UIParent:GetWidth() / 2 + 0.5), y = math.floor(bottom + 0.5) }
			self:ClearAllPoints()
			self:SetPoint("BOTTOM", UIParent, "BOTTOM", ns.db.toastAt.x, ns.db.toastAt.y)
			Place()
		end
	end)
	mover:SetScript("OnClick", function(self) self:Hide() end)
	mover:Hide()
	return mover
end

function ns.ToastMove()
	local m = Mover()
	if m:IsShown() then return m:Hide() end
	local x, y = Current()
	m:ClearAllPoints()
	m:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
	m:Show()
	ns.Print("toasts: drag the sample where they should appear; right click it when done.")
end

function ns.ToastReset()
	ns.db.toastAt = nil
	Place()
	if mover and mover:IsShown() then
		local x, y = Current()
		mover:ClearAllPoints()
		mover:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
	end
	ns.Print("toasts: where the game puts them")
end

-- (an achievement you have earned: the latest the game lists, else the first earned found through its categories,
-- Forever's Legacy Challenges among them; the latest list comes back empty on Forever)
local function EarnedAchievement()
	local latest = Clean(Safe(_G.GetLatestCompletedAchievements, true))
	if type(latest) == "number" then return latest end
	latest = Clean(Safe(_G.GetLatestCompletedAchievements))
	if type(latest) == "number" then return latest end
	local categories = { Safe(_G.GetCategoryList) }
	if type(categories[1]) == "table" then categories = categories[1] end
	for _, category in ipairs(categories) do
		local count = Clean(Safe(_G.GetCategoryNumAchievements, category, true))
		for i = 1, (type(count) == "number" and count or 0) do
			local id, _, _, completed = Safe(_G.GetAchievementInfo, category, i)
			if type(Clean(id)) == "number" and Clean(completed) then return id end
		end
	end
end

-- (real toasts, to see them: a recipe, Charred Wolf Meat, known to nearly every cook; and an achievement you earned)
function ns.ToastTest()
	local system = RecipeSystem()
	if not (system and system.AddAlert) then
		ns.Print("toasts: the game's recipe toast isn't there")
	elseif not pcall(system.AddAlert, system, 2538) then
		ns.Print("toasts: the game wouldn't show a sample recipe (it shows only recipes you know)")
	end
	local achievements = _G.AchievementAlertSystem
	if not (type(achievements) == "table" and achievements.AddAlert) then
		return ns.Print("toasts: the game's achievement toast isn't there")
	end
	local id = EarnedAchievement()
	if type(id) ~= "number" then
		return ns.Print("toasts: no earned achievement found to show")
	end
	-- (the game loads its achievements window before it shows one of their toasts: the toast borrows its code)
	if not _G.AchievementFrame then Safe(_G.AchievementFrame_LoadUI) end
	local ok, err = pcall(achievements.AddAlert, achievements, id, true) -- (true: earned before)
	local name = Clean(select(2, Safe(_G.GetAchievementInfo, id)))
	if ok then
		ns.Print(("toasts: sample achievement %s (%d)"):format(tostring(name or "?"), id))
	else
		ns.Print(("toasts: the game wouldn't show achievement %d: %s"):format(id, tostring(err)))
	end
end

-- The recipe toast's icon unbaked ---------------------------------------------------------------------------------
-- The game rounds the recipe toast's icon its old way (SetMask): the icon baked, its light border and all, into a round
-- copy ("mask9"), a picture Serene's crop can't reach into, the border showing as a pale line inside the rim. Undone:
-- the game's mask taken off, the profession's icon put back plain, Serene's own crop and round laid on it.

-- (a recipe's icon: its profession's, as the game shows it; else the recipe's own)
local function RecipeIcon(recipeID)
	if type(recipeID) ~= "number" then return end
	local trade = _G.C_TradeSkillUI
	if type(trade) == "table" then
		local line, _, parent = Safe(trade.GetTradeSkillLineForRecipe, recipeID)
		local skill = Clean(parent) or Clean(line)
		local file = skill and Clean(Safe(trade.GetTradeSkillTexture, skill))
		if file then return file end
	end
	local file = type(_G.C_Spell) == "table" and Clean(Safe(_G.C_Spell.GetSpellTexture, recipeID))
	return file or Clean(Safe(_G.GetSpellTexture, recipeID))
end

local function Baked(icon)
	local file = Clean(Safe(icon.GetTexture, icon))
	return type(file) == "string" and file:lower():find("^mask") ~= nil
end

local function Unbake(frame, file)
	local d = dressed[frame]
	local icon = d and d.icon
	if not (icon and Baked(icon)) then return end
	pcall(icon.SetMask, icon, "")
	if file then pcall(icon.SetTexture, icon, file) end
	pcall(Layout, frame, d)
end

-- Hooks --------------------------------------------------------------------------------------------------------------

local function Init()
	local anchor = Anchor()
	if anchor then
		-- (the game moves the anchor back now and then: placed again at once)
		hooksecurefunc(anchor, "SetPoint", function()
			if not placing and ns.db.toastAt then Place() end
		end)
		if anchor.AddAlertFrame then
			hooksecurefunc(anchor, "AddAlertFrame", function(_, frame)
				if ns.On("toast") and IsServed(frame) then pcall(Dress, frame) end
			end)
		end
	end
	for _, key in ipairs(SYSTEMS) do
		local system = _G[key]
		if type(system) == "table" then
			for _, method in ipairs({ "AddAlert", "ShowAlert" }) do
				if type(system[method]) == "function" then hooksecurefunc(system, method, Sweep) end
			end
		end
	end
	-- (a recipe toast just set up, its recipe known: its icon unbaked)
	local recipes = RecipeSystem()
	if recipes then
		for _, method in ipairs({ "AddAlert", "ShowAlert" }) do
			if type(recipes[method]) == "function" then
				hooksecurefunc(recipes, method, function(system, recipeID)
					local pool = system.alertFramePool
					if not (ns.On("toast") and pool and pool.EnumerateActive) then return end
					local file = RecipeIcon(recipeID)
					for frame in pool:EnumerateActive() do pcall(Unbake, frame, file) end
				end)
			end
		end
	end
	Place()
end

function ns.ToastsDebug()
	local anchor = Anchor()
	local point = anchor and { Safe(anchor.GetPoint, anchor, 1) } or {}
	-- (each toast up now, else as it was when last up)
	local lines = {}
	for frame, d in pairs(dressed) do
		if frame ~= mover and Safe(frame.IsVisible, frame) then
			lines[#lines + 1] = Describe(frame, d)
		elseif seen[frame] then
			lines[#lines + 1] = seen[frame]
		end
	end
	local parts = #lines > 0 and ("\n" .. table.concat(lines, "\n")) or "none yet"
	local systems = {}
	for _, key in ipairs(SYSTEMS) do
		local system = _G[key]
		local found = type(system) == "table" and (system.alertFramePool and "found" or "found, no pool") or "|cffff8080not found|r"
		systems[#systems + 1] = key:gsub("AlertSystem$", "") .. " " .. found
	end
	ns.Print(("toasts: %s, anchor %s (%s %s %s), systems: %s, placed %s, toasts: %s"):format(
		tostring(ns.On("toast")), anchor and "found" or "|cffff8080not found|r",
		tostring(point[1]), tostring(Clean(point[4]) and math.floor(point[4])), tostring(Clean(point[5]) and math.floor(point[5])),
		table.concat(systems, ", "),
		ns.db.toastAt and (ns.db.toastAt.x .. ", " .. ns.db.toastAt.y) or "no", parts))
end

table.insert(ns.modules, { init = Init, refresh = Place })
