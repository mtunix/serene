-- Actions.lua: the action buttons and what is on their slots, read the old way (no C_ActionBar on this client).
-- (actions_cab.lua: the same with the newer C_ActionBar calls.)

local ns = wow.load({ "Core.lua", "Actions.lua" })
local A = ns.Actions

local function Set(slot, kind, id, sub, text)
	wow.actions = wow.actions or {}
	wow.actions[slot] = { kind = kind, id = id, subType = sub, text = text }
end

-- The buttons ----------------------------------------------------------------------------------------------------------

test("before login the buttons are looked up each time; after, the list is kept", function()
	eq(#A.Buttons(), 60, "five bars of twelve in the stub")
	eq(#A.Buttons(true), 80, "with the pet's and the stances'")
	CreateFrame("CheckButton", "MultiBar5Button1", UIParent)
	eq(#A.Buttons(), 61, "a bar made late, before login: found")
	wow.loggedIn = true
	eq(#A.Buttons(), 61)
	CreateFrame("CheckButton", "MultiBar5Button2", UIParent)
	eq(#A.Buttons(), 61, "after login the list is kept")
	eq(#A.Buttons(true), 81)
end)

test("a name that isn't a button (a plain table, a string) is not taken for one", function()
	_G.MultiBar6Button1 = { action = 3 }
	_G.MultiBar6Button2 = "ActionButton"
	wow.loggedIn = true
	eq(#A.Buttons(), 60)
end)

test("each button's bar", function()
	wow.loggedIn = true
	local cases = {
		{ ActionButton1, "main" }, { ActionButton12, "main" }, { MultiBarBottomLeftButton3, "bar2" },
		{ MultiBarBottomRightButton1, "bar3" }, { MultiBarRightButton1, "bar4" }, { MultiBarLeftButton7, "bar5" },
		{ PetActionButton1, "pet" }, { StanceButton4, "stance" }, { UIParent, nil },
	}
	for _, c in ipairs(cases) do eq(A.BarOf(c[1]), c[2], c[1]:GetName()) end
end)

test("a bar's buttons, in order; a button on no action bar is its own bar", function()
	wow.loggedIn = true
	local bar = A.BarButtons(ActionButton5)
	eq(#bar, 12)
	eq(bar[1], ActionButton1)
	eq(bar[12], ActionButton12)
	eq(A.BarButtons(MultiBarRightButton2)[1], MultiBarRightButton1)
	eq(A.BarButtons(PetActionButton1), { PetActionButton1 }, "the pet's buttons hold no slots")
	local other = CreateFrame("Button")
	eq(A.BarButtons(other), { other })
end)

test("Each calls back with the button and its bar, and goes on past an error", function()
	wow.loggedIn = true
	local seen, bars = 0, {}
	A.Each(function(button, bar)
		seen = seen + 1
		bars[bar] = true
		if button == ActionButton1 then error("one bad button") end
	end)
	eq(seen, 60)
	eq(bars, { main = true, bar2 = true, bar3 = true, bar4 = true, bar5 = true })
end)

test("a button's part by its key, or by its old global name", function()
	eq(A.Region(ActionButton1, "Count"), ActionButton1.Count)
	local b = CreateFrame("CheckButton", "OldStyleButton", UIParent)
	local icon = b:CreateTexture("OldStyleButtonIcon")
	eq(A.Region(b, "Icon"), icon)
	eq(A.Region(b, "Nothing"), nil)
end)

-- The slot a button shows -------------------------------------------------------------------------------------------

test("the slot: the button's own number", function()
	wow.loggedIn = true
	eq(A.Slot(ActionButton1), 1)
	eq(A.Slot(MultiBarBottomLeftButton1), 61)
	eq(A.Slot(MultiBarRightButton12), 36)
	eq(A.Slot(PetActionButton1), nil, "the pet's buttons have no action slot")
	eq(A.Slot(nil), nil)
	eq(A.Slot("ActionButton1"), nil)
end)

test("the slot when the button keeps no number: the ways the button knows, in order", function()
	wow.loggedIn = true
	A.Buttons() -- (the fallbacks are only for buttons known to hold slots: found by Buttons first, as callers do)
	local b = ActionButton2
	b.action = nil
	b:SetAttribute("action", 14)
	eq(A.Slot(b), 14, "its attribute")
	function b:CalculateAction() return 26 end
	eq(A.Slot(b), 26, "CalculateAction before the attribute")
	function b:GetPagedID() return 38 end
	eq(A.Slot(b), 38, "GetPagedID first")
	b.action = 0
	eq(A.Slot(b), nil, "a number kept on the button is its word, even 0 (no slot)")
end)

test("a secret slot number is never used", function()
	wow.loggedIn = true
	local b = ActionButton3
	b.action = wow.secret(3)
	b:SetAttribute("action", nil)
	eq(A.Slot(b), nil)
	b:SetAttribute("action", wow.secret(3))
	eq(A.Slot(b), nil)
end)

-- What a slot holds (the words BarUse.lua saves: their form must never change) ------------------------------------

test("What: the saved words for each kind of action", function()
	Set(1, "spell", 133)
	Set(2, "item", 159)
	Set(3, "macro", 5, nil, "Heal Me")
	Set(4, "macro", 6)
	Set(5, "companion", 7, "MOUNT")
	Set(6, "equipmentset", "PvP")
	eq(A.What(1), "spell:133")
	eq(A.What(2), "item:159")
	eq(A.What(3), "macro:Heal Me", "a macro by its name: its number moves")
	eq(A.What(4), "macro:6", "a macro with no name read: its number")
	eq(A.What(5), "companion:7")
	eq(A.What(6), "equipmentset:PvP")
	eq(A.What(7), nil, "empty")
end)

test("What, SpellOn and Cast give nil for what can't be read", function()
	local real = GetActionInfo
	GetActionInfo = function() return wow.secret("spell"), wow.secret(133) end
	eq(A.What(1), nil)
	eq(A.SpellOn(1), nil)
	eq(A.Cast(1), nil)
	GetActionInfo = function() error("no such call now") end
	eq(A.What(1), nil)
	GetActionInfo = real
end)

test("SpellOn: only a spell put there directly", function()
	Set(1, "spell", 133)
	Set(2, "macro", 133, "spell", "Fire")
	Set(3, "item", 159)
	eq(A.SpellOn(1), 133)
	eq(A.SpellOn(2), nil)
	eq(A.SpellOn(3), nil)
	eq(A.SpellOn(4), nil)
end)

test("Cast: spells, items, and what a macro shows (newer and older game)", function()
	Set(1, "spell", 133)
	Set(2, "item", 159)
	Set(3, "macro", 6673, "spell", "Shout")
	Set(4, "macro", 159, "item", "Drink")
	Set(5, "macro", 7, nil, "Old item macro")
	Set(6, "macro", 8, nil, "Old spell macro")
	Set(7, "macro", 9, nil, "Says hello")
	GetMacroItem = function(id) if id == 7 then return "Linen Bandage", "|cffffffff|Hitem:1251::|h[Linen Bandage]|h|r" end end
	GetMacroSpell = function(id) if id == 8 then return 2050 end end
	local function cast(slot) return { A.Cast(slot) } end
	eq(cast(1), { "spell", 133 })
	eq(cast(2), { "item", 159 })
	eq(cast(3), { "spell", 6673 })
	eq(cast(4), { "item", 159 })
	eq(cast(5), { "item", 1251 })
	eq(cast(6), { "spell", 2050 })
	eq(cast(7), {}, "a macro casting nothing known")
	eq(cast(8), {}, "empty")
end)

-- Its state now: unknown is never a fact -----------------------------------------------------------------------------

test("Usable: usable, and short of mana", function()
	IsUsableAction = function(slot) if slot == 1 then return true, false elseif slot == 2 then return false, true end return false, false end
	eq({ A.Usable(1) }, { true, false })
	eq({ A.Usable(2) }, { false, true })
	eq({ A.Usable(3) }, { false, false })
end)

test("Usable: secret or failing answers are unknown (nil), never false", function()
	IsUsableAction = function() return wow.secret(false), wow.secret(true) end
	eq({ A.Usable(1) }, {})
	IsUsableAction = function() error("gone") end
	eq(A.Usable(1), nil)
	IsUsableAction = nil
	eq(A.Usable(1), nil)
end)

test("InRange: 1/true in range, 0/false out, nil no range; secret is unknown", function()
	local answer
	IsActionInRange = function() return answer end
	for _, c in ipairs({ { 1, true }, { true, true }, { 0, false }, { false, false } }) do
		answer = c[1]
		eq(A.InRange(1), c[2], tostring(c[1]))
	end
	answer = nil
	eq(A.InRange(1), nil)
	answer = wow.secret(0)
	eq(A.InRange(1), nil, "a secret 'out of range' is not taken as out")
	IsActionInRange = nil
	eq(A.InRange(1), nil)
end)

test("Current: in use, or repeating (auto shot); a secret answer is not in use", function()
	IsCurrentAction = function(slot) return slot == 1 end
	IsAutoRepeatAction = function(slot) return slot == 2 end
	eq(A.Current(1), true)
	eq(A.Current(2), true)
	eq(A.Current(3), false)
	IsCurrentAction = function() return wow.secret(true) end
	IsAutoRepeatAction = nil
	eq(A.Current(1), false)
end)

test("OnCooldown, the old call: longer than the global cooldown counts", function()
	local length
	GetActionCooldown = function() return wow.now, length, 1 end
	for _, c in ipairs({ { 0, false }, { 1, false }, { 1.5, false }, { 1.6, false }, { 1.7, true }, { 30, true } }) do
		length = c[1]
		eq({ A.OnCooldown(1) }, { c[2], "old call" }, "a cooldown of " .. c[1] .. " s")
	end
end)

test("OnCooldown: a secret length can't be told (nil, never false or true)", function()
	GetActionCooldown = function() return wow.secret(wow.now), wow.secret(30), 1 end
	eq({ A.OnCooldown(1) }, { nil, "unknown" })
	GetActionCooldown = nil
	eq({ A.OnCooldown(1) }, { nil, "unknown" })
end)

test("Cooldown (a duration object) needs C_ActionBar: nil without it", function()
	eq(A.Cooldown(1), nil)
end)

test("in a fight with secrets nothing about a slot is made up", function()
	wow.actions = { [1] = { kind = "spell", id = 133 } }
	wow.secretFight(true)
	eq(A.Usable(1), nil)
	eq(A.InRange(1), nil)
	eq(A.OnCooldown(1), nil)
	eq(A.What(1), "spell:133", "what is on a slot stays readable")
	wow.secretFight(false)
end)

-- Procs ---------------------------------------------------------------------------------------------------------------

test("Glows: each glow key the button has, shown or not", function()
	local b = CreateFrame("CheckButton", "GlowButton", UIParent)
	b.overlay = CreateFrame("Frame", nil, b)
	b.SpellActivationAlert = CreateFrame("Frame", nil, b)
	b.ProcGlow = "not a frame"
	local keys = {}
	A.Glows(b, function(_, key) keys[#keys + 1] = key end)
	eq(keys, { "SpellActivationAlert", "overlay" })
end)

test("Proc: a glow shown, or the game's alert manager says so", function()
	local b = CreateFrame("CheckButton", "ProcButton", UIParent)
	eq(A.Proc(b), false)
	b.SpellActivationAlert = CreateFrame("Frame", nil, b)
	b.SpellActivationAlert:Hide()
	eq(A.Proc(b), false, "a hidden glow is no proc")
	b.SpellActivationAlert:Show()
	b.SpellActivationAlert:SetAlpha(0)
	eq(A.Proc(b), true, "shown at no opacity (Glass and Round put it out of sight): still a proc")
	b.SpellActivationAlert:Hide()
	ActionButtonSpellAlertManager = { HasAlert = function(_, button) return button == b end }
	eq(A.Proc(b), true)
	ActionButtonSpellAlertManager = { HasAlert = function() return wow.secret(true) end }
	eq(A.Proc(b), false, "a secret answer is not taken as a proc")
end)
