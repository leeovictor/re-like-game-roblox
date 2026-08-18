--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupNotificationController = require(client.pickups.PickupNotificationController)
local pickupCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PickupCollected")

return function()
	describe("PickupNotificationController", function()
		type SignalConnection = {
			Disconnect: (self: SignalConnection) -> (),
		}
		local signalConnections: { SignalConnection } = {}

		beforeEach(function()
			signalConnections = {}
		end)

		afterEach(function()
			PickupNotificationController.stop()
			for _, connection in signalConnections do
				connection:Disconnect()
			end
			signalConnections = {}
		end)

		it("uses the real PickupCollected RemoteEvent", function()
			expect(pickupCollected:IsA("RemoteEvent")).to.equal(true)
		end)

		it("delivers changed notifications across an idempotent lifecycle", function()
			local receivedItemId: string? = nil
			local firstConnection = PickupNotificationController.changed:Connect(function(itemId: string)
				receivedItemId = itemId
			end) :: SignalConnection
			table.insert(signalConnections, firstConnection)

			PickupNotificationController.changed:Fire("medkit")

			expect(receivedItemId).to.equal("medkit")
			firstConnection:Disconnect()

			PickupNotificationController.stop()
			PickupNotificationController.start()
			PickupNotificationController.start()

			local restartedItemId: string? = nil
			local restartedConnection = PickupNotificationController.changed:Connect(function(itemId: string)
				restartedItemId = itemId
			end) :: SignalConnection
			table.insert(signalConnections, restartedConnection)

			PickupNotificationController.changed:Fire("iron_key")

			expect(restartedItemId).to.equal("iron_key")
			restartedConnection:Disconnect()

			PickupNotificationController.stop()
			PickupNotificationController.stop()
		end)
	end)
end
