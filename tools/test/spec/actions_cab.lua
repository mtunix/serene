-- Actions.lua with the newer C_ActionBar calls (this client in 12.x: cooldown numbers secret in a fight, isActive
-- and isOnGCD not). C_ActionBar must exist when Actions.lua loads: it is read once, at the top of the file.

local cab = {} -- what each call answers: set by the tests
C_ActionBar = {
	IsUsableAction = function(slot) return cab.usable, cab.noMana end,
	IsActionInRange = function(slot) return cab.range end,
	IsCurrentAction = function(slot) return cab.current end,
	IsAutoRepeatAction = function(slot) return cab.repeating end,
	GetActionCooldown = function(slot) return cab.cooldown end,
}
local ns = wow.load({ "Core.lua", "Actions.lua" })
local A = ns.Actions

local function Duration(zero, secret)
	return { IsZero = function() return zero end, HasSecretValues = function() return secret or false end }
end

test("the newer calls are used before the old ones", function()
	IsUsableAction = function() return false, true end
	cab.usable, cab.noMana = true, false
	eq({ A.Usable(1) }, { true, false })
	cab.range = false
	eq(A.InRange(1), false)
	cab.current = true
	eq(A.Current(1), true)
end)

test("OnCooldown by isActive / isOnGCD", function()
	cab.cooldown = { isActive = false }
	eq({ A.OnCooldown(1) }, { false, "isActive" })
	cab.cooldown = { isActive = true, isOnGCD = true, duration = 1.5 }
	eq({ A.OnCooldown(1) }, { false, "isOnGCD" }, "the global cooldown is not a cooldown")
	cab.cooldown = { isActive = true, isOnGCD = false, duration = 8 }
	eq({ A.OnCooldown(1) }, { true, "duration (secret-free)" })
	cab.cooldown = { isActive = true, duration = 1.2 }
	eq({ A.OnCooldown(1) }, { false, "duration (secret-free)" }, "no word on the GCD, short: the GCD")
end)

test("OnCooldown with a secret length: counted once it outlasts a global cooldown (1.6 s)", function()
	cab.cooldown = { isActive = true, duration = wow.secret(30) }
	eq({ A.OnCooldown(4) }, { false, "hold" }, "just seen: could still be the GCD")
	wow.now = wow.now + 1
	eq({ A.OnCooldown(4) }, { false, "hold" })
	wow.now = wow.now + 0.7
	eq({ A.OnCooldown(4) }, { true, "hold" }, "1.7 s in: a cooldown of its own")
	cab.cooldown = { isActive = false }
	eq({ A.OnCooldown(4) }, { false, "isActive" })
	cab.cooldown = { isActive = true, duration = wow.secret(30) }
	eq({ A.OnCooldown(4) }, { false, "hold" }, "a new cooldown starts the hold over")
end)

test("OnCooldown: each slot holds its own time", function()
	cab.cooldown = { isActive = true, duration = wow.secret(30) }
	A.OnCooldown(1)
	wow.now = wow.now + 2
	eq(A.OnCooldown(1), true)
	eq(A.OnCooldown(2), false, "slot 2 only now seen")
end)

test("OnCooldown: a secret isActive falls back to the old call, else unknown", function()
	cab.cooldown = { isActive = wow.secret(true), isOnGCD = wow.secret(false) }
	GetActionCooldown = function() return 0, 0, 1 end
	eq({ A.OnCooldown(1) }, { false, "old call" })
	GetActionCooldown = nil
	eq({ A.OnCooldown(1) }, { nil, "unknown" })
end)

test("OnCooldown by the duration object (the global cooldown left out)", function()
	C_ActionBar.GetActionCooldownDuration = function(slot, noGcd)
		eq(noGcd, true, "asked without the global cooldown")
		return cab.duration
	end
	cab.duration = Duration(true)
	eq({ A.OnCooldown(1) }, { false, "duration" })
	cab.duration = Duration(false)
	eq({ A.OnCooldown(1) }, { true, "duration" })
	eq(A.Cooldown(1), cab.duration, "handed on as it is")
	cab.duration = Duration(false, true)
	cab.cooldown = { isActive = false }
	eq({ A.OnCooldown(1) }, { false, "isActive" }, "a duration with secrets is never read")
	cab.duration = Duration(wow.secret(true))
	eq({ A.OnCooldown(1) }, { false, "isActive" }, "a secret IsZero is not read either")
end)
