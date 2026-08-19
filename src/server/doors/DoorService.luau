--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local catalog = require(ReplicatedStorage.Shared.inventory.catalog)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local remotes = require(ReplicatedStorage.Shared.remotes)
local interactDoor = remotes.InteractDoor :: any
local ItemUseService = require(script.Parent.Parent.items.ItemUseService)

type DoorRequest = doorTypes.DoorRequest
type DoorActionResult = doorTypes.DoorActionResult

export type Service = {
	invoke: (self: Service, player: Player, request: any) -> DoorActionResult,
	start: (self: Service) -> (),
	stop: (self: Service) -> (),
}

local MAX_DISTANCE = 6
local SIDE_EPSILON = 0.001
local EXIT_MARGIN = 3

local function failure(reason: doorTypes.DoorFailureReason): DoorActionResult
	return { success = false, reason = reason }
end

local function hasUnlockCapability(itemId: string): boolean
	local definition = catalog[itemId]
	if definition == nil then return false end
	for _, capability in definition.capabilities do
		if capability == "unlock" then return true end
	end
	return false
end

local function validRequest(request: any): boolean
	return type(request) == "table"
		and typeof(request.door) == "Instance"
		and request.door:IsA("Model")
		and (request.action == "unlock" or request.action == "enter")
end

local function getDoorParts(door: Model): (BasePart?, Attachment?)
	local doorway = door:FindFirstChild(doorTypes.DOORWAY_NAME)
	if doorway == nil or not doorway:IsA("BasePart") then return nil, nil end
	local center = doorway:FindFirstChild(doorTypes.CENTER_NAME)
	if center == nil or not center:IsA("Attachment") then return nil, nil end
	return doorway, center
end

local function validateDoor(door: Model): (BasePart?, Attachment?, boolean?, string?, DoorActionResult?)
	if not door:IsDescendantOf(Workspace) or not CollectionService:HasTag(door, doorTypes.DOOR_TAG) then
		return nil, nil, nil, nil, failure("invalid_door")
	end
	local doorway, center = getDoorParts(door)
	if doorway == nil or center == nil then return nil, nil, nil, nil, failure("invalid_door") end
	local locked = door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)
	local requiredItemId = door:GetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE)
	if type(locked) ~= "boolean" or type(requiredItemId) ~= "string" then
		return nil, nil, nil, nil, failure("invalid_config")
	end
	if locked and (requiredItemId == "" or not hasUnlockCapability(requiredItemId)) then
		return nil, nil, nil, nil, failure("invalid_config")
	end
	return doorway, center, locked, requiredItemId, nil
end

local function getRoot(player: any): BasePart?
	local character = player.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then return nil end
	return root
end

local DoorService = {}

function DoorService.new(itemUseService: ItemUseService.ItemUseService): Service
	local busy: { [Model]: boolean } = {}
	local started = false
	local service = {} :: Service
	local callback: ((Player, any) -> DoorActionResult)? = nil

	local function handle(player: Player, rawRequest: any): DoorActionResult
		if not validRequest(rawRequest) then return failure("invalid_door") end
		local request = rawRequest :: DoorRequest
		local door = request.door
		local doorway, center, locked, requiredItemId, validationFailure = validateDoor(door)
		if validationFailure ~= nil then return validationFailure end
		if doorway == nil or center == nil or locked == nil or requiredItemId == nil then
			return failure("invalid_door")
		end
		local root = getRoot(player)
		if root == nil then return failure("invalid_door") end
		local offset = root.Position - center.WorldPosition
		if offset.Magnitude > MAX_DISTANCE then return failure("too_far") end
		local signedDistance = offset:Dot(center.WorldCFrame.XVector)
		if math.abs(signedDistance) <= SIDE_EPSILON then return failure("ambiguous_side") end
		if busy[door] then return failure("busy") end
		busy[door] = true

		local result: DoorActionResult = failure("invalid_door")
		local ok = pcall(function()
			if request.action == "unlock" then
				if not locked then
					result = failure("already_unlocked")
					return
				end
				local itemResult = itemUseService:use(player, {
					capability = "unlock",
					context = { requiredItemId = requiredItemId },
				})
				if not itemResult.success then
					result = failure("missing_item")
					return
				end
				door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, false)
				result = { success = true, action = "unlock" }
				return
			end
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
		busy[door] = nil
		if not ok then return failure("invalid_door") end
		return result
	end

	function service:start(): ()
		if started then return end
		started = true
		for _, door in CollectionService:GetTagged(doorTypes.DOOR_TAG) do
			if not door:IsA("Model") then
				warn("Door tag must be on a Model")
			end
		end
		callback = function(player: Player, request: any): DoorActionResult
			return service:invoke(player, request)
		end
		interactDoor.OnServerInvoke = callback
	end

	function service:stop(): ()
		if not started then return end
		interactDoor.OnServerInvoke = nil
		callback = nil
		started = false
		table.clear(busy)
	end

	function service:invoke(player: Player, request: any): DoorActionResult
		return handle(player, request)
	end

	return service
end

return DoorService
