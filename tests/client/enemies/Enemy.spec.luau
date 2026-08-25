--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local Enemy = require(client.enemies.Enemy)

local created: { Instance } = {}
local savedCharacter: Model?
local savedCharacterParent: Instance?

local function track(instance: Instance): Instance
	table.insert(created, instance)
	return instance
end

local function makeCharacter(position: Vector3): Model
	local character = track(Instance.new("Model")) :: Model
	character.Name = "TestCharacter"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = position
	root.Anchored = true
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.Parent = workspace
	Players.LocalPlayer.Character = character
	return character
end

local function makeEnemy(position: Vector3): Model
	local model = track(Instance.new("Model")) :: Model
	model.Name = "TestEnemy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = position
	root.Anchored = true
	root.Parent = model
	local visual = Instance.new("Part")
	visual.Name = "Visual"
	visual.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.Parent = workspace
	return model
end

local function makeFloor(position: Vector3, size: Vector3): Part
	local floor = track(Instance.new("Part")) :: Part
	floor.Position = position
	floor.Size = size
	floor.Anchored = true
	floor.Parent = workspace
	return floor
end

return function()
	describe("Enemy", function()
		beforeEach(function()
			created = {}
			savedCharacter = Players.LocalPlayer.Character
			savedCharacterParent = if savedCharacter ~= nil then savedCharacter.Parent else nil
		end)
		afterEach(function()
			for _, instance in created do instance:Destroy() end
			if savedCharacter ~= nil then
				Players.LocalPlayer.Character = savedCharacter
				savedCharacter.Parent = savedCharacterParent
			else
				Players.LocalPlayer.Character = nil
			end
			created = {}
		end)

		it("inicia no estado idle", function()
			local enemy = Enemy.new(makeEnemy(Vector3.new(0, 3, 0)))
			expect(enemy.state).to.equal("idle")
			enemy:destroy()
		end)
		it("permanece idle sem player root", function()
			local enemy = Enemy.new(makeEnemy(Vector3.new(0, 3, 0)))
			Players.LocalPlayer.Character = nil
			enemy:update(0.1)
			expect(enemy.state).to.equal("idle")
			enemy:destroy()
		end)
		it("volta para idle fora do raio", function()
			makeCharacter(Vector3.new(20, 3, 0))
			local enemy = Enemy.new(makeEnemy(Vector3.new(0, 3, 0)))
			enemy:update(0.1)
			expect(enemy.state).to.equal("idle")
			enemy:destroy()
		end)
		it("entra em chasing e envia waypoint em superficie navegavel", function()
			makeFloor(Vector3.new(0, 0, 0), Vector3.new(20, 1, 20))
			makeCharacter(Vector3.new(2, 3, 0))
			local enemy = Enemy.new(makeEnemy(Vector3.new(0, 3, 0)))
			task.wait(0.5)
			enemy:update(0.1)
			expect(enemy.state).to.equal("chasing")
			expect((enemy.model.Humanoid :: Humanoid).WalkToPoint == Vector3.zero).to.equal(false)
			enemy:destroy()
		end)
		it("volta para idle quando ComputeAsync falha", function()
			makeFloor(Vector3.new(-2, 20, 0), Vector3.new(1, 1, 12))
			makeFloor(Vector3.new(2, 20, 0), Vector3.new(1, 1, 12))
			makeCharacter(Vector3.new(2, 21, 0))
			local enemy = Enemy.new(makeEnemy(Vector3.new(-2, 21, 0)))
			task.wait(0.5)
			enemy:update(0.1)
			expect(enemy.state).to.equal("idle")
			enemy:destroy()
		end)
	end)
end
