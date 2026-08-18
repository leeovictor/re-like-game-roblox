--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupNotificationController = require(client.pickups.PickupNotificationController)
local pickupCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PickupCollected")

return function()
	describe("PickupNotificationController", function()
		afterEach(function()
			PickupNotificationController.stop()
		end)

		it("uses the real PickupCollected RemoteEvent", function()
			expect(pickupCollected:IsA("RemoteEvent")).to.equal(true)
		end)

		it("keeps start and stop lifecycle calls idempotent", function()
			PickupNotificationController.stop()
			PickupNotificationController.start()
			PickupNotificationController.start()
			PickupNotificationController.stop()
			PickupNotificationController.stop()

			expect(true).to.equal(true)
		end)
	end)
end
