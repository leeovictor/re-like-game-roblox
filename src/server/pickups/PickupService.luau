--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local items = require(ReplicatedStorage.Shared.inventory.items)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
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

type RegisteredPickup = {
	instance: items.ItemInstance,
	itemId: string,
	quantity: number?,
}

type PickupResult = {
	success: boolean,
	reason: string?,
}

export type Service = {
	start: (self: Service) -> (),
	stop: (self: Service) -> (),
	invoke: (self: Service, player: Player, request: any) -> PickupResult,
}

local MAX_DISTANCE = 6
local SPAWN_RADIUS = 30

local collectPickup = remotes.CollectPickup :: any
local pickupCollected = remotes.PickupCollected :: RemoteEvent

local defaultColor = Color3.fromRGB(128, 128, 128)
local defaultMaterial = Enum.Material.SmoothPlastic

local function failure(reason: string): PickupResult
	return { success = false, reason = reason }
end

local function getCharacterRoot(player: any): BasePart?
	local character = player.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function getPickupPosition(pickup: Instance): Vector3
	if pickup:IsA("BasePart") then
		return pickup.Position
	end
	return (pickup :: Model):GetPivot().Position
end

local PickupService = {}

function PickupService.new(
	inventoryService: InventoryService,
	factory: ItemInstanceFactory,
	definitions: { PickupDefinition }?,
	notify: ((Player, string) -> ())?
): Service
	local pickupDefinitions: { PickupDefinition } = if definitions == nil then {} else definitions
	local registered: { [Instance]: RegisteredPickup } = {}
	local busy: { [Instance]: boolean } = {}
	local pendingGenerated: { [Instance]: items.ItemInstance } = {}
	local characterConnections: { [Player]: RBXScriptConnection? } = {}
	local started = false
	local spawned = false
	local tagConnection: RBXScriptConnection? = nil
	local playerAddedConnection: RBXScriptConnection? = nil
	local service = {} :: Service

	local notifyPlayer: (Player, string) -> () = if notify == nil then function(player: Player, itemId: string): ()
		pickupCollected:FireClient(player, itemId)
	end else notify :: (Player, string) -> ()

	local function registerPickup(target: Instance, suppliedInstance: items.ItemInstance?): boolean
		if registered[target] ~= nil then
			return true
		end
		if not target:IsA("BasePart") and not target:IsA("Model") then
			warn(string.format("Pickup target has an invalid class: %s", target:GetFullName()))
			return false
		end
		if not target:IsDescendantOf(Workspace) then
			warn(string.format("Pickup target is outside Workspace: %s", target:GetFullName()))
			return false
		end
		if not CollectionService:HasTag(target, interactionTypes.INTERACTABLE_TAG) then
			return false
		end
		if target:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) ~= interactionTypes.PICKUP_TYPE then
			return false
		end

		local rawItemId = target:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)
		if type(rawItemId) ~= "string" or rawItemId == "" then
			warn(string.format("Pickup target has invalid ItemId: %s", target:GetFullName()))
			return false
		end
		local rawQuantity = target:GetAttribute(interactionTypes.QUANTITY_ATTRIBUTE)
		if rawQuantity ~= nil and type(rawQuantity) ~= "number" then
			warn(string.format("Pickup target has invalid Quantity: %s", target:GetFullName()))
			return false
		end

		local itemInstance = suppliedInstance
		if itemInstance == nil then
			itemInstance = factory:create(rawItemId, nil, rawQuantity :: number?)
		end
		if itemInstance == nil or itemInstance.itemId ~= rawItemId or itemInstance.quantity ~= nil and rawQuantity ~= nil and itemInstance.quantity ~= rawQuantity then
			warn(string.format("Pickup target has invalid item configuration: %s", target:GetFullName()))
			return false
		end

		for _, descendant in target:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			end
		end
		registered[target] = {
			instance = itemInstance,
			itemId = rawItemId,
			quantity = rawQuantity :: number?,
		}
		return true
	end

	local function onTagged(target: Instance): ()
		if target:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) ~= interactionTypes.PICKUP_TYPE then
			return
		end
		local suppliedInstance = pendingGenerated[target]
		registerPickup(target, suppliedInstance)
		if suppliedInstance ~= nil then
			pendingGenerated[target] = nil
		end
	end

	local function createGeneratedPickup(folder: Folder, instance: items.ItemInstance, index: number, center: Vector3, random: Random): ()
		local item = items[instance.itemId]
		if item == nil then
			return
		end
		local part = Instance.new("Part")
		part.Name = string.format("Pickup_%s_%02d", instance.itemId, index)
		part.Anchored = true
		part.CanCollide = false
		part.Position = center + Vector3.new(
			random:NextNumber(-SPAWN_RADIUS, SPAWN_RADIUS),
			2,
			random:NextNumber(-SPAWN_RADIUS, SPAWN_RADIUS)
		)
		part.Size = Vector3.new(2, 2, 2)
		part.Color = defaultColor
		part.Material = defaultMaterial
		part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
		part:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, instance.itemId)
		if instance.quantity ~= nil then
			part:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, instance.quantity)
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Coletar"
		prompt.ObjectText = item.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = part

		part.Parent = folder
		pendingGenerated[part] = instance
		CollectionService:AddTag(part, interactionTypes.INTERACTABLE_TAG)
	end

	local function spawnPickups(center: Vector3): ()
		if spawned then
			return
		end

		local prepared: { items.ItemInstance } = {}
		for _, definition in pickupDefinitions do
			local instance = factory:create(definition.itemId, definition.attributes, definition.quantity)
			if instance == nil then
				warn(string.format("Invalid pickup definition: %s", definition.itemId))
			else
				table.insert(prepared, instance)
			end
		end
		if #prepared == 0 then
			spawned = true
			return
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
			warn("Workspace.Pickups must be a Folder")
			spawned = true
			return
		end

		spawned = true
		local random = Random.new()
		for index, instance in prepared do
			createGeneratedPickup(folder, instance, index, center, random)
		end
	end

	local function onCharacter(character: Model): ()
		if spawned then
			return
		end
		local root = character:WaitForChild("HumanoidRootPart")
		if spawned or not root:IsA("BasePart") then
			return
		end
		spawnPickups(root.Position)
	end

	local function connectCharacter(player: Player): ()
		if characterConnections[player] ~= nil then
			return
		end
		characterConnections[player] = player.CharacterAdded:Connect(onCharacter)
	end

	local function handle(player: Player, request: any): PickupResult
		if type(request) ~= "table" or typeof(request.pickup) ~= "Instance" then
			return failure("invalid_request")
		end
		local pickup = request.pickup :: Instance
		local registeredPickup = registered[pickup]
		if registeredPickup == nil then
			return failure("not_registered")
		end
		if not pickup:IsDescendantOf(Workspace)
			or not pickup:IsA("BasePart") and not pickup:IsA("Model")
			or not CollectionService:HasTag(pickup, interactionTypes.INTERACTABLE_TAG)
			or pickup:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) ~= interactionTypes.PICKUP_TYPE
		then
			return failure("invalid_pickup")
		end
		if pickup:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE) ~= registeredPickup.itemId
			or pickup:GetAttribute(interactionTypes.QUANTITY_ATTRIBUTE) ~= registeredPickup.quantity
		then
			return failure("invalid_pickup")
		end

		local root = getCharacterRoot(player)
		if root == nil then
			return failure("invalid_pickup")
		end
		if (getPickupPosition(pickup) - root.Position).Magnitude > MAX_DISTANCE then
			return failure("too_far")
		end
		if busy[pickup] then
			return failure("busy")
		end

		busy[pickup] = true
		local ok, added = pcall(function(): boolean
			return inventoryService:addInstance(player, registeredPickup.instance)
		end)
		busy[pickup] = nil
		if not ok or added ~= true then
			return failure("inventory_failed")
		end

		registered[pickup] = nil
		pickup:Destroy()
		notifyPlayer(player, registeredPickup.itemId)
		return { success = true }
	end

	function service:start(): ()
		if started then
			return
		end
		started = true
		tagConnection = CollectionService:GetInstanceAddedSignal(interactionTypes.INTERACTABLE_TAG):Connect(onTagged)
		for _, target in CollectionService:GetTagged(interactionTypes.INTERACTABLE_TAG) do
			onTagged(target)
		end
		local serverCallback = function(player: Player, request: any): PickupResult
			return service:invoke(player, request)
		end
		collectPickup.OnServerInvoke = serverCallback

		playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player): ()
			connectCharacter(player)
		end)
		for _, player in Players:GetPlayers() do
			connectCharacter(player)
			if player.Character ~= nil then
				task.spawn(onCharacter, player.Character)
			end
		end
	end

	function service:stop(): ()
		if not started then
			return
		end
		started = false
		collectPickup.OnServerInvoke = nil
		if tagConnection ~= nil then
			tagConnection:Disconnect()
			tagConnection = nil
		end
		if playerAddedConnection ~= nil then
			playerAddedConnection:Disconnect()
			playerAddedConnection = nil
		end
		for player, connection in characterConnections do
			if connection ~= nil then
				connection:Disconnect()
			end
			characterConnections[player] = nil
		end
		table.clear(registered)
		table.clear(busy)
		table.clear(pendingGenerated)
	end

	function service:invoke(player: Player, request: any): PickupResult
		return handle(player, request)
	end

	return service
end

return PickupService
