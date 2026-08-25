--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
export type Source = {
	Connect: (self: Source, callback: (itemId: string) -> ()) -> SignalConnection,
}
export type Dependencies = {
	source: Source,
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, itemId: string) -> (),
	Connect: (self: ChangedSignal, callback: (itemId: string) -> ()) -> SignalConnection,
}

local changed = (Signal.new() :: any) :: ChangedSignal
local connection: SignalConnection? = nil
local started = false
local sessionGeneration = 0

export type PickupNotificationController = {
	start: (dependencies: Dependencies) -> (),
	stop: () -> (),
	changed: typeof(changed),
}

local controller = {
	changed = changed,
} :: PickupNotificationController

function controller.start(dependencies: Dependencies): ()
	if started then
		return
	end

	sessionGeneration += 1
	local generation = sessionGeneration
	started = true
	connection = dependencies.source:Connect(function(itemId: string)
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
