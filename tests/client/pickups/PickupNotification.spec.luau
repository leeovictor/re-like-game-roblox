--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupNotificationController = require(client.pickups.PickupNotificationController)

return function()
	describe("PickupNotificationController", function()
		type SignalConnection = {
			Disconnect: (self: SignalConnection) -> (),
		}
		type Source = {
			Connect: (self: Source, callback: (itemId: string) -> ()) -> SignalConnection,
		}
		local signalConnections: { SignalConnection } = {}
		local callback: ((string) -> ())? = nil
		local disconnected = false
		local source: Source

		beforeEach(function()
			signalConnections = {}
			callback = nil
			disconnected = false
			source = {
				Connect = function(_self: Source, nextCallback: (itemId: string) -> ())
					callback = nextCallback
					return {
						Disconnect = function()
							disconnected = true
						end,
					}
				end,
			}
		end)

		afterEach(function()
			PickupNotificationController.stop()
			for _, connection in signalConnections do
				connection:Disconnect()
			end
			signalConnections = {}
		end)

		it("delivers changed notifications across an idempotent lifecycle", function()
			local receivedItemId: string? = nil
			local firstConnection = PickupNotificationController.changed:Connect(function(itemId: string)
				receivedItemId = itemId
			end) :: SignalConnection
			table.insert(signalConnections, firstConnection)

			PickupNotificationController.start({ source = source })
			local notify = assert(callback, "source callback")
			notify("medkit")

			expect(receivedItemId).to.equal("medkit")
			firstConnection:Disconnect()

			PickupNotificationController.stop()
			PickupNotificationController.start({ source = source })
			PickupNotificationController.start({ source = source })

			local restartedItemId: string? = nil
			local restartedConnection = PickupNotificationController.changed:Connect(function(itemId: string)
				restartedItemId = itemId
			end) :: SignalConnection
			table.insert(signalConnections, restartedConnection)

			local notifyRestarted = assert(callback, "source callback")
			notifyRestarted("access_card")

			expect(restartedItemId).to.equal("access_card")
			restartedConnection:Disconnect()

			PickupNotificationController.stop()
			PickupNotificationController.stop()
			expect(disconnected).to.equal(true)
		end)
	end)
end
