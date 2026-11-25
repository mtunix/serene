local _, ns = ...
local Safe = ns.Safe

-- The quest tracker hidden: the game's own and Questie's, hidden again each time they show. In a fight the game
-- may refuse to hide the game's tracker (its quest item buttons are protected): it is only made invisible then,
-- and hidden once the fight ends. A key brings them back and hides them again (Key Bindings > AddOns > Serene),
-- or /serene tracker on|off.

local NAMES = { "ObjectiveTrackerFrame", "Questie_BaseFrame" }

local hooked = {} -- frame -> true
local busy = false
local pending = false

local function On() return ns.On("tracker") end

local function Conceal(frame)
	if busy or not On() then return end
	busy = true
	if InCombatLockdown() then
		pcall(frame.SetAlpha, frame, 0)
		pending = true
	else
		pcall(frame.Hide, frame)
	end
	busy = false
end

local function Reveal(frame)
	busy = true
	pcall(frame.SetAlpha, frame, 1)
	if InCombatLockdown() then
		pending = true
	else
		pcall(frame.Show, frame)
	end
	busy = false
end

local function Hook()
	for _, name in ipairs(NAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.HookScript and not hooked[frame] then
			hooked[frame] = true
			frame:HookScript("OnShow", Conceal)
			hooksecurefunc(frame, "SetAlpha", function(self, alpha)
				if busy or not On() or alpha == 0 then return end
				busy = true
				pcall(self.SetAlpha, self, 0)
				busy = false
			end)
		end
	end
end

local function Refresh()
	Hook()
	for frame in pairs(hooked) do
		if On() then Conceal(frame) else Reveal(frame) end
	end
end

function Serene_ToggleTracker()
	ns.db.tracker = not On()
	Refresh()
end
BINDING_NAME_SERENE_TRACKER = "Show / hide the quest tracker"

local function Init()
	Refresh()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and not pending then return end
		pending = false
		Refresh()
	end)
	-- (Questie makes its tracker a little after login)
	C_Timer.After(3, Refresh)
	C_Timer.After(10, Refresh)
end

table.insert(ns.modules, { init = Init, refresh = Refresh })
