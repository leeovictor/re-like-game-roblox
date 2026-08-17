--!strict

local CameraVisibility = {}

local function requireFolder(root: Instance, name: string): Folder
	local child = root:FindFirstChild(name)
	if child == nil or not child:IsA("Folder") then
		error(string.format('CameraSystem must contain Folder "%s"', name), 3)
	end
	return child :: Folder
end

local function hideFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			(child :: BasePart).LocalTransparencyModifier = 1
		end
	end
end

function CameraVisibility.hide(root: Instance): ()
	hideFolder(requireFolder(root, "Shots"))
	hideFolder(requireFolder(root, "Zones"))
end

return CameraVisibility
