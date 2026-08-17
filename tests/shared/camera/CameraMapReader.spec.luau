--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

type LuneRoblox = {
	Vector3: { new: (number, number, number) -> any },
	CFrame: { new: (...any) -> any },
}

local roblox = require("@lune/roblox") :: LuneRoblox
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local CameraMapReader = loader.load("src/shared/camera/CameraMapReader.luau")

local function newPart(name: string, attributes: { [string]: any }, size: any?): any
	local part = {
		Name = name,
		ClassName = "Part",
		CFrame = CFrame.new(),
		Size = size or Vector3.new(10, 10, 10),
		attributes = attributes,
	}

	function part:GetAttribute(attributeName: string): any
		return self.attributes[attributeName]
	end

	function part:SetAttribute(attributeName: string, value: any): ()
		self.attributes[attributeName] = value
	end

	function part:GetChildren(): { any }
		return {}
	end

	function part:IsA(className: string): boolean
		return className == self.ClassName or className == "BasePart"
	end

	return part
end

local function newFolder(name: string, children: { any }): any
	local folder = {
		Name = name,
		ClassName = "Folder",
		children = children,
	}
	for _, child in children do
		folder[child.Name] = child
	end

	function folder:GetChildren(): { any }
		return table.clone(self.children)
	end

	function folder:FindFirstChild(childName: string): any
		for _, child in self.children do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end

	function folder:IsA(className: string): boolean
		return className == self.ClassName
	end

	return folder
end

local function newCameraSystem(): any
	local center = newPart("Center", { FieldOfView = 55 })
	local north = newPart("North", { FieldOfView = 60 })
	local first = newPart("First", { ShotId = "Center", Order = 2 })
	local second = newPart("Second", { ShotId = "North", Order = 1 })
	local shots = newFolder("Shots", { center, north })
	local zones = newFolder("Zones", { first, second })
	local root = newFolder("CameraSystem", { shots, zones })
	root.attributes = { DefaultShotId = "Center" }
	function root:GetAttribute(attributeName: string): any
		return self.attributes[attributeName]
	end
	return root
end

local function assertReadFails(root: any, identifier: string): ()
	local ok, message = pcall(function()
		CameraMapReader.read(root)
	end)
	harness.assert.falsy(ok)
	harness.assert.truthy(string.find(tostring(message), identifier, 1, true) ~= nil)
end

harness.describe("CameraMapReader", function()
	harness.it("converte shots e zonas para CameraConfig", function()
		local config = CameraMapReader.read(newCameraSystem())
		harness.assert.equal(config.defaultShotId, "Center")
		harness.assert.equal(config.shots.North.fieldOfView, 60)
		harness.assert.equal(config.zones[1].id, "Second")
		harness.assert.equal(config.zones[2].id, "First")
		harness.assert.equal(config.zones[1].shotId, "North")
	end)

	harness.it("preserva CFrame e Size das instancias", function()
		local root = newCameraSystem()
		local config = CameraMapReader.read(root)
		harness.assert.equal(config.shots.Center.cframe, root.Shots.Center.CFrame)
		harness.assert.equal(config.zones[1].volume.size, root.Zones.Second.Size)
	end)

	harness.it("rejeita ShotId inexistente", function()
		local root = newCameraSystem()
		root.Zones.First.attributes.ShotId = "Missing"
		assertReadFails(root, "First")
	end)

	harness.it("rejeita DefaultShotId inexistente", function()
		local root = newCameraSystem()
		root.attributes.DefaultShotId = "Missing"
		assertReadFails(root, "DefaultShotId")
	end)

	harness.it("rejeita FOV invalido e tamanho nao positivo", function()
		local root = newCameraSystem()
		root.Shots.Center.attributes.FieldOfView = 0
		assertReadFails(root, "Center")

		root = newCameraSystem()
		root.Zones.First.Size = Vector3.new(0, 10, 10)
		assertReadFails(root, "First")
	end)

	harness.it("rejeita Order ausente ou invalido", function()
		local root = newCameraSystem()
		root.Zones.First.attributes.Order = nil
		assertReadFails(root, "First")
	end)
end)
