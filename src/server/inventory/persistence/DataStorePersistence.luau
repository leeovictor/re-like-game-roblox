--!strict

local DataStoreService = game:GetService("DataStoreService")
local InventoryStore = require(script.Parent.Parent.InventoryStore)

type InventoryState = {
	version: number,
	items: { string },
	equipped: { [string]: string }?,
}

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
			if type(serialized) ~= "string" then
				return nil
			end
			return InventoryStore.deserialize(serialized)
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
