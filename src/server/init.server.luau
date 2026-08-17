--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryPersistence = require(script.inventory.persistence.MemoryPersistence)
local DataStorePersistence = require(script.inventory.persistence.DataStorePersistence)
local InventoryService = require(script.inventory.InventoryService)
local ItemBehaviorRegistry = require(script.items.ItemBehaviorRegistry)
local ItemUseService = require(script.items.ItemUseService)
local remotes = require(ReplicatedStorage.Shared.remotes)

local persistence = if RunService:IsStudio() then MemoryPersistence.new() else DataStorePersistence.new()
local inventoryService = InventoryService.new(persistence)
local itemUseService = ItemUseService.new(inventoryService, ItemBehaviorRegistry.new())
itemUseService:bind(remotes.UseItem :: RemoteFunction)
inventoryService:start()
