--!strict

local RunService = game:GetService("RunService")
local MemoryPersistence = require(script.inventory.persistence.MemoryPersistence)
local DataStorePersistence = require(script.inventory.persistence.DataStorePersistence)
local InventoryService = require(script.inventory.InventoryService)

local backend = if RunService:IsStudio() then MemoryPersistence.new() else DataStorePersistence.new()
InventoryService.new(backend):start()
