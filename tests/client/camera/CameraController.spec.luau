--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local CameraController = require(client.camera.CameraController)

local function newConfig(): any
	return {
		defaultShotId = "Default",
		shots = {
			Default = { cframe = CFrame.new(0, 10, -20), fieldOfView = 55 },
			First = { cframe = CFrame.new(0, 10, 20), fieldOfView = 65 },
		},
		zones = {
			{
				id = "FirstZone",
				volume = { cframe = CFrame.new(), size = Vector3.new(10, 10, 10) },
				shotId = "First",
			},
		},
	}
end

local function waitFor(predicate: () -> boolean): boolean
	local deadline = os.clock() + 3
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait()
	end
	return predicate()
end

return function()
	describe("CameraController", function()
		local controller: any
		local rootPart: BasePart
		local camera: Camera
		local previousRootCFrame: CFrame
		local previousAnchored: boolean
		local previousCameraType: Enum.CameraType
		local previousCameraCFrame: CFrame
		local previousCameraSubject: (BasePart | Humanoid)?
		local previousFieldOfView: number

		beforeEach(function()
			local character = Players.LocalPlayer.Character
			if character == nil then
				character = Players.LocalPlayer.CharacterAdded:Wait()
			end
			local characterModel = character :: Model
			rootPart = characterModel:WaitForChild("HumanoidRootPart") :: BasePart

			camera = workspace.CurrentCamera

			previousRootCFrame = rootPart.CFrame
			previousAnchored = rootPart.Anchored
			previousCameraType = camera.CameraType
			previousCameraCFrame = camera.CFrame
			previousCameraSubject = camera.CameraSubject
			previousFieldOfView = camera.FieldOfView

			rootPart.Anchored = true
			rootPart.CFrame = CFrame.new(0, 0, 20)
			controller = CameraController.new(newConfig())
			controller:start()
		end)

		afterEach(function()
			if controller ~= nil then
				controller:stop()
			end
			rootPart.CFrame = previousRootCFrame
			rootPart.Anchored = previousAnchored
			camera.CameraType = previousCameraType
			camera.CFrame = previousCameraCFrame
			camera.CameraSubject = previousCameraSubject
			camera.FieldOfView = previousFieldOfView
		end)

		it("mantem o ultimo shot ao sair de uma zona", function()
			expect(waitFor(function()
				return controller:getCurrentShotId() == "Default"
			end)).to.equal(true)

			rootPart.CFrame = CFrame.new()
			expect(waitFor(function()
				return controller:getCurrentShotId() == "First"
			end)).to.equal(true)

			rootPart.CFrame = CFrame.new(0, 0, 20)
			RunService.PreRender:Wait()
			task.wait()
			expect(controller:getCurrentShotId()).to.equal("First")
			expect(camera.CFrame).to.equal(CFrame.new(0, 10, 20))
			expect(camera.FieldOfView).to.equal(65)
		end)

		it("mantem o shot cinematic durante o PreRender", function()
			expect(controller:setCinematicShot("First")).to.equal(true)

			RunService.PreRender:Wait()
			task.wait()

			expect(controller:getCurrentShotId()).to.equal("First")
			expect(camera.CFrame).to.equal(CFrame.new(0, 10, 20))
			expect(camera.FieldOfView).to.equal(65)
		end)

		it("restaura o shot normal atual ao limpar o override", function()
			rootPart.CFrame = CFrame.new()
			expect(waitFor(function()
				return controller:getCurrentShotId() == "First"
			end)).to.equal(true)

			expect(controller:setCinematicShot("Default")).to.equal(true)
			RunService.PreRender:Wait()
			expect(controller:getCurrentShotId()).to.equal("Default")

			controller:clearCinematicShot()
			RunService.PreRender:Wait()
			task.wait()

			expect(controller:getCurrentShotId()).to.equal("First")
			expect(camera.CFrame).to.equal(CFrame.new(0, 10, 20))
			expect(camera.FieldOfView).to.equal(65)
		end)

		it("limpa o shot atual ao parar", function()
			expect(waitFor(function()
				return controller:getCurrentShotId() == "Default"
			end)).to.equal(true)

			controller:stop()
			expect(controller:getCurrentShotId()).to.equal(nil)
		end)
	end)
end
