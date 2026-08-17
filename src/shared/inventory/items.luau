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

export type ItemInstance = {
	uid: string,
	itemId: ItemId,
	quantity: number?,
	attributes: ItemAttributes?,
}

export type InventoryState = {
	version: number,
	items: { ItemInstance },
	equipped: { [string]: string },
}

export type UseContext = { [string]: ItemAttribute }

export type UseRequest = {
	capability: string,
	context: UseContext,
	itemUid: string?,
}

export type UseResult = {
	success: boolean,
	reason: string?,
	itemUid: string?,
	consumed: boolean?,
	effect: { [string]: ItemAttribute }?,
}

local items: { [ItemId]: ItemDefinition } = {
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
	},
	iron_key = {
		id = "iron_key",
		name = "Iron Key",
		category = "key",
		stackable = false,
		capabilities = { "unlock" },
	},
}

return items
