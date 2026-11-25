local _, ns = ...
local Safe, Clean, Over = ns.Safe, ns.Clean, ns.Over

-- The chat window's own look, all of it quiet and only under the mouse:
-- * a faint glass pane behind the window and a hairline under the tabs, so it reads as one window;
-- * the menu and the channels as two small drawn icons at the right of the tabs (no friends or voice buttons);
-- * a slim scroll bar on the right: a hairline track, a gold thumb as long as the part shown; drag it, click the
--   track to jump, the wheel works over it;
-- * scrolled back, a small pill at the bottom: "3 new" (or "Latest") with an arrow; a click goes back down;
-- * a dotted grip in the corner to resize the window (an unlocked one).

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local PANE = 0.3          -- the glass pane's darkness under the mouse
local HAIR = 0.08         -- the hairlines' brightness
local ICON, ICON_GAP = 14, 6
local TRACK_X = 4         -- the scroll bar's track, from the window's right edge
local THUMB_MIN = 18
local PILL_IN, PILL_OUT = 0.15, 0.3

local chat -- what Chat.lua shares (ns.chat)
local pane, hair, bar, track, thumb, grip, pill
local dragging, sizing = false, nil
local over = { bar = false, grip = false }
local hooked, unread = {}, {}
local pillAlpha = 0
local ICONS = { ChatFrameMenuButton = "IconMenu", ChatFrameChannelButton = "IconChannels",
	SereneChatCopyButton = "IconCopy" }

local function Round(value) return math.floor((value or 0) + 0.5) end

local function Words(texture, bright)
	local c = bright and chat.GOLD or chat.TAB_WORDS
	texture:SetVertexColor(c[1], c[2], c[3], bright and 1 or 0.65)
end

-- The window's buttons in our look --------------------------------------------------------------------------------

-- Every texture of the game's own button made clear, our icon over it (the button and its click left whole).
local function Reskin(button, file)
	if not button.sereneIcon then
		local icon = button:CreateTexture(nil, "OVERLAY", nil, 7)
		icon:SetTexture(MEDIA .. file)
		icon:SetSize(ICON, ICON)
		icon:SetPoint("CENTER")
		Words(icon, false)
		button.sereneIcon = icon
		button:HookScript("OnEnter", function() Words(icon, true) end)
		button:HookScript("OnLeave", function() Words(icon, false) end)
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= button.sereneIcon and region.GetObjectType and region:GetObjectType() == "Texture" then
			pcall(region.SetAlpha, region, 0)
		end
	end
end

function ns.ShellDress()
	if not chat or InCombatLockdown() then return end
	local frame = chat.Selected()
	if not frame then return end
	local x = 0
	for _, name in ipairs(chat.buttons) do
		local button = _G[name]
		if type(button) == "table" and button.GetRegions and button:GetParent() == chat.holder then
			Reskin(button, ICONS[name] or "IconMenu")
			pcall(button.SetSize, button, ICON + 4, ICON + 4)
			pcall(button.ClearAllPoints, button)
			-- (the tabs' row, at its right end, in Edit Mode's box; the menu last)
			local box = ns.ChatBox and ns.ChatBox(frame)
			if box then
				-- (on the tabs' row, at the right end of the box)
				local inside = Round((Clean(Safe(box.GetRight, box)) or 0) - (Clean(Safe(frame.GetRight, frame)) or 0))
				pcall(button.SetPoint, button, "BOTTOMRIGHT", frame, "TOPRIGHT", inside - 5 - x, 5)
			else
				pcall(button.SetPoint, button, "BOTTOMRIGHT", frame, "TOPRIGHT", 6 - x, 5)
			end
			x = x + ICON + ICON_GAP
		end
	end
end

-- The pane --------------------------------------------------------------------------------------------------------

-- (the pane fills Edit Mode's box for the chat; its parts follow the box and the window, placed again when either
-- moves or changes size)
local placed
local function Num(region, method)
	return Round(Clean(Safe(region[method], region)) or 0)
end

local function PlacePane(frame)
	local box = ns.ChatBox and ns.ChatBox(frame)
	local key
	if box then
		local dock = _G.GeneralDockManager
		key = table.concat({ tostring(frame), dock and Num(dock, "GetTop") or 0, Num(box, "GetLeft"), Num(box, "GetRight"), Num(box, "GetTop"),
			Num(box, "GetBottom"), Num(frame, "GetTop"), Num(frame, "GetBottom"), Num(frame, "GetRight") }, ":")
	else
		key = tostring(frame)
	end
	if placed == key then return end
	placed = key
	pane:ClearAllPoints()
	hair:ClearAllPoints()
	bar:ClearAllPoints()
	grip:ClearAllPoints()
	pill:ClearAllPoints()
	if box then
		local up = Num(frame, "GetTop") - Num(box, "GetTop")         -- (the window's top, from the box's)
		local down = Num(frame, "GetBottom") - Num(box, "GetBottom") -- (the window's bottom, from the box's)
		-- (the top: the tabs' top, not the box's, so no empty band above them)
		local dock = _G.GeneralDockManager
		local tabsTop = dock and Clean(Safe(dock.GetTop, dock))
		local top = tabsTop and math.min(0, Round(tabsTop + 2) - Num(box, "GetTop")) or 0
		pane:SetPoint("TOPLEFT", box, "TOPLEFT", 0, top)
		pane:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
		hair:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, up + 3)
		hair:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, up + 3)
		bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, up)
		bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, down)
		grip:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
		local inside = Num(box, "GetRight") - Num(frame, "GetRight") -- (room right of the window, in the box)
		pill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inside - 18, 6)
	else
		pane:SetPoint("TOPLEFT", frame, "TOPLEFT", -10, chat.TAB_ROOM - 2)
		pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 16, -6)
		hair:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -10, 3)
		hair:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 16, 3)
		bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", TRACK_X - 5, 0)
		bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", TRACK_X - 5, 0)
		grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 15, -5)
		pill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	end
end

-- The scroll bar --------------------------------------------------------------------------------------------------

local function Scroll(frame)
	local range = Clean(Safe(frame.GetMaxScrollRange, frame)) or 0
	local offset = Clean(Safe(frame.GetScrollOffset, frame)) or 0
	local shown = Clean(Safe(frame.GetNumVisibleLines, frame))
	if type(shown) ~= "number" or shown <= 0 then shown = #chat.Lines(frame) end
	return range, offset, math.max(1, shown)
end

local function DrawBar(frame, hover)
	local range, offset, shown = Scroll(frame)
	if range <= 0 then
		bar:Hide()
		return range, offset
	end
	bar:Show()
	local height = Clean(Safe(bar.GetHeight, bar)) or 0
	local size = math.max(THUMB_MIN, height * shown / (shown + range))
	size = math.min(size, height)
	-- dragged: the cursor sets where the window is
	if dragging then
		if not IsMouseButtonDown("LeftButton") then
			dragging = false
		else
			local _, y = GetCursorPosition()
			local scale = Clean(Safe(bar.GetEffectiveScale, bar)) or 1
			local bottom = Clean(Safe(bar.GetBottom, bar)) or 0
			local at = (y / scale - bottom - size / 2) / math.max(1, height - size)
			at = math.max(0, math.min(1, at))
			local want = math.floor(at * range + 0.5)
			if want ~= offset then
				Safe(frame.SetScrollOffset, frame, want)
				offset = want
			end
		end
	end
	local wide = (over.bar or dragging) and 4 or 2
	thumb:SetWidth(wide)
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, (height - size) * offset / range)
	local c = chat.GOLD
	thumb:SetVertexColor(c[1], c[2], c[3], (over.bar or dragging) and 0.95 or 0.6)
	return range, offset
end

-- The pill --------------------------------------------------------------------------------------------------------

local function Count(frame)
	if hooked[frame] or not frame.AddMessage then return end
	hooked[frame] = true
	hooksecurefunc(frame, "AddMessage", function(self)
		local offset = Clean(Safe(self.GetScrollOffset, self)) or 0
		if offset > 0 then unread[self] = (unread[self] or 0) + 1 end
	end)
end

local function DrawPill(frame, offset, elapsed)
	if offset <= 0 then unread[frame] = nil end
	local want = offset > 0 and 1 or 0
	pillAlpha = ns.Approach(pillAlpha, want, elapsed, PILL_IN, PILL_OUT)
	pill:SetAlpha(pillAlpha)
	pill:SetShown(pillAlpha > 0)
	local count = unread[frame]
	local text = count and count > 0 and ("%d new"):format(count) or "Latest"
	if pill.text:GetText() ~= text then
		pill.text:SetText(text)
		local width = Clean(Safe(pill.text.GetStringWidth, pill.text)) or 40
		pill:SetWidth(math.floor(width + 34 + 0.5))
	end
end

-- Every frame -----------------------------------------------------------------------------------------------------

local function Update(_, elapsed)
	local frame = chat.Selected()
	if not frame or not Safe(frame.IsVisible, frame) then
		pane:SetAlpha(0)
		hair:SetAlpha(0)
		pill:Hide()
		return
	end
	Count(frame)
	PlacePane(frame)
	local hover = chat.Hover() or 0
	pane:SetAlpha(hover * PANE)
	hair:SetAlpha(hover * HAIR)
	local _, offset = DrawBar(frame, hover)
	DrawPill(frame, offset or 0, elapsed)
	-- (under the mouse only: the bar and the grip take clicks only while they are seen)
	local live = hover > 0.3
	if bar.sereneLive ~= live then
		bar.sereneLive = live
		bar:EnableMouse(live)
		grip:EnableMouse(live)
	end
	local locked = frame.isLocked and true or false
	grip:SetShown(not locked)
	if sizing and not IsMouseButtonDown("LeftButton") then
		Safe(sizing.StopMovingOrSizing, sizing)
		if _G.FCF_SavePositionAndDimensions then Safe(_G.FCF_SavePositionAndDimensions, sizing) end
		sizing = nil
	end
end

function ns.ShellOver()
	if not bar then return false end
	return dragging or sizing ~= nil or Over(bar) or Over(grip) or (pill:IsShown() and Over(pill))
end

-- Start -----------------------------------------------------------------------------------------------------------

local function Init()
	chat = ns.chat
	if not chat then return end
	local under, holder, INK = chat.under, chat.holder, chat.INK

	pane = under:CreateTexture(nil, "BACKGROUND", nil, -8)
	pane:SetColorTexture(INK[1], INK[2], INK[3], 1)
	pane:SetAlpha(0)
	hair = under:CreateTexture(nil, "BORDER")
	hair:SetColorTexture(1, 1, 1, 1)
	hair:SetHeight(1)
	hair:SetAlpha(0)

	bar = CreateFrame("Frame", nil, holder)
	bar:SetWidth(12)
	track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(1, 1, 1, HAIR)
	track:SetWidth(1)
	track:SetPoint("TOP", bar, "TOP")
	track:SetPoint("BOTTOM", bar, "BOTTOM")
	thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(1, 1, 1, 1)
	thumb:SetWidth(2)
	bar:EnableMouse(false)
	bar:SetScript("OnEnter", function() over.bar = true end)
	bar:SetScript("OnLeave", function() over.bar = false end)
	bar:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then dragging = true end end)
	bar:SetScript("OnMouseUp", function() dragging = false end)
	if bar.EnableMouseWheel then bar:EnableMouseWheel(true) end
	bar:SetScript("OnMouseWheel", function(_, delta)
		local frame = chat.Selected()
		if not frame then return end
		if delta > 0 then Safe(frame.ScrollUp, frame) else Safe(frame.ScrollDown, frame) end
	end)

	grip = CreateFrame("Frame", nil, holder)
	grip:SetSize(14, 14)
	grip.icon = grip:CreateTexture(nil, "ARTWORK")
	grip.icon:SetAllPoints()
	grip.icon:SetTexture(MEDIA .. "Grip")
	Words(grip.icon, false)
	grip:EnableMouse(false)
	grip:SetScript("OnEnter", function() Words(grip.icon, true) end)
	grip:SetScript("OnLeave", function() Words(grip.icon, false) end)
	grip:SetScript("OnMouseDown", function(_, button)
		local frame = chat.Selected()
		if button ~= "LeftButton" or not frame or frame.isLocked then return end
		-- (docked windows share the dock's size: the first window is the one resized)
		local dock = _G.GENERAL_CHAT_DOCK
		local target = (frame.isDocked and dock and dock.primary) or frame
		if Safe(target.IsResizable, target) == false then return end
		if pcall(target.StartSizing, target, "BOTTOMRIGHT") then sizing = target end
	end)

	pill = CreateFrame("Button", nil, UIParent)
	pill:SetFrameStrata(ChatFrame1:GetFrameStrata() or "LOW")
	pill:SetFrameLevel((ChatFrame1:GetFrameLevel() or 1) + 10)
	pill:SetSize(70, 18)
	pill.ground = pill:CreateTexture(nil, "BACKGROUND")
	pill.ground:SetAllPoints()
	pill.ground:SetTexture(MEDIA .. "Pill")
	pill.ground:SetVertexColor(INK[1], INK[2], INK[3], 0.88)
	pill.arrow = pill:CreateTexture(nil, "ARTWORK")
	pill.arrow:SetTexture(MEDIA .. "IconDown")
	pill.arrow:SetSize(12, 12)
	pill.arrow:SetPoint("LEFT", pill, "LEFT", 9, 0)
	local c = chat.GOLD
	pill.arrow:SetVertexColor(c[1], c[2], c[3], 1)
	pill.text = pill:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	pill.text:SetPoint("LEFT", pill.arrow, "RIGHT", 4, 0)
	pill.text:SetTextColor(chat.TAB_WORDS[1], chat.TAB_WORDS[2], chat.TAB_WORDS[3])
	pill:SetScript("OnClick", function()
		local frame = chat.Selected()
		if frame then Safe(frame.ScrollToBottom, frame) end
		if frame then unread[frame] = nil end
	end)
	pill:SetScript("OnEnter", function() pill.text:SetTextColor(c[1], c[2], c[3]) end)
	pill:SetScript("OnLeave", function()
		pill.text:SetTextColor(chat.TAB_WORDS[1], chat.TAB_WORDS[2], chat.TAB_WORDS[3])
	end)
	pill:Hide()

	ns.ShellDress()
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", Update)
end

table.insert(ns.modules, { init = Init })
