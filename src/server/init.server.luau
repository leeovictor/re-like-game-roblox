--!strict

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryPersistence = require(script.inventory.persistence.MemoryPersistence)
local DataStorePersistence = require(script.inventory.persistence.DataStorePersistence)
local InventoryService = require(script.inventory.InventoryService)
local ItemInstanceFactory = require(script.items.ItemInstanceFactory)
local ItemBehaviorRegistry = require(script.items.ItemBehaviorRegistry)
local ItemUseService = require(script.items.ItemUseService)
local PickupService = require(script.pickups.PickupService)
local remotes = require(ReplicatedStorage.Shared.remotes)
local items = require(ReplicatedStorage.Shared.inventory.items)

type MapPickupDefinition = {
	itemId: items.ItemId,
	attributes: items.ItemAttributes?,
	quantity: number?,
}

local persistence = if RunService:IsStudio() then MemoryPersistence.new() else DataStorePersistence.new()
local inventoryService = InventoryService.new(persistence)
local behaviorRegistry = ItemBehaviorRegistry.new()
-- Concrete item effects are registered by their owning gameplay systems.
local itemUseService = ItemUseService.new(inventoryService, behaviorRegistry)
itemUseService:bind(remotes.UseItem :: RemoteFunction)
inventoryService:start()

local itemInstanceFactory = ItemInstanceFactory.new(function(): string
	return HttpService:GenerateGUID(false)
end)
local mapPickupDefinitions: { MapPickupDefinition } = if RunService:IsStudio() then {
	{
		itemId = "handgun",
		attributes = {
			damage = 18,
			loadedAmmo = 5,
		} :: items.ItemAttributes,
	},
	{
		itemId = "handgun_ammo",
		quantity = 12,
	},
	{
		itemId = "medkit",
	},
	{
		itemId = "iron_key",
	},
} else {}
local pickupService = PickupService.new(inventoryService, itemInstanceFactory, mapPickupDefinitions)
pickupService:start()
