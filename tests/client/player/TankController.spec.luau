--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local TankController = require(client.player.TankController)

return function()
	describe("TankController", function()
		afterEach(function()
			TankController.stop()
		end)

		it("binds the four tank actions once", function()
			TankController.start()
			TankController.start()

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			local expectedActions = {
				DungeonTankForward = Enum.KeyCode.W,
				DungeonTankBackward = Enum.KeyCode.S,
				DungeonTankLeft = Enum.KeyCode.A,
				DungeonTankRight = Enum.KeyCode.D,
			}

			for actionName, keyCode in expectedActions do
				local actionInfo = actions[actionName]
				expect(actionInfo).to.be.ok()
				expect(actionInfo.priorityLevel).to.equal(Enum.ContextActionPriority.High.Value)
				expect(actionInfo.inputTypes[1]).to.equal(keyCode)
			end
		end)

		it("unbinds actions when stopped", function()
			TankController.start()
			TankController.stop()

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			expect(actions.DungeonTankForward).to.equal(nil)
			expect(actions.DungeonTankBackward).to.equal(nil)
			expect(actions.DungeonTankLeft).to.equal(nil)
			expect(actions.DungeonTankRight).to.equal(nil)
		end)
	end)
end
