-- Fights with secret values (wow.secretFight): the client hides auras, health, cooldowns... from addons in a fight.
-- Serene must never do arithmetic on them or compare them; on the client that is a Lua error, here too.

local ns = wow.load()

local function World()
	wow.items[159] = { name = "Refreshing Spring Water", quality = 1, stack = 20, sell = 1, classID = 0 }
	wow.bags[0] = { size = 16, [1] = { id = 159, count = 5 } }
	wow.spells[133] = { name = "Fireball", known = true }
	wow.spells[6673] = { name = "Battle Shout", known = true }
	wow.actions = { [1] = { kind = "spell", id = 133 }, [2] = { kind = "spell", id = 6673 }, [3] = { kind = "item", id = 159 } }
	wow.units.target = { name = "Defias Thug", level = 12, class = "Warrior", classFile = "WARRIOR", enemy = true,
		guid = "Creature-0-1", health = 80, healthMax = 100, combat = true,
		debuffs = { { name = "Rend", spellId = 772, duration = 15, expirationTime = wow.now + 10, mine = true } },
		casting = { "Fireball", "", 135812, (wow.now - 1) * 1000, (wow.now + 2) * 1000, false, "Cast-2", false, 133 } }
	wow.units.focus = wow.units.target
	wow.player.buffs = { { name = "Battle Shout", spellId = 6673, duration = 120, expirationTime = wow.now + 100, mine = true } }
end

local EVENTS = { { "PLAYER_TARGET_CHANGED" }, { "UNIT_AURA", "target", { isFullUpdate = true } },
	{ "UNIT_HEALTH", "target" }, { "UNIT_POWER_UPDATE", "player", "RAGE" }, { "ACTIONBAR_UPDATE_COOLDOWN" },
	{ "SPELL_UPDATE_COOLDOWN" }, { "ACTIONBAR_UPDATE_USABLE" }, { "ACTION_RANGE_CHECK_UPDATE", 1, false, false },
	{ "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133 }, { "PLAYER_SWING", 2.6, 0 }, { "NAME_PLATE_UNIT_ADDED", "nameplate1" },
	{ "PLAYER_FOCUS_CHANGED" }, { "UNIT_AURA", "player", { isFullUpdate = wow.secret(true) } }, { "BAG_UPDATE_DELAYED" } }

local function Through()
	for _, e in ipairs(EVENTS) do
		wow.fire(unpack(e))
		wow.advance(0.25)
	end
end

test("the stub's secrets behave like the client's", function()
	local s = wow.secret(5)
	ok(issecretvalue(s))
	eq(type(s), "number", "type() says what it hides")
	raises(function() return s + 1 end, "secret")
	raises(function() return s < 3 end)
	raises(function() return s.x end, "secret")
	raises(function() return math.max(s, 1) end, "secret")
	ok(issecretvalue(s .. "x"), "concatenating gives a secret")
	eq(ns.Clean(s), nil, "ns.Clean drops a secret")
	eq(ns.Clean(5), 5)
end)

test("a whole fight with secret values, out again", function()
	World()
	wow.login(nil)
	wow.advance(2)
	wow.secretFight(true)
	Through()
	wow.advance(3)
	wow.secretFight(false)
	wow.advance(2)
	Through()
	clean()
end)

test("a fight with secrets, every boolean setting the other way round", function()
	World()
	local saved = {}
	for key, value in pairs(ns.DEFAULTS) do
		if type(value) == "boolean" then saved[key] = not value end
	end
	wow.login(saved)
	wow.advance(2)
	wow.secretFight(true)
	Through()
	wow.secretFight(false)
	clean()
end)

test("a fight with secrets, the other looks (glass, round, Serene's aura frame off)", function()
	World()
	wow.login({ barStyle = "round", auraFrame = "game", auraTime = "plate", barCooldown = "line", barCooldownText = "always",
		auraTimeWhen = "always", auraRing = "debuffs", castText = "under" })
	wow.advance(2)
	wow.secretFight(true)
	Through()
	wow.secretFight(false)
	clean()
end)

test("the mouse over Serene's frames in a fight with secrets", function()
	World()
	wow.login(nil)
	wow.advance(2)
	wow.secretFight(true)
	for _, f in ipairs(wow.frames) do
		local name = f:GetName()
		if name and name:find("^Serene") and f:IsObjectType("Frame") then
			wow.hover(f)
			wow.advance(0.2)
		end
	end
	for index = 1, 12 do
		wow.hover(_G["ActionButton" .. index])
		wow.advance(0.1)
	end
	wow.hover(nil)
	wow.secretFight(false)
	clean()
end)

test("/serene debug in a fight with secrets", function()
	World()
	wow.login(nil)
	wow.advance(1)
	wow.secretFight(true)
	wow.slash("/serene debug")
	wow.secretFight(false)
	clean()
end)
