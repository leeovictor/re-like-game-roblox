--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local TankController = require(client.player.TankController)

local function invokeForward(inputState: Enum.UserInputState)
	local info = (ContextActionService:GetAllBoundActionInfo() :: any).DungeonTankForward
	expect(info).to.be.ok()
	TankController.handleInput("DungeonTankForward", inputState)
end

local function invokeRun(inputState: Enum.UserInputState)
	local info = (ContextActionService:GetAllBoundActionInfo() :: any).DungeonTankRun
	expect(info).to.be.ok()
	TankController.handleInput("DungeonTankRun", inputState)
end

return function()
	describe("TankController", function()
		afterEach(function()
			TankController.stop()
		end)

		it("binds the tank actions once", function()
			TankController.start()
			TankController.start()

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			local expectedActions = {
				DungeonTankForward = Enum.KeyCode.W,
				DungeonTankBackward = Enum.KeyCode.S,
				DungeonTankLeft = Enum.KeyCode.A,
				DungeonTankRight = Enum.KeyCode.D,
				DungeonTankRun = Enum.KeyCode.LeftShift,
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
			expect(actions.DungeonTankRun).to.equal(nil)
		end)

		it("uses the run speed while the run action is active", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid

			TankController.start()
			invokeRun(Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			task.wait()

			expect(humanoid.WalkSpeed).to.equal(10)
		end)

		it("restores the humanoid speed when stopped", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			local originalWalkSpeed = humanoid.WalkSpeed

			TankController.start()
			invokeRun(Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			task.wait()
			TankController.stop()

			expect(humanoid.WalkSpeed).to.equal(originalWalkSpeed)
		end)

		it("reaplica a direcao comandada depois de uma rotacao externa", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

			TankController.start()
			RunService.PreRender:Wait()

			local expectedLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(25), 0)
			RunService.PreRender:Wait()

			local actualLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			expect(actualLook.X).to.be.near(expectedLook.X, 0.001)
			expect(actualLook.Z).to.be.near(expectedLook.Z, 0.001)
		end)

		it("mantem o movimento bloqueado e ressincroniza a entrada ao liberar o ultimo lock", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid

			TankController.start()
			local firstRelease = TankController.acquireMovementLock()
			local secondRelease = TankController.acquireMovementLock()

			invokeForward(Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			expect(humanoid.MoveDirection).to.equal(Vector3.zero)

			firstRelease()
			invokeForward(Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			expect(humanoid.MoveDirection).to.equal(Vector3.zero)

			secondRelease()
			RunService.PreRender:Wait()
			expect(humanoid.MoveDirection).to.equal(Vector3.zero)

			firstRelease()
			secondRelease()
		end)
	end)
end
