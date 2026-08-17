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

return {}
