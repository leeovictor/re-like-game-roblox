--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local items = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local DialogueController = require(script.Parent.Parent.dialogue.DialogueController)
local InventoryController = require(script.Parent.Parent.inventory.InventoryController)
local TransitionController = require(script.Parent.TransitionController)

type InventoryState = items.InventoryState
type DialogState = DialogueController.DialogState
type DoorRequest = doorTypes.DoorRequest
type DoorActionResult = doorTypes.DoorActionResult

export type Dependencies = {
	getInventory: () -> InventoryState?,
	invokeDoor: (request: DoorRequest) -> DoorActionResult,
	dialogue: {
		getState: () -> DialogState?,
		show: (text: string, callback: ((nil, string) -> ())?) -> (),
	},
	transition: {
		run: (request: () -> DoorActionResult, callback: (result: DoorActionResult) -> ()) -> boolean,
	},
}

local ACTION_NAME = "DungeonDoorInteract"
local PROBE_OFFSET = 2.5
local SPHERE_RADIUS = 2
local SPHERE_CLEARANCE = 0.1
local SPHERECAST_DISTANCE = PROBE_OFFSET + SPHERE_RADIUS + SPHERE_CLEARANCE

local function createController(dependencies: Dependencies)
	local started = false
	local target: Model? = nil

	local function findDoor(instance: Instance?): Model?
		local current = instance
		while current ~= nil do
			if current:IsA("Model") and CollectionService:HasTag(current, doorTypes.DOOR_TAG) then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	local function scan(): ()
		local currentCharacter = Players.LocalPlayer.Character
		if currentCharacter == nil then
			target = nil
			return
		end
		local root = currentCharacter:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			target = nil
			return
		end
		local lookVector = root.CFrame.LookVector
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { currentCharacter }
		local origin = root.Position - lookVector * (SPHERE_RADIUS + SPHERE_CLEARANCE)
		local result = workspace:Spherecast(origin, SPHERE_RADIUS, lookVector * SPHERECAST_DISTANCE, params)
		target = if result ~= nil then findDoor(result.Instance) else nil
	end

	local function showLockedDialogue(door: Model): ()
		local folder = door:FindFirstChild(doorTypes.LOCKED_DIALOGUE_NAME)
		local messages: { { name: string, text: string } } = {}
		if folder ~= nil then
			for _, child in folder:GetChildren() do
				if child:IsA("StringValue") and child.Value ~= "" then
					table.insert(messages, { name = child.Name, text = child.Value })
				end
			end
			table.sort(messages, function(left, right)
				return left.name < right.name
			end)
		end
		if #messages == 0 then
			messages = { { name = "", text = doorTypes.FALLBACK_LOCKED_MESSAGE } }
		end
		local index = 1
		local function nextMessage(_: nil, reason: string): ()
			if reason ~= "completed" then
				return
			end
			index += 1
			if messages[index] ~= nil then
				dependencies.dialogue.show(messages[index].text, nextMessage)
			end
		end
		dependencies.dialogue.show(messages[1].text, nextMessage)
	end

	local function hasItem(itemId: string): boolean
		local inventory = dependencies.getInventory()
		if inventory == nil then
			return false
		end
		for _, item in inventory.items do
			if item.itemId == itemId then
				return true
			end
		end
		return false
	end

	local function interact(_: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		scan()
		if dependencies.dialogue.getState() ~= nil then
			return Enum.ContextActionResult.Sink
		end
		local door = target
		if door == nil then
			return Enum.ContextActionResult.Sink
		end
		local locked = door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)
		if locked ~= true then
			dependencies.transition.run(function()
				return dependencies.invokeDoor({ door = door :: Model, action = "enter" })
			end, function(result)
				if result.reason == "missing_item" then
					showLockedDialogue(door :: Model)
				end
			end)
			return Enum.ContextActionResult.Sink
		end
		local requiredItemId = door:GetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE)
		if type(requiredItemId) == "string" and requiredItemId ~= "" and hasItem(requiredItemId) then
			local result = dependencies.invokeDoor({ door = door, action = "unlock" })
			if result.success and result.action == "unlock" then
				dependencies.dialogue.show("Porta destrancada")
			elseif result.reason == "missing_item" then
				showLockedDialogue(door)
			end
		else
			showLockedDialogue(door)
		end
		return Enum.ContextActionResult.Sink
	end

	local controller = {}
	function controller.start(): ()
		if started then return end
		started = true
		ContextActionService:BindActionAtPriority(ACTION_NAME, interact, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F)
	end

	function controller.stop(): ()
		if not started then return end
		started = false
		ContextActionService:UnbindAction(ACTION_NAME)
		target = nil
	end

	function controller.getTarget(): Model?
		return target
	end

	controller.interact = interact

	return controller
end

local defaultDependencies: Dependencies = {
	getInventory = InventoryController.getState,
	invokeDoor = function(request)
		local remote = remotes.InteractDoor
		if not remote:IsA("RemoteFunction") then
			return { success = false, reason = "invalid_config" }
		end
		return remote:InvokeServer(request) :: DoorActionResult
	end,
	dialogue = {
		getState = DialogueController.getState,
		show = DialogueController.show,
	},
	transition = TransitionController,
}

local defaultController = createController(defaultDependencies)
return {
	new = createController,
	start = defaultController.start,
	stop = defaultController.stop,
	getTarget = defaultController.getTarget,
}
