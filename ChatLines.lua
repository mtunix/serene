local _, ns = ...
local Safe, Clean, IsSecret, Over = ns.Safe, ns.Clean, ns.IsSecret, ns.Over

-- The lines themselves.
-- Just after the game adds a line to a window (a hook that changes nothing of what the game does), the line kept
-- in the window's history gets its new words, before it is ever drawn. A secret line (the game's, in a fight) and
-- a line not understood are left as they are.
-- * Short tags: "[1. General]" as "[1]", "[Guild]" as "[G]", "[Party Leader]" as "[PL]"... still the channel's own
--   link (a click writes there).                                                             (/serene tags on|off)
-- * One speaker, several lines in a row: the name on the first only, the others under it; each new line keeps the
--   whole group seen as long as itself (they fade together).                                 (/serene group on|off)
-- * The hour in a quiet grey. New lines fade in.
-- * In a fight, the public channels (General, Trade, Looking for Group...) wait, and come once it is over; your
--   group, guild, whispers and loot always come at once.                                      (/serene calm on|off)
-- * Alt+click a line: a box to copy its words. Web addresses become links: a click, the same box with the address.
-- * More than a line: the window's whole history on a sheet of glass, as plain words, to select with the mouse (or
--   Ctrl+A) and copy with Ctrl+C. Opened by the copy icon beside the chat's menu (under the mouse), Shift+Alt+click
--   on the chat, or /serene copy. Lines the game keeps secret (in a fight) are left out.

local HOUR = "|cff7d7d7d"
local URL = "|cff6cb4ff"
local BLANK = "Interface\\AddOns\\Serene\\Media\\Blank"
local GROUP_TIME = 120     -- seconds within which one speaker's lines are a group
local FADE_IN = 0.3        -- seconds a new line takes to fade in
local HELD_MOST = 80       -- channel lines kept per window during a fight
local INK = { 0.035, 0.04, 0.05 }
local GOLD = { 1, 0.82, 0.35 }

local function Newest(frame, index)
	local buffer = frame.historyBuffer
	local entry = type(buffer) == "table" and buffer.GetEntryAtIndex and Safe(buffer.GetEntryAtIndex, buffer, index or 1)
	return type(entry) == "table" and entry or nil
end

local function Dirty(frame)
	if frame.MarkDisplayDirty then pcall(frame.MarkDisplayDirty, frame) end
end

-- The hour --------------------------------------------------------------------------------------------------------

-- The game's hour at the start of a line ("21:04 "), as written with its option, else nil.
local stampPatterns = {}
local function StampPattern(format)
	if type(format) ~= "string" or format == "none" or format == "" then return nil end
	local pattern = stampPatterns[format]
	if pattern then return pattern end
	-- (hours as one or two digits, minutes and seconds as two, AM/PM as a word, any other code loosely)
	pattern = format:gsub("%%(.)", function(code)
		if code == "H" or code == "I" or code == "k" or code == "l" then return "\1" end
		if code == "M" or code == "S" then return "\2" end
		if code == "p" then return "\3" end
		return "\4"
	end)
	pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\1", " ?%%d%%d?"):gsub("\2", "%%d%%d"):gsub("\3", "[^%%s|]+"):gsub("\4", "[^|]-")
	stampPatterns[format] = "^(" .. pattern .. ")"
	return stampPatterns[format]
end

-- Short tags --------------------------------------------------------------------------------------------------------

local TAGS = { GUILD = "G", OFFICER = "O", PARTY = "P", RAID = "R", RAID_WARNING = "RW", INSTANCE_CHAT = "I",
	INSTANCE = "I", BATTLEGROUND = "B" }

-- (the game's own word for it, else the English one anywhere in the tag)
local function Says(shown, global, english)
	local name = _G[global]
	return (type(name) == "string" and shown == name) or shown:find(english, 1, true) ~= nil
end

local function TagFor(kind, shown)
	local number = kind:lower():match("^channel:(%d+)")
	if number then return number end
	local upper = kind:upper()
	if upper == "PARTY" then
		if Says(shown, "CHAT_MSG_PARTY_LEADER", "Leader") then return "PL" end
		if Says(shown, "CHAT_MSG_PARTY_GUIDE", "Guide") then return "PG" end
	elseif upper == "RAID" then
		if Says(shown, "CHAT_MSG_RAID_LEADER", "Leader") then return "RL" end
		if Says(shown, "CHAT_MSG_RAID_WARNING", "Warning") then return "RW" end
	elseif upper == "INSTANCE_CHAT" or upper == "INSTANCE" then
		if Says(shown, "CHAT_MSG_INSTANCE_CHAT_LEADER", "Leader") then return "IL" end
	end
	return TAGS[upper]
end

local function ShortTags(text)
	return (text:gsub("(|Hchannel:([^|]+)|h)%[([^%]|]+)%](|h)", function(open, kind, shown, close)
		local tag = TagFor(kind, shown)
		if not tag then return nil end
		return open .. "[" .. tag .. "]" .. close
	end))
end
ns.ChatShortTags = ShortTags -- (tests)

-- One speaker, several lines ----------------------------------------------------------------------------------------

local groups = {} -- window -> { who, kind, at, entries, last }
local ruler

-- A clear space as wide as these words in this window's font (a real space first: copied text keeps a gap).
local function Indent(frame, words)
	ruler = ruler or UIParent:CreateFontString(nil, "OVERLAY")
	local font, size, flags = Safe(frame.GetFont, frame)
	if not font then return nil end
	pcall(ruler.SetFont, ruler, font, size, flags)
	ruler:SetText(words)
	local width = Clean(Safe(ruler.GetStringWidth, ruler))
	ruler:SetText("")
	if type(width) ~= "number" or width <= 4 then return nil end
	-- (a few pixels less: the real space before it)
	return " |T" .. BLANK .. ":1:" .. math.floor(width - 3 + 0.5) .. "|t"
end

-- A speaker's line: who, the chat (its type and channel), and where their words start; else nil.
local function Speaker(rest)
	local from, to, target = rest:find("|H(B?N?player:[^|]+)|h.-|h")
	if not from then return nil end
	local colon = rest:find(": ", to + 1, true)
	-- (the words start right after the name's ": " or " says: ", never further: a colon inside the words is theirs)
	if not colon or colon - to > 24 then return nil end
	local fields = {}
	for field in (target .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
	local who = fields[2]
	if not who or who == "" then return nil end
	local head = rest:sub(1, colon + 1)
	-- (the chat, and the shape of the words around the name: "whispers:" and "To ...:" are two conversations' sides)
	local shape = head:gsub("|H.-|h.-|h", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local kind = (target:sub(1, 2) == "BN" and "BN" or ((fields[4] or "") .. ":" .. (fields[5] or ""))) .. shape
	return who, kind, head, rest:sub(colon + 2)
end

local function Group(frame, entry, hour, rest)
	local who, kind, head, words = Speaker(rest)
	if not who then
		return nil
	end
	local now = GetTime()
	local group = groups[frame]
	-- (the line before this one is the group's last: nothing came in between)
	if group and group.who == who and group.kind == kind and now - group.at < GROUP_TIME
		and Newest(frame, 2) == group.last then
		local indent = Indent(frame, head)
		if indent then
			group.entries[#group.entries + 1] = entry
			group.last, group.at = entry, now
			-- (the whole group seen as long as its newest line: they fade together, the name never gone first)
			for _, each in ipairs(group.entries) do
				if type(each.timestamp) == "number" then each.timestamp = now end
			end
			return indent .. words
		end
	end
	groups[frame] = { who = who, kind = kind, at = now, entries = { entry }, last = entry }
	return nil
end

-- New lines fade in -------------------------------------------------------------------------------------------------

local added, settled = {}, {} -- words -> when the line came; words -> true once given its full opacity
local purgedAt = 0

-- The opacity a line drawn with these words should have now, while it fades in (nil: not ours to touch).
function ns.ChatFadeIn(words)
	local at = added[words]
	if not at then return nil end
	local age = GetTime() - at
	if age < FADE_IN then return math.max(0.05, age / FADE_IN) end
	-- (full once, then left to the game's own fade)
	if not settled[words] then
		settled[words] = true
		return 1
	end
	return nil
end

local function Came(words)
	local now = GetTime()
	added[words] = now
	-- (long faded in by then: swept at most every 5 seconds)
	if now - purgedAt > 5 then
		purgedAt = now
		for key, at in pairs(added) do
			if now - at > 5 then added[key], settled[key] = nil, nil end
		end
	end
end

-- Each line added: its new words ------------------------------------------------------------------------------------

local function OnAdded(frame, text)
	if type(text) ~= "string" or IsSecret(text) then return end
	local entry = Newest(frame)
	-- (only the line just added, as the game wrote it: one another hook changed is left alone)
	if not entry or entry.message ~= text then return end
	local new = text
	if ns.On("tags") then new = ShortTags(new) end
	local hour, rest = "", new
	local pattern = StampPattern(Clean(Safe(GetCVar, "showTimestamps")))
	local stamp = pattern and new:match(pattern)
	if stamp and stamp ~= "" then
		hour, rest = HOUR .. stamp .. "|r", new:sub(#stamp + 1)
	end
	if ns.On("group") then rest = Group(frame, entry, hour, rest) or rest end
	new = hour .. rest
	Came(new)
	if new ~= text then
		entry.message = new
		Dirty(frame)
	end
end
ns.ChatOnAdded = OnAdded -- (tests)

-- The copy box ------------------------------------------------------------------------------------------------------

local box

-- Plain words: links as their words, no colors, no pictures.
local function Plain(text)
	return (text:gsub("|T.-|t", ""):gsub("|K.-|k", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", ""):gsub("%s%s+", " "):gsub("^%s+", ""))
end
ns.ChatPlain = Plain -- (tests)

local function CopyBox(text, title)
	if not box then
		box = CreateFrame("Frame", "SereneCopyBox", UIParent)
		box:SetSize(520, 60)
		box:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
		box:SetFrameStrata("DIALOG")
		box:EnableMouse(true)
		local ground = box:CreateTexture(nil, "BACKGROUND")
		ground:SetAllPoints()
		ground:SetColorTexture(INK[1], INK[2], INK[3], 0.94)
		local rule = box:CreateTexture(nil, "BORDER")
		rule:SetHeight(1)
		rule:SetPoint("TOPLEFT")
		rule:SetPoint("TOPRIGHT")
		rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
		box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
		box.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -8)
		hint:SetText("Ctrl+C to copy, Esc to close")
		local edit = CreateFrame("EditBox", nil, box)
		edit:SetFontObject(ChatFontNormal or GameFontHighlight)
		edit:SetAutoFocus(false)
		edit:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 8)
		edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 8)
		edit:SetHeight(22)
		local field = edit:CreateTexture(nil, "BACKGROUND")
		field:SetPoint("TOPLEFT", -4, 2)
		field:SetPoint("BOTTOMRIGHT", 4, -2)
		field:SetColorTexture(1, 1, 1, 0.06)
		edit:SetScript("OnEscapePressed", function() box:Hide() end)
		edit:SetScript("OnEnterPressed", function() box:Hide() end)
		-- (read only: anything typed puts the words back, all selected)
		edit:SetScript("OnTextChanged", function(self, typed)
			if typed then
				self:SetText(box.text or "")
				self:HighlightText()
			end
		end)
		edit:SetScript("OnKeyDown", function(_, key)
			-- (hidden a moment later, once the game has copied the words)
			if key == "C" and IsControlKeyDown() then C_Timer.After(0.15, function() box:Hide() end) end
		end)
		box.edit = edit
		table.insert(UISpecialFrames, "SereneCopyBox") -- (Esc closes it, as it does the game's windows)
	end
	box.text = text
	box.title:SetText(title or "Copy")
	box.edit:SetText(text)
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
end
ns.CopyBox = CopyBox

-- The sheet: the window's whole history, to select from --------------------------------------------------------------

local sheet

-- The window's lines, oldest first, as plain words (the game's newest is its first).
local function History(frame)
	local buffer = frame and frame.historyBuffer
	if type(buffer) ~= "table" or not buffer.GetEntryAtIndex then return {}, 0 end
	local count = buffer.GetNumElements and Clean(Safe(buffer.GetNumElements, buffer))
	if type(count) ~= "number" then
		count = 0
		while count < 5000 and Safe(buffer.GetEntryAtIndex, buffer, count + 1) do count = count + 1 end
	end
	local lines, hidden = {}, 0
	for index = count, 1, -1 do
		local entry = Safe(buffer.GetEntryAtIndex, buffer, index)
		local text = type(entry) == "table" and entry.message
		if type(text) == "string" and not IsSecret(text) then
			local plain = Plain(text)
			if plain ~= "" then lines[#lines + 1] = plain end
		elseif text ~= nil then
			hidden = hidden + 1
		end
	end
	return lines, hidden
end

local function MakeSheet()
	sheet = CreateFrame("Frame", "SereneCopySheet", UIParent)
	sheet:SetSize(640, 400)
	sheet:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	sheet:SetFrameStrata("DIALOG")
	sheet:SetClampedToScreen(true)
	sheet:EnableMouse(true)
	sheet:SetMovable(true)
	sheet:RegisterForDrag("LeftButton")
	sheet:SetScript("OnDragStart", sheet.StartMoving)
	sheet:SetScript("OnDragStop", sheet.StopMovingOrSizing)
	local ground = sheet:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.94)
	ns.Hairline(sheet)
	sheet.title = sheet:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sheet.title:SetPoint("TOPLEFT", sheet, "TOPLEFT", 12, -9)
	sheet.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local close = CreateFrame("Button", nil, sheet)
	close:SetSize(16, 16)
	close:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -8, -6)
	close.text = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	close.text:SetPoint("CENTER")
	close.text:SetText("×")
	close.text:SetTextColor(0.56, 0.56, 0.56)
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.56, 0.56, 0.56) end)
	close:SetScript("OnClick", function() sheet:Hide() end)
	local hint = sheet:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", close, "LEFT", -8, 0)
	hint:SetText("Select with the mouse  ·  Ctrl+A all  ·  Ctrl+C copy  ·  Esc close")
	local rule = sheet:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", sheet, "TOPLEFT", 12, -26)
	rule:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -12, -26)
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	-- the words: a scrolling field, read only
	local scroll = CreateFrame("ScrollFrame", nil, sheet)
	scroll:SetPoint("TOPLEFT", sheet, "TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -18, 12)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal or GameFontHighlight)
	-- (0: no limit, so a long history isn't cut off)
	if edit.SetMaxLetters then edit:SetMaxLetters(0) end
	if edit.SetMaxBytes then edit:SetMaxBytes(0) end
	edit:SetWidth(640 - 30)
	edit:SetTextInsets(0, 4, 0, 0)
	scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed", function() sheet:Hide() end)
	edit:SetScript("OnTextChanged", function(self, typed)
		if typed then self:SetText(sheet.text or "") end -- (read only: anything typed is undone)
	end)
	-- (the field follows the cursor; the wheel scrolls)
	if _G.ScrollingEdit_OnCursorChanged and _G.ScrollingEdit_OnUpdate then
		edit:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
		edit:SetScript("OnUpdate", function(self, elapsed) _G.ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local most = self:GetVerticalScrollRange() or 0
		self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * 42)))
	end)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	-- (a thin gold line telling where in the history)
	local thumb = sheet:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
	thumb:SetWidth(2)
	sheet:SetScript("OnUpdate", function()
		local seen, most = scroll:GetHeight() or 0, scroll:GetVerticalScrollRange() or 0
		if most <= 0 or seen <= 0 then return thumb:Hide() end
		local length = math.max(18, seen * seen / (most + seen))
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -(seen - length) * (scroll:GetVerticalScroll() / most))
		thumb:SetHeight(length)
		thumb:Show()
	end)
	sheet.scroll, sheet.edit = scroll, edit
	table.insert(UISpecialFrames, "SereneCopySheet")
end

-- The whole history of a chat window on the sheet, the newest line in view.
local function CopyHistory(frame)
	frame = frame or (ns.chat and ns.chat.Selected and ns.chat.Selected()) or _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
	if not frame then return end
	if not sheet then MakeSheet() end
	local lines, hidden = History(frame)
	local name = frame.GetID and _G.GetChatWindowInfo and Clean((Safe(_G.GetChatWindowInfo, frame:GetID())))
	sheet.title:SetText(("Copy from %s  |cff8f8f8f%d lines%s|r"):format(name or "the chat", #lines,
		hidden > 0 and (", %d hidden in a fight"):format(hidden) or ""))
	sheet.text = table.concat(lines, "\n")
	sheet.edit:SetText(sheet.text)
	sheet:Show()
	sheet.edit:SetFocus()
	sheet.edit:SetCursorPosition(#sheet.text)
	-- (next frame: the scroll range is known once the words are laid out)
	C_Timer.After(0, function()
		sheet.scroll:SetVerticalScroll(sheet.scroll:GetVerticalScrollRange() or 0)
	end)
end
ns.CopyHistory = CopyHistory

-- The copy icon beside the chat's menu (ChatShell.lua places and dresses it with the others).
local function CopyButton()
	local chat = ns.chat
	if not (chat and chat.holder and chat.buttons) or _G.SereneChatCopyButton then return end
	local button = CreateFrame("Button", "SereneChatCopyButton", chat.holder)
	button:SetSize(18, 18)
	button:SetScript("OnClick", function() CopyHistory() end)
	button:SetScript("OnEnter", function(self)
		if ns.ShowTip then
			ns.ShowTip(self, function(tip)
				tip:SetText("Copy the chat")
				if ns.TipHint then ns.TipHint(tip, "Shift+Alt+click the chat: the same") end
			end, "ANCHOR_TOP")
		end
	end)
	button:SetScript("OnLeave", function() if ns.HideTip then ns.HideTip() end end)
	-- (one of the chat's kept buttons: under the mouse, placed and dressed with them)
	table.insert(chat.buttons, "SereneChatCopyButton")
	if ns.ShellDress then Safe(ns.ShellDress) end
end

-- Alt+click a line: its words in the box.
local function LineUnderMouse(frame)
	local list = frame.visibleLines
	if type(list) ~= "table" then
		list = {}
		local container = frame.FontStringContainer
		if type(container) == "table" and container.GetRegions then
			for _, region in ipairs({ container:GetRegions() }) do list[#list + 1] = region end
		end
	end
	for _, line in ipairs(list) do
		if Safe(line.IsShown, line) and Over(line) then return line end
	end
end

local function OnMouseDown(frame, button)
	if button ~= "LeftButton" or not IsAltKeyDown() then return end
	if IsShiftKeyDown() then return CopyHistory(frame) end
	local line = LineUnderMouse(frame)
	local text = line and Safe(line.GetText, line)
	if type(text) ~= "string" or IsSecret(text) or text == "" then return end
	CopyBox(Plain(text), "Copy this line")
end

-- Web addresses -----------------------------------------------------------------------------------------------------

-- Each word that is a web address (outside the game's own links) as a link of ours.
local function Words(text)
	return (text:gsub("%S+", function(word)
		local lower = word:lower()
		-- (a word holding an escape code is part of the game's markup: left alone)
		if not (lower:find("^https?://") or lower:find("^www%.[%w%-]+%.%a")) or word:find("|", 1, true) then return nil end
		local tail = word:match("[%.,!%?%)%]\"']+$") or "" -- (the sentence's punctuation, not the address's)
		local address = word:sub(1, #word - #tail)
		if #address < 8 then return nil end
		return URL .. "|Haddon:Serene:url:" .. address .. "|h" .. address .. "|h|r" .. tail
	end))
end

local function Linkify(text)
	local out, at = {}, 1
	while true do
		local from, to = text:find("|H.-|h.-|h", at)
		if not from then
			out[#out + 1] = Words(text:sub(at))
			break
		end
		out[#out + 1] = Words(text:sub(at, from - 1))
		out[#out + 1] = text:sub(from, to)
		at = to + 1
	end
	return table.concat(out)
end
ns.ChatLinkify = Linkify -- (tests)

local function UrlFilter(_, _, text, ...)
	if not ns.On("chat") or type(text) ~= "string" or IsSecret(text) then return false end
	local lower = text:lower()
	if not (lower:find("http", 1, true) or lower:find("www.", 1, true)) then return false end
	local new = Linkify(text)
	if new == text then return false end
	return false, new, ...
end

-- A click on one: the address in the box (heard both ways the game hands addons' links over, told once).
local lastLink, lastAt = nil, -math.huge
local function OnLink(link)
	if type(link) ~= "string" or IsSecret(link) then return end
	if link == lastLink and GetTime() - lastAt < 0.3 then return end
	lastLink, lastAt = link, GetTime()
	local address = link:match("^addon:Serene:url:(.+)$")
	if address then CopyBox(address, "Copy this link") end
end

function ns.UrlTooltip(owner, link)
	if type(link) ~= "string" or not link:find("^addon:Serene:url:") then return false end
	ns.ShowTip(owner, function(tip)
		tip:SetText(link:match("^addon:Serene:url:(.+)$") or "")
		ns.TipHint(tip, "Click to copy the link")
	end)
	return true
end

-- In a fight, the public channels wait ----------------------------------------------------------------------------

local fighting, replaying = false, false
local held = {} -- window -> { { event, n, args... }, ... }

local function Hold(frame, event, ...)
	if replaying or not fighting or not (ns.On("chat") and ns.On("calm")) or type(frame) ~= "table" then return false end
	local list = held[frame] or {}
	held[frame] = list
	list[#list + 1] = { event = event, n = select("#", ...), ... } -- (n: the arguments hold nils)
	if #list > HELD_MOST then table.remove(list, 1) end
	return true
end
ns.ChatHold = Hold -- (tests)

-- The fight over: each window's waiting lines, through the game's own handling (its filters, its look).
local function Replay()
	if fighting then return end -- (a new fight began meanwhile: they wait for its end)
	replaying = true -- (Hold lets them through)
	for frame, list in pairs(held) do
		local handler = frame.GetScript and frame:GetScript("OnEvent")
		for _, each in ipairs(list) do
			if handler then pcall(handler, frame, each.event, unpack(each, 1, each.n)) end
		end
	end
	replaying = false
	wipe(held)
end
ns.ChatReplay = Replay -- (tests)
function ns.ChatFighting(value) fighting = value end -- (tests)

-- Start -----------------------------------------------------------------------------------------------------------

local hooked = {}
function ns.LinesPolish(frame)
	if hooked[frame] or not frame.AddMessage then return end
	hooked[frame] = true
	hooksecurefunc(frame, "AddMessage", OnAdded)
	if frame.HookScript then frame:HookScript("OnMouseDown", OnMouseDown) end
end

local URL_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }

local function Init()
	if not ns.On("chat") then return end
	local add = _G.ChatFrame_AddMessageEventFilter or (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
	if add then
		pcall(add, "CHAT_MSG_CHANNEL", Hold)
		for _, event in ipairs(URL_EVENTS) do pcall(add, event, UrlFilter) end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) OnLink(link) end, ns)
	end
	if _G.SetItemRef then hooksecurefunc("SetItemRef", function(link) OnLink(link) end) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		fighting = event == "PLAYER_REGEN_DISABLED"
		if not fighting then C_Timer.After(0.5, Replay) end
	end)
	fighting = InCombatLockdown() and true or false -- (a /reload in a fight)
	pcall(CopyButton)
end

table.insert(ns.modules, { init = Init })
