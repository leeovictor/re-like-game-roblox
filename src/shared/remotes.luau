local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Cria (ou reutiliza) um RemoteEvent dentro de ReplicatedStorage.Remotes.
local function ensureRemote(name: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

return {}
