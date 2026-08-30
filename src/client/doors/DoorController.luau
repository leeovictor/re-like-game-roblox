--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local modelProfiles = require(ReplicatedStorage.Shared.modelProfiles)
local GameplayEvents = require(StarterPlayer.StarterPlayerScripts.Client.events.GameplayEvents)
local CharacterRoot = require(StarterPlayer.StarterPlayerScripts.Client.player.CharacterRoot)
local DoorManager = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorManager)
local DialogueController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)
local TankController = require(StarterPlayer.StarterPlayerScripts.Client.player.TankController)
local TransitionController = require(StarterPlayer.StarterPlayerScripts.Client.doors.TransitionController)
local DoorSoundPlayer = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorSoundPlayer)

local DoorController = {}
DoorController.__index = DoorController

type InteractionHandler = interactionTypes.InteractionHandler

export type Dependencies = {
	manager: DoorManager.DoorManager,
	dialogue: DialogueController.DialogueController,
	movement: TankController.MovementController,
	transition: TransitionController.TransitionController,
}

function DoorController.new(dependencies: Dependencies): InteractionHandler
	local warnedDoors: { [Model]: boolean } = {}
	local doorSounds = DoorSoundPlayer.new()

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

	local function showDoorDialogue(door: Model, folderName: string, fallback: string, onCompleted: () -> ()): ()
		local folder = door:FindFirstChild(folderName)
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
			messages = { { name = "", text = fallback } }
		end

		InputManager.switchContext('DialogueContext')
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
				onCompleted()
				InputManager.switchContext('PlayContext')
			end
		end

		dependencies.dialogue:show(messages[1].text, nextMessage)
	end

	local function showLockedDialogue(door: Model): ()
		showDoorDialogue(door, doorTypes.LOCKED_DIALOGUE_NAME, doorTypes.FALLBACK_LOCKED_MESSAGE, function()
			publishDoorEvent(door, "door_blocked")
		end)
	end

	local function showSealedDialogue(door: Model): ()
		showDoorDialogue(door, doorTypes.SEALED_DIALOGUE_NAME, doorTypes.FALLBACK_SEALED_MESSAGE, function()
			publishDoorEvent(door, "door_blocked")
		end)
	end

	local controller = {} :: InteractionHandler

	function controller.interact(target: Instance): ()
		if not target:IsA("Model") then
			return
		end
		local door = target
		local sealed, sealedReason = dependencies.manager:isSealed(door)
		if sealed == nil or sealedReason ~= nil then
			return
		end
		if sealed then
			doorSounds:playOneShot("locked")
			showSealedDialogue(door)
			return
		end

		local locked, reason = dependencies.manager:isLocked(door)
		if locked == nil or reason ~= nil then
			return
		end

		if not locked then
			local stopTransitionOpenSound: DoorSoundPlayer.StopPlayback? = nil
			local stopTransitionCloseSound: DoorSoundPlayer.StopPlayback? = nil
			local transitionCloseDuration = doorSounds:getDuration("transitionClose")
			InputManager.disable()
			local accepted = dependencies.transition.run(function()
				local result = dependencies.manager:enter(door)
				if result.success and result.action == "enter" then
					local root = CharacterRoot.get()
					if root ~= nil then
						dependencies.movement:setCFrame(root.CFrame)
					end
				end
				if stopTransitionOpenSound ~= nil then
					stopTransitionOpenSound()
					stopTransitionOpenSound = nil
				end
				return result
			end, function(result)
				if stopTransitionOpenSound ~= nil then
					stopTransitionOpenSound()
					stopTransitionOpenSound = nil
				end
				if stopTransitionCloseSound ~= nil then
					stopTransitionCloseSound()
					InputManager.enable()
					stopTransitionCloseSound = nil
				end
				if result.reason == "missing_item" then
					showLockedDialogue(door)
				elseif result.reason == "sealed" then
					showSealedDialogue(door)
				elseif result.success and result.action == "enter" then
					publishDoorEvent(door, "door_entered")
				end
			end, function(fadeOutDuration, result)
				if result.success and result.action == "enter" then
					stopTransitionCloseSound = doorSounds:startAtEnd("transitionClose", fadeOutDuration)
				end
			end, transitionCloseDuration)
			if accepted then
				stopTransitionOpenSound = doorSounds:start("transitionOpen")
			end
			return
		end

		local result = dependencies.manager:unlock(door)
		if result.success and result.action == "unlock" then
			doorSounds:playOneShot("unlocked")
			modelProfiles.setProfile(door, 'unlocked')
			InputManager.switchContext("DialogueContext")
			dependencies.dialogue:show("Porta destrancada.", function (_, dialogueReason)
				if dialogueReason == "completed" then
					publishDoorEvent(door, "door_unlocked")
					InputManager.switchContext("PlayContext")
				end
			end)
		elseif result.reason == "missing_item" then
			doorSounds:playOneShot("locked")
			showLockedDialogue(door)
		elseif result.reason == "sealed" then
			doorSounds:playOneShot("locked")
			showSealedDialogue(door)
		end
		return
	end

	return controller
end

return DoorController
