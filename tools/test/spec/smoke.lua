-- The whole addon loaded and run against the stub: login, every module's refresh, every switch and setting, a fight,
-- the debug commands and a storm of the game's events. Nothing may error.
--
-- Catches: a local used above its definition (nil at call time), a typo in an ns.* export, a module that breaks on a
-- setting nobody tried, a script that errors on an event's arguments. It can't see whether anything *looks* right.

local ns = wow.load()

-- Every boolean setting and every word setting, read from Core.lua's DEFAULTS (a word setting's choices are the
-- quoted words in its comment: castText = "in", -- "in" the bar, "under" it, or "none").
local function Choices()
	local choices = {}
	for line in io.lines(wow.root .. "/Core.lua") do
		local key, value, comment = line:match('^%s+([%w_]+)%s*=%s*"([%w_]+)",?%s*%-%-(.*)$')
		if key and ns.DEFAULTS[key] == value then
			local words = {}
			for word in comment:gmatch('"([%w_]+)"') do words[#words + 1] = word end
			if #words > 0 then choices[key] = words end
		end
	end
	return choices
end

local function Refreshes()
	-- (called directly: Core's Refresh() runs each in pcall and drops the error)
	for index, module in ipairs(ns.modules) do
		if module.refresh then wow.call("module " .. index .. " refresh", module.refresh) end
	end
end

-- Plausible arguments for the events Serene listens to.
local ARGS = {
	UNIT_AURA = { "player", { isFullUpdate = true } }, UNIT_HEALTH = { "player" }, UNIT_POWER_UPDATE = { "player", "MANA" },
	UNIT_POWER_FREQUENT = { "player", "MANA" }, UNIT_DISPLAYPOWER = { "player" }, UNIT_PET = { "player" },
	UNIT_INVENTORY_CHANGED = { "player" }, UNIT_SPELLCAST_SUCCEEDED = { "player", "Cast-1", 133 },
	UNIT_ATTACK_SPEED = { "player" }, UNIT_RANGEDDAMAGE = { "player" }, UNIT_FACTION = { "target" },
	UNIT_CLASSIFICATION_CHANGED = { "target" }, UNIT_PORTRAIT_UPDATE = { "player" }, UNIT_COMBAT = { "player", "WOUND", "", 10, 1 },
	UNIT_ENTERED_VEHICLE = { "player" }, UNIT_EXITED_VEHICLE = { "player" },
	BAG_UPDATE = { 0 }, BAG_CONTAINER_UPDATE = {}, ITEM_LOCK_CHANGED = { 0, 1 }, PLAYER_SWING = { 2.6, 0 },
	CVAR_UPDATE = { "showSwingTimer", "1" }, MODIFIER_STATE_CHANGED = { "LSHIFT", 1 }, ACTIONBAR_SLOT_CHANGED = { 1 },
	NAME_PLATE_UNIT_ADDED = { "nameplate1" }, PLAYER_EQUIPMENT_CHANGED = { 16, false }, GET_ITEM_INFO_RECEIVED = { 2589, true },
	LEARNED_SPELL_IN_SKILL_LINE = { 133 }, LEARNED_SPELL_IN_TAB = { 133, 1 }, PLAYER_ENTERING_WORLD = { false, false },
	PLAYER_INTERACTION_MANAGER_FRAME_HIDE = { 5 }, SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = { 133 },
	SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = { 133 }, PLAYER_LEVEL_UP = { 61 },
}
local EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER_UPDATE",
	"UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_PET", "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE",
	"UNIT_COMBAT", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "BAG_UPDATE_COOLDOWN",
	"BAG_NEW_ITEMS_UPDATED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
	"PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_SWING",
	"PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "CVAR_UPDATE",
	"MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN",
	"ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "ACTION_USABLE_CHANGED", "ACTION_RANGE_CHECK_UPDATE",
	"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USES", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB",
	"SKILL_LINES_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
	"UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE", "UPDATE_MULTI_CAST_ACTIONBAR", "PLAYER_EQUIPMENT_CHANGED",
	"UPDATE_INVENTORY_DURABILITY", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_STARTED_MOVING",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_GAINED",
	"CURSOR_CHANGED", "GET_ITEM_INFO_RECEIVED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED",
	"GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED", "PLAYER_GUILD_UPDATE", "UPDATE_BATTLEFIELD_STATUS",
	"LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
	"SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_ENTERING_WORLD", "MERCHANT_SHOW", "MERCHANT_UPDATE",
	"MERCHANT_FILTER_ITEM_UPDATE", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "WHO_LIST_UPDATE" }

local function Storm()
	for _, event in ipairs(EVENTS) do
		wow.fire(event, unpack(ARGS[event] or {}))
		wow.advance(0.2)
	end
end

-- A player with something in their bags, a target, a few spells and actions on the bars.
local function World()
	wow.items[2589] = { name = "Linen Cloth", quality = 1, stack = 20, sell = 13, classID = 7, subclassID = 5 }
	wow.items[4865] = { name = "Ruined Pelt", quality = 0, stack = 10, sell = 5, classID = 15 }
	wow.items[2512] = { name = "Rough Arrow", quality = 1, stack = 200, sell = 1, classID = 6 }
	wow.items[25] = { name = "Worn Shortsword", quality = 1, sell = 7, classID = 2, equipLoc = "INVTYPE_WEAPONMAINHAND" }
	wow.items[159] = { name = "Refreshing Spring Water", quality = 1, stack = 20, sell = 1, classID = 0 }
	wow.bags[0] = { size = 16, [1] = { id = 2589, count = 7 }, [2] = { id = 4865, count = 2 }, [3] = { id = 25 },
		[4] = { id = 159, count = 5 } }
	wow.bags[1] = { size = 10, [1] = { id = 2512, count = 200 } }
	wow.spells[133] = { name = "Fireball", known = true }
	wow.spells[6673] = { name = "Battle Shout", known = true }
	wow.actions = { [1] = { kind = "spell", id = 133 }, [2] = { kind = "spell", id = 6673 }, [3] = { kind = "item", id = 159 } }
	wow.units.target = { name = "Defias Thug", level = 12, class = "Warrior", classFile = "WARRIOR", enemy = true,
		guid = "Creature-0-1", classification = "normal" }
	wow.player.buffs = { { name = "Battle Shout", spellId = 6673, duration = 120, expirationTime = wow.now + 100, mine = true } }
end

test("a new player logs in (no saved settings)", function()
	wow.login(nil)
	wow.advance(5)
	clean()
	ok(ns.db, "ns.db set at ADDON_LOADED")
	for key, value in pairs(ns.DEFAULTS) do
		if type(value) ~= "table" then eq(ns.db[key], value, "default " .. key) end
	end
end)

test("every module's refresh runs after login", function()
	World()
	wow.login(nil)
	wow.advance(2)
	Refreshes()
	wow.advance(2)
	clean()
end)

test("every switch turned off and on again with /serene", function()
	World()
	wow.login(nil)
	wow.advance(1)
	for _, word in ipairs({ "chat", "tags", "group", "card", "loot", "gains", "quiet", "calm", "minimap", "fade", "bars",
		"keys", "macros", "empty", "ready", "menu", "swing", "shots", "units", "portraits", "elite", "castbar", "auras",
		"auraunits", "regen", "xpgain", "toasts", "hints", "tooltip", "tipcalm", "tipmore", "tipcard", "tipvendor",
		"tracker", "top", "bags", "bagcounts", "merchant", "junk", "repair", "idle" }) do
		wow.slash("/serene " .. word .. " off")
		Refreshes()
		wow.advance(0.5)
		wow.slash("/serene " .. word .. " on")
		Refreshes()
		wow.advance(0.5)
	end
	clean()
end)

test("every boolean setting the other way round from login", function()
	World()
	local saved = {}
	for key, value in pairs(ns.DEFAULTS) do
		if type(value) == "boolean" then saved[key] = not value end
	end
	wow.login(saved)
	wow.advance(2)
	Refreshes()
	Storm()
	clean()
end)

test("every boolean setting off from login", function()
	World()
	local saved = {}
	for key, value in pairs(ns.DEFAULTS) do
		if type(value) == "boolean" then saved[key] = false end
	end
	wow.login(saved)
	wow.advance(2)
	Storm()
	clean()
end)

test("every word setting through each of its choices", function()
	World()
	wow.login(nil)
	wow.advance(1)
	local tried = 0
	for key, words in pairs(Choices()) do
		for _, word in ipairs(words) do
			ns.db[key] = word
			Refreshes()
			wow.advance(0.3)
			tried = tried + 1
		end
		ns.db[key] = ns.DEFAULTS[key]
	end
	ok(tried > 40, "the choices were read from Core.lua (" .. tried .. ")")
	clean()
end)

test("each word setting's choices at login", function()
	World()
	for key, words in pairs(Choices()) do
		for _, word in ipairs(words) do
			-- (each ADDON_LOADED migrates the value set the turn before; init runs only at the login below)
			local saved = { [key] = word }
			wow.fire("ADDON_LOADED", "Serene")
			SereneDB = saved
		end
	end
	wow.login({ barStyle = "round", auraFrame = "game", castText = "under", auraTime = "plate", compass = "world",
		edge = "square", topShow = "always", bankAt = "free", merchantAt = "game", auraDebuffAt = "free",
		hintReveal = "bars", barCooldown = "line", barCooldownText = "always", auraShape = "square", auraRing = "none" })
	wow.advance(2)
	Storm()
	clean()
end)

test("the slash command's other words", function()
	World()
	wow.login(nil)
	wow.advance(1)
	for _, line in ipairs({ "help", "rest 40", "lines 60", "idle 300", "compass world", "top calm", "border none",
		"edge square", "barstyle glass", "swingsize 150", "auratime plate", "castheight 12", "castwidth 200",
		"columns 12", "fade bars off", "fade bars on", "sets", "sets save Test", "sets load Test", "sets delete Test",
		"review", "supply food", "ping", "toasts test", "aurasmove", "aurasmove", "nonsense words" }) do
		wow.slash("/serene " .. line)
		wow.advance(0.3)
	end
	eq(ns.db.rest, 40)
	eq(ns.db.castWidth, 200)
	eq(ns.db.groups.bars, true)
	clean()
end)

test("/serene debug and its special words", function()
	World()
	wow.login(nil)
	wow.advance(1)
	for _, word in ipairs({ "", " menu", " mouse", " auras", " glow", " units", " units PlayerFrame", " taint" }) do
		wow.slash("/serene debug" .. word)
	end
	-- (the game's answer, as the stub has none: every key written by Serene)
	issecurevariable = function() return false, "Serene" end
	wow.slash("/serene debug taint PlayerFrame")
	ok(#SereneDB.probeTaint > 0, "what addons wrote kept")
	clean()
end)

test("the game blocking Serene: said and kept, the last 20; another addon's block: not", function()
	World()
	wow.login(nil)
	for i = 1, 22 do wow.fire("ADDON_ACTION_FORBIDDEN", "Serene", "UNKNOWN()") end
	wow.fire("ADDON_ACTION_BLOCKED", "Questie", "CastSpell()")
	eq(#SereneDB.probeBlocked, 20, "the last 20")
	ok(SereneDB.probeBlocked[20]:find("forbidden UNKNOWN%(%)"), "the action named")
	clean()
end)

test("a fight: in, events, out", function()
	World()
	wow.login(nil)
	wow.advance(2)
	wow.fight(true)
	wow.advance(1)
	Storm()
	wow.fight(false)
	wow.advance(3)
	clean()
end)

test("the mouse over each of Serene's own frames", function()
	World()
	wow.login(nil)
	wow.advance(2)
	for _, f in ipairs(wow.frames) do
		local name = f:GetName()
		if name and name:find("^Serene") and f:IsObjectType("Frame") then
			wow.hover(f)
			wow.advance(0.2)
		end
	end
	wow.hover(nil)
	clean()
end)

test("idle: nothing done for a long while, then back", function()
	World()
	wow.login(nil)
	wow.advance(ns.db.idleAfter + 30, 1)
	wow.cursorX = 10
	wow.advance(2)
	clean()
end)
