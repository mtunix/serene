local _, ns = ...
local Safe, Clean = ns.Safe, ns.Clean

-- Names over heads hidden or shown with one key (` by default; Key Bindings > AddOns > Serene): players', NPCs',
-- pets', your own, guilds and titles. Hiding remembers how each was set and showing gives exactly that back, also
-- after a reload or the next login.

local CVARS = { "UnitNameOwn", "UnitNameNPC", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
	"UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
	"UnitNameFriendlyTotemName", "UnitNameEnemyTotemName", "UnitNameNonCombatCreatureName", "UnitNamePlayerGuild",
	"UnitNamePlayerPVPTitle", "UnitNameGuildTitle", "UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
	"UnitNameInteractiveNPC", "UnitNameHostleNPC", "UnitNameFriendlySpecialNPCName" } -- ("Hostle": the game's spelling)
local DEFAULT_KEY = "`"

local function GetVar(name)
	if C_CVar and C_CVar.GetCVar then return Clean(Safe(C_CVar.GetCVar, name)) end
	return Clean(Safe(GetCVar, name))
end

local function SetVar(name, value)
	if C_CVar and C_CVar.SetCVar then return Safe(C_CVar.SetCVar, name, value) end
	return Safe(SetCVar, name, value)
end

local function Hidden() return type(ns.db.namesSaved) == "table" end

local function Hide()
	if Hidden() then return end
	local saved = {}
	for _, name in ipairs(CVARS) do
		local value = GetVar(name)
		if value ~= nil then -- (only the ones this client has)
			saved[name] = value
			SetVar(name, "0")
		end
	end
	ns.db.namesSaved = saved
	ns.Print("names hidden")
end

local function Show()
	if not Hidden() then return end
	for name, value in pairs(ns.db.namesSaved) do SetVar(name, value) end
	ns.db.namesSaved = nil
	ns.Print("names shown")
end

function Serene_ToggleNames()
	if Hidden() then Show() else Hide() end
end
BINDING_NAME_SERENE_NAMES = "Hide / show names over heads"

-- The key: given once, at the first login with this, when nothing else (but an addon no longer here) holds it.
local function BindOnce()
	if ns.db.namesKeyGiven or InCombatLockdown() then return end
	ns.db.namesKeyGiven = true
	if Safe(GetBindingKey, "SERENE_NAMES") then return end
	local action = Clean(Safe(GetBindingAction, DEFAULT_KEY)) or ""
	if action ~= "" and not action:find("^WANDERER") then -- (Wanderer's bindings outlive the addon)
		ns.Print(("the key %s does %s already: set one for \"Hide / show names\" in Key Bindings > AddOns")
			:format(DEFAULT_KEY, action))
		return
	end
	if pcall(SetBinding, DEFAULT_KEY, "SERENE_NAMES") then
		local set = Clean(Safe(GetCurrentBindingSet))
		if set then Safe(SaveBindings, set) end -- (kept past this session)
	end
end

local function Init()
	BindOnce()
	-- (names left hidden last time: still hidden, the game may have reset some of them)
	if Hidden() then
		for name in pairs(ns.db.namesSaved) do SetVar(name, "0") end
	end
end

table.insert(ns.modules, { init = Init })
