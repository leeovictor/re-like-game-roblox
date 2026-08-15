--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Cria (ou reutiliza) um RemoteEvent dentro de ReplicatedStorage.Remotes.
local function _ensureRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Remotes"
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	if folder == nil then
		error("failed to create ReplicatedStorage.Remotes", 2)
	end

	local remote = folder:FindFirstChild(name)
	if remote == nil then
		local newRemote = Instance.new("RemoteEvent")
		newRemote.Name = name
		newRemote.Parent = folder
		remote = newRemote
	end
	if remote == nil then
		error(string.format("failed to create Remotes.%s", name), 2)
	end

	if not remote:IsA("RemoteEvent") then
		error(string.format("Remotes.%s must be a RemoteEvent", name), 2)
	end
	return remote
end

return {}
