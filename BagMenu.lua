local _, ns = ...

-- A small menu of Serene's own, on glass at the mouse (not the game's dropdown): the bags' "whose bags" and "whose
-- bank", an item's section (Alt-right-click), removing a section of your own. A title in gold, choices in white (the
-- bags' own sections muted), a gold dot by the one in use, and a field to type a new section's name. It closes by
-- itself once the mouse has left it a moment, with Esc, or on a click elsewhere in it.
--   ns.BagMenu(owner, rows)   opened at the mouse (again on the same owner: closed)
--   ns.BagMenuHide()          closed

local MEDIA = "Interface\\AddOns\\Serene\\Media\\"
local INK, SOFT, MUTED_RGB = ns.INK, ns.SOFT_RGB, ns.MUTED_RGB
local GOLD = { 1, 0.82, 0.35 }

local MENU_ROW, MENU_WIDTH = 20, 180
local menu
local menuLast = 0

local function MakeMenu()
	menu = CreateFrame("Frame", "SereneBagsMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	local ground = menu:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(INK[1], INK[2], INK[3], 0.94)
	local rule = menu:CreateTexture(nil, "BORDER")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
	menu.rows = {}
	local edit = CreateFrame("EditBox", nil, menu)
	edit:SetAutoFocus(false)
	edit:SetFontObject("GameFontHighlightSmall")
	edit:SetHeight(MENU_ROW)
	edit:SetMaxLetters(32)
	edit:SetTextInsets(4, 4, 0, 0)
	local line = edit:CreateTexture(nil, "BACKGROUND")
	line:SetAllPoints()
	line:SetColorTexture(1, 1, 1, 0.06)
	edit.hint = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	edit.hint:SetPoint("LEFT", edit, "LEFT", 4, 0)
	edit.hint:SetTextColor(MUTED_RGB[1], MUTED_RGB[2], MUTED_RGB[3])
	edit:SetScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() menu:Hide() end)
	edit:SetScript("OnEnterPressed", function(self)
		local text = strtrim(self:GetText() or "")
		self:ClearFocus()
		menu:Hide()
		if text ~= "" and self.done then self.done(text) end
	end)
	edit:Hide()
	menu.edit = edit
	-- (the mouse gone from it a moment, a little margin allowed: it closes by itself)
	menu:SetScript("OnUpdate", function(self)
		if self:IsMouseOver(4, -4, -4, 4) or edit:HasFocus() then menuLast = GetTime() return end
		if GetTime() - menuLast > 1.2 then self:Hide() end
	end)
	tinsert(UISpecialFrames, "SereneBagsMenu")
end

local function MenuRow(index)
	local row = menu.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, menu)
	row:SetSize(MENU_WIDTH - 16, MENU_ROW)
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.light = row:CreateTexture(nil, "BACKGROUND")
	row.light:SetAllPoints()
	row.light:SetColorTexture(SOFT[1], SOFT[2], SOFT[3], 0.06)
	row.light:Hide()
	row.knob = row:CreateTexture(nil, "ARTWORK")
	row.knob:SetTexture(MEDIA .. "Disc")
	row.knob:SetSize(7, 7)
	row.knob:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.knob:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	row:SetScript("OnEnter", function(self) if self.action then self.light:Show() end end)
	row:SetScript("OnLeave", function(self) self.light:Hide() end)
	row:SetScript("OnClick", function(self)
		if not self.action then return end
		menu:Hide()
		self.action()
	end)
	menu.rows[index] = row
	return row
end

-- rows: { text, action (nil: a title), on (a gold dot), muted, edit (a text field: called with the words) }
function ns.BagMenu(owner, rows)
	if not menu then MakeMenu() end
	if menu:IsShown() and menu.owner == owner then return menu:Hide() end
	if ns.HideTip then ns.HideTip() end
	menu.owner = owner
	menu.edit:Hide()
	local y = -8
	for index, spec in ipairs(rows) do
		local row = MenuRow(index)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
		if spec.edit then
			row:Hide()
			menu.edit:ClearAllPoints()
			menu.edit:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
			menu.edit:SetWidth(MENU_WIDTH - 16)
			menu.edit:SetText("")
			menu.edit.done = spec.edit
			menu.edit.hint:SetText(spec.text or "A new section...")
			menu.edit.hint:Show()
			menu.edit:Show()
		else
			row.text:SetText(spec.text)
			local color = spec.action and (spec.muted and MUTED_RGB or SOFT) or GOLD
			row.text:SetTextColor(color[1], color[2], color[3])
			row.knob:SetShown(spec.on and true or false)
			row.action = spec.action
			row:Show()
		end
		y = y - MENU_ROW
	end
	for index = #rows + 1, #menu.rows do menu.rows[index]:Hide() end
	menu:SetSize(MENU_WIDTH, -y + 8)
	menu:ClearAllPoints()
	-- (the cursor in screen pixels: brought into UIParent's units)
	local x, top = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, top / scale + 10)
	menuLast = GetTime()
	menu:Show()
end

function ns.BagMenuHide()
	if menu then menu:Hide() end
end
