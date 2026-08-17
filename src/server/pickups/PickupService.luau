--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local items = require(ReplicatedStorage.Shared.inventory.items)

type InventoryService = {
	addItem: (self: InventoryService, player: Player, itemId: string) -> boolean,
}

export type Service = {
	start: (self: Service) -> (),
}

local pickupDefinitions = {
	{ itemId = "torch", count = 10 },
	{ itemId = "ration", count = 10 },
	{ itemId = "crystal", count = 10 },
}
local spawnRadius = 30

local visuals = {
	torch = { color = Color3.fromRGB(255, 170, 0), material = Enum.Material.Neon },
	ration = { color = Color3.fromRGB(98, 190, 110), material = Enum.Material.SmoothPlastic },
	crystal = { color = Color3.fromRGB(95, 160, 255), material = Enum.Material.Neon },
}

local function createPickup(
	folder: Folder,
	inventoryService: InventoryService,
	itemId: string,
	index: number,
	center: Vector3,
	random: Random
): ()
	local item = assert(items[itemId], string.format("Unknown pickup item: %s", itemId))
	local visual = assert(visuals[itemId], string.format("Missing pickup visual: %s", itemId))
	local offset = Vector3.new(
		random:NextNumber(-spawnRadius, spawnRadius),
		2,
		random:NextNumber(-spawnRadius, spawnRadius)
	)

	local part = Instance.new("Part")
	part.Name = string.format("Pickup_%s_%02d", itemId, index)
	part.Anchored = true
	part.CanCollide = false
	part.Position = center + offset
	part.Size = Vector3.new(2, 2, 2)
	part.Color = visual.color
	part.Material = visual.material
	part:SetAttribute("ItemId", itemId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Coletar"
	prompt.ObjectText = item.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local collected = false
	prompt.Triggered:Connect(function(player: Player)
		if collected then
			return
		end

		collected = true
		prompt.Enabled = false
		if inventoryService:addItem(player, itemId) then
			part:Destroy()
		else
			collected = false
			prompt.Enabled = true
		end
	end)

	part.Parent = folder
end

local PickupService = {}

function PickupService.new(inventoryService: InventoryService): Service
	local spawned = false
	local started = false
	local service = {} :: Service

	local function spawnPickups(center: Vector3): ()
		if spawned then
			return
		end

		for _, definition in pickupDefinitions do
			assert(items[definition.itemId], string.format("Unknown pickup item: %s", definition.itemId))
		end

		local existing = Workspace:FindFirstChild("Pickups")
		local folder: Folder
		if existing == nil then
			folder = Instance.new("Folder")
			folder.Name = "Pickups"
			folder.Parent = Workspace
		elseif existing:IsA("Folder") then
			folder = existing
		else
			error("Workspace.Pickups must be a Folder")
		end

		spawned = true
		local random = Random.new()
		for _, definition in pickupDefinitions do
			for index = 1, definition.count do
				createPickup(folder, inventoryService, definition.itemId, index, center, random)
			end
		end
	end

	local function onCharacter(character: Model): ()
		if spawned then
			return
		end

		local root = character:WaitForChild("HumanoidRootPart") :: BasePart
		if spawned then
			return
		end

		spawnPickups(root.Position)
	end

	function service:start(): ()
		if started then
			return
		end
		started = true

		for _, player in Players:GetPlayers() do
			if player.Character ~= nil then
				onCharacter(player.Character)
			end
			player.CharacterAdded:Connect(onCharacter)
		end
		Players.PlayerAdded:Connect(function(player: Player)
			player.CharacterAdded:Connect(onCharacter)
		end)
	end

	return service
end

return PickupService
