--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Cria (ou reutiliza) um remoto dentro de ReplicatedStorage.Remotes.
local function _ensureRemote(name: string, className: "RemoteEvent" | "RemoteFunction"): RemoteEvent | RemoteFunction
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
		local newRemote = Instance.new(className)
		newRemote.Name = name
		newRemote.Parent = folder
		remote = newRemote
	end
	if remote == nil then
		error(string.format("failed to create Remotes.%s", name), 2)
	end

	if not remote:IsA(className) then
		error(string.format("Remotes.%s must be a %s", name, className), 2)
	end

	if className == "RemoteEvent" then
		return remote :: RemoteEvent
	end
	return remote :: RemoteFunction
end

return {
	InventoryChanged = _ensureRemote("InventoryChanged", "RemoteEvent"),
	GetInventory = _ensureRemote("GetInventory", "RemoteFunction"),
	UseItem = _ensureRemote("UseItem", "RemoteFunction"),
	PickupCollected = _ensureRemote("PickupCollected", "RemoteEvent"),
	InteractDoor = _ensureRemote("InteractDoor", "RemoteFunction"),
}
