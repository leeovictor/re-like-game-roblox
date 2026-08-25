--!strict

local Players = game:GetService("Players")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local InventoryController = require(client.inventory.InventoryController)

return function()
	describe("InventoryController", function()
		beforeEach(function()
			InventoryController.stop()
		end)

		afterEach(function()
			InventoryController.stop()
		end)

		it("starts with an empty local inventory", function()
			InventoryController.start()
			local state = assert(InventoryController.getState())
			expect(state.version).to.equal(2)
			expect(#state.items).to.equal(0)
		end)

		it("does not reset an active session on repeated start", function()
			InventoryController.start()
			expect(InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })).to.equal(true)
			InventoryController.start()
			expect(#assert(InventoryController.getState()).items).to.equal(1)
		end)

		it("clears the state on stop and starts a fresh session", function()
			InventoryController.start()
			InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })
			InventoryController.stop()
			expect(InventoryController.getState()).to.equal(nil)
			InventoryController.start()
			expect(#assert(InventoryController.getState()).items).to.equal(0)
		end)

		it("adds a valid item and publishes the new snapshot", function()
			local received: any = nil
			local connection = InventoryController.changed:Connect(function(snapshot)
				received = snapshot
			end)
			InventoryController.start()

			expect(InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })).to.equal(true)
			expect(received.items[1].uid).to.equal("local-1")
			connection:Disconnect()
		end)

		it("preserves state and signal count for an invalid item", function()
			local changes = 0
			local connection = InventoryController.changed:Connect(function()
				changes += 1
			end)
			InventoryController.start()

			expect(InventoryController.addInstance({ uid = "invalid-1", itemId = "unknown" })).to.equal(false)
			expect(#assert(InventoryController.getState()).items).to.equal(0)
			expect(changes).to.equal(0)
			connection:Disconnect()
		end)

		it("rejects addInstance before start without creating state", function()
			expect(InventoryController.addInstance({ uid = "local-1", itemId = "access_card" })).to.equal(false)
			expect(InventoryController.getState()).to.equal(nil)
		end)
	end)
end
