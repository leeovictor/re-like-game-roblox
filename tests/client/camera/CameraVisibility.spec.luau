--!strict

local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local CameraVisibility = require(client.camera.CameraVisibility)

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

return function()
	describe("CameraVisibility", function()
		beforeEach(function()
			createdRoots = {}
		end)

		afterEach(function()
			for _, root in createdRoots do
				root:Destroy()
			end
			createdRoots = {}
		end)

		it("hides only direct shots and zones", function()
			local root = newFolder("CameraSystem", nil)
			local shots = newFolder("Shots", root)
			local zones = newFolder("Zones", root)
			local shot = newPart("Center", shots, Vector3.new(10, 10, 10))
			local zone = newPart("Entrance", zones, Vector3.new(10, 10, 10))
			local nestedFolder = newFolder("NestedFolder", shots)
			local nested = newPart("Nested", nestedFolder, Vector3.new(10, 10, 10))

			CameraVisibility.hide(root)

			expect(shot.LocalTransparencyModifier).to.equal(1)
			expect(zone.LocalTransparencyModifier).to.equal(1)
			expect(nested.LocalTransparencyModifier).to.equal(0)
		end)
	end)
end
