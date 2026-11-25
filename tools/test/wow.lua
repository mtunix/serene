-- A stub of the game for Serene's tests: just enough of the client for the addon's files to load, build their frames
-- and run their logic outside the game. Run by tools/test/run.py under Lua 5.1 (the game's own Lua).
--
-- What it is not: a model of the game. Frames keep their state (size, points, shown, alpha, text...) and report it
-- back, but nothing is drawn and layout is crude. Every API answers from the `wow` table below, which a test fills in
-- (wow.bags, wow.items, wow.cvars, wow.combat...). A global the stub doesn't define reads as nil, as on a client that
-- lacks it; wow.missing records each one the addon looked up.
--
-- Secret values (the game hides some values in a fight): wow.secret(v) makes one. Like the game's, it errors on
-- arithmetic, ordering (<, >), indexing, calling and #; concatenating gives another secret; type() says what it hides;
-- issecretvalue() says true. Unlike the game's, == and truth tests can't be made to error in plain Lua: a test can't
-- catch those.

local wow = {}
_G.wow = wow

wow.root = SERENE_ROOT -- the addon's folder (set by run.py)
wow.errors = {}        -- errors caught in scripts, timers and hooks: { where, message }
wow.printed = {}       -- every line added to a chat frame
wow.missing = {}       -- globals looked up that the stub doesn't define: name -> count
wow.now = 1000         -- GetTime()
wow.combat = false     -- InCombatLockdown() and UnitAffectingCombat("player")
local regenDisabling = false -- (wow.fight: in the fight, but not locked down yet)
wow.money = 123456
wow.cvars = { showSwingTimer = "1", countdownForCooldowns = "1", showTimestamps = "none", nameplateShowAll = "1" }
wow.player = { name = "Tester", realm = "Testrealm", class = "Warrior", classFile = "WARRIOR", classID = 1, level = 60,
	race = "Human", raceFile = "Human", sex = 2, guid = "Player-1-00000001", faction = "Alliance" }

local realType = type -- (the real one: the stub's own, below, answers for secrets)
local unpack = unpack

local function trace(message)
	return debug.traceback(tostring(message), 2)
end

-- Run a piece of the addon the way the game would (a script, a timer, a hook): an error is kept, not raised.
function wow.call(where, fn, ...)
	local args, n = { ... }, select("#", ...)
	local ok, problem = xpcall(function() return fn(unpack(args, 1, n)) end, trace)
	if not ok then table.insert(wow.errors, { where = where, message = problem }) end
	return ok
end

-- Secret values ----------------------------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" }) -- proxy -> { value } (weak: a secret no one holds is forgotten)
local secretMeta = {}

local function secretError(what)
	return function() error("attempt to " .. what .. " a secret value", 2) end
end
secretMeta.__add = secretError("perform arithmetic on")
secretMeta.__sub = secretMeta.__add
secretMeta.__mul = secretMeta.__add
secretMeta.__div = secretMeta.__add
secretMeta.__mod = secretMeta.__add
secretMeta.__pow = secretMeta.__add
secretMeta.__unm = secretMeta.__add
secretMeta.__lt = secretError("compare")
secretMeta.__le = secretMeta.__lt
secretMeta.__index = secretError("index")
secretMeta.__newindex = secretMeta.__index
secretMeta.__call = secretError("call")
secretMeta.__len = secretError("get the length of")
secretMeta.__concat = function(a, b) return wow.secret("") end
secretMeta.__tostring = function() return "<secret>" end

-- (userdata, not tables: Lua 5.1 honours __len only on userdata, and pairs or rawget can't look inside one)
local template = newproxy(true)
for key, value in pairs(secretMeta) do getmetatable(template)[key] = value end

function wow.secret(value)
	local proxy = newproxy(template)
	secrets[proxy] = { value = value }
	return proxy
end

function wow.isSecret(value) return secrets[value] ~= nil end
function wow.reveal(value)
	local secret = secrets[value]
	if secret then return secret.value end -- (a secret false is false, not the secret itself)
	return value
end

_G.issecretvalue = function(value) return secrets[value] ~= nil end
_G.type = function(value)
	local s = secrets[value]
	if s then return realType(s.value) end
	return realType(value)
end
local type = _G.type -- (from here on the stub, too, sees the type a secret hides)
-- (the game's tostring/tonumber pass a secret on as a secret)
local realToString, realToNumber = tostring, tonumber
_G.tostring = function(value) if secrets[value] then return wow.secret("") end return realToString(value) end
_G.tonumber = function(value, base) if secrets[value] then return value end return realToNumber(value, base) end
-- (math on a secret errors, as arithmetic does)
for _, name in ipairs({ "max", "min", "floor", "ceil", "abs", "fmod", "sqrt" }) do
	local fn = math[name]
	math[name] = function(...)
		for index = 1, select("#", ...) do
			if secrets[(select(index, ...))] then error("bad argument to math." .. name .. ": secret value", 2) end
		end
		return fn(...)
	end
end

-- Lua extensions the game has -----------------------------------------------------------------------------------------

_G.strtrim = function(s, chars)
	chars = chars and ("[" .. chars:gsub("[%]%%%^%-]", "%%%0") .. "]") or "%s"
	return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end
_G.strsplit = function(sep, s, limit)
	local out, start = {}, 1
	while true do
		if limit and #out == limit - 1 then break end
		local a, b = s:find(sep, start, true)
		if not a then break end
		out[#out + 1] = s:sub(start, a - 1)
		start = b + 1
	end
	out[#out + 1] = s:sub(start)
	return unpack(out)
end
_G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
_G.strlower, _G.strupper, _G.strlen, _G.strsub, _G.strfind, _G.strmatch, _G.gsub, _G.format =
	string.lower, string.upper, string.len, string.sub, string.find, string.match, string.gsub, string.format
_G.strrep, _G.strbyte, _G.strchar, _G.gmatch = string.rep, string.byte, string.char, string.gmatch
_G.tinsert, _G.tremove, _G.sort, _G.tContains = table.insert, table.remove, table.sort, function(t, v)
	for _, x in pairs(t) do if x == v then return true end end
	return false
end
_G.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
table.wipe = _G.wipe
_G.floor, _G.ceil, _G.abs, _G.max, _G.min, _G.mod = math.floor, math.ceil, math.abs, math.max, math.min, math.fmod
_G.date, _G.time = os.date, os.time
-- (Lua 5.1 has no bit operators: band and bor done by halving)
_G.bit = { band = function(a, b)
	local r, bitv = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
		a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
	end
	return r
end, bor = function(a, b)
	local r, bitv = 0, 1
	while a > 0 or b > 0 do
		if a % 2 == 1 or b % 2 == 1 then r = r + bitv end
		a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
	end
	return r
end }

-- Frames ---------------------------------------------------------------------------------------------------------------

local frames = {}  -- every widget made, in order
local eventFrames = {} -- frame -> { event = true }
local allEvents = setmetatable({}, { __mode = "k" }) -- frame -> true (RegisterAllEvents)
wow.frames = frames

local Widget = {}
local WidgetMeta = {}

-- The verbs a widget method starts with: an unknown method with one of these is a quiet no-op (it records the call),
-- so frame.Icon (a child key) still reads nil but frame:SetSomethingNew() works.
local VERBS = { "Set", "Clear", "Enable", "Disable", "Register", "Unregister", "Hook", "Add", "Remove", "Play", "Stop",
	"Start", "Lock", "Unlock", "Raise", "Lower", "Adjust", "Scroll", "Highlight", "Reset", "Release", "Refresh",
	"Pause", "Restart", "Finish", "Highlight", "Insert", "Toggle", "Click", "Update", "Apply", "Fit", "Layout",
	"Mark", "Flash", "Cancel", "Get", "Is", "Has", "Can", "Should", "Does" }

-- (the verb, then a capital: SetAlpha is a call, Settings is not)
local function isVerb(key)
	if type(key) ~= "string" then return false end
	for _, verb in ipairs(VERBS) do
		if key:sub(1, #verb) == verb and key:sub(#verb + 1, #verb + 1):match("[A-Z%z]") then return true end
	end
	return false
end

-- (so a part whose key starts with a verb, frame.CancelButton, reads as a method: anything done with it then says so,
-- rather than only "attempt to index a function value". Functions share one metatable in Lua 5.1: no function is
-- ever meant to be indexed, so nothing else changes.)
debug.setmetatable(function() end, { __index = function(_, key)
	error(("a function indexed (.%s): a frame's part read as a method? A key starting with a verb and a capital is "
		.. "one in the stub: make the part in the stub or the spec"):format(tostring(key)), 2)
end })

WidgetMeta.__index = function(self, key)
	local method = Widget[key]
	if method ~= nil then return method end
	if isVerb(key) then
		-- (a getter the stub doesn't know answers nil; a setter is remembered)
		return function(widget, ...)
			local calls = rawget(widget, "_calls")
			if calls then calls[#calls + 1] = { key, ... } end
		end
	end
	return nil
end

local nextId = 0
local function New(kind, name, parent, templates)
	nextId = nextId + 1
	local w = setmetatable({}, WidgetMeta)
	-- (the widget's state, kept apart from the fields the addon sets on it)
	rawset(w, "_s", { kind = kind, name = name, parent = parent, shown = true, alpha = 1, scale = 1, width = 0,
		height = 0, points = {}, scripts = {}, hooks = {}, children = {}, regions = {}, attributes = {},
		level = parent and parent._s and (parent._s.level + 1) or 1, strata = "MEDIUM", text = nil, id = 0,
		templates = templates or "", serial = nextId, mouse = false })
	rawset(w, "_calls", {}) -- (the unknown verbs called on it: wow.calls)
	if name then
		-- ("$parent" in a name stands for the parent's name, as in the game's templates)
		if parent and name:find("$parent", 1, true) then
			name = name:gsub("%$parent", parent:GetName() or "")
			w._s.name = name
		end
		_G[name] = w
	end
	frames[#frames + 1] = w
	return w
end
wow.NewWidget = New

local function S(w) return rawget(w, "_s") end

function Widget:GetObjectType() return S(self).kind end
-- (the game's widget kinds, roughly: everything is a Region; textures, font strings and animations aren't Frames)
function Widget:IsObjectType(kind)
	local mine = S(self).kind
	if mine == kind then return true end
	if kind == "Region" or kind == "ScriptObject" or kind == "Object" then return true end
	if kind == "Frame" then
		return mine ~= "Texture" and mine ~= "FontString" and mine ~= "MaskTexture" and mine ~= "Line"
			and mine ~= "AnimationGroup" and mine ~= "Animation" and mine ~= "Alpha" and mine ~= "Scale"
	end
	if kind == "Button" then return mine == "CheckButton" end
	if kind == "Texture" then return mine == "MaskTexture" end
	return false
end
function Widget:GetName() return S(self).name end
function Widget:GetDebugName() return S(self).name or ("<" .. S(self).kind .. ">") end
function Widget:GetParent() return S(self).parent end
function Widget:SetParent(parent)
	local s = S(self)
	if s.parent and S(s.parent) then
		local list = (s.kind == "Texture" or s.kind == "FontString") and S(s.parent).regions or S(s.parent).children
		for index, item in ipairs(list) do if item == self then table.remove(list, index) break end end
	end
	s.parent = parent
	if parent and S(parent) then
		local list = (s.kind == "Texture" or s.kind == "FontString" or s.kind == "MaskTexture")
			and S(parent).regions or S(parent).children
		list[#list + 1] = self
	end
end
function Widget:GetChildren() return unpack(S(self).children) end
function Widget:GetNumChildren() return #S(self).children end
function Widget:GetRegions() return unpack(S(self).regions) end
function Widget:GetNumRegions() return #S(self).regions end
function Widget:IsForbidden() return false end
function Widget:IsProtected() return S(self).protected or false, S(self).protected or false end
function Widget:CanChangeProtectedState() return not InCombatLockdown() end

-- shown / alpha / scale
-- (OnShow and OnHide on this widget only: unlike the game, its children hear nothing when it changes)
function Widget:Show()
	local s = S(self)
	if s.shown then return end
	s.shown = true
	if self:IsVisible() then self:_Fire("OnShow") end
end
function Widget:Hide()
	local s = S(self)
	if not s.shown then return end
	local was = self:IsVisible()
	s.shown = false
	if was then self:_Fire("OnHide") end
end
function Widget:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Widget:IsShown() return S(self).shown end
function Widget:IsVisible()
	local w = self
	while w do
		if not S(w) then return true end
		if not S(w).shown then return false end
		w = S(w).parent
	end
	return true
end
function Widget:SetAlpha(alpha)
	if secrets[alpha] then S(self).alpha = alpha return end -- (the game takes a secret and draws it)
	assert(type(alpha) == "number", "SetAlpha: a number expected")
	S(self).alpha = math.max(0, math.min(1, alpha))
end
function Widget:GetAlpha() return S(self).alpha end
function Widget:GetEffectiveAlpha()
	local alpha, w = 1, self
	-- (a secret opacity counts as full: the stub can't multiply by it)
	while w and S(w) do alpha = alpha * (type(S(w).alpha) == "number" and S(w).alpha or 1) w = S(w).parent end
	return alpha
end
-- (the game reads the secret on its side; the stub peeks)
function Widget:SetAlphaFromBoolean(value, a, b) S(self).alpha = wow.reveal(value) and (a or 1) or (b or 0) end
function Widget:SetScale(scale) S(self).scale = scale end
function Widget:GetScale() return S(self).scale end
function Widget:GetEffectiveScale()
	local scale, w = 1, self
	while w and S(w) do scale = scale * S(w).scale w = S(w).parent end
	return scale
end
function Widget:SetIgnoreParentAlpha(v) S(self).ignoreParentAlpha = v end
function Widget:IsIgnoringParentAlpha() return S(self).ignoreParentAlpha or false end
function Widget:SetIgnoreParentScale(v) S(self).ignoreParentScale = v end

-- size and place
function Widget:SetSize(width, height) S(self).width, S(self).height = width, height or width end
function Widget:SetWidth(width) S(self).width = width end
function Widget:SetHeight(height) S(self).height = height end
function Widget:GetWidth() return S(self).width end
function Widget:GetHeight() return S(self).height end
function Widget:GetSize() return S(self).width, S(self).height end
function Widget:GetRect()
	local left, bottom = self:GetLeft(), self:GetBottom()
	if not left then return nil end
	return left, bottom, S(self).width, S(self).height
end
function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
	-- (the game's short forms: SetPoint(point, x, y), SetPoint(point, frame, x, y), a frame by its name)
	if type(relativeTo) == "number" then relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint end
	if type(relativeTo) == "string" then relativeTo = _G[relativeTo] end
	if relativeTo == self then error("SetPoint: a region can't be anchored to itself", 2) end
	if type(relativePoint) ~= "string" then relativePoint, x, y = point, relativePoint, x end
	local s = S(self)
	for index, p in ipairs(s.points) do
		if p[1] == point then table.remove(s.points, index) break end
	end
	table.insert(s.points, { point, relativeTo or s.parent, relativePoint or point, x or 0, y or 0 })
end
function Widget:SetAllPoints(other)
	other = other or S(self).parent
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", other, "TOPLEFT")
	self:SetPoint("BOTTOMRIGHT", other, "BOTTOMRIGHT")
	-- (the size copied too: the crude layout doesn't follow points)
	if other and S(other) then S(self).width, S(self).height = S(other).width, S(other).height end
end
function Widget:ClearAllPoints() S(self).points = {} end
function Widget:ClearPoint(point)
	for index, p in ipairs(S(self).points) do if p[1] == point then table.remove(S(self).points, index) return end end
end
function Widget:GetNumPoints() return #S(self).points end
function Widget:GetPoint(index)
	local p = S(self).points[index or 1]
	if p then return unpack(p) end
end
function Widget:GetPointByName(name)
	for _, p in ipairs(S(self).points) do if p[1] == name then return unpack(p) end end
end
-- (crude layout: a region with points sits at its offset from the screen's bottom left; one without has no place)
function Widget:GetLeft() local p = S(self).points[1] if p then return 100 + (p[4] or 0) end end
function Widget:GetBottom() local p = S(self).points[1] if p then return 100 + (p[5] or 0) end end
function Widget:GetRight() local l = self:GetLeft() return l and l + S(self).width end
function Widget:GetTop() local b = self:GetBottom() return b and b + S(self).height end
function Widget:GetCenter()
	local l, b = self:GetLeft(), self:GetBottom()
	if l then return l + S(self).width / 2, b + S(self).height / 2 end
end
function Widget:GetBoundsRect() return self:GetRect() end
function Widget:IsRectValid() return #S(self).points > 0 end
function Widget:IsAnchoringRestricted() return false end

-- levels
function Widget:SetFrameLevel(level) S(self).level = level end
function Widget:GetFrameLevel() return S(self).level end
function Widget:SetFrameStrata(strata) S(self).strata = strata end
function Widget:GetFrameStrata() return S(self).strata end
function Widget:SetDrawLayer(layer, sub) S(self).layer, S(self).sublevel = layer, sub end
function Widget:GetDrawLayer() return S(self).layer or "ARTWORK", S(self).sublevel or 0 end
function Widget:SetID(id) S(self).id = id end
function Widget:GetID() return S(self).id end
function Widget:SetAttribute(key, value) S(self).attributes[key] = value end
function Widget:GetAttribute(key) return S(self).attributes[key] end

-- mouse
function Widget:EnableMouse(on) S(self).mouse = on and true or false end
function Widget:IsMouseEnabled() return S(self).mouse end
function Widget:IsMouseOver() return S(self).mouseOver or false end
function Widget:IsMouseMotionFocus() return S(self).mouseOver or false end
function Widget:SetMovable(v) S(self).movable = v end
function Widget:IsMovable() return S(self).movable or false end
function Widget:IsClampedToScreen() return S(self).clamped or false end
function Widget:SetClampedToScreen(v) S(self).clamped = v end
function Widget:IsUserPlaced() return false end

-- scripts and events
-- (a new script drops the hooks on the old one, as in the game)
function Widget:SetScript(name, fn) S(self).scripts[name] = fn S(self).hooks[name] = nil end
function Widget:GetScript(name) return S(self).scripts[name] end
function Widget:HasScript(name) return true end
function Widget:HookScript(name, fn)
	local hooks = S(self).hooks
	hooks[name] = hooks[name] or {}
	table.insert(hooks[name], fn)
end
function Widget:_Fire(name, ...)
	local s = S(self)
	local where = (s.name or s.kind) .. ":" .. name
	if s.scripts[name] then wow.call(where, s.scripts[name], self, ...) end
	for _, hook in ipairs(s.hooks[name] or {}) do wow.call(where .. " (hook)", hook, self, ...) end
end
function Widget:RegisterEvent(event)
	-- (an event this client lacks, listed by a test in wow.unknownEvents, errors as in game: why Serene pcalls these)
	if wow.unknownEvents and wow.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"", 2) end
	eventFrames[self] = eventFrames[self] or {}
	eventFrames[self][event] = true
end
function Widget:RegisterUnitEvent(event, ...) self:RegisterEvent(event) end -- (the units not kept: heard for every unit)
function Widget:UnregisterEvent(event) if eventFrames[self] then eventFrames[self][event] = nil end end
function Widget:UnregisterAllEvents() eventFrames[self] = nil allEvents[self] = nil end
function Widget:RegisterAllEvents() allEvents[self] = true end
function Widget:IsEventRegistered(event) return eventFrames[self] and eventFrames[self][event] or false end

-- text
function Widget:SetText(text) S(self).text = text end
function Widget:GetText() return S(self).text end
function Widget:SetFormattedText(format, ...) S(self).text = format:format(...) end
function Widget:GetStringWidth()
	local text = S(self).text
	if secrets[text] then return wow.secret(60) end
	return text and #tostring(text) * 6 or 0 -- (6 px a character)
end
function Widget:GetUnboundedStringWidth() return self:GetStringWidth() end
function Widget:GetStringHeight() return 12 end
function Widget:GetNumLines() return 1 end
function Widget:IsTruncated() return false end
function Widget:SetFont(font, size, flags) S(self).font = { font, size, flags } return true end
function Widget:GetFont()
	local f = S(self).font
	if f then return f[1], f[2], f[3] end
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
function Widget:SetFontObject(object) S(self).fontObject = object end
function Widget:GetFontObject() return S(self).fontObject end
function Widget:SetTextColor(r, g, b, a) S(self).textColor = { r, g, b, a or 1 } end
function Widget:GetTextColor() local c = S(self).textColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Widget:GetJustifyH() return S(self).justifyH or "CENTER" end
function Widget:SetJustifyH(v) S(self).justifyH = v end
function Widget:GetShadowOffset() return 0, 0 end
function Widget:GetShadowColor() return 0, 0, 0, 1 end
function Widget:CopyFontObject(other) end
function Widget:GetSpacing() return 0 end
function Widget:GetLineHeight() return 12 end

-- textures
function Widget:SetTexture(texture) S(self).texture = texture S(self).atlas = nil return true end
function Widget:GetTexture() return S(self).texture end
function Widget:GetTextureFileID() return type(S(self).texture) == "number" and S(self).texture or nil end
function Widget:GetTextureFilePath() return type(S(self).texture) == "string" and S(self).texture or nil end
function Widget:SetAtlas(atlas) S(self).atlas = atlas S(self).texture = nil return true end
function Widget:GetAtlas() return S(self).atlas end
function Widget:SetColorTexture(r, g, b, a) S(self).texture = "color" S(self).color = { r, g, b, a or 1 } end
function Widget:SetVertexColor(r, g, b, a) S(self).vertex = { r, g, b, a or 1 } end
function Widget:GetVertexColor() local c = S(self).vertex or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Widget:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Widget:GetBlendMode() return S(self).blend or "BLEND" end
function Widget:SetBlendMode(mode) S(self).blend = mode end
function Widget:IsDesaturated() return false end
function Widget:GetDesaturation() return 0 end
function Widget:AddMaskTexture(mask) table.insert(S(self).masks, mask) end
function Widget:RemoveMaskTexture(mask)
	for index, m in ipairs(S(self).masks) do if m == mask then table.remove(S(self).masks, index) return end end
end
function Widget:GetNumMaskTextures() return #(S(self).masks or {}) end
function Widget:GetMaskTexture(index) return (S(self).masks or {})[index] end
function Widget:GetRotation() return 0 end

local function Region(kind, parent, name, layer)
	local r = New(kind, name, parent)
	S(r).layer = layer
	S(r).masks = {}
	if parent and S(parent) then table.insert(S(parent).regions, r) end
	return r
end
function Widget:CreateTexture(name, layer) return Region("Texture", self, name, layer) end
function Widget:CreateMaskTexture(name, layer) return Region("MaskTexture", self, name, layer) end
function Widget:CreateLine(name, layer) return Region("Line", self, name, layer) end
function Widget:CreateFontString(name, layer, inherits)
	local fs = Region("FontString", self, name, layer)
	S(fs).fontObject = inherits
	return fs
end

-- animations
function Widget:CreateAnimationGroup(name)
	local g = New("AnimationGroup", name, self)
	S(g).anims = {}
	return g
end
function Widget:CreateAnimation(kind, name)
	local a = New(kind or "Animation", name, self)
	table.insert(S(self).anims, a)
	return a
end
function Widget:Play() S(self).playing = true self:_Fire("OnPlay") end
function Widget:Stop() S(self).playing = false self:_Fire("OnStop") end
function Widget:Finish() S(self).playing = false self:_Fire("OnFinished") end
function Widget:IsPlaying() return S(self).playing or false end
function Widget:GetAnimations() return unpack(S(self).anims or {}) end
function Widget:GetDuration() return S(self).duration or 0 end
function Widget:SetDuration(d) S(self).duration = d end
function Widget:GetProgress() return 0 end
function Widget:GetElapsed() return 0 end
function Widget:GetLoopState() return "NONE" end
function Widget:GetRegionParent() return S(self).parent and S(S(self).parent).parent end

-- buttons
function Widget:GetFontString()
	local s = S(self)
	if not s.fontString then s.fontString = self:CreateFontString() end
	return s.fontString
end
function Widget:SetFontString(fs) S(self).fontString = fs end
-- (a texture object is taken as it is; a path or file id makes the button's own texture show it)
local function buttonTexture(key)
	return function(self, texture)
		local s = S(self)
		if type(texture) == "table" then s[key] = texture return end
		if not s[key] then s[key] = self:CreateTexture() end
		if texture then s[key]:SetTexture(texture) end
	end, function(self) return S(self)[key] end
end
Widget.SetNormalTexture, Widget.GetNormalTexture = buttonTexture("normalTexture")
Widget.SetPushedTexture, Widget.GetPushedTexture = buttonTexture("pushedTexture")
Widget.SetHighlightTexture, Widget.GetHighlightTexture = buttonTexture("highlightTexture")
Widget.SetDisabledTexture, Widget.GetDisabledTexture = buttonTexture("disabledTexture")
Widget.SetCheckedTexture, Widget.GetCheckedTexture = buttonTexture("checkedTexture")
function Widget:Enable() S(self).enabled = true end
function Widget:Disable() S(self).enabled = false end
function Widget:SetEnabled(v) S(self).enabled = v and true or false end
function Widget:IsEnabled() return S(self).enabled ~= false end
function Widget:SetChecked(v) S(self).checked = v and true or false end
function Widget:GetChecked() return S(self).checked or false end
function Widget:Click(button) self:_Fire("PreClick", button or "LeftButton", false) self:_Fire("OnClick", button or "LeftButton", false) self:_Fire("PostClick", button or "LeftButton", false) end
function Widget:GetButtonState() return "NORMAL" end

-- edit boxes and scroll frames
function Widget:HasFocus() return S(self).focus or false end
function Widget:SetFocus() S(self).focus = true end
function Widget:ClearFocus() S(self).focus = false end
function Widget:GetCursorPosition() return S(self).cursor or 0 end
function Widget:SetCursorPosition(p) S(self).cursor = p end
function Widget:GetNumLetters() return #(S(self).text or "") end
function Widget:GetMaxLetters() return 0 end
function Widget:GetInputLanguage() return "ROMAN" end
function Widget:GetTextInsets() return 0, 0, 0, 0 end
function Widget:IsMultiLine() return S(self).multi or false end
function Widget:SetMultiLine(v) S(self).multi = v end
function Widget:GetVerticalScroll() return S(self).vscroll or 0 end
function Widget:SetVerticalScroll(v) S(self).vscroll = v end
function Widget:GetHorizontalScroll() return 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:GetHorizontalScrollRange() return 0 end
function Widget:SetScrollChild(child) S(self).scrollChild = child end
function Widget:GetScrollChild() return S(self).scrollChild end

-- status bars, sliders, cooldowns
function Widget:SetMinMaxValues(a, b) S(self).min, S(self).max = a, b end
function Widget:GetMinMaxValues() return S(self).min or 0, S(self).max or 1 end
function Widget:SetValue(v) S(self).value = v self:_Fire("OnValueChanged", v, true) end
function Widget:GetValue() return S(self).value or 0 end
function Widget:GetValueStep() return 1 end
function Widget:SetStatusBarTexture(texture)
	local s = S(self)
	if type(texture) == "table" then s.barTexture = texture return end
	s.barTexture = s.barTexture or self:CreateTexture()
	s.barTexture:SetTexture(texture)
end
function Widget:GetStatusBarTexture()
	local s = S(self)
	s.barTexture = s.barTexture or self:CreateTexture()
	return s.barTexture
end
function Widget:GetStatusBarColor() return 1, 1, 1, 1 end
function Widget:GetOrientation() return "HORIZONTAL" end
function Widget:GetReverseFill() return false end
function Widget:GetThumbTexture() return S(self).thumb end
function Widget:SetThumbTexture(t) S(self).thumb = type(t) == "table" and t or self:CreateTexture() end
function Widget:SetCooldown(start, duration) S(self).cooldown = { start, duration } end
-- (in milliseconds, as the game gives them)
function Widget:GetCooldownTimes() local c = S(self).cooldown if c then return c[1] * 1000, c[2] * 1000 end return 0, 0 end
function Widget:GetCooldownDuration() local c = S(self).cooldown return c and c[2] * 1000 or 0 end
function Widget:Clear() S(self).cooldown = nil end
function Widget:GetDrawSwipe() return true end
function Widget:GetDrawEdge() return false end
function Widget:GetDrawBling() return true end
function Widget:GetReverse() return false end
function Widget:IsPaused() return false end
function Widget:GetHideCountdownNumbers() return false end
function Widget:GetCountdownFontString() return self:GetFontString() end

-- tooltips (GameTooltip and those made from GameTooltipTemplate)
function Widget:SetOwner(owner, anchor)
	if S(self).lines then self:ClearLines() end
	S(self).owner, S(self).anchor, S(self).lines = owner, anchor, {}
end
function Widget:GetProcessingTooltipInfo() local d = S(self).data if d then return { tooltipData = d } end end
function Widget:GetOwner() return S(self).owner end
function Widget:IsOwned(owner) return S(self).owner == owner end
function Widget:GetAnchorType() return S(self).anchor or "ANCHOR_NONE" end
-- (the game's tooltip lines are font strings named GameTooltipTextLeft1, ...Right1: made as needed, hidden)
local function tooltipLine(self, index)
	local name = S(self).name
	if not name then return end
	for _, side in ipairs({ "Left", "Right" }) do
		local key = name .. "Text" .. side .. index
		if not rawget(_G, key) then
			local fs = self:CreateFontString(key)
			fs:Hide()
		end
	end
	return _G[name .. "TextLeft" .. index], _G[name .. "TextRight" .. index]
end
function Widget:AddLine(text, r, g, b)
	local s = S(self)
	s.lines = s.lines or {}
	table.insert(s.lines, { left = text, color = { r, g, b } })
	local left = tooltipLine(self, #s.lines)
	if left then left:SetText(text) left:SetTextColor(r or 1, g or 1, b or 1) left:Show() end
end
function Widget:AddDoubleLine(a, b2, r1, g1, b1, r2, g2, bb2)
	local s = S(self)
	s.lines = s.lines or {}
	table.insert(s.lines, { left = a, right = b2 })
	local left, right = tooltipLine(self, #s.lines)
	if left then left:SetText(a) left:Show() right:SetText(b2) right:Show() end
end
function Widget:NumLines() return #(S(self).lines or {}) end
function Widget:ClearLines()
	local s = S(self)
	for index = 1, #(s.lines or {}) do
		local left, right = tooltipLine(self, index)
		if left then left:SetText(nil) left:Hide() right:SetText(nil) right:Hide() end
	end
	s.lines = {}
end
function Widget:GetTooltipData() return S(self).data end
function Widget:GetPrimaryTooltipData() return S(self).data end
function Widget:GetItem() local d = S(self).item if d then return d.name, d.link, d.id end end
function Widget:GetUnit() local u = S(self).unit if u then return UnitName(u), u end end
function Widget:GetSpell() end

-- scroll message frames (the chat)
function Widget:AddMessage(text, r, g, b, ...)
	local s = S(self)
	s.messages = s.messages or {}
	table.insert(s.messages, { text = text, r = r, g = g, b = b, extra = { ... } })
	-- (a window with the game's history, as the chat windows below: the newest line first)
	local history = rawget(self, "lines")
	if history then table.insert(history, 1, { message = text, timestamp = wow.now, r = r, g = g, b = b }) end
	table.insert(wow.printed, text)
end
function Widget:GetNumMessages() return #(S(self).messages or {}) end
function Widget:GetMessageInfo(index) local m = (S(self).messages or {})[index] if m then return m.text, m.r, m.g, m.b end end
function Widget:GetScrollOffset() return 0 end
function Widget:AtBottom() return true end
function Widget:GetFadeDuration() return 3 end
function Widget:GetTimeVisible() return 120 end
function Widget:GetFading() return true end
function Widget:GetMaxLines() return 128 end
function Widget:GetInsertMode() return "BOTTOM" end
function Widget:GetIndentedWordWrap() return false end

-- models and the minimap
function Widget:GetZoom() return 0 end
function Widget:GetZoomLevels() return 5 end
function Widget:GetPingPosition() return 0, 0 end

-- What a widget's state is (for tests).
function wow.state(widget) return S(widget) end
function wow.calls(widget, name)
	local found = {}
	for _, call in ipairs(rawget(widget, "_calls") or {}) do
		if call[1] == name then found[#found + 1] = call end
	end
	return found
end

-- CreateFrame and the templates the addon asks for
local TEMPLATE_PARTS = {
	-- (the tooltip's first two lines exist from the start, empty and hidden)
	GameTooltipTemplate = function(f)
		S(f).lines = {}
		for index = 1, 2 do f:AddLine("") end
		f:ClearLines()
	end,
	UIPanelScrollFrameTemplate = function(f)
		local name = f:GetName()
		local bar = CreateFrame("Slider", name and (name .. "ScrollBar"), f)
		f.ScrollBar = bar
	end,
	InputBoxTemplate = function(f) end,
}

function CreateFrame(kind, name, parent, templates)
	assert(type(kind) == "string", "CreateFrame: a frame type expected")
	local f = New(kind, name, parent, templates)
	if parent and S(parent) then table.insert(S(parent).children, f) end
	if kind == "GameTooltip" then TEMPLATE_PARTS.GameTooltipTemplate(f) end
	for template in (templates or ""):gmatch("[^,%s]+") do
		if TEMPLATE_PARTS[template] then TEMPLATE_PARTS[template](f) end
		if template:find("SecureActionButton") or template:find("Secure") then S(f).protected = true end
	end
	if kind == "Button" or kind == "CheckButton" then S(f).enabled = true end
	return f
end

function CreateFont(name)
	local f = New("Font", name, nil)
	return f
end

-- Events, time, the mouse ---------------------------------------------------------------------------------------------

-- Fire a game event at every frame that registered it (in the order they were made).
function wow.fire(event, ...)
	-- (the list taken first: a frame that registers while the event runs doesn't hear it; one that unregisters,
	-- checked again below, doesn't either)
	local list = {}
	for _, f in ipairs(frames) do
		if (eventFrames[f] and eventFrames[f][event]) or allEvents[f] then list[#list + 1] = f end
	end
	for _, f in ipairs(list) do
		if (eventFrames[f] and eventFrames[f][event]) or allEvents[f] then f:_Fire("OnEvent", event, ...) end
	end
	if EventRegistry then EventRegistry:_Trigger(event, ...) end
	return #list
end

local timers = {}
-- Move time on: timers due run, then every visible frame's OnUpdate (in steps of at most `step` seconds).
function wow.advance(seconds, step)
	step = step or 0.1
	local left = seconds
	repeat
		local dt = math.min(step, left)
		wow.now = wow.now + dt
		left = left - dt
		-- (due ones only, taken before any runs: a timer made while they run, After(0) too, waits for the next step,
		-- as the next frame in the game; 1e-9 for the sums of steps that never quite add up)
		local due = {}
		for index = #timers, 1, -1 do
			local t = timers[index]
			if not t.cancelled and t.at <= wow.now + 1e-9 then due[#due + 1] = t end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, t in ipairs(due) do
			if t.iterations then
				t.left = t.left - 1
				-- (a ticker runs at most once a step: one shorter than the step falls behind)
				if t.left <= 0 then t.cancelled = true else t.at = t.at + t.interval end
			else
				t.cancelled = true
			end
			wow.call("timer", t.fn, t.handle)
		end
		for index = #timers, 1, -1 do if timers[index].cancelled then table.remove(timers, index) end end
		for _, f in ipairs(frames) do
			local s = S(f)
			if (s.scripts.OnUpdate or s.hooks.OnUpdate) and f:IsVisible() then f:_Fire("OnUpdate", dt) end
		end
	until left <= 1e-9
end

local function Timer(seconds, fn, iterations)
	local handle = {}
	local t = { at = wow.now + math.max(seconds or 0, 0), fn = fn, interval = seconds, iterations = iterations,
		left = iterations or 1, handle = handle }
	function handle:Cancel() t.cancelled = true end
	function handle:IsCancelled() return t.cancelled or false end
	timers[#timers + 1] = t
	return handle
end
C_Timer = {
	After = function(seconds, fn) Timer(seconds, fn) end,
	NewTimer = function(seconds, fn) return Timer(seconds, fn) end,
	NewTicker = function(seconds, fn, iterations) return Timer(seconds, fn, iterations or math.huge) end,
}
function wow.timers() return #timers end

function GetTime() return wow.now end
function GetTimePreciseSec() return wow.now end
function GetServerTime() return os.time() end
function GetFramerate() return 60 end
function GetNetStats() return 0, 0, 30, 40 end
function GetGameTime() return 12, 30 end
function GameTime_GetTime() return "12:30" end
function GetCursorPosition() return wow.cursorX or 500, wow.cursorY or 400 end
function GetPhysicalScreenSize() return 1920, 1080 end
function GetScreenWidth() return 1365 end
function GetScreenHeight() return 768 end
function GetMouseFoci() return wow.focus and { wow.focus } or {} end
function GetMouseFocus() return wow.focus end
function IsMouseButtonDown() return false end
function IsShiftKeyDown() return wow.shift or false end
function IsControlKeyDown() return wow.ctrl or false end
function IsAltKeyDown() return wow.alt or false end
function IsModifiedClick() return false end
function IsModifierKeyDown() return wow.shift or wow.ctrl or wow.alt or false end
function IsLoggedIn() return wow.loggedIn or false end
function InCombatLockdown() return wow.combat and not regenDisabling end
function ReloadUI() wow.reloaded = true end

-- Pass the mouse over a frame: its OnEnter (and OnLeave from the one before).
function wow.hover(frame)
	if wow.focus and wow.focus ~= frame then S(wow.focus).mouseOver = false wow.focus:_Fire("OnLeave") end
	wow.focus = frame
	if frame then S(frame).mouseOver = true frame:_Fire("OnEnter", false) end
end

-- The combat state, with the events that say so.
-- (PLAYER_REGEN_DISABLED comes just before the lockdown: the last moment secure frames can still be hidden)
function wow.fight(on)
	wow.combat = on and true or false
	regenDisabling = wow.combat
	wow.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	regenDisabling = false
end

-- hooksecurefunc: the hook runs after the function (on a table, or a global by name).
function hooksecurefunc(target, name, hook)
	if type(target) == "string" then target, name, hook = _G, target, name end
	local original = target[name]
	if type(original) ~= "function" then
		-- (on a frame, an unknown method: the stub's own; give it a body to hook)
		if type(target) == "table" and getmetatable(target) == WidgetMeta then
			original = WidgetMeta.__index(target, name)
		end
		if type(original) ~= "function" then error("hooksecurefunc: no function " .. tostring(name), 2) end
	end
	-- (the wrapper set on that table only: on a frame, that frame's method, not every frame's)
	rawset(target, name, function(...)
		local results = { original(...) }
		wow.call("hook " .. tostring(name), hook, ...)
		return unpack(results)
	end)
end

-- Saved variables, slash commands, keys ----------------------------------------------------------------------------------

SlashCmdList = {}
function wow.slash(text)
	local command, rest = text:match("^(/%S+)%s*(.-)$")
	for key, fn in pairs(SlashCmdList) do
		-- (the game's way: SlashCmdList.KEY answers the words in SLASH_KEY1, SLASH_KEY2...)
		for index = 1, 9 do
			local word = rawget(_G, "SLASH_" .. key .. index)
			if word and word:lower() == command:lower() then return fn(rest) end
		end
	end
	error("no slash command " .. command)
end
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data) wow.popup = { which = which, a = a, b = b, data = data } end
function StaticPopup_Hide(which) wow.popup = nil end
function GetBindingKey(action) return wow.bindings and wow.bindings[action] end
function GetBindingText(key) return key end
function GetBindingAction(key) for action, k in pairs(wow.bindings or {}) do if k == key then return action end end return "" end
function GetCurrentBindingSet() return 2 end
function SetBinding(key, action) wow.bindings = wow.bindings or {} if action then wow.bindings[action] = key end return true end
function SaveBindings() end
function GetCVar(name) return wow.cvars[name] end
function GetCVarBool(name) return wow.cvars[name] == "1" end
function SetCVar(name, value) wow.cvars[name] = tostring(value) return true end
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool,
	GetCVarDefault = function() return "0" end, RegisterCVar = function() end }

-- The player and units ---------------------------------------------------------------------------------------------------

wow.units = {} -- unit -> { name, level, class, classFile, exists, dead, health, healthMax, power, powerMax, enemy,
-- reaction (1 to 8; else 2 for an enemy, 5 otherwise), tapped, ... }
local function U(unit)
	if unit == "player" then return wow.player end
	return wow.units[unit]
end
function UnitExists(unit) return U(unit) ~= nil end
-- (the realm only for another realm's player, as the game gives it)
function UnitName(unit) local u = U(unit) if u then return u.name, u.realm ~= wow.player.realm and u.realm or nil end end
function UnitFullName(unit) local u = U(unit) if u then return u.name, u.realm end end
function GetUnitName(unit, realm) return (UnitName(unit)) end
function UnitGUID(unit) local u = U(unit) return u and u.guid end
function UnitClass(unit) local u = U(unit) if u then return u.class, u.classFile, u.classID end end
function UnitClassBase(unit) local u = U(unit) if u then return u.classFile, u.classID end end
function UnitRace(unit) local u = U(unit) if u then return u.race, u.raceFile end end
function UnitSex(unit) local u = U(unit) return u and u.sex or 2 end
function UnitLevel(unit) local u = U(unit) return u and u.level or 0 end
function UnitEffectiveLevel(unit) return UnitLevel(unit) end
function UnitFactionGroup(unit) local u = U(unit) if u then return u.faction or "Alliance", u.faction or "Alliance" end end
function UnitIsPlayer(unit) local u = U(unit) return u ~= nil and (unit == "player" or u.player or false) end
function UnitIsUnit(a, b) return U(a) ~= nil and U(a) == U(b) end
function UnitIsDead(unit) local u = U(unit) return u and u.dead or false end
function UnitIsDeadOrGhost(unit) local u = U(unit) return u and u.dead or false end
function UnitIsGhost() return false end
function UnitIsAFK(unit) local u = U(unit) return u and u.afk or false end
function UnitIsDND() return false end
function UnitIsConnected(unit) return U(unit) ~= nil end
function UnitIsTapDenied(unit) local u = U(unit) return u and u.tapped or false end
function UnitIsEnemy(a, b) local u = U(b) return u and u.enemy or false end
function UnitIsFriend(a, b) local u = U(b) return u and not u.enemy or false end
function UnitCanAttack(a, b) local u = U(b) return u and u.enemy or false end
function UnitCanAssist(a, b) local u = U(b) return u and not u.enemy or false end
-- (how one unit and another stand: the one that isn't you says, either way round)
function UnitReaction(a, b) local u = U(b == "player" and a or b) if u then return u.reaction or (u.enemy and 2 or 5) end end
function UnitClassification(unit) local u = U(unit) return u and u.classification or "normal" end
function UnitCreatureType() return "Humanoid" end
function UnitAffectingCombat(unit) if unit == "player" then return wow.combat end local u = U(unit) return u and u.combat or false end
function UnitHealth(unit) local u = U(unit) return u and (u.health or 100) or 0 end
function UnitHealthMax(unit) local u = U(unit) return u and (u.healthMax or 100) or 0 end
function UnitPower(unit) local u = U(unit) return u and (u.power or 100) or 0 end
function UnitPowerMax(unit) local u = U(unit) return u and (u.powerMax or 100) or 0 end
function UnitPowerType(unit) local u = U(unit) return u and (u.powerType or 1) or 0, u and (u.powerToken or "RAGE") end
function UnitXP() return wow.xp or 1000 end
function UnitXPMax() return wow.xpMax or 5000 end
function GetXPExhaustion() return wow.rested end
function UnitCastingInfo(unit) local u = U(unit) if u and u.casting then return unpack(u.casting) end end
function UnitChannelInfo(unit) local u = U(unit) if u and u.channel then return unpack(u.channel) end end
function UnitInVehicle() return false end
function UnitOnTaxi() return wow.taxi or false end
function UnitInParty() return false end
function UnitInRaid() return nil end
function UnitAttackSpeed() return wow.speed or 2.6, wow.offSpeed end
function UnitRangedDamage() return wow.rangedSpeed or 0 end
function UnitGetIncomingHeals() return 0 end
function UnitGetTotalAbsorbs() return 0 end
function UnitGetDetailedHealPrediction() return 0, 0, 0 end
function UnitHasVehicleUI() return false end
function UnitThreatSituation() return nil end
function UnitBuff(unit, index) local u = U(unit) local a = u and u.buffs and u.buffs[index] if a then return a.name, a.icon, a.count or 0, a.dispelName, a.duration or 0, a.expirationTime or 0, a.sourceUnit, false, nil, a.spellId end end
function UnitDebuff(unit, index) local u = U(unit) local a = u and u.debuffs and u.debuffs[index] if a then return a.name, a.icon, a.count or 0, a.dispelName, a.duration or 0, a.expirationTime or 0, a.sourceUnit, false, nil, a.spellId end end
function UnitAura(unit, index, filter)
	if filter and filter:find("HARMFUL") then return UnitDebuff(unit, index) end
	return UnitBuff(unit, index)
end
function GetUnitSpeed() return wow.speedNow or 0, 7, 7, 4.72 end
function GetPlayerFacing() return 0 end
function IsResting() return wow.resting or false end
function IsMounted() return wow.mounted or false end
function IsFlying() return false end
function IsInGroup() return false end
function IsInRaid() return false end
function IsInInstance() return false, "none" end
function IsInGuild() return wow.guild ~= nil end
function GetGuildInfo(unit) if unit == "player" and wow.guild then return wow.guild, "Member", 1 end end
function GetNumGroupMembers() return 0 end
function GetNumGuildMembers() return 0, 0 end
function GetRealmName() return wow.player.realm end
function GetNormalizedRealmName() return wow.player.realm end
function GetMoney() return wow.money end
function GetMaxPlayerLevel() return 60 end
function GetMaxLevelForPlayerExpansion() return 60 end
MAX_PLAYER_LEVEL = 60
function GetLootThreshold() return 2 end
function GetBindLocation() return "Goldshire" end
function GetZoneText() return wow.zone or "Elwynn Forest" end
function GetRealZoneText() return GetZoneText() end
function GetSubZoneText() return wow.subzone or "Goldshire" end
function GetMinimapZoneText() return wow.subzone or "Goldshire" end
function GetZonePVPInfo() return wow.pvp or "friendly" end
function GetPlayerInfoByGUID() end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.16.0", "70961", "Nov 1 2026", 11600 end
function GetAddOnMemoryUsage() return 1024 end
function UpdateAddOnMemoryUsage() end
function BreakUpLargeNumbers(n) return tostring(n) end
function GetInventoryItemID(unit, slot) local i = wow.equipped and wow.equipped[slot] return i and i.id end
function GetInventoryItemLink(unit, slot) local i = wow.equipped and wow.equipped[slot] return i and i.link end
function GetInventoryItemTexture(unit, slot) local i = wow.equipped and wow.equipped[slot] return i and i.icon end
function GetInventoryItemDurability(slot) local i = wow.equipped and wow.equipped[slot] if i and i.durability then return i.durability[1], i.durability[2] end end
function GetWeaponEnchantInfo() return false end
function GetSpellInfo(id)
	local s = wow.spells and wow.spells[id]
	if s then return s.name, nil, s.icon, 0, 0, 0, s.id or id end
end
function IsSpellKnown(id) local s = wow.spells and wow.spells[id] return s and s.known or false end
function IsPlayerSpell(id) return IsSpellKnown(id) end
function IsCurrentSpell() return false end
function IsAutoRepeatSpell() return false end
function GetShapeshiftForm() return 0 end
function GetActionInfo(slot) local a = wow.actions and wow.actions[slot] if a then return a.kind, a.id, a.subType end end
function GetActionText(slot) local a = wow.actions and wow.actions[slot] return a and a.text end
function GetActionTexture(slot) local a = wow.actions and wow.actions[slot] return a and a.icon end
function HasAction(slot) return wow.actions and wow.actions[slot] ~= nil or false end
function GetActionCooldown() return 0, 0, 1 end
function IsUsableAction(slot) return HasAction(slot), false end
function IsActionInRange() return nil end
function IsCurrentAction() return false end
function IsHarmfulAction(slot) return false end
function IsAutoRepeatAction() return false end
function GetActionCount(slot) local a = wow.actions and wow.actions[slot] return a and a.count or 0 end
function GetMacroSpell() end
function GetMacroItem() end
function GetMacroIndexByName(name) return wow.macros and wow.macros[name] and 1 or 0 end
function GetMacroInfo() end
function CreateMacro(name) wow.macros = wow.macros or {} wow.macros[name] = true return 1 end
function EditMacro() end
function PickupMacro() end
function PickupAction() end
function PlaceAction() end
-- (not "wow.cursor and unpack(...)": an and keeps only the first of unpack's values)
function GetCursorInfo() if wow.cursor then return unpack(wow.cursor) end end
function ClearCursor() wow.cursor = nil end
function CursorHasItem() return wow.cursor ~= nil and wow.cursor[1] == "item" end
function DeleteCursorItem() wow.cursor = nil end

-- Items and bags -------------------------------------------------------------------------------------------------------
-- wow.items[id] = { name, quality, level, minLevel, type, subType, stack, equipLoc, icon, sell, classID, subclassID }
-- wow.bags[bag] = { size = n, [slot] = { id = , count = , quality = , locked = , quest = , noValue = } }

wow.items = {}
wow.bags = { [0] = { size = 16 } }
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
NUM_CONTAINER_FRAMES = 13
BANK_CONTAINER = -1
INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED = 16, 17, 18

function wow.link(id)
	local item = wow.items[id]
	-- (coloured by quality; the link's level, 60, in its ninth field)
	local colors = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
	return ("|c%s|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(colors[item and item.quality or 1] or "ffffffff", id,
		item and item.name or ("Item " .. id))
end

-- (an item by its id, its link, or its name, as GetItemInfo takes them)
local function idOf(item)
	if type(item) == "number" then return item end
	if type(item) == "string" then return tonumber(item:match("item:(%d+)")) or (function()
		for id, info in pairs(wow.items) do if info.name == item then return id end end
	end)() end
end

local function ItemInfo(item)
	local id = idOf(item)
	local i = id and wow.items[id]
	if not i then return nil end
	return i.name, wow.link(id), i.quality or 1, i.level or 1, i.minLevel or 1, i.type or "Miscellaneous",
		i.subType or "Junk", i.stack or 1, i.equipLoc or "", i.icon or 134400, i.sell or 0, i.classID or 15,
		i.subclassID or 0, 0, 0, nil, false
end
local function ItemInfoInstant(item)
	local id = idOf(item)
	local i = id and wow.items[id]
	if not i then return nil end
	return id, i.type or "Miscellaneous", i.subType or "Junk", i.equipLoc or "", i.icon or 134400, i.classID or 15, i.subclassID or 0
end
GetItemInfo, GetItemInfoInstant = ItemInfo, ItemInfoInstant
function GetItemCount(item)
	local id, total = idOf(item), 0
	for _, bag in pairs(wow.bags) do
		for slot = 1, bag.size or 0 do if bag[slot] and bag[slot].id == id then total = total + (bag[slot].count or 1) end end
	end
	return total
end
C_Item = {
	GetItemInfo = ItemInfo, GetItemInfoInstant = ItemInfoInstant, GetItemCount = GetItemCount,
	GetItemNameByID = function(id) local i = wow.items[idOf(id)] return i and i.name end,
	GetItemQualityByID = function(id) local i = wow.items[idOf(id)] return i and i.quality end,
	GetItemMaxStackSizeByID = function(id) local i = wow.items[idOf(id)] return i and (i.stack or 1) end,
	GetItemIconByID = function(id) local i = wow.items[idOf(id)] return i and (i.icon or 134400) end,
	GetItemSpell = function() end,
	IsItemDataCachedByID = function() return true end,
	RequestLoadItemDataByID = function() end,
	DoesItemExistByID = function(id) return wow.items[idOf(id)] ~= nil end,
	IsUsableItem = function() return true, false end,
	GetItemCooldown = function() return 0, 0, 1 end,
	IsEquippableItem = function(id) local i = wow.items[idOf(id)] return i and (i.equipLoc or "") ~= "" end,
}

local function bagSlot(bag, slot)
	local b = wow.bags[bag]
	return b and slot <= (b.size or 0) and b[slot]
end
C_Container = {
	GetContainerNumSlots = function(bag) local b = wow.bags[bag] return b and b.size or 0 end,
	GetContainerNumFreeSlots = function(bag)
		local b, free = wow.bags[bag], 0
		for slot = 1, b and b.size or 0 do if not b[slot] then free = free + 1 end end
		return free, b and b.family or 0 -- (family: a special bag's kind, 1 a quiver...)
	end,
	GetContainerItemInfo = function(bag, slot)
		local s = bagSlot(bag, slot)
		if not s then return nil end
		local i = wow.items[s.id] or {}
		return { iconFileID = i.icon or 134400, stackCount = s.count or 1, isLocked = s.locked or false,
			quality = s.quality or i.quality or 1, isReadable = false, hasLoot = false, hyperlink = wow.link(s.id),
			isFiltered = false, hasNoValue = s.noValue or (i.sell or 0) == 0, itemID = s.id, isBound = s.bound or false }
	end,
	GetContainerItemLink = function(bag, slot) local s = bagSlot(bag, slot) return s and wow.link(s.id) end,
	GetContainerItemID = function(bag, slot) local s = bagSlot(bag, slot) return s and s.id end,
	GetContainerItemQuestInfo = function(bag, slot)
		local s = bagSlot(bag, slot)
		return { isQuestItem = s and s.quest or false, questID = nil, isActive = false }
	end,
	GetContainerItemCooldown = function() return 0, 0, 1 end,
	GetBagName = function(bag) return bag == 0 and "Backpack" or ("Bag " .. bag) end,
	GetBagSlotFlag = function() return false end,
	PickupContainerItem = function(bag, slot) wow.cursor = { "item", (bagSlot(bag, slot) or {}).id } end,
	UseContainerItem = function(bag, slot) wow.used = wow.used or {} table.insert(wow.used, { bag, slot }) end,
	SplitContainerItem = function() end,
	SortBags = function() end,
	GetSortBagsRightToLeft = function() return false end,
	ContainerIDToInventoryID = function(bag) return 19 + bag end, -- (bags 1 to 4 sit in inventory slots 20 to 23)
	GetItemCooldown = function() return 0, 0, 1 end,
	IsContainerFiltered = function() return false end,
	ShowContainerSellCursor = function() end,
}
function GetCoinTextureString(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end
GetMoneyString = GetCoinTextureString
C_CurrencyInfo = { GetCoinTextureString = GetCoinTextureString, GetCoinText = GetCoinTextureString }
C_NewItems = { IsNewItem = function() return false end, RemoveNewItem = function() end, ClearAll = function() end }

-- The merchant (wow.merchant = { open, items = { { id, price, stack, numAvailable, ... } }, buyback = {}, repair })
wow.merchant = { items = {}, buyback = {} }
function GetMerchantNumItems() return #wow.merchant.items end
function GetMerchantItemInfo(index)
	local m = wow.merchant.items[index]
	if not m then return nil end
	local i = wow.items[m.id] or {}
	-- (name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost)
	return i.name, i.icon or 134400, m.price or 0, m.stack or 1, m.numAvailable or -1, m.purchasable ~= false,
		m.usable ~= false, m.extended or false
end
function GetMerchantItemLink(index) local m = wow.merchant.items[index] return m and wow.link(m.id) end
function GetMerchantItemID(index) local m = wow.merchant.items[index] return m and m.id end
function GetMerchantItemMaxStack(index) local m = wow.merchant.items[index] local i = m and wow.items[m.id] return i and i.stack or 1 end
function GetMerchantItemCostInfo() return 0 end
function GetNumBuybackItems() return #wow.merchant.buyback end
function GetBuybackItemInfo(index) local m = wow.merchant.buyback[index] local i = m and wow.items[m.id] if i then return i.name, i.icon, m.price or 0, m.count or 1 end end
function GetBuybackItemLink(index) local m = wow.merchant.buyback[index] return m and wow.link(m.id) end
function BuyMerchantItem(index, count) wow.bought = wow.bought or {} table.insert(wow.bought, { index, count }) end
function CanMerchantRepair() return wow.merchant.repair or false end
function GetRepairAllCost() return wow.merchant.repairCost or 0, (wow.merchant.repairCost or 0) > 0 end
function RepairAllItems(guild) wow.repaired = guild and "guild" or "gold" wow.merchant.repairCost = 0 end
function CanGuildBankRepair() return wow.merchant.guildRepair or false end
function GetGuildBankWithdrawMoney() return wow.merchant.guildRepair and -1 or 0 end
function CloseMerchant() wow.merchant.open = false end
C_MerchantFrame = { GetNumJunkItems = function() return 0 end, IsSellAllJunkEnabled = function() return false end,
	GetItemInfo = function(index)
		local name, icon, price, stack, available, purchasable, usable, extended = GetMerchantItemInfo(index)
		if name then return { name = name, texture = icon, price = price, stackCount = stack, numAvailable = available,
			isPurchasable = purchasable, isUsable = usable, hasExtendedCost = extended } end
	end,
}

-- Spells -----------------------------------------------------------------------------------------------------------------
wow.spells = {}
C_Spell = {
	GetSpellInfo = function(id)
		local s = wow.spells[id]
		if s then return { name = s.name, iconID = s.icon or 136243, spellID = s.id or id, castTime = 0, minRange = 0, maxRange = 0 } end
	end,
	GetSpellName = function(id) local s = wow.spells[id] return s and s.name end,
	GetSpellTexture = function(id) local s = wow.spells[id] return s and (s.icon or 136243) end,
	GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } end,
	GetSpellCharges = function() end,
	IsSpellUsable = function() return true, false end,
	IsSpellInRange = function() return nil end,
	GetSpellCastCount = function() return 0 end,
	GetSpellPowerCost = function() return {} end,
	GetSpellLink = function(id) local s = wow.spells[id] return s and ("|Hspell:" .. id .. "|h[" .. s.name .. "]|h") end,
	GetSpellSubtext = function(id) local s = wow.spells[id] return s and s.rank end,
	DoesSpellExist = function(id) return wow.spells[id] ~= nil end,
	GetSpellIDForSpellIdentifier = function(id) return id end,
	GetOverrideSpell = function(id) return id end,
	IsCurrentSpell = function() return false end,
	IsAutoRepeatSpell = function() return false end,
	GetSpellDescription = function() return "" end,
	IsConsumableSpell = function() return false end,
	PickupSpell = function(id) wow.cursor = { "spell", id } end,
}
C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end, IsSpellKnown = function(id) return IsSpellKnown(id) end,
	GetSpellBookItemInfo = function() end, HasPetSpells = function() return nil end,
	GetSpellBookSkillLineInfo = function() end, IsSpellBookItemLowRank = function() return false end,
	PickupSpellBookItem = function() end }

-- Auras (wow.units.player.buffs = { { name, icon, spellId, duration, expirationTime, count, dispelName, auraInstanceID } })
local function auraData(unit, index, filter)
	local u = U(unit)
	local list = u and (filter and filter:find("HARMFUL") and u.debuffs or u.buffs)
	local a = list and list[index]
	if not a then return nil end
	return { name = a.name, icon = a.icon or 136243, applications = a.count or 0, dispelName = a.dispelName,
		duration = a.duration or 0, expirationTime = a.expirationTime or 0, sourceUnit = a.sourceUnit,
		isStealable = false, spellId = a.spellId, auraInstanceID = a.auraInstanceID or index,
		isHelpful = not (filter and filter:find("HARMFUL")), isHarmful = filter and filter:find("HARMFUL") and true or false,
		canApplyAura = false, isFromPlayerOrPlayerPet = a.mine or false, timeMod = 1 }
end
C_UnitAuras = {
	GetAuraDataByIndex = auraData,
	GetBuffDataByIndex = function(unit, index, filter) return auraData(unit, index, "HELPFUL" .. (filter or "")) end,
	GetDebuffDataByIndex = function(unit, index, filter) return auraData(unit, index, "HARMFUL" .. (filter or "")) end,
	GetAuraDataBySpellName = function(unit, name, filter)
		for index = 1, 40 do
			local a = auraData(unit, index, filter)
			if not a then return nil end
			if a.name == name then return a end
		end
	end,
	GetAuraDataByAuraInstanceID = function(unit, id)
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			for index = 1, 40 do
				local a = auraData(unit, index, filter)
				if not a then break end
				if a.auraInstanceID == id then return a end
			end
		end
	end,
	GetPlayerAuraBySpellID = function(id)
		for index = 1, 40 do
			local a = auraData("player", index, "HELPFUL")
			if not a then return nil end
			if a.spellId == id then return a end
		end
	end,
	GetAuraSlots = function() return nil end,
	GetUnitAuras = function(unit, filter)
		local out = {}
		for index = 1, 40 do local a = auraData(unit, index, filter) if not a then break end out[#out + 1] = a end
		return out
	end,
	IsAuraFilteredOutByInstanceID = function() return false end,
	GetAuraDuration = function() return nil end,
	GetAuraDispelTypeColor = function() return nil end,
	GetAuraApplicationDisplayCount = function(unit, id) return "" end,
}

-- Tooltip data (wow.tooltipData[kind .. ":" .. key] = { lines = { { leftText = , rightText = , leftColor = } } })
wow.tooltipData = {}
-- (a C_TooltipInfo getter answers wow.tooltipData["kind:arg"], or "kind:arg:arg2" with two arguments)
local function data(kind) return function(a, b) return wow.tooltipData[kind .. ":" .. tostring(a) .. (b and (":" .. tostring(b)) or "")] end end
C_TooltipInfo = { GetBagItem = data("bag"), GetMerchantItem = data("merchant"), GetUnit = data("unit"),
	GetHyperlink = data("link"), GetItemByID = data("item"), GetSpellByID = data("spell"), GetAction = data("action"),
	GetInventoryItem = function(unit, slot) return wow.tooltipData["inventory:" .. slot] end,
	GetUnitAura = data("aura"), GetUnitBuff = data("aura"), GetUnitDebuff = data("debuff") }
TooltipUtil = { SurfaceArgs = function() end, GetDisplayedItem = function(tip) return tip:GetItem() end }
TooltipDataProcessor = { AllTypes = "ALL",
	AddTooltipPostCall = function(kind, fn) wow.tooltipPostCalls = wow.tooltipPostCalls or {} table.insert(wow.tooltipPostCalls, { kind, fn }) end,
	AddLinePreCall = function(kind, fn) wow.linePreCalls = wow.linePreCalls or {} table.insert(wow.linePreCalls, { kind, fn }) end,
	AddLinePostCall = function(kind, fn) wow.linePostCalls = wow.linePostCalls or {} table.insert(wow.linePostCalls, { kind, fn }) end }
Enum = {
	TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4, Currency = 5, Macro = 25, Toy = 21 },
	TooltipDataLineType = { None = 0, Blank = 1, UnitName = 2, SellPrice = 11 },
	BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1, Keyring = -2,
		Characterbanktab = 6, AccountBankTab_1 = 12 },
	ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7 },
	ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
		Tradegoods = 7, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 },
	PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 },
	PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
	EditModeSwingTimerSystemIndices = { MainHand = 1, OffHand = 2 },
	BankType = { Character = 0, Guild = 1, Account = 2 },
	PlayerInteractionType = { Merchant = 5, Banker = 8 },
	StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
	UnitAuraSortRule = { Default = 0, BigDefensive = 1, Expiration = 2, Name = 3 },
	UnitAuraSortDirection = { Normal = 0, Reverse = 1 },
	AuraButtonDispelTypeTextureStyle = { None = 0, Color = 1 },
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
	LuaCurveType = { Linear = 0, Step = 1 },
}

-- Colours, fonts, misc globals -----------------------------------------------------------------------------------------
local Color = {}
Color.__index = Color
function Color:GetRGB() return self.r, self.g, self.b end
function Color:GetRGBA() return self.r, self.g, self.b, self.a end
function Color:GenerateHexColor() return ("ff%02x%02x%02x"):format(self.r * 255, self.g * 255, self.b * 255) end
function Color:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
function Color:WrapTextInColorCode(text) return "|c" .. self:GenerateHexColor() .. text .. "|r" end
function Color:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a or 1 end
function Color:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
function CreateColor(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, Color) end
RAID_CLASS_COLORS = {}
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
	local c = CreateColor(0.7, 0.6, 0.5)
	c.colorStr = c:GenerateHexColor()
	RAID_CLASS_COLORS[class] = c
end
ITEM_QUALITY_COLORS = {}
for q = 0, 7 do local c = CreateColor(1, 1, 1) c.hex = "|cffffffff" c.color = c ITEM_QUALITY_COLORS[q] = c end
C_ClassColor = { GetClassColor = function(class) return RAID_CLASS_COLORS[class] end }
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", ROGUE = "Rogue", HUNTER = "Hunter",
	PALADIN = "Paladin", SHAMAN = "Shaman", WARLOCK = "Warlock", DRUID = "Druid" }
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE
ChatTypeInfo = setmetatable({}, { __index = function(t, k) local v = { r = 1, g = 1, b = 1, id = 1 } rawset(t, k, v) return v end })
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UNIT_NAME_FONT = STANDARD_TEXT_FONT
CHAT_FRAMES = {}
NUM_CHAT_WINDOWS = 10
MAX_BATTLEFIELD_QUEUES = 3

-- (objects whose every method is a quiet no-op, through the widgets' verbs)
function CreateUnitHealPredictionCalculator() return setmetatable({}, WidgetMeta) end
C_CurveUtil = {
	CreateCurve = function() local c = setmetatable({}, WidgetMeta) rawset(c, "_s", { points = {} }) rawset(c, "_calls", {}) return c end,
	CreateColorCurve = function() local c = setmetatable({}, WidgetMeta) rawset(c, "_s", { points = {} }) rawset(c, "_calls", {}) return c end,
}
AnchorUtil = { CreateGridLayout = function() return {} end, GridLayout = function() end, CreateAnchor = function(...) return { ... } end }
GridLayoutMixin = { Direction = { TopLeftToBottomRight = 1, TopRightToBottomLeft = 2, BottomLeftToTopRight = 3 } }
C_AddOns = { IsAddOnLoaded = function(name) return wow.addons and wow.addons[name] or false end,
	GetAddOnMetadata = function() return nil end, LoadAddOn = function() return false end,
	GetNumAddOns = function() return 1 end, GetAddOnInfo = function() return "Serene" end }
IsAddOnLoaded = C_AddOns.IsAddOnLoaded
C_Map = { GetBestMapForUnit = function() return 1429 end,
	GetPlayerMapPosition = function() return { x = 0.4, y = 0.6, GetXY = function(self) return self.x, self.y end } end,
	GetMapInfo = function(id) return { mapID = id, name = "Elwynn Forest", mapType = 3 } end }
C_Calendar = { GetNumPendingInvites = function() return 0 end, OpenCalendar = function() end, GetDate = function() return { monthDay = 25, month = 11, year = 2026 } end }
C_PartyInfo = { IsPartyFull = function() return false end }
C_LFGList = { GetActiveEntryInfo = function() end, HasActiveEntryInfo = function() return false end }
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end }
C_ChatInfo = { GetChannelShortcut = function() end, IsChannelRegional = function() return false end }
C_FriendList = { GetNumFriends = function() return 0 end, GetFriendInfoByIndex = function() end, GetFriendInfo = function() end, IsFriend = function() return false end }
C_GuildInfo = { GuildRoster = function() end }
GuildRoster = function() end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
C_Texture = { GetAtlasInfo = function(atlas) return { width = 16, height = 16, file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return false end }
C_Bank = { FetchPurchasedBankTabIDs = function() return {} end, FetchPurchasedBankTabData = function() return {} end,
	CanUseBank = function() return false end, FetchViewableBankTypes = function() return {} end }
-- (absent here, so the addon takes its fallbacks; a spec that needs one sets it before loading)
C_SwingTimer = nil -- (Forever-only; its shape isn't known well enough to stub)
C_Secrets = nil
C_StringUtil = nil
C_ActionBar = nil
C_Timer = C_Timer
GetNumBattlefieldScores = function() return 0 end
GetBattlefieldStatus = function() return "none" end
GetMaxBattlefieldID = function() return 0 end
GetBattlefieldEstimatedWaitTime = function() return 0 end
GetBattlefieldTimeWaited = function() return 0 end
GetLFGMode = function() return nil end
GetLFGQueueStats = function() return nil end
UnitFrameHealPredictionBars_Update = function() end
-- (frames only, not their regions, in the order they were made)
EnumerateFrames = function(after)
	local index = 0
	if after then for i, f in ipairs(frames) do if f == after then index = i break end end end
	for i = index + 1, #frames do
		local f = frames[i]
		if f:IsObjectType("Frame") then return f end
	end
end
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end, ID = name } end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function(id) wow.settingsOpened = id end,
}
HandleModifiedItemClick = function() return false end
GameTooltip_Hide = function() GameTooltip:Hide() end
-- EventRegistry: callbacks by event or by name
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner) self.callbacks[event] = self.callbacks[event] or {} table.insert(self.callbacks[event], { fn, owner }) end
function EventRegistry:UnregisterCallback(event, owner) end
function EventRegistry:RegisterFrameEventAndCallback(event, fn, owner) self:RegisterCallback(event, fn, owner) end
function EventRegistry:TriggerEvent(event, ...) self:_Trigger(event, ...) end
function EventRegistry:_Trigger(event, ...)
	for _, cb in ipairs(self.callbacks[event] or {}) do
		-- (an owner is passed first, as the game's callback registry does)
		if cb[2] ~= nil then wow.call("EventRegistry " .. event, cb[1], cb[2], ...) else wow.call("EventRegistry " .. event, cb[1], ...) end
	end
end
LibStub = nil

-- The chat: message filters, and a line said (filters first, as the game runs them, then onto the chat frame).
wow.chatFilters = {} -- event -> { fn }
function ChatFrame_AddMessageEventFilter(event, fn)
	wow.chatFilters[event] = wow.chatFilters[event] or {}
	table.insert(wow.chatFilters[event], fn)
end
function ChatFrame_RemoveMessageEventFilter(event, fn)
	for index, f in ipairs(wow.chatFilters[event] or {}) do
		if f == fn then table.remove(wow.chatFilters[event], index) return end
	end
end
-- Say a line in a chat event: returns the text shown (nil: a filter hid it) and whether it was shown.
function wow.say(event, text, ...)
	local args = { text, ... }
	local frame = wow.chatFrame or ChatFrame1
	for _, filter in ipairs(wow.chatFilters[event] or {}) do
		-- (at least 13 arguments, as a chat event has: the missing ones nil)
		local results = { pcall(filter, frame, event, unpack(args, 1, math.max(#args, 13))) }
		if not results[1] then
			table.insert(wow.errors, { where = "chat filter " .. event, message = tostring(results[2]) })
			break
		end
		if results[2] then return nil, false end -- (true: the line hidden; else what it returns replaces the arguments)
		if results[3] ~= nil then for index = 3, #results do args[index - 2] = results[index] end end
	end
	frame:AddMessage(args[1], 1, 1, 1)
	return args[1], true
end
function ChatEdit_GetActiveWindow() return wow.activeEditBox end
function GetActionBarPage() return wow.page or 1 end
function GetBonusBarOffset() return 0 end
function SetItemRef(link, text, button) wow.itemRef = link end
-- The game's bag windows: the toggles show and hide ContainerFrameCombinedBags (closed at login).
wow.bagCalls = {}
local function GameBags(show)
	local f = rawget(_G, "ContainerFrameCombinedBags")
	if not f then return end
	if show == nil then show = not f:IsShown() end
	f:SetShown(show)
end
for name, show in pairs({ OpenAllBags = true, CloseAllBags = false, ToggleAllBags = "toggle", OpenBackpack = true,
	CloseBackpack = false, ToggleBackpack = "toggle", OpenBag = true, CloseBag = false, ToggleBag = "toggle" }) do
	_G[name] = function(...)
		table.insert(wow.bagCalls, name)
		if show == "toggle" then GameBags(nil) else GameBags(show) end
	end
end
function SetTooltipMoney() end
function PickupBagFromSlot() end
function PutItemInBag() end
function OpenStackSplitFrame() end

-- The game's frames ---------------------------------------------------------------------------------------------------
-- The ones Serene restyles or reads, made bare. A test can add the parts it needs.

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1365, 768)
WorldFrame = CreateFrame("Frame", "WorldFrame")
for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
	"GameFontDisable", "GameFontDisableSmall", "ChatFontNormal", "NumberFontNormal", "SystemFont_Shadow_Small",
	"GameFontNormalLarge", "GameFontHighlightLarge", "NumberFontNormalSmall", "GameFontWhite", "TextStatusBarText" }) do
	CreateFont(name)
end

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip:Hide()
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent)
ShoppingTooltip1 = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent)
ShoppingTooltip2 = CreateFrame("GameTooltip", "ShoppingTooltip2", UIParent)

for index = 1, NUM_CHAT_WINDOWS do
	local name = "ChatFrame" .. index
	local f = CreateFrame("ScrollingMessageFrame", name, UIParent)
	f:SetID(index)
	f:SetSize(430, 180)
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 100)
	local edit = CreateFrame("EditBox", name .. "EditBox", f)
	f.editBox = edit
	CreateFrame("Button", name .. "Tab", UIParent)
	CreateFrame("Frame", name .. "ButtonFrame", f)
	CHAT_FRAMES[index] = name
	if index > 2 then f:Hide() end
	-- (the history the game keeps, newest first: what ChatLoot and ChatLines rewrite lines through)
	local lines = {}
	f.lines = lines
	f.historyBuffer = { GetEntryAtIndex = function(_, i) return lines[i] end, GetNumElements = function() return #lines end }
	f.RemoveMessagesByPredicate = function(_, drop)
		for i = #lines, 1, -1 do if drop(lines[i]) then table.remove(lines, i) end end
	end
	f.MarkDisplayDirty = function() end
end
DEFAULT_CHAT_FRAME = ChatFrame1
SELECTED_CHAT_FRAME = ChatFrame1
function ChatFrame1:_FireMessage(event, ...) end

Minimap = CreateFrame("Minimap", "Minimap", UIParent)
Minimap:SetSize(140, 140)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)

-- the action buttons (Actions.FAMILIES)
for _, family in ipairs({ { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "PetActionButton", 10 }, { "StanceButton", 10 } }) do
	local bar = CreateFrame("Frame", family[1] == "ActionButton" and "MainMenuBar" or (family[1]:gsub("Button$", "")), UIParent)
	for index = 1, family[2] do
		local b = CreateFrame("CheckButton", family[1] .. index, bar, "SecureActionButtonTemplate")
		b:SetSize(36, 36)
		b:SetID(index)
		b.icon = b:CreateTexture(family[1] .. index .. "Icon")
		b.HotKey = b:CreateFontString(family[1] .. index .. "HotKey")
		b.Count = b:CreateFontString(family[1] .. index .. "Count")
		b.Name = b:CreateFontString(family[1] .. index .. "Name")
		b.cooldown = CreateFrame("Cooldown", family[1] .. index .. "Cooldown", b)
		b.NormalTexture = b:CreateTexture()
		if family[1] ~= "PetActionButton" and family[1] ~= "StanceButton" then
			-- (the slots each bar shows in the game: 1-12, bottom left 61-72, bottom right 49-60, right 25-36, left 37-48)
			local page = ({ ActionButton = 0, MultiBarBottomLeftButton = 5, MultiBarBottomRightButton = 4,
				MultiBarRightButton = 2, MultiBarLeftButton = 3 })[family[1]]
			b.action = page * 12 + index
			b:SetAttribute("action", b.action)
		end
	end
end

for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "TargetFrameToT", "FocusFrameToT",
	"BuffFrame", "DebuffFrame", "MainMenuBarArtFrame", "MicroButtonAndBagsBar", "MicroMenu", "BagsBar",
	"MainStatusTrackingBarContainer", "StatusTrackingBarManager", "ObjectiveTrackerFrame", "QuestWatchFrame",
	"MerchantFrame", "BankFrame", "PlayerCastingBarFrame", "CastingBarFrame", "EditModeManagerFrame",
	"ContainerFrameCombinedBags", "ChatFrameMenuButton", "QuickJoinToastButton", "ChatFrameChannelButton",
	"GameMenuFrame", "LootFrame", "StackSplitFrame", "AlertFrame", "ZoneTextFrame", "UIErrorsFrame" }) do
	CreateFrame("Frame", name, UIParent)
end
for index = 1, NUM_CONTAINER_FRAMES do CreateFrame("Frame", "ContainerFrame" .. index, UIParent):Hide() end
ContainerFrameCombinedBags:Hide()
MerchantFrame:Hide()
BankFrame:Hide()
EditModeManagerFrame:Hide()
-- (the how-many popup's parts, as the newer template keys them: a key read as a method otherwise, CancelButton
-- starting with a verb)
for _, key in ipairs({ "OkayButton", "CancelButton", "LeftButton", "RightButton" }) do
	StackSplitFrame[key] = CreateFrame("Button", nil, StackSplitFrame)
	StackSplitFrame[key]:SetSize(64, 24)
end
StackSplitFrame.StackSplitText = StackSplitFrame:CreateFontString()
for index = 1, 10 do
	local b = CreateFrame("Button", "MerchantItem" .. index, MerchantFrame)
	CreateFrame("Button", "MerchantItem" .. index .. "ItemButton", b)
end

-- A fight as this client has it: secret values -----------------------------------------------------------------------
-- wow.secretFight(true) puts the player in a fight (with PLAYER_REGEN_DISABLED) and makes the calls the client hides
-- in a fight answer as it does (measured in game, see docs/forever-client.md):
--   * the player's auras: GetAuraDataByIndex / GetUnitAuras / GetAuraSlots give nothing,
--     GetAuraDataByAuraInstanceID errors, UNIT_AURA's updateInfo fields are secret;
--   * other units' auras: every field secret;
--   * other units' health and power, cast info, cooldowns, usability and range: secret.
-- wow.secretFight(false) ends it (PLAYER_REGEN_ENABLED) and puts the plain calls back.
-- (An approximation: where the real client is unknown, it errs on the side of more secrets.)

local plain = {}
local function swap(holder, key, fn)
	plain[#plain + 1] = { holder, key, holder[key] }
	holder[key] = fn
end

local function secretFields(t, keep)
	if type(t) ~= "table" then return t end
	local out = {}
	for key, value in pairs(t) do out[key] = (keep and keep[key]) and value or wow.secret(value) end
	return out
end

local function secretAll(...)
	local out = { ... }
	for index = 1, select("#", ...) do if out[index] ~= nil then out[index] = wow.secret(out[index]) end end
	return unpack(out, 1, select("#", ...))
end

local function forOthers(fn)
	return function(unit, ...)
		if unit == "player" then return fn(unit, ...) end
		return secretAll(fn(unit, ...))
	end
end

function wow.secretFight(on)
	if on and #plain == 0 then -- (once: a second call doesn't wrap the wrappers)
		local A = C_UnitAuras
		local byIndex, byId, all = A.GetAuraDataByIndex, A.GetAuraDataByAuraInstanceID, A.GetUnitAuras
		swap(A, "GetAuraDataByIndex", function(unit, ...)
			if unit == "player" then return nil end
			return secretFields(byIndex(unit, ...))
		end)
		-- (through the wrapped call above: nothing for the player, secrets for the others)
		swap(A, "GetBuffDataByIndex", function(unit, index, filter) return A.GetAuraDataByIndex(unit, index, "HELPFUL" .. (filter or "")) end)
		swap(A, "GetDebuffDataByIndex", function(unit, index, filter) return A.GetAuraDataByIndex(unit, index, "HARMFUL" .. (filter or "")) end)
		swap(A, "GetAuraDataByAuraInstanceID", function(unit, id)
			if unit == "player" then error("GetAuraDataByAuraInstanceID: secret in combat") end
			return secretFields(byId(unit, id))
		end)
		swap(A, "GetUnitAuras", function(unit, ...) if unit == "player" then return {} end return all(unit, ...) end)
		swap(A, "GetAuraSlots", function() return nil end)
		swap(A, "GetPlayerAuraBySpellID", function() return nil end)
		swap(A, "GetAuraDataBySpellName", function() return nil end)
		local buff, debuff = UnitBuff, UnitDebuff
		swap(_G, "UnitBuff", function(unit, ...) if unit == "player" then return nil end return secretAll(buff(unit, ...)) end)
		swap(_G, "UnitDebuff", function(unit, ...) if unit == "player" then return nil end return secretAll(debuff(unit, ...)) end)
		for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitCastingInfo",
			"UnitChannelInfo", "UnitGetIncomingHeals", "UnitGetTotalAbsorbs" }) do
			swap(_G, name, forOthers(_G[name]))
		end
		for _, name in ipairs({ "GetActionCooldown", "IsUsableAction", "IsActionInRange", "GetActionCount" }) do
			local fn = _G[name]
			if fn then swap(_G, name, function(...) return secretAll(fn(...)) end) end
		end
		local cooldown = C_Spell.GetSpellCooldown
		swap(C_Spell, "GetSpellCooldown", function(...) return secretFields(cooldown(...), { isEnabled = true }) end)
		local usable, range = C_Spell.IsSpellUsable, C_Spell.IsSpellInRange
		swap(C_Spell, "IsSpellUsable", function(...) return secretAll(usable(...)) end)
		swap(C_Spell, "IsSpellInRange", function(...) return secretAll(range(...)) end)
		wow.fight(true)
		-- (the update a fight starts with: every field of its info secret)
		wow.fire("UNIT_AURA", "player", { isFullUpdate = wow.secret(false), addedAuras = wow.secret({}),
			removedAuraInstanceIDs = wow.secret({}), updatedAuraInstanceIDs = wow.secret({}) })
	elseif not on then
		for index = #plain, 1, -1 do
			local p = plain[index]
			p[1][p[2]] = p[3]
		end
		plain = {}
		wow.fight(false)
	end
end

-- Loading the addon ----------------------------------------------------------------------------------------------------

-- The addon's files in TOC order (Serene.toc).
function wow.tocFiles()
	local list = {}
	for line in io.lines(wow.root .. "/Serene.toc") do
		line = line:gsub("\r", "")
		if line:match("%.lua$") and not line:match("^#") then list[#list + 1] = line end
	end
	return list
end

-- Load some (or all) of the addon's files into one namespace, as the game does: each gets ("Serene", ns).
-- Core.lua always comes first. Returns ns.
function wow.load(files, opts)
	opts = opts or {}
	local ns = opts.ns or {}
	files = files or wow.tocFiles()
	-- (Core.lua first: it makes ns.modules and the helpers every file copies into locals at load)
	if files[1] ~= "Core.lua" then table.insert(files, 1, "Core.lua") end
	for _, file in ipairs(files) do
		local chunk, problem = loadfile(wow.root .. "/" .. file)
		if not chunk then error(problem, 0) end
		local ok, err = xpcall(function() chunk("Serene", ns) end, trace)
		if not ok then error(file .. " failed to load: " .. err, 0) end
	end
	wow.ns = ns
	return ns
end

-- The game's login: saved variables loaded (SereneDB, or nil for a new player), ADDON_LOADED, PLAYER_LOGIN (every
-- module's init), PLAYER_ENTERING_WORLD.
function wow.login(saved)
	SereneDB = saved -- (the game sets saved variables just before ADDON_LOADED)
	wow.fire("ADDON_LOADED", "Serene")
	wow.loggedIn = true
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", true, false) -- (isInitialLogin, isReloadingUi)
end

-- Lines the addon printed in red (a module's init that failed, caught by Core.lua).
function wow.redLines()
	local found = {}
	for _, line in ipairs(wow.printed) do
		if type(line) == "string" and line:find("|cffff6060", 1, true) then found[#found + 1] = line end
	end
	return found
end

-- Globals looked up that nothing defines (realistic: the game reads them as nil). Kept for the report.
-- (set last, so the stub's own lookups while it builds itself aren't counted)
setmetatable(_G, { __index = function(_, key)
	if type(key) == "string" then wow.missing[key] = (wow.missing[key] or 0) + 1 end
	return nil
end })

return wow
