--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local items = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local DialogueController = require(script.Parent.Parent.dialogue.DialogueController)
local InventoryController = require(script.Parent.Parent.inventory.InventoryController)
local TransitionController = require(script.Parent.TransitionController)
local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)

type InventoryState = items.InventoryState
type DoorRequest = doorTypes.DoorRequest
type DoorActionResult = doorTypes.DoorActionResult
type InteractionHandler = interactionTypes.InteractionHandler

export type Dependencies = {
	getInventory: () -> InventoryState?,
	invokeDoor: (request: DoorRequest) -> DoorActionResult,
	emit: (event: GameplayEvents.GameplayEvent) -> (),
	dialogue: {
		show: (text: string, callback: ((nil, string) -> ())?) -> (),
	},
	transition: {
		run: (request: () -> DoorActionResult, callback: (result: DoorActionResult) -> ()) -> boolean,
	},
}

local function createController(dependencies: Dependencies): InteractionHandler
	local warnedDoors: { [Model]: boolean } = {}

	local function publishDoorEvent(
		door: Model,
		eventName: "door_blocked" | "door_unlocked" | "door_entered"
	): ()
		local doorKey = door:GetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE)
		if type(doorKey) ~= "string" or doorKey == "" then
			if not warnedDoors[door] then
				warnedDoors[door] = true
				warn(string.format("Door has no valid DoorKey: %s", door:GetFullName()))
			end
			return
		end
		if eventName == "door_blocked" then
			dependencies.emit({ name = "door_blocked", doorKey = doorKey })
		elseif eventName == "door_unlocked" then
			dependencies.emit({ name = "door_unlocked", doorKey = doorKey })
		else
			dependencies.emit({ name = "door_entered", doorKey = doorKey })
		end
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
			local message = messages[index]
			if message ~= nil then
				dependencies.dialogue.show(message.text, nextMessage)
			else
				publishDoorEvent(door, "door_blocked")
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

	local controller = {} :: InteractionHandler

	function controller.interact(target: Instance): ()
		if not target:IsA("Model") then
			return
		end
		local door = target

		if door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE) == false then
			dependencies.transition.run(function()
				return dependencies.invokeDoor({ door = door, action = "enter" })
			end, function(result)
				if result.reason == "missing_item" then
					showLockedDialogue(door)
				elseif result.success and result.action == "enter" then
					publishDoorEvent(door, "door_entered")
				end
			end)
			return
		end

		local requiredItemId = door:GetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE)
		if type(requiredItemId) == "string" and requiredItemId ~= "" and hasItem(requiredItemId) then
			local result = dependencies.invokeDoor({ door = door, action = "unlock" })
			if result.success and result.action == "unlock" then
				dependencies.dialogue.show("Porta destrancada.", function ()
					publishDoorEvent(door, "door_unlocked")
				end)
			elseif result.reason == "missing_item" then
				showLockedDialogue(door)
			end
			return
		end

		showLockedDialogue(door)
	end

	return controller
end

local defaultDependencies: Dependencies = {
	getInventory = InventoryController.getState,
	emit = GameplayEvents.emit,
	invokeDoor = function(request)
		local remote = remotes.InteractDoor
		if not remote:IsA("RemoteFunction") then
			return { success = false, reason = "invalid_config" }
		end
		return remote:InvokeServer(request) :: DoorActionResult
	end,
	dialogue = {
		show = DialogueController.show,
	},
	transition = TransitionController,
}

local defaultController = createController(defaultDependencies)
return {
	new = createController,
	interact = defaultController.interact,
}
