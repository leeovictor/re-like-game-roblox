--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local catalog = require(ReplicatedStorage.Shared.inventory.catalog)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local items = require(ReplicatedStorage.Shared.inventory.items)
local InventoryController = require(script.Parent.Parent.inventory.InventoryController)
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)

type DoorActionResult = doorTypes.DoorActionResult
type InventoryState = items.InventoryState

export type Dependencies = {
	inventory: InventoryController.InventoryController,
}

export type DoorManager = {
	isLocked: (self: DoorManager, door: Model) -> (boolean?, doorTypes.DoorFailureReason?),
	unlock: (self: DoorManager, door: Model) -> DoorActionResult,
	enter: (self: DoorManager, door: Model) -> DoorActionResult,
}

local MAX_DISTANCE = 6
local SIDE_EPSILON = 0.001
local EXIT_MARGIN = 3

local function failure(reason: doorTypes.DoorFailureReason): DoorActionResult
	return { success = false, reason = reason }
end

local function hasUnlockCapability(itemId: string): boolean
	local definition = catalog[itemId]
	if definition == nil then
		return false
	end
	for _, capability in definition.capabilities do
		if capability == "unlock" then
			return true
		end
	end
	return false
end

local function getDoorParts(door: Model): (BasePart?, Attachment?)
	local doorway = door:FindFirstChild(doorTypes.DOORWAY_NAME)
	if doorway == nil or not doorway:IsA("BasePart") then
		return nil, nil
	end
	local center = doorway:FindFirstChild(doorTypes.CENTER_NAME)
	if center == nil or not center:IsA("Attachment") then
		return nil, nil
	end
	return doorway, center
end

local function validateDoor(door: Model): (BasePart?, Attachment?, boolean?, string?, DoorActionResult?)
	if not door:IsA("Model") or not door:IsDescendantOf(Workspace) then
		return nil, nil, nil, nil, failure("invalid_door")
	end
	if not CollectionService:HasTag(door, interactionTypes.INTERACTABLE_TAG) then
		return nil, nil, nil, nil, failure("invalid_door")
	end
	if door:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE) ~= interactionTypes.DOOR_TYPE then
		return nil, nil, nil, nil, failure("invalid_door")
	end
	local doorway, center = getDoorParts(door)
	if doorway == nil or center == nil then
		return nil, nil, nil, nil, failure("invalid_door")
	end
	local locked = door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)
	local requiredItemId = door:GetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE)
	if type(locked) ~= "boolean" or type(requiredItemId) ~= "string" then
		return nil, nil, nil, nil, failure("invalid_config")
	end
	if locked and (requiredItemId == "" or catalog[requiredItemId] == nil or not hasUnlockCapability(requiredItemId)) then
		return nil, nil, nil, nil, failure("invalid_config")
	end
	return doorway, center, locked, requiredItemId, nil
end

local DoorManager = {}

function DoorManager.new(dependencies: Dependencies): DoorManager
	assert(type(dependencies) == "table", "DoorManager dependencies must be a table")
	assert(type(dependencies.inventory) == "table", "DoorManager inventory dependency must be a table")
	assert(type(dependencies.inventory.getState) == "function", "DoorManager inventory.getState must be callable")

	local manager = {} :: DoorManager

	function manager:isLocked(door: Model): (boolean?, doorTypes.DoorFailureReason?)
		local _, _, locked, _, validationFailure = validateDoor(door)
		if validationFailure ~= nil then
			return nil, validationFailure.reason
		end
		return locked, nil
	end

	function manager:unlock(door: Model): DoorActionResult
		local doorway, center, locked, requiredItemId, validationFailure = validateDoor(door)
		if validationFailure ~= nil then
			return validationFailure
		end
		if doorway == nil or center == nil or locked == nil or requiredItemId == nil then
			return failure("invalid_door")
		end
		local root = CharacterRoot.get()
		if root == nil then
			return failure("invalid_door")
		end
		local offset = root.Position - center.WorldPosition
		if offset.Magnitude > MAX_DISTANCE then
			return failure("too_far")
		end
		local signedDistance = offset:Dot(center.WorldCFrame.XVector)
		if math.abs(signedDistance) <= SIDE_EPSILON then
			return failure("ambiguous_side")
		end
		local result: DoorActionResult
		local ok = pcall(function()
			if not locked then
				result = failure("already_unlocked")
				return
			end
			local snapshot: InventoryState?
			local snapshotOk = pcall(function()
				snapshot = dependencies.inventory.getState()
			end)
			if not snapshotOk then
				result = failure("invalid_door")
				return
			end
			local found = false
			if snapshot ~= nil then
				for _, item in snapshot.items do
					if item.itemId == requiredItemId then
						found = true
						break
					end
				end
			end
			if not found then
				result = failure("missing_item")
				return
			end
			door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, false)
			result = { success = true, action = "unlock" }
		end)
		if not ok then
			return failure("invalid_door")
		end
		return result :: DoorActionResult
	end

	function manager:enter(door: Model): DoorActionResult
		local doorway, center, locked, _, validationFailure = validateDoor(door)
		if validationFailure ~= nil then
			return validationFailure
		end
		if doorway == nil or center == nil or locked == nil then
			return failure("invalid_door")
		end
		local root = CharacterRoot.get()
		if root == nil then
			return failure("invalid_door")
		end
		local offset = root.Position - center.WorldPosition
		if offset.Magnitude > MAX_DISTANCE then
			return failure("too_far")
		end
		local signedDistance = offset:Dot(center.WorldCFrame.XVector)
		if math.abs(signedDistance) <= SIDE_EPSILON then
			return failure("ambiguous_side")
		end
		local result: DoorActionResult
		local ok = pcall(function()
			if locked then
				result = failure("locked")
				return
			end
			local side = if signedDistance > 0 then 1 else -1
			local direction = -center.WorldCFrame.XVector * side
			local destination = center.WorldPosition + direction * (doorway.Size.X / 2 + EXIT_MARGIN)
			destination = Vector3.new(destination.X, root.Position.Y, destination.Z)
			root.CFrame = CFrame.lookAt(destination, destination + direction)
			result = { success = true, action = "enter" }
		end)
		if not ok then
			return failure("invalid_door")
		end
		return result :: DoorActionResult
	end

	return manager
end

return DoorManager
