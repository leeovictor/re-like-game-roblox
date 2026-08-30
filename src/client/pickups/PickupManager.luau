--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StarterPlayer = game:GetService("StarterPlayer")

local CharacterRoot = require(StarterPlayer.StarterPlayerScripts.Client.player.CharacterRoot)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local items = require(ReplicatedStorage.Shared.inventory.items)
local Signal = require(ReplicatedStorage.Packages.Signal)

type ItemInstance = items.ItemInstance
local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)

type InventoryController = InventoryControllerModule.InventoryController
type Factory = ItemInstanceFactory.Factory

export type Dependencies = {
	inventory: InventoryController,
	factory: Factory,
}

export type PickupFailureReason = "invalid_pickup" | "not_registered" | "too_far" | "inventory_failed"
export type PickupFailure = { success: false, reason: PickupFailureReason }
export type PickupSuccess = { success: true, itemId: string }
export type PickupResult = PickupFailure | PickupSuccess

type SignalConnection = { Disconnect: (self: SignalConnection) -> () }
type CollectedSignal = {
	Fire: (self: CollectedSignal, itemId: string) -> (),
	Connect: (self: CollectedSignal, callback: (itemId: string) -> ()) -> SignalConnection,
}

export type RegisteredPickup = {
	instance: ItemInstance,
	itemId: string,
	quantity: number?,
}

export type PickupManager = {
	start: (self: PickupManager) -> (),
	stop: (self: PickupManager) -> (),
	collect: (self: PickupManager, pickup: Instance) -> PickupResult,
	collected: CollectedSignal,
}

local MAX_DISTANCE = 6

local function getPosition(pickup: Instance): Vector3
	if pickup:IsA("BasePart") then
		return pickup.Position
	end
	return (pickup :: Model):GetPivot().Position
end

local function isValidAttributes(pickup: Instance, registered: RegisteredPickup): boolean
	return pickup:IsDescendantOf(Workspace)
		and (pickup:IsA("BasePart") or pickup:IsA("Model"))
		and CollectionService:HasTag(pickup, interactionTypes.INTERACTABLE_TAG)
		and pickup:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) == interactionTypes.PICKUP_TYPE
		and pickup:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE) == registered.itemId
		and pickup:GetAttribute(interactionTypes.QUANTITY_ATTRIBUTE) == registered.quantity
end

local PickupManager = {}

function PickupManager.new(dependencies: Dependencies): PickupManager
	assert(type(dependencies) == "table", "PickupManager dependencies are required")
	assert(type(dependencies.inventory.addInstance) == "function", "PickupManager inventory.addInstance is required")
	assert(type(dependencies.factory.create) == "function", "PickupManager factory.create is required")

	local registered: { [Instance]: RegisteredPickup } = {}
	local started = false
	local tagConnection: RBXScriptConnection? = nil
	local collected = (Signal.new() :: any) :: CollectedSignal

	local manager = {
		collected = collected,
	} :: PickupManager

	local function registerPickup(target: Instance): boolean
		if registered[target] ~= nil then
			return true
		end
		if not target:IsA("BasePart") and not target:IsA("Model") then
			return false
		end
		if not target:IsDescendantOf(Workspace)
			or not CollectionService:HasTag(target, interactionTypes.INTERACTABLE_TAG)
			or target:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) ~= interactionTypes.PICKUP_TYPE
		then
			return false
		end
		local itemId = target:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)
		local quantity = target:GetAttribute(interactionTypes.QUANTITY_ATTRIBUTE)
		if type(itemId) ~= "string" or itemId == "" then
			return false
		end
		if quantity ~= nil and type(quantity) ~= "number" then
			return false
		end
		local instance = dependencies.factory:create(itemId :: any, nil, quantity :: number?)
		if instance == nil then
			return false
		end
		for _, descendant in target:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			end
		end
		registered[target] = { instance = instance, itemId = itemId, quantity = quantity :: number? }
		return true
	end

	function manager:start(): ()
		if started then
			return
		end
		started = true
		tagConnection = CollectionService:GetInstanceAddedSignal(interactionTypes.INTERACTABLE_TAG):Connect(function(target)
			if target:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) == interactionTypes.PICKUP_TYPE then
				registerPickup(target)
			end
		end)
		for _, target in CollectionService:GetTagged(interactionTypes.INTERACTABLE_TAG) do
			registerPickup(target)
		end
	end

	function manager:stop(): ()
		if not started then
			return
		end
		started = false
		if tagConnection ~= nil then
			tagConnection:Disconnect()
			tagConnection = nil
		end
		table.clear(registered)
	end

	function manager:collect(pickup: Instance): PickupResult
		local registeredPickup = registered[pickup]
		if registeredPickup == nil then
			return { success = false, reason = "not_registered" }
		end
		if not isValidAttributes(pickup, registeredPickup) then
			return { success = false, reason = "invalid_pickup" }
		end
		local root = CharacterRoot.get()
		if root == nil or (getPosition(pickup) - root.Position).Magnitude > MAX_DISTANCE then
			return { success = false, reason = "too_far" }
		end
		local ok, added = pcall(function()
			return dependencies.inventory:addInstance(registeredPickup.instance)
		end)
		if not ok or added ~= true then
			return { success = false, reason = "inventory_failed" }
		end
		registered[pickup] = nil
		pickup:Destroy()
		collected:Fire(registeredPickup.itemId)
		return { success = true, itemId = registeredPickup.itemId }
	end

	return manager
end

return PickupManager
