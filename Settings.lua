local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Serene's settings: a page of its own in the game's Options (AddOns > Serene), or its own window where the game
-- has no such page. /serene opens it. Pages of their own (General, Chat, Map, Action bars, Unit frames, Buffs, Bags,
-- Tooltips), chosen by quiet words across the top (the chosen one gold on a hairline), each in two columns of
-- sections; the page last open opens again. Every change is saved and applied at once (some parts themselves on a
-- reload: a button says so).

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local GOLD = { 1, 0.82, 0.35 }
local TEXT = { 0.92, 0.91, 0.88 }
local MUTED = ns.MUTED_RGB
local INK = ns.INK
local COLUMN, GAP = 290, 28
local HEAD = 94      -- the title, its words and the pages' names above the scrolling page
local PAGE_TOP = 4   -- the page's first row below its top
local TAB_GAP = 20   -- between two pages' names
local ROW, CHOICE_ROW, SLIDER_ROW, HEAD_ROW = 22, 44, 42, 32

local canvas -- the page as the game's Options (or Serene's window) hold it
local panel  -- what scrolls inside it: the pages
local page   -- (the page being built)
local scroll, Thumb
local pages = {} -- in order: { key, name, frame, height, tab }
local controls = {} -- each with :Update()
local needsReload = false
local reloadButton
local category

local function Apply()
	if ns.Refresh then ns.Refresh() end
	for _, control in ipairs(controls) do control:Update() end
end

-- A setting read and written by its path ("fade", "groups.bars").
local function Get(path)
	local table_, key = ns.db, path
	local first, rest = path:match("^(%w+)%.(%w+)$")
	if first then table_, key = ns.db[first], rest end
	return table_ and table_[key]
end

local function Set(path, value)
	local first, rest = path:match("^(%w+)%.(%w+)$")
	if first then ns.db[first][rest] = value else ns.db[path] = value end
end

-- Widgets ---------------------------------------------------------------------------------------------------------

local function Label(parent, text, font, color)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	label:SetText(text)
	if color then label:SetTextColor(color[1], color[2], color[3]) end
	label:SetJustifyH("LEFT")
	return label
end

-- A column: rows put one under the other.
local function Column(x)
	return { x = x, y = -PAGE_TOP }
end

local function Place(column, frame, height)
	frame:SetPoint("TOPLEFT", page, "TOPLEFT", column.x, column.y)
	frame:SetSize(COLUMN, height)
	column.y = column.y - height
end

-- (a row whose setting only matters while another is on, or set to one value ("auraFrame=serene"): dimmed when not)
local function Dims(row, depends)
	function row:Dimmed()
		if not depends then return false end
		for _, path in ipairs(depends) do
			local key, value = path:match("^(.-)=(.+)$")
			local off = path:match("^!(.+)$")
			if off then
				if Get(off) then return true end
			elseif key then
				if Get(key) ~= value then return true end
			elseif not Get(path) then
				return true
			end
		end
		return false
	end
end

local function Header(column, text)
	local row = CreateFrame("Frame", nil, page)
	Place(column, row, HEAD_ROW)
	local label = Label(row, text:upper(), "GameFontNormalSmall", GOLD)
	label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 10)
	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)
	line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
end

-- A switch: a small rounded track, a knob sliding to the right when on (gold).
local function Toggle(column, text, path, opts)
	opts = opts or {}
	local row = CreateFrame("Button", nil, page)
	Place(column, row, ROW)
	Dims(row, opts.depends)
	row.label = Label(row, text)
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	if opts.note then
		row.note = Label(row, opts.note, "GameFontHighlightSmall", MUTED)
		row.note:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
	end
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetTexture(MEDIA .. "Track")
	row.track:SetSize(32, 16)
	row.track:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.knob = row:CreateTexture(nil, "OVERLAY")
	row.knob:SetTexture(MEDIA .. "Disc")
	row.knob:SetSize(12, 12)
	row.at = 0
	local function Knob()
		row.knob:ClearAllPoints()
		row.knob:SetPoint("LEFT", row.track, "LEFT", 2 + row.at * 16, 0)
	end
	function row:Update()
		local on = Get(path) and true or false
		self.on = on
		if on then
			self.track:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
			self.knob:SetVertexColor(INK[1], INK[2], INK[3], 1)
		else
			self.track:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.16)
			self.knob:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
		end
		self:SetAlpha(self:Dimmed() and 0.4 or 1)
		if not self.sliding then
			self.at = on and 1 or 0
			Knob()
		end
	end
	-- (the knob slides)
	row:SetScript("OnUpdate", function(self, elapsed)
		local want = self.on and 1 or 0
		if self.at == want then self.sliding = false return end
		self.sliding = true
		self.at = ns.Approach(self.at, want, elapsed, 0.12, 0.12)
		Knob()
	end)
	row:SetScript("OnClick", function(self)
		Set(path, not Get(path))
		if opts.reload then needsReload = true end
		if opts.after then opts.after() end
		Apply()
	end)
	row:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
	row:SetScript("OnLeave", function(self) self.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3]) end)
	controls[#controls + 1] = row
	return row
end

-- A choice: its label, then its options side by side; the chosen one in gold on a soft pill.
local function Choice(column, text, path, options, opts)
	opts = opts or {}
	local row = CreateFrame("Frame", nil, page)
	Place(column, row, CHOICE_ROW)
	Dims(row, opts.depends)
	row.label = Label(row, text)
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
	row.chips = {}
	local x = 0
	for _, option in ipairs(options) do
		local chip = CreateFrame("Button", nil, row)
		chip.value = option[1]
		chip.ground = chip:CreateTexture(nil, "BACKGROUND")
		chip.ground:SetTexture(MEDIA .. "Pill")
		chip.ground:SetAllPoints()
		chip.text = Label(chip, option[2], "GameFontHighlightSmall")
		chip.text:SetPoint("CENTER")
		local width = math.floor((Clean(Safe(chip.text.GetStringWidth, chip.text)) or 50) + 18 + 0.5)
		chip:SetSize(width, 18)
		chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -22)
		x = x + width + 4
		chip:SetScript("OnClick", function()
			Set(path, chip.value)
			if opts.after then opts.after() end
			Apply()
		end)
		chip:SetScript("OnEnter", function(self) if not self.chosen then self.text:SetTextColor(1, 1, 1) end end)
		chip:SetScript("OnLeave", function() row:Update() end)
		row.chips[#row.chips + 1] = chip
	end
	function row:Update()
		local value = Get(path)
		for _, chip in ipairs(self.chips) do
			chip.chosen = chip.value == value
			if chip.chosen then
				chip.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
				chip.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			else
				chip.ground:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.06)
				chip.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
			end
		end
		self:SetAlpha(self:Dimmed() and 0.4 or 1)
	end
	controls[#controls + 1] = row
	return row
end

-- A row of buttons (doing something, not a setting): its label, then soft pills side by side.
local function Actions(column, text, actions, opts)
	opts = opts or {}
	local row = CreateFrame("Frame", nil, page)
	Place(column, row, CHOICE_ROW)
	Dims(row, opts.depends)
	row.label = Label(row, text)
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
	local x = 0
	for _, action in ipairs(actions) do
		local chip = CreateFrame("Button", nil, row)
		chip.ground = chip:CreateTexture(nil, "BACKGROUND")
		chip.ground:SetTexture(MEDIA .. "Pill")
		chip.ground:SetAllPoints()
		chip.ground:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.06)
		chip.text = Label(chip, action[1], "GameFontHighlightSmall")
		chip.text:SetPoint("CENTER")
		chip.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
		local width = math.floor((Clean(Safe(chip.text.GetStringWidth, chip.text)) or 50) + 18 + 0.5)
		chip:SetSize(width, 18)
		chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -22)
		x = x + width + 4
		chip:SetScript("OnClick", function()
			if action[2] then action[2]() end
			Apply()
		end)
		chip:SetScript("OnEnter", function(self)
			self.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
			self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		end)
		chip:SetScript("OnLeave", function(self)
			self.ground:SetVertexColor(TEXT[1], TEXT[2], TEXT[3], 0.06)
			self.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.75)
		end)
	end
	function row:Update() self:SetAlpha(self:Dimmed() and 0.4 or 1) end
	controls[#controls + 1] = row
	return row
end

-- A slider: its label and value above, a hairline track filled in gold up to a round knob.
local function Slider(column, text, path, low, high, step, show, opts)
	opts = opts or {}
	local row = CreateFrame("Frame", nil, page)
	Place(column, row, SLIDER_ROW)
	Dims(row, opts.depends)
	row.label = Label(row, text)
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
	row.value = Label(row, "", "GameFontHighlightSmall", GOLD)
	row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -5)
	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -22)
	slider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -22)
	slider:SetHeight(14)
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(TEXT[1], TEXT[2], TEXT[3], 0.16)
	track:SetHeight(2)
	track:SetPoint("LEFT", slider, "LEFT", 0, 0)
	track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(MEDIA .. "Disc")
	thumb:SetSize(12, 12)
	thumb:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	slider:SetThumbTexture(thumb)
	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
	fill:SetHeight(2)
	fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
	fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
	row.slider = slider
	local quiet = false
	slider:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value / step + 0.5) * step
		row.value:SetText(show(value))
		if quiet then return end
		Set(path, value)
		if opts.after then opts.after() end
		if ns.Refresh then ns.Refresh() end
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(math.max(low, math.min(high, (self:GetValue() or low) + delta * step)))
	end)
	function row:Update()
		quiet = true
		local value = tonumber(Get(path)) or low
		self.slider:SetValue(value)
		self.value:SetText(show(value))
		quiet = false
		self:SetAlpha(self:Dimmed() and 0.4 or 1)
	end
	controls[#controls + 1] = row
	return row
end

local function Seconds(value)
	if value < 60 then return ("%d s"):format(value) end
	local minutes, seconds = math.floor(value / 60), value % 60
	if seconds == 0 then return ("%d min"):format(minutes) end
	return ("%d min %d s"):format(minutes, seconds)
end

-- Quiet lines of words ------------------------------------------------------------------------------------------------

-- A quiet line of words (how something works).
local function Note(column, text, opts)
	opts = opts or {}
	local row = CreateFrame("Frame", nil, page)
	Place(column, row, ROW)
	Dims(row, opts.depends)
	row.label = Label(row, text, "GameFontHighlightSmall", MUTED)
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	function row:Update() self:SetAlpha(self:Dimmed() and 0.4 or 1) end
	controls[#controls + 1] = row
	return row
end

local function Hints()
	if ns.HintsDirty then ns.HintsDirty() end
end

-- The pages ------------------------------------------------------------------------------------------------------------
-- Each builds its sections into a left and a right column.

local PAGES = {
	{ "general", "General", function(left, right)
		Header(left, "Fading")
		Toggle(left, "Fade the interface when calm", "fade")
		Toggle(left, "Action bars", "groups.bars", { depends = { "fade" } })
		Toggle(left, "Your portrait and pet", "groups.unit", { depends = { "fade" } })
		Toggle(left, "Buffs and debuffs", "groups.buffs", { depends = { "fade" } })
		Toggle(left, "Menu, bags and experience", "groups.menu", { depends = { "fade" } })
		Toggle(left, "Compass", "groups.minimap", { depends = { "fade" } })
		Slider(left, "Faded parts stay visible", "rest", 0, 100, 5, function(v) return ("%d%%"):format(v) end,
			{ depends = { "fade" } })
		Toggle(left, "Experience gained: its bar, lit", "xpGain", { note = "the new part" })

		Header(right, "Rest")
		Toggle(right, "Rest mode when you are idle", "idle")
		Slider(right, "Rest after", "idleAfter", 30, 900, 30, Seconds, { depends = { "idle" } })
		Toggle(right, "Hide the quest tracker", "tracker")

		Header(right, "Hints")
		Toggle(right, "Glow on buttons worth using", "hints")
		Choice(right, "When something glows, show", "hintReveal",
			{ { "none", "Nothing" }, { "button", "Its button" }, { "bar", "Its bar" }, { "bars", "All bars" } },
			{ depends = { "hints" }, after = Hints })
		Toggle(right, "Food when you are not Well Fed", "hintFood", { depends = { "hints" }, after = Hints })
		Toggle(right, "What your class keeps up", "hintBuffs", { depends = { "hints" }, note = "when missing",
			after = Hints })
		Note(right, "Buffs, armors, auras, poisons, imbues.", { depends = { "hints", "hintBuffs" } })
		Toggle(right, "Faintly as it runs out", "hintBuffSoon", { depends = { "hints", "hintBuffs" }, note = "still glow",
			after = Hints })
		Slider(right, "Running out from", "hintBuffSoonAt", 30, 600, 15, Seconds,
			{ depends = { "hints", "hintBuffs", "hintBuffSoon" }, after = Hints })
	end },

	{ "chat", "Chat", function(left, right)
		Header(left, "Chat")
		Toggle(left, "Chat in glass", "chat", { note = "reload", reload = true })
		Slider(left, "Messages stay", "lineTime", 5, 300, 5, Seconds, { depends = { "chat" } })
		Toggle(left, "Short channel tags  [G] [1]", "tags", { depends = { "chat" } })
		Toggle(left, "One speaker's lines together", "group", { depends = { "chat" } })
		Toggle(left, "Player card on hover", "card", { depends = { "chat" } })
		Toggle(left, "Arrow keys move in what you write", "chatArrows",
			{ note = "Up/Down: what you sent", depends = { "chat" } })
		Toggle(left, "Messages down to the bottom", "chatRoom",
			{ note = "they rise as you write", depends = { "chat" } })
		Toggle(left, "All messages while you write", "chatReveal",
			{ note = "the faded ones too", depends = { "chat" } })

		Header(right, "Fewer lines")
		Toggle(right, "Loot and rolls in few lines", "loot", { depends = { "chat" } })
		Toggle(right, "Money, experience, reputation", "gains", { note = "one line", depends = { "chat" } })
		Toggle(right, "Quiet online and offline lines", "quiet", { depends = { "chat" } })
		Toggle(right, "Public channels wait during fights", "calm", { depends = { "chat" } })
	end },

	{ "map", "Map and top bar", function(left, right)
		Header(left, "Compass")
		Toggle(left, "Serene's compass", "minimap", { note = "reload", reload = true })
		Choice(left, "Its edge", "edge", { { "round", "Round" }, { "square", "Square" } },
			{ depends = { "minimap" }, after = function() if ns.MinimapEdge then Safe(ns.MinimapEdge) end end })
		Choice(left, "It shows", "compass", { { "hover", "On hover only" }, { "world", "Out in the world" } },
			{ depends = { "fade", "groups.minimap" } })
		Note(left, "Fading it: General.", { depends = { "minimap" } })

		Header(right, "Top bar")
		Toggle(right, "Serene's top bar", "top", { note = "instead of Titan Panel" })
		Choice(right, "It shows", "topShow", { { "hover", "On hover" }, { "calm", "Away in fights" }, { "always", "Always" } },
			{ depends = { "top", "fade" } })
		Note(right, "Right click it: what it shows.  Shift and drag: move it.", { depends = { "top" } })

		Header(right, "Menu and bags")
		Toggle(right, "The menu and bags as words", "menuBar", { note = "reload", reload = true })
		Note(right, "Under the top bar, shown when the mouse comes to it.", { depends = { "menuBar" } })
	end },

	{ "bars", "Action bars", function(left, right)
		Header(left, "Action bars")
		Toggle(left, "Serene's action bars", "actionBars", { note = "reload", reload = true })
		Toggle(left, "Keys on the buttons", "barKeys", { depends = { "actionBars" } })
		Toggle(left, "Macro names", "barNames", { depends = { "actionBars" } })
		Toggle(left, "Show empty slots", "barEmpty", { note = "off: see-through", depends = { "actionBars" } })
		Note(left, "Where they sit and how big: the game's Edit Mode.", { depends = { "actionBars" } })

		local ready = { "barReady" }
		Header(left, "Readiness")
		Toggle(left, "Fade what isn't ready", "barReady", { note = "the rest stays full" })
		Choice(left, "When", "barReadyWhen", { { "always", "Always" }, { "fight", "In fights only" } },
			{ depends = ready })
		Slider(left, "Not ready stays at", "barReadyDim", 0, 80, 5, function(v) return ("%d%%"):format(v) end,
			{ depends = ready })
		Toggle(left, "On cooldown", "barReadyCooldown", { note = "not the global one", depends = ready })
		Toggle(left, "Short of mana, rage, energy", "barReadyPower", { depends = ready })
		Toggle(left, "Unusable now", "barReadyUnusable", { note = "form, reagent...", depends = ready })
		Toggle(left, "Attacks without an enemy", "barReadyTarget", { note = "you, a friend", depends = ready })
		Toggle(left, "Out of range", "barReadyRange", { depends = ready })
		Toggle(left, "The bar under the mouse at full", "barReadyHover", { depends = ready })
		Note(left, "Procs, hints and the action in use always stay full.", { depends = ready })

		local bars = { "actionBars" }
		local styles = { { "classic", "Classic" }, { "glass", "Glass" }, { "round", "Round" } }
		Header(left, "Look")
		Choice(left, "The buttons", "barStyle", styles, { depends = { "actionBars", "barStyleSame" } })
		Toggle(left, "The same for every bar", "barStyleSame", { depends = bars, after = function()
			-- (each bar starts from the look every bar had)
			if not ns.db.barStyleSame then
				for _, bar in ipairs(ns.BAR_KEYS or {}) do ns.db.barStyles[bar[1]] = ns.db.barStyle end
			end
		end })
		for _, bar in ipairs(ns.BAR_KEYS or {}) do
			Choice(left, bar[2], "barStyles." .. bar[1], styles, { depends = { "actionBars", "!barStyleSame" } })
		end
		Note(left, "A new look waits for the end of a fight.", { depends = bars })

		Header(right, "Cooldowns")
		Choice(right, "On the buttons", "barCooldown", { { "style", "The look's own" }, { "sweep", "Sweep" },
			{ "line", "Line" }, { "none", "None" } }, { depends = bars })
		Note(right, "The look's own: Classic a sweep, Glass a line, Round its ring.", { depends = bars })
		Choice(right, "Their numbers", "barCooldownText", { { "game", "The game's" }, { "soon", "Last 3 s" },
			{ "always", "Always" }, { "never", "Never" } }, { depends = bars })
		Toggle(right, "One global cooldown line", "barGcd", { note = "under bar 1", depends = bars })
		Toggle(right, "A ring when a long one is back", "barPing", { note = "once", depends = bars })
		Slider(right, "Long from", "barPingMin", 5, 300, 5, Seconds, { depends = { "actionBars", "barPing" } })
		Note(right, "Seen on faded bars too, the spell's icon with it.", { depends = { "actionBars", "barPing" } })

		Header(right, "Keys and pages")
		Toggle(right, "Keys that teach", "barKeysLearn", { note = "bright, then away", depends = { "actionBars", "barKeys" } })
		Note(right, "Clicked: its key bright.  Always pressed by key: away.", { depends = { "actionBars", "barKeys" } })
		Toggle(right, "Calm page changes", "barPages", { note = "and the page's number" })

		Header(right, "Ranks and reagents")
		Toggle(right, "New ranks onto the bars", "barRanks", { note = "your old highest only" })
		Toggle(right, "By itself", "barRanksAuto", { note = "off: a mark and a button", depends = { "barRanks" } })
		Toggle(right, "Reagents running low", "barReagents", { note = "amber; a word at merchants",
			depends = bars })
		Slider(right, "Low from", "barReagentLow", 1, 20, 1, function(v) return ("%d casts left"):format(v) end,
			{ depends = { "actionBars", "barReagents" } })

		Header(right, "Your bars kept")
		Toggle(right, "Keep a copy of your bars", "barSets", { note = "a talent reset..." })
		Note(right, "What leaves them by itself: a button over bar 1 puts it back.", { depends = { "barSets" } })
		Actions(right, "Save these bars as", { { "Solo", function() ns.BarSetSave("solo") end },
			{ "Group", function() ns.BarSetSave("group") end }, { "Raid", function() ns.BarSetSave("raid") end } })
		Actions(right, "Put on", { { "Solo", function() ns.BarSetLoad("solo") end },
			{ "Group", function() ns.BarSetLoad("group") end }, { "Raid", function() ns.BarSetLoad("raid") end },
			{ "Undo", function() ns.BarSetLoad("undo") end } })
		Note(right, "Any name: /serene sets save|load <name>. For each character.")

		Header(right, "Supplies")
		Toggle(right, "The best food, water, potions", "barSupplies", { note = "kept up to date" })
		local supplies = {}
		for _, kind in ipairs(ns.SUPPLY_KINDS or {}) do
			supplies[#supplies + 1] = { kind.label, function() ns.SupplyPickup(kind.key) end }
		end
		Actions(right, "Onto the cursor, for a bar", supplies, { depends = { "barSupplies" } })
		Note(right, "Each a macro of this character's, rewritten out of fights.", { depends = { "barSupplies" } })

		Header(right, "How you use them")
		Toggle(right, "Point out unused buttons", "barUse", { note = "a line in the chat", depends = bars })
		Slider(right, "Unused after", "barUseHours", 2, 50, 1, function(v) return ("%d h of play"):format(v) end,
			{ depends = { "actionBars", "barUse" } })
		Actions(right, "Your bars", { { "Review", function() ns.BarReview() end },
			{ "Ask about kept ones again", function() ns.BarUseUnkeep() end } }, { depends = { "actionBars", "barUse" } })
		Note(right, "Unused: keep, fade (with readiness) or clear. Easier keys: a swap.", { depends = { "actionBars", "barUse" } })

		Header(right, "Swing timer")
		Toggle(right, "The game's swing timer made calm", "swing", { note = "thin lines" })
		Toggle(right, "Auto Shot and wands", "swingRanged", { note = "in gold", depends = { "swing" } })
		Slider(right, "Size", "swingSize", 50, 300, 10, function(v) return ("%d%%"):format(v) end,
			{ depends = { "swing" } })
		Note(right, "Shown by the game's option; where it sits and how wide: Edit Mode.")
	end },

	{ "units", "Unit frames", function(left, right)
		Header(left, "Unit frames")
		Toggle(left, "Serene's unit frames", "units", { note = "reload", reload = true })
		Toggle(left, "Portraits", "unitPortraits", { note = "round", depends = { "units" } })
		Toggle(left, "Elite and rare dragon", "unitElite", { note = "the game's art", depends = { "units", "unitPortraits" } })
		Choice(left, "Edge", "unitBorder", { { "line", "Hairline of gold" }, { "none", "Glass only" } },
			{ depends = { "units" } })
		Toggle(left, "Mana regeneration timer", "manaRegen", { note = "five seconds, in gold" })
		Note(left, "You, pet, target, focus.  Where they sit: Edit Mode.", { depends = { "units" } })

		Header(right, "Cast bar")
		Toggle(right, "Your cast bar made calm", "castBar", { note = "reload", reload = true })
		Slider(right, "Height", "castHeight", 4, 24, 1, function(v) return ("%d"):format(v) end, { depends = { "castBar" } })
		Slider(right, "Width", "castWidth", ns.CAST_WIDTH_GAME, 400, 10, function(v)
			return v <= ns.CAST_WIDTH_GAME and "Edit Mode's" or ("%d"):format(v)
		end, { depends = { "castBar" } })
		Toggle(right, "The spell's icon", "castIcon", { depends = { "castBar" } })
		Choice(right, "The spell's name", "castText", { { "in", "In the bar" }, { "under", "Under it" }, { "none", "None" } },
			{ depends = { "castBar" } })
		Slider(right, "Text size", "castFont", ns.CAST_FONT_AUTO, 16, 1, function(v)
			return v <= ns.CAST_FONT_AUTO and "Auto" or ("%d"):format(v)
		end, { depends = { "castBar" } })
		Note(right, "Where it sits, its scale and the time: Edit Mode.", { depends = { "castBar" } })
	end },

	{ "auras", "Buffs", function(left, right)
		local on = { "auras" }
		local own = { "auras", "auraFrame=serene" }
		local step = { "auras", "auraFrame=serene", "auraTiers" }
		local function Secs(v) return Seconds(v) end
		Header(left, "Your buffs")
		Toggle(left, "Serene's buffs and debuffs", "auras", { note = "reload", reload = true })
		Choice(left, "Shown in", "auraFrame", { { "serene", "Serene's frame" }, { "game", "The game's, restyled" } },
			{ depends = on, after = function() needsReload = true end })
		Slider(left, "Size", "auraSize", 20, 48, 1, function(v) return ("%d"):format(v) end, { depends = own })
		Slider(left, "In a row", "auraPerRow", 4, 20, 1, function(v) return ("%d"):format(v) end, { depends = own })
		Choice(left, "Icons", "auraShape", { { "round", "Round" }, { "square", "Square" } }, { depends = on })
		Choice(left, "A line around", "auraRing",
			{ { "all", "Every one" }, { "debuffs", "Debuffs only" }, { "none", "None" } }, { depends = on })
		Slider(left, "Its thickness", "auraRingSize", 1, 3, 1, function(v)
			return v == 1 and "a hairline" or ("%d pixels"):format(v)
		end, { depends = on })
		Toggle(left, "Icon and ring darken as time runs out", "auraDim", { depends = on })
		Toggle(left, "Others' rings drain as time runs out", "auraDrain", { note = "target, nameplates", depends = on })
		Toggle(left, "A dark edge around it", "auraEdge", { note = "on bright ground", depends = on })
		Actions(left, "Where they sit", {
			{ "Place them", function() if ns.AuraMove then ns.AuraMove() end end },
			{ "The game's place", function() if ns.AuraReset then ns.AuraReset() end end },
		}, { depends = own })

		Header(left, "Stepping back")
		Toggle(left, "Long, steady buffs step back", "auraTiers", { depends = own })
		Slider(left, "Into a row of small rings, sized", "auraSmall", 10, 24, 1, function(v) return ("%d"):format(v) end,
			{ depends = step })
		Slider(left, "Full size when it lasts up to", "auraShort", 30, 900, 30, Secs, { depends = step })
		Note(left, "Auras, stances, an hour of Fortitude: in the small row.", { depends = step })

		Header(left, "Missing and precious")
		Toggle(left, "Missing class buffs, faint", "auraGhosts", { note = "click: cast", depends = own })
		Toggle(left, "World buffs on a shelf of their own", "auraWorld", { depends = own })

		Header(right, "Time left")
		Choice(right, "Shown", "auraTimeWhen", { { "soon", "In its last stretch" }, { "always", "Always" },
			{ "never", "Never" } }, { depends = own })
		Slider(right, "Its last stretch", "auraSoon", 15, 600, 15, Secs, { depends = { "auras", "auraFrame=serene",
			"auraTimeWhen=soon" } })
		Choice(right, "Its look", "auraTime", { { "outline", "Outlined" }, { "plate", "On glass" }, { "none", "Hidden" } },
			{ depends = on })
		Choice(right, "Where", "auraTimeAt", { { "under", "Under the icon" }, { "on", "On its edge" } },
			{ depends = on })
		Slider(right, "Its size", "auraTimeSize", ns.AURA_FONT_AUTO or 6, 14, 1, function(v)
			return v <= (ns.AURA_FONT_AUTO or 6) and "Auto" or ("%d"):format(v)
		end, { depends = on })
		Note(right, "Muted; soft white in the last seconds.", { depends = on })

		Header(right, "Debuffs")
		Slider(right, "Size", "auraDebuffSize", 20, 56, 1, function(v) return ("%d"):format(v) end, { depends = own })
		Choice(right, "Where", "auraDebuffAt", { { "buffs", "Under the buffs" }, { "portrait", "By your portrait" },
			{ "free", "Where placed" } }, { depends = own })
		Toggle(right, "Those you can remove in colour", "auraDispel", { note = "the rest grey", depends = own })
		Choice(right, "Their colours", "auraColors", { { "quiet", "Quiet shades" }, { "game", "The game's" } },
			{ depends = on })

		Header(right, "Under the mouse")
		Note(right, "The game's tooltip.  Right click: cancel.", { depends = own })

		Header(right, "Others' auras")
		Toggle(right, "Target and focus", "auraUnits", { note = "reload", reload = true, depends = on })
		Toggle(right, "Nameplates", "auraPlates", { note = "your debuffs on enemies; reload", reload = true,
			depends = on })
		Toggle(right, "The game's fold arrow on hover only", "auraArrow", { depends = { "auras", "auraFrame=game" } })
	end },

	{ "bags", "Bags", function(left, right)
		Header(left, "Bags and bank")
		Toggle(left, "Serene's bags and bank", "bags", { note = "reload", reload = true })
		Slider(left, "Cells in a row", "bagColumns", 6, 16, 1, function(v) return tostring(v) end, { depends = { "bags" } })
		Toggle(left, "Counts in item tooltips", "bagCounts", { note = "bank, alts", depends = { "bags" } })
		Choice(left, "The bank opens", "bankAt", { { "bags", "Beside the bags" }, { "free", "Where you put it" } },
			{ depends = { "bags" } })
		Note(left, "Alt-right-click an item: its section.", { depends = { "bags" } })
		Note(left, "Shift and drag: move.", { depends = { "bags" } })

		Header(right, "Merchants")
		Toggle(right, "Serene's merchant window", "merchant")
		Choice(right, "It opens", "merchantAt", { { "bags", "Beside the bags" }, { "game", "Where the game's does" } },
			{ depends = { "merchant" } })
		Toggle(right, "How many you have", "merchantCounts", { note = "bags, bank", depends = { "merchant" } })
		Toggle(right, "Search and \"usable only\"", "merchantSearch", { depends = { "merchant" } })
		Toggle(right, "Sell the junk", "sellJunk", { note = "greys, the bags' Junk" })
		Toggle(right, "Repair everything", "autoRepair")
		Toggle(right, "With the guild's money first", "repairGuild", { depends = { "autoRepair" } })
		Toggle(right, "Buy a full stack", "vendor", { note = "Alt-click" })
		Note(right, "Right click: buy one.  Shift-click: how many.")
		Note(right, "Shift held when opening: nothing sold or repaired.")
	end },

	{ "tips", "Tooltips", function(left, right)
		Header(left, "Tooltips")
		Toggle(left, "Calm tooltips", "tooltip", { note = "glass, soft, Shift for more" })
		Toggle(left, "Wait during fights", "tipcalm", { note = "enemies show; Shift shows the rest",
			depends = { "tooltip" } })
		Toggle(left, "Addons' lines on items", "tipmore", { note = "with Shift", depends = { "tooltip" } })
		Toggle(left, "Players as a card", "tipcard", { depends = { "tooltip" } })
		Toggle(left, "Vendor price on items", "tipvendor", { note = "the whole stack" })

		Header(right, "Toasts")
		Toggle(right, "Recipes and achievements", "toast", { note = "reload", reload = true })
		Actions(right, "Where toasts appear", {
			{ "Place them", function() if ns.ToastMove then ns.ToastMove() end end },
			{ "The game's place", function() if ns.ToastReset then ns.ToastReset() end end },
			{ "A sample", function() if ns.ToastTest then ns.ToastTest() end end },
		})
		Note(right, "Cards of glass; every toast stacks up from there.")
	end },
}

local WIDTH = 16 * 2 + COLUMN * 2 + GAP

-- (the page longer than the space for it: the mouse wheel scrolls it, a thin gold line tells where)
local function Scrolling()
	scroll = CreateFrame("ScrollFrame", nil, canvas)
	scroll:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -HEAD)
	scroll:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)
	panel = CreateFrame("Frame", nil, scroll)
	panel:SetSize(WIDTH, 600)
	scroll:SetScrollChild(panel)
	local thumb = canvas:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	thumb:SetWidth(2)
	local function Most()
		return math.max(0, (panel:GetHeight() or 0) - (scroll:GetHeight() or 0))
	end
	Thumb = function()
		local most, seen = Most(), scroll:GetHeight() or 0
		if most <= 0 or seen <= 0 then return thumb:Hide() end
		local whole = most + seen
		local length = math.max(24, seen * seen / whole)
		local at = (seen - length) * (scroll:GetVerticalScroll() / most)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -3, -HEAD - at)
		thumb:SetHeight(length)
		thumb:Show()
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(Most(), self:GetVerticalScroll() - delta * 48)))
		Thumb()
	end)
	scroll:SetScript("OnSizeChanged", function(self, width)
		panel:SetWidth(math.max(WIDTH, width or 0))
		self:SetVerticalScroll(math.min(Most(), self:GetVerticalScroll()))
		Thumb()
	end)
	canvas:HookScript("OnShow", Thumb)
end

-- The pages' names across the top: quiet words, the chosen one gold on a hairline.
local function PaintTabs()
	local chosen = ns.db and ns.db.settingsPage
	for _, p in ipairs(pages) do
		local tab = p.tab
		local on = p.key == chosen
		tab.on = on
		if on then
			tab.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		elseif tab.over then
			tab.text:SetTextColor(1, 1, 1)
		else
			tab.text:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 0.7)
		end
		tab.line:SetShown(on)
	end
end

local function Show(key)
	local found
	for _, p in ipairs(pages) do
		if p.key == key then found = p end
	end
	found = found or pages[1]
	ns.db.settingsPage = found.key
	for _, p in ipairs(pages) do p.frame:SetShown(p == found) end
	panel:SetHeight(found.height)
	scroll:SetVerticalScroll(0)
	PaintTabs()
	Thumb()
end

local function Tabs()
	local x = 16
	for _, p in ipairs(pages) do
		local tab = CreateFrame("Button", nil, canvas)
		tab.text = Label(tab, p.name, "GameFontHighlight")
		tab.text:SetPoint("LEFT", tab, "LEFT", 0, 0)
		local width = math.floor((Clean(Safe(tab.text.GetStringWidth, tab.text)) or 60) + 0.5)
		tab:SetSize(width, 22)
		tab:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -62)
		x = x + width + TAB_GAP
		tab.line = tab:CreateTexture(nil, "ARTWORK")
		tab.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
		tab.line:SetHeight(1)
		tab.line:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -3)
		tab.line:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", 0, -3)
		tab:SetScript("OnClick", function() Show(p.key) end)
		tab:SetScript("OnEnter", function(self) self.over = true PaintTabs() end)
		tab:SetScript("OnLeave", function(self) self.over = false PaintTabs() end)
		p.tab = tab
	end
	-- (a hairline under them all, the chosen one's brighter on it)
	local rule = canvas:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -62 - 22 - 3)
	rule:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -16, -62 - 22 - 3)
end

local function Build()
	canvas = CreateFrame("Frame", "SereneSettingsPanel")
	canvas.name = "Serene"
	canvas:Hide()
	Scrolling()

	local title = Label(canvas, "Serene", "GameFontNormalHuge", GOLD)
	title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
	local tagline = Label(canvas, "A calm interface: what you don't need fades away and comes back when it matters.",
		"GameFontHighlightSmall", MUTED)
	tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	for _, def in ipairs(PAGES) do
		page = CreateFrame("Frame", nil, panel)
		page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
		page:SetSize(WIDTH, 10)
		page:Hide()
		local left, right = Column(16), Column(16 + COLUMN + GAP)
		def[3](left, right)
		local height = -math.min(left.y, right.y) + 24
		page:SetHeight(height)
		pages[#pages + 1] = { key = def[1], name = def[2], frame = page, height = height }
	end
	page = nil
	Tabs()
	Show(ns.db.settingsPage)

	-- (a setting needing a reload: a button to do it)
	reloadButton = CreateFrame("Button", nil, canvas)
	reloadButton:SetSize(150, 22)
	reloadButton:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -16, -20)
	reloadButton:SetFrameLevel(panel:GetFrameLevel() + 10)
	reloadButton.ground = reloadButton:CreateTexture(nil, "BACKGROUND")
	reloadButton.ground:SetTexture(MEDIA .. "Pill")
	reloadButton.ground:SetAllPoints()
	reloadButton.ground:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
	reloadButton.text = Label(reloadButton, "Reload to apply", "GameFontHighlightSmall", INK)
	reloadButton.text:SetPoint("CENTER")
	reloadButton:SetScript("OnClick", function() ReloadUI() end)
	reloadButton:Hide()

	local base = Apply
	Apply = function()
		base()
		reloadButton:SetShown(needsReload)
	end
	canvas:HookScript("OnShow", function() Apply() end)
end

-- Where the page lives ------------------------------------------------------------------------------------------------

local window -- (only where the game's Options have no page for addons)
local function Window()
	if window then return window end
	window = CreateFrame("Frame", "SereneSettingsWindow", UIParent)
	window:SetSize(WIDTH, 640)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	local ground = window:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.94)
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
	tinsert(UISpecialFrames, "SereneSettingsWindow")
	canvas:SetParent(window)
	canvas:ClearAllPoints()
	canvas:SetAllPoints(window)
	canvas:Show()
	window:Hide()
	return window
end

-- (a page by its key: "general", "chat", "map", "bars", "units", "auras", "bags", "tips")
function ns.OpenSettings(key)
	if not canvas then Build() end
	if key then Show(key) end
	if category and Settings and Settings.OpenToCategory then
		local id = category.GetID and category:GetID() or category.ID
		Safe(Settings.OpenToCategory, id)
		return
	end
	if _G.InterfaceOptionsFrame_OpenToCategory and canvas.parent == nil and canvas.registered then
		Safe(_G.InterfaceOptionsFrame_OpenToCategory, canvas)
		Safe(_G.InterfaceOptionsFrame_OpenToCategory, canvas)
		return
	end
	local w = Window()
	w:SetShown(not w:IsShown())
end

local function Init()
	Build()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, made = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "Serene")
		if ok and made then
			category = made
			pcall(Settings.RegisterAddOnCategory, category)
		end
	elseif _G.InterfaceOptions_AddCategory then
		if pcall(_G.InterfaceOptions_AddCategory, canvas) then canvas.registered = true end
	end
end

table.insert(ns.modules, { init = Init })
