-- AuraFrame.lua: Serene's own frame for your buffs and debuffs, built on the game's aura containers. The stub's
-- containers fill nothing themselves; they record what Serene asks of them (its groups, their filters, which are on),
-- and a test makes icons the way the game would, through each group's initializeFrame.
-- Covered: the groups and their filters, what your class can remove, the short buffs learned out of a fight, settings
-- applied without a reload (and after a fight), the missing buffs placed beside the top row, the game's frames put away.

local ns = wow.load({ "Core.lua", "Auras.lua", "AuraFrame.lua" })

local GAP, SMALL_GAP = 5, 4

-- (Hints.lua's answer, stubbed: one class buff missing)
local missing = { { name = "Battle Shout", spell = 6673, icon = 132333 } }
ns.MissingClassBuffs = function() return missing end

-- (the game's buff frame holds a container of its own; the debuff frame here doesn't)
BuffFrame.AuraContainer = CreateFrame("Frame", nil, BuffFrame)

-- Each group the container was given: kind -> { filter, opts }, and their order.
local function Groups(container)
	local by, order = {}, {}
	for _, call in ipairs(wow.calls(container, "AddAuraGroup")) do
		by[call[2]] = { filter = call[3], opts = call[4] }
		order[#order + 1] = call[2]
	end
	return by, order
end

-- What was last asked of a container for a group (nil: never).
local function Last(container, method, kind)
	local found
	for _, call in ipairs(wow.calls(container, method)) do
		if call[2] == kind then found = { call[3] } end
	end
	return found and found[1]
end

local function near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 0.001 then
		error((what and (what .. ": ") or "") .. "expected about " .. expected .. ", got " .. tostring(actual), 2)
	end
end

-- Icons of a kind, made as the game makes them when auras arrive.
local function Make(container, kind, n)
	local maker = Groups(container)[kind].opts.initializeFrame
	local list = {}
	for index = 1, n do
		local button = CreateFrame("Button", nil, container)
		maker(button)
		list[index] = button
	end
	return list
end

-- Where the missing buffs sit: their row's right edge, from the buffs' top right.
local function GhostOffset()
	local point, relative, relativePoint, x = SereneAuraGhosts:GetPoint(1)
	eq({ point, relative, relativePoint }, { "TOPRIGHT", SereneAuras, "TOPRIGHT" }, "the missing buffs' anchor")
	return x
end

-- The groups ---------------------------------------------------------------------------------------------------------

test("buffs in three groups (world, full, small), debuffs in two (removable, other)", function()
	wow.login({})
	local buffs, order = Groups(SereneAuras)
	eq(order, { "world", "full", "small" }, "buff groups")
	eq(buffs.full.filter, "HELPFUL")
	local _, debuffOrder = Groups(SereneDebuffs)
	eq(debuffOrder, { "removable", "other" }, "debuff groups")
	-- (each group after the first starts a new line: the top row is the first group shown)
	no(buffs.world.opts.layout.forceNewLine, "world")
	ok(buffs.full.opts.layout.forceNewLine, "full")
	ok(buffs.small.opts.layout.forceNewLine, "small")
	clean()
end)

test("full holds what is short and not a world buff; the world shelf holds the world buffs", function()
	wow.login({ auraShort = 120 })
	local buffs = Groups(SereneAuras)
	eq(buffs.full.opts.candidateFilters.maxDuration, 120, "short: up to auraShort")
	ok(buffs.full.opts.candidateFilters.excludeSpellIDs[22888], "Rallying Cry kept out of full")
	ok(buffs.world.opts.candidateFilters.includeSpellIDs[22888], "Rallying Cry on the shelf")
	ok(buffs.small.opts.candidateFilters.excludeSpellIDs[22888], "and out of the small row")
	clean()
end)

test("with tiers and world buffs off, full holds every buff and the other two groups are switched off", function()
	wow.login({ auraTiers = false, auraWorld = false })
	local buffs = Groups(SereneAuras)
	eq(buffs.full.opts.candidateFilters, {}, "full: everything")
	eq(Last(SereneAuras, "SetAuraGroupEnabled", "small"), false, "small off")
	eq(Last(SereneAuras, "SetAuraGroupEnabled", "world"), false, "world off")
	clean()
end)

test("a warrior removes nothing: no removable group, every debuff in other", function()
	wow.login({})
	eq(Last(SereneDebuffs, "SetAuraGroupEnabled", "removable"), false, "removable off")
	eq(Groups(SereneDebuffs).other.opts.candidateFilters, {}, "other: every debuff")
	clean()
end)

test("a priest who knows Dispel Magic and Cure Disease: those kinds first, the rest after", function()
	wow.player.class, wow.player.classFile = "Priest", "PRIEST"
	wow.spells[527] = { known = true }
	wow.spells[528] = { known = true }
	wow.login({})
	local debuffs = Groups(SereneDebuffs)
	eq(debuffs.removable.opts.candidateFilters, { includeDispelTypes = { Magic = true, Disease = true } })
	eq(debuffs.other.opts.candidateFilters, { excludeDispelTypes = { Magic = true, Disease = true } })
	eq(Last(SereneDebuffs, "SetAuraGroupEnabled", "removable"), nil, "removable stays on")
	clean()
end)

test("a priest who can't remove anything yet learns it: the groups change without a reload", function()
	wow.player.class, wow.player.classFile = "Priest", "PRIEST"
	wow.login({})
	eq(Last(SereneDebuffs, "SetAuraGroupEnabled", "removable"), false, "nothing to remove at first")
	wow.spells[527] = { known = true }
	wow.fire("SPELLS_CHANGED")
	wow.advance(0.5)
	eq(Last(SereneDebuffs, "SetAuraGroupEnabled", "removable"), true, "removable on")
	eq(Last(SereneDebuffs, "SetAuraGroupCandidateFilters", "removable"), { includeDispelTypes = { Magic = true } })
	clean()
end)

-- Short buffs, learned -------------------------------------------------------------------------------------------------

test("a buff seen to be short is learned out of a fight and left out of the small row", function()
	wow.player.buffs = { { name = "Power Word: Shield", spellId = 17, duration = 30 },
		{ name = "Fortitude", spellId = 1243, duration = 1800 } }
	wow.login({})
	ok(ns.db.auraShortSpells[17], "the shield: short")
	no(ns.db.auraShortSpells[1243], "Fortitude: long")
	ok(Groups(SereneAuras).small.opts.candidateFilters.excludeSpellIDs[17], "kept out of the small row")
	clean()
end)

test("a spell that turns out long again is let go; in a fight nothing is learned", function()
	wow.player.buffs = { { name = "Shield", spellId = 17, duration = 30 } }
	wow.login({})
	wow.player.buffs = { { name = "Shield", spellId = 17, duration = 3600 } }
	wow.fire("UNIT_AURA", "player")
	wow.advance(0.5)
	no(ns.db.auraShortSpells[17], "long now")
	eq(Last(SereneAuras, "SetAuraGroupCandidateFilters", "small").excludeSpellIDs[17], nil, "the small row takes it again")
	wow.fight(true)
	wow.player.buffs = { { name = "Renew", spellId = 139, duration = 15 } }
	wow.fire("UNIT_AURA", "player")
	wow.advance(0.5)
	no(ns.db.auraShortSpells[139], "not in a fight")
	clean()
end)

test("a reload in a fight learns nothing", function()
	wow.player.buffs = { { name = "Renew", spellId = 139, duration = 15 } }
	wow.combat = true
	wow.login({})
	eq(ns.db.auraShortSpells and ns.db.auraShortSpells[139], nil)
	clean()
end)

-- Settings ---------------------------------------------------------------------------------------------------------------

test("a setting changed applies at once out of a fight, and only after it in one", function()
	wow.login({})
	ns.db.auraShort = 60
	ns.Refresh()
	eq(Last(SereneAuras, "SetAuraGroupCandidateFilters", "full").maxDuration, 60, "out of a fight")
	wow.fight(true)
	ns.db.auraShort = 90
	ns.Refresh()
	eq(Last(SereneAuras, "SetAuraGroupCandidateFilters", "full").maxDuration, 60, "waits in the fight")
	wow.fight(false)
	wow.advance(0.5)
	eq(Last(SereneAuras, "SetAuraGroupCandidateFilters", "full").maxDuration, 90, "after it")
	clean()
end)

test("icons are sized by kind: full, small, and the debuffs", function()
	wow.login({ auraSize = 30, auraSmall = 14, auraDebuffSize = 40 })
	local full, small = Make(SereneAuras, "full", 1)[1], Make(SereneAuras, "small", 1)[1]
	local other = Make(SereneDebuffs, "other", 1)[1]
	ok(full:GetWidth() >= 30 and full:GetWidth() < 32, "full: 30 and its ring")
	ok(small:GetWidth() >= 14 and small:GetWidth() < 16, "small: 14 and its ring")
	ok(other:GetWidth() >= 40 and other:GetWidth() < 42, "a debuff: 40 and its ring")
	ns.db.auraSize = 40
	ns.Refresh()
	ok(full:GetWidth() >= 40, "a new size applied to icons already made")
	clean()
end)

-- The missing buffs, beside the top row ----------------------------------------------------------------------------------

test("the missing buffs sit one gap left of the top row's icons", function()
	wow.login({})
	local full = Make(SereneAuras, "full", 3)
	ns.Refresh()
	local w = full[1]:GetWidth()
	near(GhostOffset(), -(3 * w + 2 * GAP + GAP))
	ok(SereneAuraGhosts:IsShown(), "shown")
	eq(SereneAuraGhost1:GetAttribute("spell"), 6673, "a click casts it")
	clean()
end)

test("the top row ends where a row is full", function()
	wow.login({ auraPerRow = 3 })
	local full = Make(SereneAuras, "full", 5)
	ns.Refresh()
	local w = full[1]:GetWidth()
	near(GhostOffset(), -(3 * w + 2 * GAP + GAP))
	clean()
end)

test("the top row is the first group shown: the small row and the world shelf start lines of their own", function()
	wow.login({})
	local full = Make(SereneAuras, "full", 2)
	Make(SereneAuras, "small", 3)
	ns.Refresh()
	near(GhostOffset(), -(2 * full[1]:GetWidth() + GAP + GAP), "full, then small below")
	local world = Make(SereneAuras, "world", 1)
	ns.Refresh()
	near(GhostOffset(), -(world[1]:GetWidth() + GAP), "the world shelf on top, alone")
	clean()
end)

test("only small icons: the top row is theirs, with their narrower gaps", function()
	wow.login({})
	local small = Make(SereneAuras, "small", 4)
	ns.Refresh()
	near(GhostOffset(), -(4 * small[1]:GetWidth() + 3 * SMALL_GAP + GAP))
	clean()
end)

test("nothing missing: no row of ghosts; a fight hides them before it locks them", function()
	missing = {}
	wow.login({})
	no(SereneAuraGhosts:IsShown(), "nothing missing")
	missing = { { name = "Battle Shout", spell = 6673 } }
	ns.Refresh()
	ok(SereneAuraGhosts:IsShown(), "one missing")
	wow.fight(true)
	no(SereneAuraGhosts:IsShown(), "in a fight")
	clean()
end)

-- The game's frames ----------------------------------------------------------------------------------------------------

test("the game's buff container is silenced, not hidden, and stays so; a frame without one is put away", function()
	wow.login({})
	local inner = BuffFrame.AuraContainer
	eq(inner:GetAlpha(), 0, "unseen")
	eq(inner:GetScale(), 0.01, "too small to catch the mouse")
	ok(BuffFrame:IsVisible(), "the buff frame itself still shown (Edit Mode places it)")
	inner:SetAlpha(1)
	inner:SetScale(1)
	eq(inner:GetAlpha(), 0, "the game's alpha undone")
	eq(inner:GetScale(), 0.01, "and its scale")
	no(DebuffFrame:IsVisible(), "no container inside: the frame itself put away")
	clean()
end)

test("with the game's buff frame chosen, Serene makes none of its own", function()
	wow.login({ auraFrame = "game" })
	eq(rawget(_G, "SereneAuras"), nil)
	eq(BuffFrame.AuraContainer:GetAlpha(), 1, "the game's left alone")
	clean()
end)
