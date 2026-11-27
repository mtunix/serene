-- Minimap.lua: the compass's round buttons and the game's pieces placed on its ring.

local ns = wow.load({ "Core.lua", "Minimap.lua" })

-- (the game's day and night: what IsDayTime says, changed by a test)
local isDay = true
C_DateAndTime = { IsDayTime = function() return isDay end }

-- (the game's mail holder, hung from its zone plate as on this client)
MinimapCluster.ZoneTextButton = CreateFrame("Button", nil, MinimapCluster)
MinimapCluster.IndicatorFrame = CreateFrame("Frame", nil, MinimapCluster)
MinimapCluster.IndicatorFrame:SetSize(32, 24)
MinimapCluster.IndicatorFrame:SetPoint("TOPLEFT", MinimapCluster.ZoneTextButton, "BOTTOMLEFT", 0, 0)
-- (the day and night: nameless, hung from the map's container high on the right)
MinimapCluster.MinimapContainer = CreateFrame("Frame", nil, MinimapCluster)
MinimapCluster.DielFrame = CreateFrame("Frame", nil, MinimapCluster.MinimapContainer)
MinimapCluster.DielFrame:SetPoint("CENTER", 55, 86)
wow.login({})

local function AddonsBadge()
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child.key == "addons" then return child end
	end
end

local function CalendarBadge()
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child.key == "calendar" then return child end
	end
end

-- The calendar's sun or moon, shown; nil when neither shows.
local function Glyph()
	for _, region in ipairs({ CalendarBadge():GetRegions() }) do
		local texture = region.GetTexture and region:GetTexture()
		if type(texture) == "string" and texture:find("Icon[SM][uo][no]") and region:IsShown() then
			return texture:match("(Icon%a+)$")
		end
	end
end

local function Where(frame)
	local point, relative, _, x, y = frame:GetPoint(1)
	return point, relative, x, y
end

test("the mail sits on the ring at the lower corner the addons' button leaves free", function()
	local mail = MinimapCluster.IndicatorFrame
	local point, relative, x, y = Where(mail)
	eq(point, "CENTER")
	eq(relative, Minimap)
	local _, _, bx, by = Where(AddonsBadge())
	eq(by < 0, true, "the addons' button low on the ring")
	eq(math.abs(x - -bx) < 0.01 and math.abs(y - by) < 0.01, true, "the mail its mirror")
end)

test("the mail is put back when the game moves it (Edit Mode's header)", function()
	local mail = MinimapCluster.IndicatorFrame
	local _, _, x, y = Where(mail)
	mail:ClearAllPoints()
	mail:SetPoint("BOTTOMLEFT", MinimapCluster.ZoneTextButton, "TOPLEFT", 0, 0)
	local point, relative, nx, ny = Where(mail)
	eq(point, "CENTER")
	eq(relative, Minimap)
	eq(nx, x)
	eq(ny, y)
end)

test("the day and night goes (it sat on the calendar's button)", function()
	local diel = MinimapCluster.DielFrame
	eq(diel:GetParent() ~= MinimapCluster.MinimapContainer, true, "taken from the map")
	eq(diel:IsVisible(), false)
end)

test("the calendar holds the day: a small sun over the date", function()
	isDay = true
	wow.advance(0.5)
	eq(Glyph(), "IconSun")
end)

test("and the night: a crescent, the glass gone deep blue", function()
	isDay = false
	wow.advance(0.5)
	eq(Glyph(), "IconMoon")
	local badge = CalendarBadge()
	local disc = select(1, badge:GetRegions())
	local r, _, b = disc:GetVertexColor()
	eq(b > r, true, "blue glass")
	isDay = true
end)

test("day or night unknown (hidden in a fight): the date alone on plain glass", function()
	isDay = wow.secret(true)
	wow.advance(0.5)
	eq(Glyph(), nil)
	isDay = nil
	wow.advance(0.5)
	eq(Glyph(), nil)
	isDay = true
end)

test("the calendar, larger than the other buttons, has its middle on the ring like theirs", function()
	local tracking
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child.key == "tracking" then tracking = child end
	end
	local calendar = CalendarBadge()
	eq(calendar:GetWidth() > tracking:GetWidth(), true, "larger")
	local _, _, cx, cy = Where(calendar)
	local _, _, tx, ty = Where(tracking)
	eq(math.abs(math.sqrt(cx * cx + cy * cy) - math.sqrt(tx * tx + ty * ty)) < 0.01, true, "the same distance out")
end)
