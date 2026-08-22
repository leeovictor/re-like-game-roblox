--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local items = require(ReplicatedStorage.Shared.inventory.items)
local remotes = require(ReplicatedStorage.Shared.remotes)
local DialogueController = require(script.Parent.Parent.dialogue.DialogueController)
local InventoryController = require(script.Parent.Parent.inventory.InventoryController)
local TransitionController = require(script.Parent.TransitionController)

type InventoryState = items.InventoryState
type DoorRequest = doorTypes.DoorRequest
type DoorActionResult = doorTypes.DoorActionResult
type InteractionHandler = interactionTypes.InteractionHandler

export type Dependencies = {
	getInventory: () -> InventoryState?,
	invokeDoor: (request: DoorRequest) -> DoorActionResult,
	dialogue: {
		show: (text: string, callback: ((nil, string) -> ())?) -> (),
	},
	transition: {
		run: (request: () -> DoorActionResult, callback: (result: DoorActionResult) -> ()) -> boolean,
	},
}

local function createController(dependencies: Dependencies): InteractionHandler
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
				end
			end)
			return
		end

		local requiredItemId = door:GetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE)
		if type(requiredItemId) == "string" and requiredItemId ~= "" and hasItem(requiredItemId) then
			local result = dependencies.invokeDoor({ door = door, action = "unlock" })
			if result.success and result.action == "unlock" then
				dependencies.dialogue.show("Porta destrancada.")
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
