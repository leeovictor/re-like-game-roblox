--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameplayEvents = require(script.Parent.GameplayEvents)
local remotes = require(ReplicatedStorage.Shared.remotes)

export type Source = {
	Connect: (
		self: Source,
		callback: (itemId: string) -> ()
	) -> GameplayEvents.SignalConnection,
}

export type Dependencies = {
	source: Source,
	emit: (event: GameplayEvents.GameplayEvent) -> (),
}

export type PickupEventBridge = {
	start: () -> (),
	stop: () -> (),
}

local defaultSource = (remotes.PickupCollected :: RemoteEvent).OnClientEvent :: any

local function createBridge(dependencies: Dependencies): PickupEventBridge
	local connection: GameplayEvents.SignalConnection? = nil

	local bridge = {} :: PickupEventBridge

	function bridge.start(): ()
		if connection ~= nil then
			return
		end

		connection = dependencies.source:Connect(function(itemId: string)
			if type(itemId) ~= "string" or itemId == "" then
				return
			end
			dependencies.emit({ name = "item_collected", itemId = itemId })
		end)
	end

	function bridge.stop(): ()
		if connection == nil then
			return
		end

		connection:Disconnect()
		connection = nil
	end

	return bridge
end

local defaultDependencies: Dependencies = {
	source = defaultSource,
	emit = GameplayEvents.emit,
}
local defaultBridge = createBridge(defaultDependencies)

return {
	new = createBridge,
	start = function()
		defaultBridge.start()
	end,
	stop = function()
		defaultBridge.stop()
	end,
}
