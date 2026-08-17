--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local CameraVisibility = loader.load("src/client/camera/CameraVisibility.luau")

local function newPart(name: string): any
	local part = {
		Name = name,
		ClassName = "Part",
		LocalTransparencyModifier = 0,
	}

	function part:IsA(className: string): boolean
		return className == "BasePart" or className == self.ClassName
	end

	return part
end

local function newFolder(name: string, children: { any }): any
	local folder = {
		Name = name,
		ClassName = "Folder",
		children = children,
	}

	function folder:FindFirstChild(childName: string): any
		for _, child in self.children do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end

	function folder:GetChildren(): { any }
		return table.clone(self.children)
	end

	function folder:IsA(className: string): boolean
		return className == self.ClassName
	end

	return folder
end

harness.describe("CameraVisibility", function()
	harness.it("hides only direct shots and zones", function()
		local shot = newPart("Center")
		local zone = newPart("Entrance")
		local nested = newPart("Nested")
		local shots = newFolder("Shots", { shot, newFolder("NestedFolder", { nested }) })
		local zones = newFolder("Zones", { zone })
		local root = newFolder("CameraSystem", { shots, zones })

		CameraVisibility.hide(root)

		harness.assert.equal(shot.LocalTransparencyModifier, 1)
		harness.assert.equal(zone.LocalTransparencyModifier, 1)
		harness.assert.equal(nested.LocalTransparencyModifier, 0)
	end)
end)
