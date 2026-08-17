--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local items = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)

type InventoryService = {
	addInstance: (self: InventoryService, player: Player, instance: items.ItemInstance) -> boolean,
}

type ItemInstanceFactory = {
	create: (
		self: ItemInstanceFactory,
		itemId: string,
		attributes: items.ItemAttributes?,
		quantity: number?
	) -> items.ItemInstance?,
}

type PickupDefinition = {
	itemId: string,
	attributes: items.ItemAttributes?,
	quantity: number?,
}

type PickupVisual = {
	color: Color3,
	material: Enum.Material,
}

export type Service = {
	start: (self: Service) -> (),
}

local spawnRadius = 30
local pickupCollected = remotes.PickupCollected :: RemoteEvent

local visuals: { [string]: PickupVisual } = {}

local function createPickup(
	folder: Folder,
	inventoryService: InventoryService,
	instance: items.ItemInstance,
	index: number,
	center: Vector3,
	random: Random
): ()
	local itemId = instance.itemId
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
		if inventoryService:addInstance(player, instance) then
			part:Destroy()
			pickupCollected:FireClient(player, itemId)
		else
			collected = false
			prompt.Enabled = true
		end
	end)

	part.Parent = folder
end

local PickupService = {}

function PickupService.new(
	inventoryService: InventoryService,
	factory: ItemInstanceFactory,
	definitions: { PickupDefinition }?
): Service
	local spawned = false
	local started = false
	local pickupDefinitions: { PickupDefinition } = if definitions == nil then {} else definitions
	local service = {} :: Service

	local function spawnPickups(center: Vector3): ()
		if spawned then
			return
		end

		local prepared: { items.ItemInstance } = {}
		for _, definition in pickupDefinitions do
			local instance = assert(
				factory:create(definition.itemId, definition.attributes, definition.quantity),
				string.format("Invalid pickup definition: %s", definition.itemId)
			)
			assert(items[definition.itemId], string.format("Unknown pickup item: %s", definition.itemId))
			assert(visuals[definition.itemId], string.format("Missing pickup visual: %s", definition.itemId))
			table.insert(prepared, instance)
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
		for index, instance in prepared do
			createPickup(folder, inventoryService, instance, index, center, random)
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

		Players.PlayerAdded:Connect(function(player: Player)
			player.CharacterAdded:Connect(onCharacter)
		end)
		for _, player in Players:GetPlayers() do
			player.CharacterAdded:Connect(onCharacter)
		end
		for _, player in Players:GetPlayers() do
			if player.Character ~= nil then
				task.spawn(onCharacter, player.Character)
			end
		end
	end

	return service
end

return PickupService
