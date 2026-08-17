--!strict

local catalog = require(script.Parent.catalog)

export type ItemId = catalog.ItemId
export type ItemAttribute = catalog.ItemAttribute
export type ItemAttributes = catalog.ItemAttributes
export type ItemDefinition = catalog.ItemDefinition

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

return catalog
