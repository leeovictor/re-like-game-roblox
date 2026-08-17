--!strict

local InventoryStore = require(script.Parent.Parent.InventoryStore)
local inventoryTypes = require(script.Parent.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.items)

type InventoryState = inventoryTypes.InventoryState

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
