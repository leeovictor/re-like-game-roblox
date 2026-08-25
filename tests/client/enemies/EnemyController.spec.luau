--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local EnemyController = require(client.enemies.EnemyController)

type SavedInstance = {
	instance: Instance,
	parent: Instance,
}

local function saveAndDetach(parent: Instance, name: string, saved: { SavedInstance }): ()
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(saved, {
				instance = child,
				parent = parent,
			})
			child.Parent = nil
		end
	end
end

return function()
	describe("EnemyController", function()
		local savedInstances: { SavedInstance } = {}
		local fixtures: { Instance } = {}
		local connections: { RBXScriptConnection } = {}
		local marker: Part
		local controller: any

		local function track<T>(instance: T): T
			table.insert(fixtures, instance :: any)
			return instance
		end

		local function makeMarker(): Part
			local value = track(Instance.new("Part")) :: Part
			value.Name = "SpawnMarker"
			value.CFrame = CFrame.new(12, 3, -8) * CFrame.Angles(0, math.rad(25), 0)
			value.Size = Vector3.new(2, 1, 2)
			value.Transparency = 0.35
			value.CanCollide = true
			value.Anchored = true
			return value
		end

		local function makeTemplate(): Model
			local model = track(Instance.new("Model")) :: Model
			model.Name = "Enemy"

			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = CFrame.new(-20, 7, 15) * CFrame.Angles(0, math.rad(-40), math.rad(15))
			root.Size = Vector3.new(2, 2, 1)
			root.Anchored = true
			root.Parent = model

			local humanoid = Instance.new("Humanoid")
			humanoid.Parent = model
			return model
		end

		local function getEnemies(): Folder
			local enemies = Workspace:FindFirstChild("Enemies")
			assert(enemies ~= nil and enemies:IsA("Folder"), "Enemies fixture must be a Folder")
			return enemies
		end

		beforeEach(function()
			savedInstances = {}
			fixtures = {}
			connections = {}

			saveAndDetach(Workspace, "EnemiesMarkers", savedInstances)
			saveAndDetach(ReplicatedStorage, "Models", savedInstances)
			saveAndDetach(Workspace, "Enemies", savedInstances)

			local markers = track(Instance.new("Folder")) :: Folder
			markers.Name = "EnemiesMarkers"
			markers.Parent = Workspace
			marker = makeMarker()
			marker.Parent = markers

			local models = track(Instance.new("Folder")) :: Folder
			models.Name = "Models"
			models.Parent = ReplicatedStorage
			local template = makeTemplate()
			template.Parent = models

			local enemies = track(Instance.new("Folder")) :: Folder
			enemies.Name = "Enemies"
			enemies.Parent = Workspace

			controller = EnemyController.new()
		end)

		afterEach(function()
			controller:stop()
			for _, connection in connections do
				connection:Disconnect()
			end
			connections = {}

			for _, fixture in fixtures do
				if fixture.Parent ~= nil then
					fixture:Destroy()
				end
			end
			fixtures = {}

			for _, saved in savedInstances do
				saved.instance.Parent = saved.parent
			end
			savedInstances = {}
		end)

		it("cria um inimigo por marker BasePart direto", function()
			controller:start()

			expect(#controller.enemies).to.equal(1)
			local clone = getEnemies():GetChildren()[1]
			expect(clone:IsA("Model")).to.equal(true)
			local root = (clone :: Model):FindFirstChild("HumanoidRootPart")
			assert(root ~= nil and root:IsA("BasePart"), "clone must have a root")
			local rootPosition = root.Position
			expect(rootPosition.X).to.be.near(marker.Position.X, 0.001)
			expect(rootPosition.Y).to.be.near(marker.Position.Y, 0.001)
			expect(rootPosition.Z).to.be.near(marker.Position.Z, 0.001)
		end)

		it("oculta markers durante o runtime", function()
			controller:start()

			expect(marker.Transparency).to.equal(1)
			expect(marker.CanCollide).to.equal(false)
		end)

		it("restaura markers e destroi clones em stop", function()
			local originalTransparency = marker.Transparency
			local originalCanCollide = marker.CanCollide
			controller:start()
			controller:stop()

			expect(marker.Transparency).to.equal(originalTransparency)
			expect(marker.CanCollide).to.equal(originalCanCollide)
			expect(#getEnemies():GetChildren()).to.equal(0)
		end)

		it("mantem start e stop idempotentes", function()
			local originalTransparency = marker.Transparency
			controller:start()
			controller:start()
			expect(#controller.enemies).to.equal(1)
			expect(controller.heartbeatConnection).to.be.ok()

			controller:stop()
			controller:stop()

			expect(#getEnemies():GetChildren()).to.equal(0)
			expect(marker.Transparency).to.equal(originalTransparency)
			expect(controller.heartbeatConnection).to.equal(nil)
		end)
	end)
end
