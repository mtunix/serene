local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Pages turned calmly. When Action Bar 1 changes what it holds (a page turned, a stance or form taken: the game
-- swaps its buttons at once), its icons come in softly instead of snapping. A paged bar says which page: a small
-- quiet number at its left end (not on the first page, not in a form, whose own buttons say it).
-- Only icons' opacity and a word of Serene's: safe in a fight. (Settings > Action bars > Pages)

local FADE = 0.22    -- seconds for the icons to come in
local FROM = 0.15    -- where they start

local fading = 0     -- 0..1 while the icons come in (1: done)
local lastPage, lastBonus
local mark
local driver

local function Icon(index)
	local button = _G["ActionButton" .. index]
	if type(button) ~= "table" then return nil end
	return rawget(button, "icon") or _G["ActionButton" .. index .. "Icon"]
end

local function SetIcons(alpha)
	for index = 1, 12 do
		local icon = Icon(index)
		if icon then pcall(icon.SetAlpha, icon, alpha) end
	end
end

local function Page()
	local page = Clean(Safe(_G.GetActionBarPage)) or 1
	local bonus = Clean(Safe(_G.GetBonusBarOffset)) or 0
	return page, bonus
end

local function Mark()
	if mark then return mark end
	local first = _G.ActionButton1
	if type(first) ~= "table" then return nil end
	local bar = _G.MainActionBar or _G.MainMenuBar
	mark = (type(bar) == "table" and bar or UIParent):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mark:SetPoint("RIGHT", first, "LEFT", -6, 0)
	local muted = ns.MUTED_RGB
	mark:SetTextColor(muted[1], muted[2], muted[3])
	return mark
end

local function ShowMark(page, bonus)
	local text = Mark()
	if not text then return end
	if ns.On("barPages") and page ~= 1 and bonus == 0 then
		text:SetText(page)
		text:Show()
	else
		text:Hide()
	end
end

local function Changed()
	local page, bonus = Page()
	if page == lastPage and bonus == lastBonus then return end
	local first = lastPage == nil -- (the first reading, at login: nothing to fade from)
	lastPage, lastBonus = page, bonus
	ShowMark(page, bonus)
	if first or not ns.On("barPages") then return end
	-- (the new icons are on already: they start faint and come in)
	fading = 0
	SetIcons(FROM)
	driver:Show()
end

local function Init()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(self, elapsed)
		fading = math.min(1, fading + elapsed / FADE)
		SetIcons(FROM + (1 - FROM) * fading)
		if fading >= 1 then self:Hide() end
	end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
		"PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function() pcall(Changed) end)
end

local function Refresh()
	local page, bonus = Page()
	ShowMark(page, bonus)
	if not ns.On("barPages") and driver and driver:IsShown() then
		driver:Hide()
		SetIcons(1)
	end
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
