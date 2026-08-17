--!strict

export type ShotId = string
export type ZoneId = string

export type Shot = {
	cframe: CFrame,
	fieldOfView: number,
}

export type Volume = {
	cframe: CFrame,
	size: Vector3,
}

export type Zone = {
	id: ZoneId,
	volume: Volume,
	shotId: ShotId,
}

export type Config = {
	defaultShotId: ShotId,
	shots: { [ShotId]: Shot },
	zones: { Zone },
}

local CameraConfig: Config = {
	defaultShotId = "Center",

	shots = {
		Entrance = {
			cframe = CFrame.lookAt(Vector3.new(-48, 24, 36), Vector3.new(-40, 0, 0)),
			fieldOfView = 55,
		},
		Center = {
			cframe = CFrame.lookAt(Vector3.new(0, 28, 42), Vector3.new(0, 0, 0)),
			fieldOfView = 55,
		},
		Exit = {
			cframe = CFrame.lookAt(Vector3.new(48, 24, 36), Vector3.new(40, 0, 0)),
			fieldOfView = 60,
		},
		WestChamber = {
			cframe = CFrame.lookAt(Vector3.new(-78, 30, 28), Vector3.new(-80, 0, 0)),
			fieldOfView = 48,
		},
		NorthGallery = {
			cframe = CFrame.lookAt(Vector3.new(0, 22, 92), Vector3.new(0, 0, 60)),
			fieldOfView = 52,
		},
		SouthGallery = {
			cframe = CFrame.lookAt(Vector3.new(-28, 18, -90), Vector3.new(0, 0, -64)),
			fieldOfView = 58,
		},
		UpperGallery = {
			cframe = CFrame.lookAt(Vector3.new(42, 62, 30), Vector3.new(0, 40, 0)),
			fieldOfView = 50,
		},
		EastChamber = {
			cframe = CFrame.lookAt(Vector3.new(106, 20, 18), Vector3.new(80, 0, 0)),
			fieldOfView = 64,
		},
	},

	zones = {
		{
			id = "EntranceZone",
			volume = {
				cframe = CFrame.new(-40, 0, 0),
				size = Vector3.new(40, 40, 80),
			},
			shotId = "Entrance",
		},
		{
			id = "CenterZone",
			volume = {
				cframe = CFrame.new(0, 0, 0),
				size = Vector3.new(40, 40, 80),
			},
			shotId = "Center",
		},
		{
			id = "ExitZone",
			volume = {
				cframe = CFrame.new(40, 0, 0),
				size = Vector3.new(40, 40, 80),
			},
			shotId = "Exit",
		},
		{
			id = "WestChamberZone",
			volume = {
				cframe = CFrame.new(-80, 0, 0),
				size = Vector3.new(40, 48, 56),
			},
			shotId = "WestChamber",
		},
		{
			id = "NorthGalleryZone",
			volume = {
				cframe = CFrame.new(0, 0, 60),
				size = Vector3.new(40, 40, 40),
			},
			shotId = "NorthGallery",
		},
		{
			id = "SouthGalleryZone",
			volume = {
				cframe = CFrame.new(0, 0, -64),
				size = Vector3.new(40, 36, 48),
			},
			shotId = "SouthGallery",
		},
		{
			id = "UpperGalleryZone",
			volume = {
				cframe = CFrame.new(0, 40, 0),
				size = Vector3.new(40, 40, 80),
			},
			shotId = "UpperGallery",
		},
		{
			id = "EastChamberZone",
			volume = {
				cframe = CFrame.new(80, 0, 0),
				size = Vector3.new(40, 30, 50),
			},
			shotId = "EastChamber",
		},
	},
}

return CameraConfig
