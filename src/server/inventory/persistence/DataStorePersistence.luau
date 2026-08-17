--!strict

local DataStoreService = game:GetService("DataStoreService")
local InventoryStore = require(script.Parent.Parent.InventoryStore)
local inventoryTypes = require(script.Parent.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.items)

type InventoryState = inventoryTypes.InventoryState

export type Persistence = {
	load: (self: Persistence, userId: number) -> InventoryState?,
	save: (self: Persistence, userId: number, state: InventoryState) -> (),
}

local DataStorePersistence = {}

function DataStorePersistence.new(): Persistence
	local dataStore = DataStoreService:GetDataStore("PlayerInventory")
	local persistence: Persistence

	persistence = {
		load = function(_: Persistence, userId: number): InventoryState?
			local serialized = dataStore:GetAsync(tostring(userId))
			if serialized == nil then
				return nil
			end
			if type(serialized) ~= "string" then
				error("Stored inventory payload is not a string")
			end
			local state = InventoryStore.deserialize(serialized)
			if state == nil then
				error("Stored inventory payload is invalid")
			end
			return state
		end,
		save = function(_: Persistence, userId: number, state: InventoryState): ()
			dataStore:UpdateAsync(tostring(userId), function(_: any): string
				return InventoryStore.serialize(state)
			end)
		end,
	}

	return persistence
end

return DataStorePersistence
