-- The stub's own rules, where a spec could trip over them (tools/test/wow.lua).

wow.load({ "Core.lua" })

test("a frame's part whose key starts with a verb reads as a method; using it says what happened", function()
	local frame = CreateFrame("Frame")
	eq(type(frame.CancelButton), "function", "read as a method")
	raises(function() return frame.CancelButton:GetHeight() end, "a frame's part read as a method")
	eq(frame.Icon, nil, "a key that is no verb: nil")
	frame.CancelButton = CreateFrame("Button", nil, frame)
	eq(frame.CancelButton:GetObjectType(), "Button", "made in the spec: the part")
end)
