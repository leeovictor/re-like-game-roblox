--!strict

export type Sound = "HandgunShot" | "HandgunReload"

local SoundEnum: {
	HandgunShot: Sound,
	HandgunReload: Sound,
} = {
	HandgunShot = "HandgunShot",
	HandgunReload = "HandgunReload",
}

return table.freeze(SoundEnum)
