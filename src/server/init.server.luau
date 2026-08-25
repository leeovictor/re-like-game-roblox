--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryService = require(script.inventory.InventoryService)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
local ItemBehaviorRegistry = require(script.items.ItemBehaviorRegistry)
local ItemUseService = require(script.items.ItemUseService)
local PickupService = require(script.pickups.PickupService)
local CharacterLightService = require(script.player.CharacterLightService)
local remotes = require(ReplicatedStorage.Shared.remotes)

local inventoryService = InventoryService.new()
local behaviorRegistry = ItemBehaviorRegistry.new()

local itemUseService = ItemUseService.new(inventoryService, behaviorRegistry)
itemUseService:bind(remotes.UseItem :: RemoteFunction)
inventoryService:start()

local factory = ItemInstanceFactory.new(function(): string
	return HttpService:GenerateGUID(false)
end)
local pickupService = PickupService.new(inventoryService, factory)
pickupService:start()

local characterLightService = CharacterLightService.new()
characterLightService:start()
