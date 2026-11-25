local _, ns = ...
local Safe, Clean, IsSecret, Over = ns.Safe, ns.Clean, ns.IsSecret, ns.Over

-- The chat in glass.
-- * No window: the chat's frame, its background, its buttons and scroll bar are taken away. Each message lies on
--   its own soft dark backdrop, as wide as the window, and goes with it when the game fades it out. Nothing is
--   drawn where there is no message.
-- * The game's own lines and colors ("[1. General] [Name]: text"), the channel's zone dropped ("[2. Trade]").
-- * The tabs as plain words (the one shown in gold, over a fine gold line), only under the mouse. The line to
--   write in gets a dark glass ground with a gold edge while you type. The window's own look (a faint pane, the
--   menu and channels as small icons, a slim scroll bar, the "new" pill, the resize grip): ChatShell.lua.
-- * A message naming you: a thin gold edge and a light gold tint; a whisper: a violet edge.
-- * The mouse over an item, a spell or a quest in a message: its tooltip, no click needed. Friends and guild coming
--   online or going offline in a quiet grey, shorter (/serene quiet on|off).
-- * The lines themselves (short tags, one speaker's lines together, the hour, new lines fading in, the public
--   channels waiting in a fight, copying): ChatLines.lua. Loot, rolls, money and experience: ChatLoot.lua.
-- The game's chat engine is left whole (windows, tabs, links, filters, history): only its look changes.

local INK = { 0.035, 0.04, 0.05 }
local VEIL = 0.5            -- the backdrop's darkness
local PAD_X = 6             -- room left of the words (above and below: half the line spacing, so backdrops meet)
local TAIL = 0              -- (a soft end beyond the window's edge: none, the backdrop fills the window)
local EDGE = 2              -- the coloured edge's width: a message naming you, a whisper, the line being written
local TINT = 0.09           -- the gold tint over a message naming you
local GOLD = { 1, 0.82, 0.35 }
local VIOLET = { 0.886, 0.545, 0.91 }
local TAB_WORDS = { 0.92, 0.91, 0.88 }
local FADE_DURATION = 3     -- seconds a message takes to fade out, once its time is up
local HOVER_IN, HOVER_OUT, LINGER = 0.15, 0.35, 1.2 -- the controls coming, going; seconds kept after the mouse leaves
local TAB_ROOM, BOX_ROOM = 30, 34 -- the tabs above the lines, the line to write in below, counted as the chat
local ROOM_PAD = 4          -- (the messages, let down into the line to write in's room, stop this short of its foot)
local GLIDE_UP, GLIDE_DOWN = 0.22, 0.34 -- seconds for the messages to rise as you start writing, and settle after
local REVEAL = 0.3          -- seconds for the faded messages to come back as you start writing

local FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft",
	"HighlightMiddle", "HighlightRight", "SelectedLeft", "SelectedMiddle", "SelectedRight", "glow" }
local BOX_ART = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }
-- The chat's buttons: the menu and the channels kept (in our own look, ChatShell.lua), the rest taken away.
local BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton" }
local DROPPED = { "QuickJoinToastButton", "FriendsMicroButton", "ChatFrameSocialButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "TextToSpeechButtonFrame" }

local hidden = CreateFrame("Frame")
hidden:Hide()
local under, holder -- the backdrops' layer; the chat's buttons, shown under the mouse
local dressed = {} -- chat window -> true
local veils = setmetatable({}, { __mode = "k" }) -- a drawn line -> its backdrop
local widths = setmetatable({}, { __mode = "k" }) -- chat window -> its last known width (hidden in a fight)
local seen = {} -- the backdrops drawn this frame (any other is hidden)
local myName, myPattern
local hover, lastNear = 0, -math.huge
local FadeTabs -- (below)
local active = false

-- (moved into a frame never shown, not hidden: the game shows its art again)
local function Tuck(region)
	if type(region) == "table" and region.SetParent and region:GetParent() ~= hidden then
		pcall(region.SetParent, region, hidden)
	end
end

local function Round(value) return math.floor((value or 0) + 0.5) end

-- Windows -----------------------------------------------------------------------------------------------------------

local function Windows()
	local list = {}
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. index]
		if type(frame) == "table" and frame.AddMessage then list[#list + 1] = frame end
	end
	-- (the private messages' own windows, opened by the game)
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if type(frame) == "table" and frame.AddMessage then
			local known = false
			for _, each in ipairs(list) do known = known or each == frame end
			if not known then list[#list + 1] = frame end
		end
	end
	return list
end

local function Selected()
	local get, dock = _G.FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK
	return get and dock and Safe(get, dock) or ChatFrame1
end

-- Tabs: plain words, the one shown in gold over a fine gold line.
local function PaintTab(tab, selected)
	if type(tab) ~= "table" then return end
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if type(text) ~= "table" or not text.SetTextColor then return end
	if selected == nil then -- (not told by the game: its window compared with the one shown)
		local name = tab.GetName and tab:GetName()
		local frame = name and _G[(name:gsub("Tab$", ""))]
		selected = frame ~= nil and frame == Selected()
	end
	local c = selected and GOLD or TAB_WORDS
	text:SetTextColor(c[1], c[2], c[3])
	if tab.sereneLine then tab.sereneLine:SetShown(selected and true or false) end
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 1)
end

local function StyleTab(tab)
	if type(tab) ~= "table" then return end
	local name = tab.GetName and tab:GetName() or ""
	for _, key in ipairs(TAB_ART) do
		Tuck(tab[key])
		Tuck(_G[name .. key])
	end
	if not tab.sereneLine and tab.CreateTexture then
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		local line = tab:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
		line:SetHeight(1)
		if type(text) == "table" and text.GetObjectType then
			line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
			line:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 0, -3)
		else
			line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 4)
			line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 4)
		end
		tab.sereneLine = line
	end
	PaintTab(tab)
end

-- The line to write in: the arrow keys move in what you write (Ctrl: a word at a time), as in any text field;
-- Up and Down bring back what you sent before. The game's line wants Alt held for moving (its "classic" chat
-- style), and its own memory of sent lines answers only Up and Down with Alt then: so with this on, Serene keeps
-- that memory itself (the one way ElvUI and Prat do it), and Alt+Up/Down still reach the game's. Lines with a
-- secure command (/cast, /use, /target...) are left to the game's memory (Alt+Up/Down): written back by an
-- addon, the game might refuse to run them.
local sent = {}           -- what you sent, oldest first (all the windows' lines)
local SENT_MOST = 50
local boxes = {}          -- the lines to write in, dressed

local function Secure(text)
	local command = text:match("^(/%S+)")
	if not command then return false end
	local isSecure = rawget(_G, "IsSecureCmd")
	if type(isSecure) ~= "function" then return true end -- (can't tell: left to the game)
	return Safe(isSecure, command:lower()) and true or false
end

local function Remember(_, text)
	if type(text) ~= "string" or IsSecret(text) or text == "" or Secure(text) then return end
	if sent[#sent] == text then return end
	sent[#sent + 1] = text
	if #sent > SENT_MOST then table.remove(sent, 1) end
end

local function Recall(box, key)
	if not ns.On("chatArrows") or (key ~= "UP" and key ~= "DOWN") then return end
	if IsAltKeyDown() or #sent == 0 then return end -- (Alt: the game's own memory)
	local back = box.sereneBack or 0
	if key == "UP" then
		back = math.min(back + 1, #sent)
	else
		back = back - 1
		if back < 1 then
			box.sereneBack = 0
			box:SetText("")
			return
		end
	end
	box.sereneBack = back
	box:SetText(sent[#sent - back + 1])
	box:SetCursorPosition(#sent[#sent - back + 1])
end

local function Arrows(box)
	pcall(box.SetAltArrowKeyMode, box, not ns.On("chatArrows"))
end

local function HearKeys(box)
	boxes[box] = true
	Arrows(box)
	if box.AddHistoryLine then hooksecurefunc(box, "AddHistoryLine", Remember) end
	box:HookScript("OnKeyDown", Recall)
	box:HookScript("OnEditFocusLost", function(self) self.sereneBack = 0 end)
	box:HookScript("OnEditFocusGained", Arrows) -- (should the game set its own mode back, e.g. its chat style changed)
end

-- The line to write in: no art; while you type, a dark glass ground with a gold edge on its left.
local function StyleBox(box)
	if type(box) ~= "table" or box.sereneGround then return end
	local name = box.GetName and box:GetName() or ""
	for _, key in ipairs(BOX_ART) do
		Tuck(box[key])
		Tuck(_G[name .. key])
	end
	local ground = box:CreateTexture(nil, "BACKGROUND")
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.82)
	ground:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -4)
	ground:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 4)
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	edge:SetWidth(EDGE)
	edge:SetPoint("TOPLEFT", ground, "TOPLEFT")
	edge:SetPoint("BOTTOMLEFT", ground, "BOTTOMLEFT")
	local rim = box:CreateTexture(nil, "BORDER")
	rim:SetColorTexture(1, 1, 1, 0.06)
	rim:SetHeight(1)
	rim:SetPoint("TOPLEFT", ground, "TOPLEFT", EDGE, 0)
	rim:SetPoint("TOPRIGHT", ground, "TOPRIGHT")
	box.sereneGround = ground
	local function Show()
		local focused = Safe(box.HasFocus, box) and true or false
		ground:SetShown(focused)
		edge:SetShown(focused)
		rim:SetShown(focused)
	end
	box:HookScript("OnEditFocusGained", Show)
	box:HookScript("OnEditFocusLost", Show)
	box:HookScript("OnShow", Show)
	Show()
	HearKeys(box)
end

local Polish -- (below)
local function Dress(frame)
	if dressed[frame] then return end
	dressed[frame] = true
	Polish(frame)
	local name = frame:GetName() or ""
	for _, key in ipairs(FRAME_ART) do Tuck(_G[name .. key]) end
	Tuck(frame.buttonFrame or _G[name .. "ButtonFrame"])
	Tuck(frame.ScrollBar)
	Tuck(frame.ScrollToBottomButton)
	Tuck(_G[name .. "ResizeButton"])
	pcall(frame.SetFading, frame, true)
	pcall(frame.SetTimeVisible, frame, ns.db.lineTime)
	pcall(frame.SetFadeDuration, frame, FADE_DURATION)
	StyleTab(_G[name .. "Tab"])
	StyleBox(frame.editBox or _G[name .. "EditBox"])
end

-- The chat's buttons: the kept ones carried into a frame of ours, shown under the mouse (ChatShell.lua places
-- and dresses them); the others taken away.
local function Carry()
	if InCombatLockdown() then return end -- (lockdown: the buttons wait for the next pass after the fight)
	for _, list in ipairs({ BUTTONS, DROPPED }) do
		local into = list == BUTTONS and holder or hidden
		for _, name in ipairs(list) do
			local button = _G[name]
			if type(button) == "table" and button.SetParent and button:GetParent() ~= into then
				-- (a protected button stays with the game: moving it would taint)
				local protected = button.IsProtected and select(1, button:IsProtected())
				if not protected then pcall(button.SetParent, button, into) end
			end
		end
	end
	if ns.ShellDress then Safe(ns.ShellDress) end
end

local function DressAll()
	for _, frame in ipairs(Windows()) do Dress(frame) end
	Carry()
end

-- The window as Edit Mode shows it ----------------------------------------------------------------------------------
-- Edit Mode's box for the chat holds the tabs, the line to write in and, on the left, the room of the game's button
-- strip (taken away here). The messages are widened into that room, and the window's look (ChatShell.lua) fills the
-- box, so the chat is as large as Edit Mode says.

local function Box(frame)
	local box = type(frame) == "table" and frame.Selection
	-- (a docked window has no box of its own: the dock's, on the first window; unreadable, as in a fight: none)
	if not box and type(frame) == "table" and frame.isDocked and ChatFrame1 then box = ChatFrame1.Selection end
	if type(box) == "table" and box.GetLeft and Clean(Safe(box.GetLeft, box)) then return box end
end
ns.ChatBox = Box

function ns.ChatDebug()
	local frame = Selected()
	local function Rect(r) 
		if not r then return "none" end
		return ("%s %s %s %s"):format(tostring(Round(Clean(Safe(r.GetLeft, r)))), tostring(Round(Clean(Safe(r.GetRight, r)))),
			tostring(Round(Clean(Safe(r.GetTop, r)))), tostring(Round(Clean(Safe(r.GetBottom, r)))))
	end
	ns.Print("chat window (l r t b): " .. Rect(frame) .. "  edit mode box: " .. Rect(frame and Box(frame))
		.. "  widened by " .. tostring(frame and frame.sereneGain))
end

-- The line to write in's room ----------------------------------------------------------------------------------------
-- The line to write in lies under the window, inside Edit Mode's box: an empty band while nobody writes. So the
-- messages are let down into it then, and rise to make way as you start writing (the line itself fading in under
-- them), settling back once you're done: a smooth glide each way, never a jump.

local function WriteBox(frame)
	local name = frame:GetName() or ""
	return frame.editBox or _G[name .. "EditBox"]
end

-- (how far below the window the messages may go: down to Edit Mode's box's foot, else the line to write in's)
local function Room(frame, box)
	if not ns.On("chatRoom") then return 0 end
	local mode = Safe(frame.GetInsertMode, frame)
	if mode ~= nil and mode == _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP then return 0 end
	local own = Clean(Safe(frame.GetBottom, frame))
	local foot = Box(frame)
	foot = foot and Clean(Safe(foot.GetBottom, foot))
	if not foot and type(box) == "table" then foot = Clean(Safe(box.GetBottom, box)) end
	if own and foot then
		local room = Round(own - foot - ROOM_PAD)
		-- (a line to write in above the window, or one far off: no room taken)
		frame.sereneRoom = (room > 0 and room <= 60) and room or 0
	end
	return frame.sereneRoom or 0 -- (positions unreadable, as in a fight: the room last measured)
end

local function Ease(t) return t * t * (3 - 2 * t) end

-- (the line being written in, if any: in the game's "classic" style the docked windows all write in the first's)
local function Writing()
	local util = rawget(_G, "ChatFrameUtil")
	local get = rawget(_G, "ChatEdit_GetActiveWindow") or (type(util) == "table" and util.GetActiveWindow)
	local box = type(get) == "function" and Safe(get)
	if type(box) == "table" and Safe(box.HasFocus, box) then return box end
end

-- Every message seen while you write --------------------------------------------------------------------------------
-- As you start writing, the messages the game had faded come back (each from where its fade had got to, over a
-- moment): the window stops fading. Once you're done they fade away again from then on, over the game's own fade,
-- as any message does (the game counts a message's fade from the later of its own time and the window's
-- overrideFadeTimestamp: that is set to "just now, its time to be seen over").

local revealed = {} -- window -> { at = when, from = { [message] = its opacity then } }

local function Reveal(frame)
	if revealed[frame] or not ns.On("chatReveal") then return end
	local from = {}
	for _, line in ipairs(type(frame.visibleLines) == "table" and frame.visibleLines or {}) do
		local message = rawget(line, "messageInfo")
		if message then
			local alpha = Safe(line.IsShown, line) and Clean(Safe(line.GetAlpha, line)) or 0
			if alpha < 0.99 then from[message] = alpha end
		end
	end
	revealed[frame] = { at = GetTime(), from = from }
	pcall(frame.SetFading, frame, false)
	-- (the game shows them all at once on its next refresh: it is asked now, and each is set back where it was)
	pcall(frame.RefreshIfNecessary, frame)
	for _, line in ipairs(type(frame.visibleLines) == "table" and frame.visibleLines or {}) do
		local alpha = from[rawget(line, "messageInfo") or false]
		if alpha then pcall(line.SetAlpha, line, alpha) end
	end
end

local function Settle(frame)
	if not revealed[frame] then return end
	revealed[frame] = nil
	local now = GetTime()
	local visible = Clean(Safe(frame.GetTimeVisible, frame)) or ns.db.lineTime or 30
	local override = rawget(frame, "overrideFadeTimestamp")
	if type(override) == "number" and not IsSecret(override) then
		-- (never moved back: a later one the game set stands)
		frame.overrideFadeTimestamp = math.max(override, now - visible)
	end
	pcall(frame.SetFading, frame, true)
end

-- (one step of a returning message's opacity: from where it was to fully seen)
local function Revealing(frame, line)
	local r = revealed[frame]
	if not (r and r.from) then return end
	local t = math.min(1, (GetTime() - r.at) / REVEAL)
	local from = r.from[rawget(line, "messageInfo") or false]
	if from then pcall(line.SetAlpha, line, from + (1 - from) * Ease(t)) end
	if t >= 1 then r.from = nil end
end

-- How far down the messages lie now (0 while you write), one step of the glide further.
local function Glide(frame, elapsed)
	local box = WriteBox(frame)
	local room = Room(frame, box)
	local active = Writing()
	local owner = active and rawget(active, "chatFrame")
	local writing = active ~= nil and (active == box
		or (frame.isDocked and type(owner) == "table" and owner.isDocked)) or false
	if writing then
		box = active
		Reveal(frame)
	else
		Settle(frame)
	end
	local target = writing and 1 or 0
	local up = frame.sereneUp or target -- (first seen: already in place, no glide at login)
	up = ns.Approach(up, target, elapsed or 0, GLIDE_UP, GLIDE_DOWN)
	frame.sereneUp = up
	if room > 0 and type(box) == "table" then
		-- (the line to write in comes in under the rising messages, and goes as they settle over it)
		-- (held each frame: the game sets its own opacity on it as it opens and closes it)
		local alpha = writing and Ease(up) or 0
		box.sereneAlpha = alpha
		local now = Clean(Safe(box.GetAlpha, box))
		if now == nil or math.abs(now - alpha) > 0.002 then pcall(box.SetAlpha, box, alpha) end
	elseif type(box) == "table" and box.sereneAlpha then
		box.sereneAlpha = nil
		pcall(box.SetAlpha, box, 1)
	end
	return Round(room * (1 - Ease(up))), room
end

local function Gain(frame)
	local box = Box(frame)
	local left = box and Clean(Safe(box.GetLeft, box))
	local own = Clean(Safe(frame.GetLeft, frame))
	if not (left and own) then return 0 end
	-- (the backdrop's own pad and a little air kept inside the box's left edge)
	return math.max(0, Round(own - left - PAD_X - 4))
end

-- (the game lays its lines from the window's left edge, as wide as the window; the first moved left by the gain,
-- every one as much wider, the window's mouse area with them)
-- (and let down by drop, into the room under the window: see Glide)
local function Widen(frame, width, drop, room)
	local lines = frame.visibleLines
	if type(lines) ~= "table" or not lines[1] then return 0 end
	local gain = Gain(frame)
	drop, room = drop or 0, room or 0
	-- (it runs every frame: laid out again only when something changed)
	if frame.sereneGain == gain and frame.sereneFirst == lines[1] and frame.sereneWidth == width
		and frame.sereneCount == #lines and frame.sereneDrop == drop and frame.sereneRoomAt == room then
		return gain
	end
	frame.sereneGain, frame.sereneFirst, frame.sereneWidth, frame.sereneCount = gain, lines[1], width, #lines
	frame.sereneDrop, frame.sereneRoomAt = drop, room
	local mode = Safe(frame.GetInsertMode, frame)
	local top = mode ~= nil and mode == _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP
	local corner = top and "TOPLEFT" or "BOTTOMLEFT"
	pcall(lines[1].ClearAllPoints, lines[1])
	pcall(lines[1].SetPoint, lines[1], corner, frame, corner, -gain, top and 0 or -drop)
	for _, line in ipairs(lines) do pcall(line.SetWidth, line, width + gain) end
	pcall(frame.SetHitRectInsets, frame, -gain, 0, 0, -drop)
	-- (the lines' holder cuts what lies outside it: it is widened the same way, and reaches down into the room)
	local holder = frame.FontStringContainer
	if type(holder) == "table" and holder.SetPoint and (holder.sereneGain ~= gain or holder.sereneRoom ~= room) then
		holder.sereneGain, holder.sereneRoom = gain, room
		pcall(holder.ClearAllPoints, holder)
		pcall(holder.SetPoint, holder, "TOPLEFT", frame, "TOPLEFT", -gain, 0)
		pcall(holder.SetPoint, holder, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -room)
	end
	return gain
end

-- The line to write in and the tabs, their words starting where the messages' words start. Each is moved sideways
-- by its left anchors only (a right anchor stays: the line to write in keeps its right end); checked now and then,
-- so a place the game gives them again is corrected.
local function Shift(region, by)
	local count = Clean(Safe(region.GetNumPoints, region)) or 0
	if count == 0 then return end
	local points = {}
	for at = 1, count do points[at] = { Safe(region.GetPoint, region, at) } end
	pcall(region.ClearAllPoints, region)
	for _, p in ipairs(points) do
		local point, relative, relativePoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
		if type(point) == "string" and (point:find("LEFT") or not point:find("RIGHT")) then x = x + by end
		pcall(region.SetPoint, region, point, relative, relativePoint, x, y)
	end
end

-- (where in it the words start: measured once seen, if likely; else the last measure, else a guess)
local function Inset(region, words, guess)
	local left = Clean(Safe(region.GetLeft, region))
	local at = type(words) == "table" and Clean(Safe(words.GetLeft, words))
	if left and at and at - left > 0 and at - left < 60 then region.sereneInset = Round(at - left) end
	return region.sereneInset or guess
end

local function Align(region, words, guess, left)
	if type(region) ~= "table" or not region.GetLeft then return end
	local inset = Inset(region, words, guess)
	local now = Clean(Safe(region.GetLeft, region))
	if not now then return end
	local by = Round(left - inset - now)
	if by ~= 0 then Shift(region, by) end
	return inset
end

local function AlignAll()
	local frame = Selected()
	local own = frame and Clean(Safe(frame.GetLeft, frame))
	if not own then return end
	local left = own - (frame.sereneGain or 0) -- (where the messages' words start)
	for _, each in ipairs(Windows()) do
		local name = each:GetName() or ""
		local box = each.editBox or _G[name .. "EditBox"]
		if box and (each == frame or box:IsShown()) then
			local inset = Align(box, box.header or _G[name .. "EditBoxHeader"], 15, left)
			-- (its glass and gold edge where the messages' backdrops start)
			if inset and box.sereneGround and box.sereneGroundAt ~= inset then
				box.sereneGroundAt = inset
				box.sereneGround:ClearAllPoints()
				box.sereneGround:SetPoint("TOPLEFT", box, "TOPLEFT", inset - PAD_X, -4)
				box.sereneGround:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 4)
			end
		end
	end
	local dock, tab = _G.GeneralDockManager, _G.ChatFrame1Tab
	-- (a protected dock is the game's to place)
	if dock and tab and not Safe(dock.IsProtected, dock) then
		local words = tab.Text or (tab.GetFontString and tab:GetFontString())
		local tabLeft, dockLeft = Clean(Safe(tab.GetLeft, tab)), Clean(Safe(dock.GetLeft, dock))
		-- (the tab's words, counted from the dock's left: the first tab sits at the dock's left)
		local wordsLeft = type(words) == "table" and Clean(Safe(words.GetLeft, words))
		if tabLeft and dockLeft and wordsLeft and wordsLeft - dockLeft > 0 and wordsLeft - dockLeft < 60 then
			dock.sereneInset = Round(wordsLeft - dockLeft)
		end
		if dockLeft then
			local by = Round(left - (dock.sereneInset or 12) - dockLeft)
			if by ~= 0 then Shift(dock, by) end
		end
	end
end
ns.ChatAlign = AlignAll -- (tests)

-- The tabs ----------------------------------------------------------------------------------------------------------
-- Docked tabs live in the game's dock: the dock fades as one, under the mouse. A window of its own has its tab
-- faded alone. A tab calling you (a new whisper in another tab) stays seen.
FadeTabs = function(alpha)
	local dock = _G.GeneralDockManager
	if dock and dock.SetAlpha and dock.sereneAlpha ~= alpha then
		dock.sereneAlpha = alpha
		pcall(dock.SetAlpha, dock, alpha)
	end
	for _, frame in ipairs(Windows()) do
		local tab = _G[(frame:GetName() or "") .. "Tab"]
		if type(tab) == "table" and tab.SetAlpha then
			local alert = tab.alerting and true or false
			if tab.sereneAlert ~= alert then
				-- (an alerting tab stays seen while the dock it sits in is faded)
				tab.sereneAlert = alert
				pcall(tab.SetIgnoreParentAlpha, tab, alert)
			end
			-- (in the dock: the dock's opacity is the tab's)
			local inDock, parent = false, tab:GetParent()
			for _ = 1, 4 do
				if not parent then break end
				if parent == dock then inDock = true break end
				parent = parent.GetParent and parent:GetParent() or nil
			end
			local want = (alert or inDock) and 1 or alpha
			if Safe(tab.GetAlpha, tab) ~= want then pcall(tab.SetAlpha, tab, want) end
		end
	end
end

-- Backdrops ---------------------------------------------------------------------------------------------------------

local function Lines(frame)
	local list = frame.visibleLines
	if type(list) == "table" then return list end
	local container = frame.FontStringContainer
	if type(container) == "table" and container.GetRegions then
		local found = {}
		for _, region in ipairs({ container:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then found[#found + 1] = region end
		end
		return found
	end
	return {}
end

local function Veil(line)
	local v = veils[line]
	if v then return v end
	v = { alpha = -1 } -- (-1: never drawn, so the first opacity always applies)
	v.solid = under:CreateTexture(nil, "BACKGROUND")
	v.solid:SetColorTexture(INK[1], INK[2], INK[3], VEIL)
	v.tail = under:CreateTexture(nil, "BACKGROUND")
	v.tail:SetColorTexture(1, 1, 1, 1)
	v.tail:SetWidth(math.max(1, TAIL))
	v.tint = under:CreateTexture(nil, "BORDER")
	v.edge = under:CreateTexture(nil, "ARTWORK")
	v.edge:SetWidth(EDGE)
	v.parts = { v.solid, v.tail, v.tint, v.edge }
	for _, part in ipairs(v.parts) do part:Hide() end
	veils[line] = v
	return v
end

ns.ChatVeil = function(line) return veils[line] end -- (tests)

local function HideVeil(v)
	if v.alpha == 0 then return end
	for _, part in ipairs(v.parts) do part:Hide() end
	v.alpha = 0
end

-- A gradient's own colors carry its opacity (the game draws it whatever SetAlpha says).
local function Tail(v, alpha)
	local key = math.floor(alpha * 100 + 0.5)
	if v.tailKey == key then return end
	v.tailKey = key
	local a = VEIL * key / 100
	if v.tail.SetGradient and CreateColor then
		v.tail:SetGradient("HORIZONTAL", CreateColor(INK[1], INK[2], INK[3], a), CreateColor(INK[1], INK[2], INK[3], 0))
	else
		v.tail:SetColorTexture(INK[1], INK[2], INK[3], a / 2)
	end
end

-- (above and below: exactly half the spacing between lines, so two backdrops meet edge to edge and never
-- overlap: an overlap of two veils reads as a dark line between messages)
local function Place(v, line, width, spacing)
	local half = spacing / 2
	if v.line ~= line or v.spacing ~= spacing then
		v.line, v.spacing = line, spacing
		v.solid:ClearAllPoints()
		v.solid:SetPoint("TOPLEFT", line, "TOPLEFT", -PAD_X, half)
		v.solid:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -PAD_X, -half)
		v.tail:ClearAllPoints()
		v.tail:SetPoint("TOPLEFT", v.solid, "TOPRIGHT")
		v.tail:SetPoint("BOTTOMLEFT", v.solid, "BOTTOMRIGHT")
		v.tint:ClearAllPoints()
		v.tint:SetPoint("TOPLEFT", v.solid, "TOPLEFT")
		v.tint:SetPoint("BOTTOMRIGHT", v.solid, "BOTTOMRIGHT")
		v.edge:ClearAllPoints()
		v.edge:SetPoint("TOPLEFT", v.solid, "TOPLEFT")
		v.edge:SetPoint("BOTTOMLEFT", v.solid, "BOTTOMLEFT")
	end
	width = Round(width + PAD_X * 2)
	if v.width ~= width then
		v.width = width
		v.solid:SetWidth(width)
	end
end

-- What a message says of you: "named" (gold), "whisper" (violet) or nil. Read again only when its words change.
local function Strip(text)
	return (text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
ns.ChatStrip = Strip -- (tests)

local function MarkOf(v, text)
	if text == nil or IsSecret(text) then
		v.text, v.mark = nil, nil
		return nil
	end
	if text == v.text then return v.mark end
	v.text = text
	local mark
	if text:find("|Hplayer:[^|]*:WHISPER") or text:find("|HBNplayer:", 1, true) then
		mark = "whisper"
	elseif myPattern then
		-- (your name in the words, not as the one who wrote them)
		local mine = myName and text:find("|Hplayer:" .. myName, 1, true)
		local words = Strip(text):lower()
		local body = words:match("^.-%]: (.*)$") or words
		if not mine and body:find(myPattern) then mark = "named" end
	end
	if mark ~= v.mark then
		v.mark = mark
		local c = mark == "whisper" and VIOLET or GOLD
		v.edge:SetColorTexture(c[1], c[2], c[3], 0.95)
		v.tint:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], TINT)
		v.alpha = -1 -- (drawn again next, so the tint and edge show or hide for the new mark)
	end
	return mark
end
ns.ChatMarkOf = MarkOf -- (tests)

-- Each frame: every message's backdrop at the message's own opacity (the game fades each message).
local function DrawWindow(frame, elapsed)
	local width = Clean(Safe(frame.GetWidth, frame))
	if type(width) == "number" and width > 0 then widths[frame] = width else width = widths[frame] or 400 end
	local spacing = Clean(Safe(frame.GetSpacing, frame)) or 0
	local top, bottom = Clean(Safe(frame.GetTop, frame)), Clean(Safe(frame.GetBottom, frame))
	local drop = 0
	if frame.visibleLines then
		local room
		drop, room = Glide(frame, elapsed)
		width = width + Widen(frame, width, drop, room)
	end
	if bottom then bottom = bottom - drop end -- (the messages let down: their backdrops with them)
	local whole = Clean(Safe(UIParent.GetEffectiveAlpha, UIParent)) or 1
	if whole <= 0 then whole = 1 end -- (the whole interface faded out: nothing to divide by)
	for _, line in ipairs(Lines(frame)) do
		local v = Veil(line)
		seen[v] = true
		Revealing(frame, line)
		-- (a new line fades in: ChatLines.lua knows when it came)
		if ns.ChatFadeIn then
			local words = Safe(line.GetText, line)
			if type(words) == "string" and not IsSecret(words) then
				local fade = ns.ChatFadeIn(words)
				if fade then pcall(line.SetAlpha, line, fade) end
			end
		end
		local alpha = 0
		if Safe(line.IsShown, line) then
			-- (a message's opacity as the eye sees it: its own times its frame's, the interface's taken out)
			local own = Clean(Safe(line.GetAlpha, line)) or 0
			local parent = Safe(line.GetParent, line)
			local above = type(parent) == "table" and Clean(Safe(parent.GetEffectiveAlpha, parent)) or whole
			alpha = math.min(1, own * above / whole)
		end
		-- (scrolled out of the window: no backdrop where no words are seen; one the window's edge cuts, as the
		-- messages glide, fades with the part of it still seen)
		if alpha > 0 and top and bottom then
			local lineTop, lineBottom = Clean(Safe(line.GetTop, line)), Clean(Safe(line.GetBottom, line))
			if lineTop and lineBottom and (lineBottom < bottom - 1 or lineTop > top + 1) then
				local tall = lineTop - lineBottom
				local seenPart = tall > 0 and (math.min(lineTop, top) - math.max(lineBottom, bottom)) / tall or 0
				alpha = alpha * math.max(0, math.min(1, seenPart))
			end
		end
		local text = alpha > 0 and Safe(line.GetText, line) or nil
		-- (secret words, the game's in a fight, keep their backdrop: only an empty line has none)
		if text == nil or (not IsSecret(text) and text == "") then alpha = 0 end
		if alpha <= 0 then
			HideVeil(v)
		else
			-- (the whole width of the window, whatever the length of the words)
			Place(v, line, width, spacing)
			local mark = MarkOf(v, text)
			if alpha ~= v.alpha then
				v.alpha = alpha
				v.solid:SetAlpha(alpha)
				Tail(v, alpha)
				v.tint:SetAlpha(alpha)
				v.edge:SetAlpha(alpha)
				v.solid:Show()
				v.tail:SetShown(TAIL > 0)
				v.tint:SetShown(mark == "named")
				v.edge:SetShown(mark ~= nil)
			end
		end
	end
end

local function DrawLines(elapsed)
	wipe(seen)
	for frame in pairs(dressed) do
		if Safe(frame.IsVisible, frame) then DrawWindow(frame, elapsed) end
	end
	-- (a window left while you wrote, its tab changed: it fades again once nobody writes)
	if next(revealed) and not Writing() then
		for frame in pairs(revealed) do Settle(frame) end
	end
	-- (a message the game took out of its list, or a window hidden: its backdrop goes)
	for _, v in pairs(veils) do
		if not seen[v] then HideVeil(v) end
	end
end

-- Under the mouse ---------------------------------------------------------------------------------------------------

local function Near()
	local frame = Selected()
	if Over(frame, TAB_ROOM, -BOX_ROOM, -(frame and frame.sereneGain or 0) - 16, 16) then return true end
	if Over(_G.GeneralDockManager) then return true end
	if ns.ShellOver and ns.ShellOver() then return true end
	for _, name in ipairs(BUTTONS) do
		local button = _G[name]
		if type(button) == "table" and button:GetParent() == holder and Over(button) then return true end
	end
	local box = frame and (frame.editBox or _G[(frame:GetName() or "") .. "EditBox"])
	return box ~= nil and Safe(box.HasFocus, box) and true or false
end

-- Channel names without their zone ("2. Trade - City" as "2. Trade"). The game finds the window's channel by
-- comparing names only shorter than the one in the line, so the shorter name is used only when it stays longer
-- than the window's own entry for this channel (found by its zone channel id or its base name, as the game does).
local function ShortChannel(frame, _, text, author, language, channel, target, flags, zoneID, index, base, ...)
	if not ns.On("chat") or type(channel) ~= "string" or IsSecret(channel) then return false end
	local number, name = channel:match("^(%d+%. )(.-)%s+%-%s+.+$")
	if not (number and name and name ~= "") then return false end
	local short = number .. name
	if type(text) ~= "string" or IsSecret(text) or text == "" then return false end
	local list = type(frame) == "table" and type(frame.channelList) == "table" and frame.channelList or {}
	local zones = type(frame) == "table" and type(frame.zoneChannelList) == "table" and frame.zoneChannelList or {}
	local matched = false
	for at, each in pairs(list) do
		if type(each) == "string" then
			local byZone = type(zoneID) == "number" and not IsSecret(zoneID) and zoneID > 0 and zones[at] == zoneID
			local byName = type(base) == "string" and not IsSecret(base) and each:upper() == base:upper()
			if byZone or byName then
				if #short <= #each then return false end
				matched = true
			end
		end
	end
	if not matched then return false end
	return false, text, author, language, short, target, flags, zoneID, index, base, ...
end
ns.ChatShortChannel = ShortChannel -- (tests)

-- Polish ------------------------------------------------------------------------------------------------------------

local QUIET = ns.MUTED

-- The mouse over a link in a message: an item's, a spell's, a quest's tooltip; a roll's own (ChatLoot.lua).
local SHOWN_LINKS = { item = true, spell = true, quest = true, achievement = true, enchant = true, currency = true,
	talent = true, battlepet = true }
local linkShown = false
local function OnLinkEnter(frame, link)
	if type(link) ~= "string" or IsSecret(link) then return end
	if (ns.RollTooltip and ns.RollTooltip(frame, link)) or (ns.UrlTooltip and ns.UrlTooltip(frame, link))
		or (ns.PlayerCard and ns.PlayerCard(frame, link)) then
		linkShown = true
		return
	end
	local kind = link:match("^(%a+):")
	if kind and SHOWN_LINKS[kind] then
		GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
		-- (a link this client can't show raises an error: no tooltip then)
		if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
			GameTooltip:Show()
			linkShown = true
		end
	end
end

local function OnLinkLeave()
	if linkShown then
		linkShown = false
		ns.HideTip()
	end
end

-- Friends and guild coming online or going offline: quiet and short.
local function QuietSystem(_, _, text, ...)
	if not (ns.On("chat") and ns.On("quiet")) or type(text) ~= "string" or IsSecret(text) or not ns.FormatMatch then
		return false
	end
	local online = ns.FormatMatch(text, _G.ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online.")
	if online and online[1] and online[2] then
		return false, QUIET .. "|Hplayer:" .. online[1] .. "|h" .. online[2] .. "|h came online|r", ...
	end
	local offline = ns.FormatMatch(text, _G.ERR_FRIEND_OFFLINE_S or "%s has gone offline.")
	if offline and offline[1] then
		return false, QUIET .. offline[1] .. " went offline|r", ...
	end
	return false
end
ns.ChatQuietSystem = QuietSystem -- (tests)

local polished = {}
Polish = function(frame)
	if polished[frame] then return end
	polished[frame] = true
	-- (links answer the mouse, so OnHyperlinkEnter is heard)
	if frame.SetHyperlinksEnabled then pcall(frame.SetHyperlinksEnabled, frame, true) end
	-- (the game lays its lines out again: they are widened again)
	if type(frame.RefreshLayout) == "function" then
		hooksecurefunc(frame, "RefreshLayout", function(self) self.sereneFirst = nil end)
	end
	if frame.HookScript then
		frame:HookScript("OnHyperlinkEnter", OnLinkEnter)
		frame:HookScript("OnHyperlinkLeave", OnLinkLeave)
	end
	-- (the lines' own new words, the copy box, the addresses: ChatLines.lua)
	if ns.LinesPolish then ns.LinesPolish(frame) end
end

-- Start -------------------------------------------------------------------------------------------------------------

-- The chat's alerts (a friend coming online, the Battle.net toasts): the game hangs them off the window's column of
-- buttons, which sits to the left of the window; with those buttons tucked away and the chat at the screen's edge,
-- they were cut off. Placed instead just above the chat (its tabs' top, where Serene's glass begins) and at the
-- screen's left edge, a little margin from both. The toast lands ~90 above the container's corner (measured, not
-- assumed: see alertGap).
local ALERT_MARGIN = 8
local alertGap = 0 -- how far above the container's corner the toast lands (the game stacks it over whatever else
                   -- the container holds); measured once the game has placed it, remembered for the next one
local alertBusy = false
local alertTarget -- the toast's bottom wanted, in the container's units (nil: positions unreadable)
local PlaceAlerts

-- (a frame after a toast shows, once the game has hung it on the container: the gap measured, and the container
-- moved by it when it changed)
local function MeasureAlerts()
	local alerts, toast = _G.ChatAlertFrame, _G.BNToastFrame
	if not alertTarget or type(alerts) ~= "table" or type(toast) ~= "table" then return end
	if not Clean(Safe(toast.IsShown, toast)) then return end
	local own, toastScale = Clean(Safe(alerts.GetEffectiveScale, alerts)), Clean(Safe(toast.GetEffectiveScale, toast))
	local bottom, corner = Clean(Safe(toast.GetBottom, toast)), Clean(Safe(alerts.GetBottom, alerts))
	if type(own) ~= "number" or own <= 0 or type(toastScale) ~= "number" or type(bottom) ~= "number"
		or type(corner) ~= "number" then return end
	local gap = bottom * toastScale / own - corner
	-- (a toast not on the container yet, or somewhere unexpected: left alone)
	if gap < -1 or gap > 400 then return end
	if math.abs(gap - alertGap) > 0.5 then
		alertGap = gap
		PlaceAlerts()
	end
end

PlaceAlerts = function()
	local alerts, chat = _G.ChatAlertFrame, _G.DEFAULT_CHAT_FRAME or ChatFrame1
	if type(alerts) ~= "table" or type(chat) ~= "table" or not alerts.SetPoint then return end
	local dock = _G.GeneralDockManager
	local above = type(dock) == "table" and dock or chat
	local top = Clean(Safe(above.GetTop, above))
	local scale, own = Clean(Safe(above.GetEffectiveScale, above)), Clean(Safe(alerts.GetEffectiveScale, alerts))
	alertBusy = true
	pcall(alerts.ClearAllPoints, alerts)
	if type(top) == "number" and type(scale) == "number" and type(own) == "number" and own > 0 then
		-- (the tabs' top in the container's own units, from the screen's bottom)
		alertTarget = top * scale / own + ALERT_MARGIN
		pcall(alerts.SetPoint, alerts, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", ALERT_MARGIN, alertTarget - alertGap)
	else
		-- (positions unreadable, a fight: above the tabs, at the window's edge)
		alertTarget = nil
		pcall(alerts.SetPoint, alerts, "BOTTOMLEFT", above, "TOPLEFT", 0, ALERT_MARGIN)
	end
	alertBusy = false
	local toast = _G.BNToastFrame
	if type(toast) == "table" and toast.SetClampedToScreen then pcall(toast.SetClampedToScreen, toast, true) end
end

local function HearAlerts()
	local alerts = _G.ChatAlertFrame
	if type(alerts) ~= "table" or not alerts.SetPoint then return end
	-- (the game, or another addon, placing it again: put back)
	hooksecurefunc(alerts, "SetPoint", function()
		if alertBusy then return end -- (Serene's own placing)
		C_Timer.After(0, PlaceAlerts) -- (next frame: after the game has finished placing it)
	end)
	-- (placed again as each toast shows: the chat may have moved since)
	local toast = _G.BNToastFrame
	if type(toast) == "table" and toast.HookScript then
		toast:HookScript("OnShow", function()
			PlaceAlerts()
			C_Timer.After(0, MeasureAlerts)
		end)
	end
	PlaceAlerts()
end

local function Init()
	if not ns.On("chat") or not ChatFrame1 then return end
	active = true
	local name = Clean(Safe(UnitName, "player"))
	if type(name) == "string" and #name > 2 then
		myName = name
		myPattern = "%f[%a]" .. name:lower():gsub("%W", "%%%0") .. "%f[%A]"
	end
	-- (one level under the chat window, so the backdrops lie behind its words)
	under = CreateFrame("Frame", nil, UIParent)
	under:SetAllPoints(UIParent)
	under:SetFrameStrata(ChatFrame1:GetFrameStrata() or "LOW")
	under:SetFrameLevel(math.max(0, (ChatFrame1:GetFrameLevel() or 1) - 1))
	-- (above the chat; its opacity is the hover)
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:SetAlpha(0)
	-- The tabs: only under the mouse, coming and going with the rest of the window (FadeTabs). The game's own
	-- fading of them is made to change nothing (every opacity it would give: full), so the two never fight.
	for _, key in ipairs({ "SELECTED_NOMOUSE", "NORMAL_NOMOUSE", "ALERTING_NOMOUSE", "SELECTED_MOUSEOVER",
		"NORMAL_MOUSEOVER", "ALERTING_MOUSEOVER" }) do
		_G["CHAT_FRAME_TAB_" .. key .. "_ALPHA"] = 1
	end
	-- (for the window's own look: ChatShell.lua)
	ns.chat = { holder = holder, under = under, Selected = Selected, Lines = Lines, Hover = function() return hover end,
		buttons = BUTTONS, GOLD = GOLD, INK = INK, TAB_WORDS = TAB_WORDS, TAB_ROOM = TAB_ROOM }
	DressAll()
	pcall(HearAlerts)
	local add = _G.ChatFrame_AddMessageEventFilter or (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
	if add then
		pcall(add, "CHAT_MSG_CHANNEL", ShortChannel)
		pcall(add, "CHAT_MSG_SYSTEM", QuietSystem)
	end
	if _G.FCFTab_UpdateColors then hooksecurefunc("FCFTab_UpdateColors", function(tab, selected) PaintTab(tab, selected) end) end
	-- (next frame: the game has finished making or docking the window by then)
	local soon = function() C_Timer.After(0, DressAll) end
	for _, fn in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow", "FCF_DockFrame", "FCF_UnDockFrame" }) do
		if _G[fn] then hooksecurefunc(fn, soon) end
	end
	local since, aligned = 0, 0
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		DrawLines(elapsed)
		local now = GetTime()
		if Near() then lastNear = now end
		local want = (now - lastNear < LINGER) and 1 or 0
		local alpha = ns.Approach(hover, want, elapsed, HOVER_IN, HOVER_OUT)
		if alpha ~= hover then
			hover = alpha
			holder:SetAlpha(alpha)
		end
		FadeTabs(hover)
		since = since + elapsed
		aligned = aligned + elapsed
		if aligned > 0.25 then
			aligned = 0
			Safe(AlignAll)
		end
		-- (now and then: a button the game moved back, a window opened meanwhile)
		if since > 2 then
			since = 0
			DressAll()
		end
	end)
end

local function Refresh()
	if not active then return end
	FadeTabs(hover)
	for frame in pairs(dressed) do pcall(frame.SetTimeVisible, frame, ns.db.lineTime) end
	for box in pairs(boxes) do Arrows(box) end
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
