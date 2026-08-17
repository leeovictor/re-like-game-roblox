--!strict

local InventoryStore = require(script.Parent.Parent.InventoryStore)

type InventoryState = {
	version: number,
	items: { ItemInstance },
	equipped: { [string]: string },
}
type ItemInstance = {
	uid: string,
	itemId: string,
	quantity: number?,
	attributes: { [string]: string | number | boolean }?,
}

export type Persistence = {
	load: (self: Persistence, userId: number) -> InventoryState,
	save: (self: Persistence, userId: number, state: InventoryState) -> (),
}

local MemoryPersistence = {}

local function copyState(state: InventoryState): InventoryState
	return InventoryStore.copyState(state)
end

function MemoryPersistence.new(): Persistence
	local states: { [number]: InventoryState } = {}
	local persistence: Persistence

	persistence = {
		load = function(_: Persistence, userId: number): InventoryState
			local state = states[userId]
			if state == nil then
				state = InventoryStore.defaultInventory()
				states[userId] = state
			end
			return copyState(state)
		end,
		save = function(_: Persistence, userId: number, state: InventoryState): ()
			states[userId] = copyState(state)
		end,
	}

	return persistence
end

return MemoryPersistence
