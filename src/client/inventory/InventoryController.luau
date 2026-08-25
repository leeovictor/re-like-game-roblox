--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local items = require(ReplicatedStorage.Shared.inventory.items)
local InventoryStore = require(ReplicatedStorage.Shared.inventory.InventoryStore)
local Signal = require(ReplicatedStorage.Packages.Signal)

type InventoryState = items.InventoryState
type SignalConnection = {
	Disconnect: (self: SignalConnection) -> ()
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, snapshot: InventoryState?) -> (),
	Connect: (self: ChangedSignal, callback: (snapshot: InventoryState?) -> ()) -> SignalConnection,
}

local changed = (Signal.new() :: any) :: ChangedSignal

export type InventoryController = {
	start: () -> (),
	stop: () -> (),
	getState: () -> InventoryState?,
	addInstance: (instance: items.ItemInstance) -> boolean,
	changed: typeof(changed),
}
local state: InventoryState? = nil
local started = false

local controller = {
	changed = changed,
} :: InventoryController

function controller.start(): ()
	if started then
		return
	end
	started = true
	state = InventoryStore.defaultInventory()
end

function controller.stop(): ()
	if not started then
		return
	end
	started = false
	state = nil
end

function controller.getState(): InventoryState?
	return state
end

function controller.addInstance(instance: items.ItemInstance): boolean
	if not started or state == nil then
		return false
	end
	local updated = InventoryStore.addInstance(state, instance)
	if updated == nil then
		return false
	end
	state = updated
	changed:Fire(updated)
	return true
end

return controller
