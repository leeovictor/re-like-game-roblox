--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)
local DoorManager = require(script.Parent.DoorManager)
local DialogueController = require(script.Parent.Parent.dialogue.DialogueController)
local TransitionController = require(script.Parent.TransitionController)

local DoorController = {}
DoorController.__index = DoorController

type InteractionHandler = interactionTypes.InteractionHandler

export type Dependencies = {
	manager: DoorManager.DoorManager,
	dialogue: DialogueController.DialogueController,
	transition: TransitionController.TransitionController,
}

function DoorController.new(dependencies: Dependencies): InteractionHandler
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
			GameplayEvents.emit({ name = "door_blocked", doorKey = doorKey })
		elseif eventName == "door_unlocked" then
			GameplayEvents.emit({ name = "door_unlocked", doorKey = doorKey })
		else
			GameplayEvents.emit({ name = "door_entered", doorKey = doorKey })
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
					dependencies.dialogue:show(message.text, nextMessage)
			else
				publishDoorEvent(door, "door_blocked")
			end
		end

		dependencies.dialogue:show(messages[1].text, nextMessage)
	end

	local controller = {} :: InteractionHandler

	function controller.interact(target: Instance): ()
		if not target:IsA("Model") then
			return
		end
		local door = target

		local locked, reason = dependencies.manager:isLocked(door)
		if locked == nil or reason ~= nil then
			return
		end

		if not locked then
			dependencies.transition.run(function()
				return dependencies.manager:enter(door)
			end, function(result)
				if result.reason == "missing_item" then
					showLockedDialogue(door)
				elseif result.success and result.action == "enter" then
					publishDoorEvent(door, "door_entered")
				end
			end)
			return
		end

		local result = dependencies.manager:unlock(door)
		if result.success and result.action == "unlock" then
			dependencies.dialogue:show("Porta destrancada.", function (_, dialogueReason)
				if dialogueReason == "completed" then
					publishDoorEvent(door, "door_unlocked")
				end
			end)
		elseif result.reason == "missing_item" then
			showLockedDialogue(door)
		end
		return
	end

	return controller
end

return DoorController
