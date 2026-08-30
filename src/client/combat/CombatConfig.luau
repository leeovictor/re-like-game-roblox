--!strict

local SoundEnum = require(game:GetService("ReplicatedStorage").Shared.audio.SoundEnum)

export type WeaponConfig = {
	itemId: string,
	ammoItemId: string,
	shotSound: SoundEnum.Sound,
	reloadSound: SoundEnum.Sound,
	magazineSize: number,
	damage: number,
	shotCooldown: number,
	acquisitionRadius: number,
	shotRange: number,
	reloadDuration: number,
	aimTurnSpeed: number,
}

local CombatConfig: { [string]: WeaponConfig } = {
	handgun = {
		itemId = "handgun",
		ammoItemId = "handgun_ammo",
		shotSound = SoundEnum.HandgunShot,
		reloadSound = SoundEnum.HandgunReload,
		magazineSize = 6,
		damage = 25,
		shotCooldown = 0.8,
		acquisitionRadius = 40,
		shotRange = 80,
		reloadDuration = 1.5,
		aimTurnSpeed = 2.5
	},
}

return CombatConfig
