--!strict

local theme = {
	panel = Color3.fromRGB(20, 22, 30),
	text = Color3.fromRGB(241, 237, 255),
	textMuted = Color3.fromRGB(173, 179, 198),
	surface = Color3.fromRGB(39, 42, 56),
	surfaceHover = Color3.fromRGB(52, 55, 70),
	surfaceActive = Color3.fromRGB(78, 65, 111),
	stroke = Color3.fromRGB(78, 82, 105),
	accent = Color3.fromRGB(107, 92, 168),
	accentStrong = Color3.fromRGB(132, 104, 205),
	accentBright = Color3.fromRGB(175, 142, 255),
	success = Color3.fromRGB(191, 223, 161),
	successMuted = Color3.fromRGB(173, 196, 162),
	slotEmpty = Color3.fromRGB(31, 34, 45),
	slotHighlight = Color3.fromRGB(57, 52, 78),
	equipped = Color3.fromRGB(107, 78, 168),
	equippedHover = Color3.fromRGB(142, 103, 209),
	overlay = Color3.fromRGB(8, 9, 14),
	white = Color3.fromRGB(255, 255, 255),
	objectiveText = Color3.fromRGB(225, 222, 239),
}

export type Theme = typeof(theme)

return theme
