local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Keys that teach and then step back. Each action button with a key bound learns how you press it: by its key, or
-- clicked with the mouse. Clicked although it has a key: its key comes up bright (soft white instead of grey), to
-- be seen and learnt. Pressed by its key, again and again, never clicked: the key is known, and its label goes away
-- (back under the mouse). A new key on the button starts it over. Remembered for each character.
--   (Settings > Action bars > Keys; with Serene's action bars)

local GAIN = 0.07      -- each press by the key: this much of the way to "known"
local LOSS = 0.5       -- a click: what is left of it
local KNOWN = 0.85     -- known from here: the label away
local BRIGHT = 0.35    -- below this, after a click: the label bright
local START = 0.4      -- a new key

local store            -- this character's: button name -> { key = the key's text, score = 0..1, clicked = bool }
local lastClick = {}   -- button -> time (one click heard once, down and up)
local over = {}        -- button -> under the mouse

local function Name(button) return button.GetName and button:GetName() end

-- The key bound to the button, as the game shows it.
local function Key(button)
	local name = Name(button)
	local label = rawget(button, "HotKey") or (name and _G[name .. "HotKey"])
	local text = label and Clean(Safe(label.GetText, label))
	-- (the game's dot on a button with no key bound is not a key)
	if type(text) ~= "string" or text == "" or (_G.RANGE_INDICATOR and text == _G.RANGE_INDICATOR) then return nil end
	return text
end

local function Entry(button)
	local name, key = Name(button), Key(button)
	if not store or not name or not key then return nil end
	local entry = store[name]
	if not entry or entry.key ~= key then
		entry = { key = key, score = START, clicked = false }
		store[name] = entry
	end
	return entry
end

-- How the key looks now: "hidden" (known), "bright" (being learnt), or nil (as always).
function ns.KeyLook(button)
	if not ns.On("barKeysLearn") or over[button] then return nil end
	local name = Name(button)
	local entry = store and name and store[name]
	if not entry or entry.key ~= Key(button) then return nil end
	if entry.score >= KNOWN then return "hidden" end
	if entry.clicked and entry.score <= BRIGHT then return "bright" end
	return nil
end

local function Show(button)
	if ns.BarsKey then ns.BarsKey(button) end
end

-- (others told of every press too: BarUse.lua counts them)
local listeners = {}
function ns.OnBarPress(fn) listeners[#listeners + 1] = fn end

local function Pressed(button, byKey)
	for _, fn in ipairs(listeners) do pcall(fn, button, byKey) end
	if not ns.On("barKeysLearn") then return end
	local entry = Entry(button)
	if not entry then return end
	local before = ns.KeyLook(button)
	if byKey then
		entry.score = entry.score + (1 - entry.score) * GAIN
		if entry.score > BRIGHT then entry.clicked = false end
	else
		entry.score = entry.score * LOSS
		entry.clicked = true
	end
	if ns.KeyLook(button) ~= before then Show(button) end
end

local function Init()
	if not ns.On("actionBars") then return end
	local who = (Clean(Safe(GetRealmName)) or "?") .. "-" .. (Clean(Safe(UnitName, "player")) or "?")
	ns.db.keyLearn = ns.db.keyLearn or {}
	ns.db.keyLearn[who] = ns.db.keyLearn[who] or {}
	store = ns.db.keyLearn[who]
	-- (by the key: the game's key bindings press a button through this, on the way down and up)
	if type(_G.TryUseActionButton) == "function" then
		hooksecurefunc("TryUseActionButton", function(button, down)
			-- (the down press only; nil when the game doesn't say, counted)
			if down ~= false and type(button) == "table" then pcall(Pressed, button, true) end
		end)
	end
	-- (by the mouse: the button's click, which a key binding doesn't go through)
	local done = {}
	local function Hook(button)
		if done[button] or not button.HookScript then return end
		done[button] = true
		button:HookScript("OnClick", function(self, mouse)
			if mouse ~= "LeftButton" and mouse ~= "RightButton" then return end
			local now = GetTime()
			if lastClick[self] and now - lastClick[self] < 0.3 then return end
			lastClick[self] = now
			pcall(Pressed, self, false)
		end)
		-- (a known key shown again under the mouse)
		button:HookScript("OnEnter", function(self) over[self] = true Show(self) end)
		button:HookScript("OnLeave", function(self) over[self] = nil Show(self) end)
	end
	local function All() if ns.BarsEach then ns.BarsEach(Hook) end end
	All()
	-- (again a moment later, for buttons ActionBars.lua dresses just after login)
	-- NOTE: buttons dressed only after a fight (a /reload in one) never get these hooks
	C_Timer.After(1, All)
end

local function Refresh()
	if ns.BarsEach then ns.BarsEach(Show) end
end

function ns.KeysDebug()
	local known, bright, total = 0, 0, 0
	if ns.BarsEach then
		ns.BarsEach(function(button)
			local look = ns.KeyLook(button)
			if Key(button) then total = total + 1 end
			if look == "hidden" then known = known + 1 elseif look == "bright" then bright = bright + 1 end
		end)
	end
	ns.Print(("keys: learning %s; %d bound, %d known (away), %d bright"):format(tostring(ns.On("barKeysLearn")),
		total, known, bright))
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
