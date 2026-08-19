--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryService = require(script.inventory.InventoryService)
local ItemBehaviorRegistry = require(script.items.ItemBehaviorRegistry)
local ItemUseService = require(script.items.ItemUseService)
local DoorService = require(script.doors.DoorService)
local DoorUnlockBehavior = require(script.doors.DoorUnlockBehavior)
local remotes = require(ReplicatedStorage.Shared.remotes)

local inventoryService = InventoryService.new()
local behaviorRegistry = ItemBehaviorRegistry.new()
assert(behaviorRegistry:register("unlock", DoorUnlockBehavior.create()), "unlock behavior registration")

local itemUseService = ItemUseService.new(inventoryService, behaviorRegistry)
itemUseService:bind(remotes.UseItem :: RemoteFunction)
inventoryService:start()

local doorService = DoorService.new(itemUseService)
doorService:start()
