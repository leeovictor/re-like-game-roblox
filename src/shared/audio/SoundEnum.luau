--!strict

export type Sound = "HandgunShot" | "HandgunReload" | "LeverSwitch"

local SoundEnum: {
	HandgunShot: Sound,
	HandgunReload: Sound,
	LeverSwitch: Sound,
} = {
	HandgunShot = "HandgunShot",
	HandgunReload = "HandgunReload",
	LeverSwitch = "LeverSwitch",
}

return table.freeze(SoundEnum)
