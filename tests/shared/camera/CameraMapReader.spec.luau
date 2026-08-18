--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)

local createdRoots: { Instance } = {}

local function newFolder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	if parent == nil then
		table.insert(createdRoots, folder)
	end
	return folder
end

local function newPart(name: string, parent: Instance?, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.CFrame = CFrame.new()
	part.Size = size
	part.Parent = parent
	return part
end

local function getFolder(parent: Instance, name: string): Folder
	return parent:WaitForChild(name) :: Folder
end

local function getPart(parent: Instance, name: string): Part
	return parent:WaitForChild(name) :: Part
end

local function newCameraSystem(): Folder
	local root = newFolder("CameraSystem", nil)
	local shots = newFolder("Shots", root)
	local zones = newFolder("Zones", root)
	root:SetAttribute("DefaultShotId", "Center")

	local center = newPart("Center", shots, Vector3.new(10, 10, 10))
	center:SetAttribute("FieldOfView", 55)

	local north = newPart("North", shots, Vector3.new(10, 10, 10))
	north:SetAttribute("FieldOfView", 60)

	local first = newPart("First", zones, Vector3.new(10, 10, 10))
	first:SetAttribute("ShotId", "Center")
	first:SetAttribute("Order", 2)

	local second = newPart("Second", zones, Vector3.new(10, 10, 10))
	second:SetAttribute("ShotId", "North")
	second:SetAttribute("Order", 1)

	return root
end

local function readFails(root: Instance): (boolean, any)
	return pcall(function()
		CameraMapReader.read(root)
	end)
end

return function()
	describe("CameraMapReader", function()
		beforeEach(function()
			createdRoots = {}
		end)

		afterEach(function()
			for _, root in createdRoots do
				root:Destroy()
			end
			createdRoots = {}
		end)

		it("converte shots e zonas para CameraConfig", function()
			local config = CameraMapReader.read(newCameraSystem())
			expect(config.defaultShotId).to.equal("Center")
			expect(config.shots.North.fieldOfView).to.equal(60)
			expect(config.zones[1].id).to.equal("Second")
			expect(config.zones[2].id).to.equal("First")
			expect(config.zones[1].shotId).to.equal("North")
		end)

		it("ordena zonas alfabeticamente quando Order empata", function()
			local root = newCameraSystem()
			local zones = getFolder(root, "Zones")
			getPart(zones, "First"):SetAttribute("Order", 1)

			local config = CameraMapReader.read(root)
			expect(config.zones[1].id).to.equal("First")
			expect(config.zones[2].id).to.equal("Second")
		end)

		it("preserva CFrame e Size das instancias", function()
			local root = newCameraSystem()
			local shots = getFolder(root, "Shots")
			local zones = getFolder(root, "Zones")
			local expectedShotCFrame = CFrame.new(12, 5, -8)
			local expectedZoneSize = Vector3.new(7, 11, 13)
			getPart(shots, "Center").CFrame = expectedShotCFrame
			getPart(zones, "Second").Size = expectedZoneSize

			local config = CameraMapReader.read(root)
			expect(config.shots.Center.cframe).to.equal(expectedShotCFrame)
			expect(config.zones[1].volume.size).to.equal(expectedZoneSize)
		end)

		it("rejeita ShotId inexistente", function()
			local root = newCameraSystem()
			getPart(getFolder(root, "Zones"), "First"):SetAttribute("ShotId", "Missing")
			local ok, message = readFails(root)
			expect(ok).to.equal(false)
			expect(string.find(tostring(message), "First", 1, true) ~= nil).to.equal(true)
		end)

		it("rejeita DefaultShotId inexistente", function()
			local root = newCameraSystem()
			root:SetAttribute("DefaultShotId", "Missing")
			local ok, message = readFails(root)
			expect(ok).to.equal(false)
			expect(string.find(tostring(message), "DefaultShotId", 1, true) ~= nil).to.equal(true)
		end)

		it("rejeita FOV invalido", function()
			local root = newCameraSystem()
			getPart(getFolder(root, "Shots"), "Center"):SetAttribute("FieldOfView", 0)
			local ok, message = readFails(root)
			expect(ok).to.equal(false)
			expect(string.find(tostring(message), "Center", 1, true) ~= nil).to.equal(true)
		end)

		it("rejeita Order ausente ou invalido", function()
			local root = newCameraSystem()
			getPart(getFolder(root, "Zones"), "First"):SetAttribute("Order", nil)
			local ok, message = readFails(root)
			expect(ok).to.equal(false)
			expect(string.find(tostring(message), "First", 1, true) ~= nil).to.equal(true)
		end)
	end)
end
