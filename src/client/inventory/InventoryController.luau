--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local items = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

type InventoryState = items.InventoryState
type UseRequest = items.UseRequest
type UseResult = items.UseResult
type Connection = RBXScriptConnection
type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, snapshot: InventoryState?) -> (),
	Connect: (self: ChangedSignal, callback: (snapshot: InventoryState?) -> ()) -> SignalConnection,
}

local inventoryChanged = remotes.InventoryChanged :: RemoteEvent
local getInventory = remotes.GetInventory :: RemoteFunction
local useItem = remotes.UseItem :: RemoteFunction

local changed = (Signal.new() :: any) :: ChangedSignal

export type InventoryController = {
	start: () -> (),
	stop: () -> (),
	getState: () -> InventoryState?,
	use: (request: UseRequest) -> UseResult,
	changed: typeof(changed),
}
local state: InventoryState? = nil
local connection: Connection? = nil
local started = false
local sessionGeneration = 0

local function applySnapshot(snapshot: InventoryState?, generation: number): ()
	if not started or generation ~= sessionGeneration then
		return
	end
	state = snapshot
	changed:Fire(snapshot)
end

local controller = {
	changed = changed,
} :: InventoryController

function controller.start(): ()
	if started then
		return
	end
	sessionGeneration += 1
	local generation = sessionGeneration
	started = true

	connection = inventoryChanged.OnClientEvent:Connect(function(snapshot: InventoryState)
		applySnapshot(snapshot, generation)
	end)

	local snapshot = getInventory:InvokeServer() :: InventoryState?
	applySnapshot(snapshot, generation)
end

function controller.stop(): ()
	if not started then
		return
	end
	started = false
	sessionGeneration += 1
	if connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
end

function controller.getState(): InventoryState?
	return state
end

function controller.use(request: UseRequest): UseResult
	return useItem:InvokeServer(request) :: UseResult
end

return controller
