--!strict

export type ItemId = string
export type ItemAttribute = string | number | boolean
export type ItemAttributes = { [string]: ItemAttribute }

export type ItemDefinition = {
	id: ItemId,
	name: string,
	category: string,
	stackable: boolean,
	capabilities: { string },
}

local items: { [ItemId]: ItemDefinition } = {
	access_card = {
		id = "access_card",
		name = "Access Card",
		category = "key",
		stackable = false,
		capabilities = { "unlock" },
	},
	pliers = {
		id = "pliers",
		name = "Pliers",
		category = "tool",
		stackable = false,
		capabilities = { "unlock" },
	},
	handgun = {
		id = "handgun",
		name = "Handgun",
		category = "weapon",
		stackable = false,
		capabilities = { "equip", "fire", "reload" },
	},
	handgun_ammo = {
		id = "handgun_ammo",
		name = "Handgun Ammo",
		category = "ammunition",
		stackable = true,
		capabilities = { "reload-ammo" },
	},
	medkit = {
		id = "medkit",
		name = "Medkit",
		category = "consumable",
		stackable = false,
		capabilities = { "consume", "heal" },
	}
}

return items
