--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = require(ReplicatedStorage.Shared.remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

type Connection = RBXScriptConnection
type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, itemId: string) -> (),
	Connect: (self: ChangedSignal, callback: (itemId: string) -> ()) -> SignalConnection,
}

local pickupCollected = remotes.PickupCollected :: RemoteEvent
local changed = (Signal.new() :: any) :: ChangedSignal
local connection: Connection? = nil
local started = false
local sessionGeneration = 0

export type PickupNotificationController = {
	start: () -> (),
	stop: () -> (),
	changed: typeof(changed),
}

local controller = {
	changed = changed,
} :: PickupNotificationController

function controller.start(): ()
	if started then
		return
	end

	sessionGeneration += 1
	local generation = sessionGeneration
	started = true
	connection = pickupCollected.OnClientEvent:Connect(function(itemId: string)
		if not started or generation ~= sessionGeneration then
			return
		end
		changed:Fire(itemId)
	end)
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

return controller
