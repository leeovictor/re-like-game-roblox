--!strict

export type ItemId = string
export type ItemDef = { id: ItemId, name: string, stackable: boolean }
export type InventoryState = { version: number, items: { ItemId } }

local items: { [ItemId]: ItemDef } = {
	torch = { id = "torch", name = "Tocha", stackable = true },
	ration = { id = "ration", name = "Ração", stackable = true },
	crystal = { id = "crystal", name = "Cristal", stackable = false },
}

return items
