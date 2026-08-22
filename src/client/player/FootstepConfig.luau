--!strict

export type Range = {
	min: number,
	max: number,
}

export type Config = {
	soundIds: { string },
	surfaceSounds: { [Enum.Material]: { string } },
	playbackSpeed: Range,
	volume: Range,
	referenceSpeed: number,
	referenceStepInterval: number,
	minInterval: number,
	maxInterval: number,
	movementThreshold: number,
	rollOffMode: Enum.RollOffMode,
	rollOffMinDistance: number,
	rollOffMaxDistance: number,
}

local config: Config = {
	-- Fill this list with the desired rbxassetid:// sound IDs.
	soundIds = {
		"rbxassetid://140165597842270",
		"rbxassetid://98375658066754",
		"rbxassetid://119796817067297",
		"rbxassetid://140165597842270",
		"rbxassetid://138750508569819",
		"rbxassetid://111154292786687",
		"rbxassetid://138750508569819",
		"rbxassetid://111154292786687",
		"rbxassetid://129873522422425",
		"rbxassetid://134689890007261",
		"rbxassetid://121613327190310",
		"rbxassetid://78929988454004",
		"rbxassetid://119989047815622",
		"rbxassetid://108386584391768",
		"rbxassetid://103963258527392"
	},
	surfaceSounds = {
		[Enum.Material.Metal] = {
			"rbxassetid://98688524036111",
			"rbxassetid://138898236956764",
			"rbxassetid://98915841855850",
			"rbxassetid://121770947554725",
			"rbxassetid://127841183521474"
		}
	},
	playbackSpeed = {
		min = 0.95,
		max = 1.05,
	},
	volume = {
		min = 0.1,
		max = 0.15,
	},
	referenceSpeed = 5,
	referenceStepInterval = 0.35,
	minInterval = 0.28,
	maxInterval = 0.7,
	movementThreshold = 0.5,
	rollOffMode = Enum.RollOffMode.Linear,
	rollOffMinDistance = 2.5,
	rollOffMaxDistance = 50,
}

return config
