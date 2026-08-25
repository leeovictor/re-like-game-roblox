--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
local Signal = require(ReplicatedStorage.Packages.Signal)
local TankController = require(script.Parent.Parent.player.TankController)

export type DialogReason = "completed" | "cancelled" | "replaced"

export type DialogOption = {
	id: string,
	text: string,
}

export type DialogState = {
	kind: "message" | "question",
	text: string,
	visibleText: string,
	isTyping: boolean,
	options: { DialogOption },
	selectedIndex: number?,
}

export type ShowCallback = (value: nil, reason: DialogReason) -> ()
export type AskCallback = (optionId: string?, reason: DialogReason) -> ()

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, nextState: DialogState?) -> (),
	Connect: (self: ChangedSignal, callback: (nextState: DialogState?) -> ()) -> SignalConnection,
}
type ActiveCallback = (optionId: string?, reason: DialogReason) -> ()

local CHARACTER_DELAY = 0.02
local CONFIRM_ACTION = "DungeonDialogueConfirm"
local CANCEL_ACTION = "DungeonDialogueCancel"
local PREVIOUS_ACTION = "DungeonDialoguePrevious"
local NEXT_ACTION = "DungeonDialogueNext"
local ACTIONS = { CONFIRM_ACTION, CANCEL_ACTION, PREVIOUS_ACTION, NEXT_ACTION }
local ACTION_PRIORITY = ActionPriorities.DIALOGUE

export type Dependencies = {
	movement: TankController.MovementController,
}

export type DialogueController = {
	dependencies: Dependencies,
	changed: ChangedSignal,
	state: DialogState?,
	activeCallback: ActiveCallback?,
	movementRelease: (() -> ())?,
	started: boolean,
	generation: number,
	start: (self: DialogueController) -> (),
	stop: (self: DialogueController) -> (),
	getState: (self: DialogueController) -> DialogState?,
	show: (self: DialogueController, text: string, callback: ShowCallback?) -> (),
	ask: (self: DialogueController, text: string, options: { DialogOption }, callback: AskCallback?) -> (),
}

local DialogueController = {}
DialogueController.__index = DialogueController

local function validateText(value: any, label: string): string
	if type(value) ~= "string" or value == "" then
		error(label .. " must be a non-empty string", 3)
	end
	return value
end

local function validateOptions(value: any): { DialogOption }
	if type(value) ~= "table" or #value == 0 then
		error("options must contain at least one option", 3)
	end

	local ids: { [string]: boolean } = {}
	local copy: { DialogOption } = {}
	for index, option in value do
		if type(option) ~= "table" then
			error(string.format("options[%d] must be a table", index), 3)
		end
		local id = validateText(option.id, string.format("options[%d].id", index))
		local text = validateText(option.text, string.format("options[%d].text", index))
		if ids[id] then
			error("option ids must be unique", 3)
		end
		ids[id] = true
		table.insert(copy, { id = id, text = text })
	end
	return copy
end

local function publish(self: DialogueController, nextState: DialogState?): ()
	self.state = nextState
	self.changed:Fire(nextState)
end

local function unbindActions(): ()
	for _, actionName in ACTIONS do
		ContextActionService:UnbindAction(actionName)
	end
end

local function closeCurrent(self: DialogueController, optionId: string?, reason: DialogReason): ()
	local release = self.movementRelease
	self.movementRelease = nil
	if release ~= nil then
		release()
	end

	if self.state == nil then
		return
	end

	self.generation += 1
	local callback = self.activeCallback
	self.activeCallback = nil
	unbindActions()
	publish(self, nil)
	if callback ~= nil then
		callback(optionId, reason)
	end
end

local function reveal(self: DialogueController): ()
	local current = self.state
	if current == nil or not current.isTyping then
		return
	end

	publish(self, {
		kind = current.kind,
		text = current.text,
		visibleText = current.text,
		isTyping = false,
		options = current.options,
		selectedIndex = current.selectedIndex,
	})
end

local function startTyping(self: DialogueController, text: string, dialogGeneration: number): ()
	task.spawn(function()
		local boundaries = { 1 }
		for byteIndex in utf8.codes(text) do
			if byteIndex > 1 then
				table.insert(boundaries, byteIndex)
			end
		end
		table.insert(boundaries, #text + 1)

		for index = 2, #boundaries do
			task.wait(CHARACTER_DELAY)
			local current = self.state
			if self.generation ~= dialogGeneration or current == nil or not current.isTyping then
				return
			end
			local visibleText = string.sub(text, 1, boundaries[index] - 1)
			local isTyping = index < #boundaries
			publish(self, {
				kind = current.kind,
				text = current.text,
				visibleText = visibleText,
				isTyping = isTyping,
				options = current.options,
				selectedIndex = current.selectedIndex,
			})
		end
	end)
end

local function handleAction(self: DialogueController, actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end

	local current = self.state
	if current == nil then
		return Enum.ContextActionResult.Sink
	end

	if actionName == CONFIRM_ACTION then
		if current.isTyping then
			reveal(self)
		elseif current.kind == "message" then
			closeCurrent(self, nil, "completed")
		else
			local selected = current.options[current.selectedIndex :: number]
			closeCurrent(self, selected.id, "completed")
		end
	elseif actionName == CANCEL_ACTION then
		closeCurrent(self, nil, "cancelled")
	elseif actionName == PREVIOUS_ACTION and current.kind == "question" and not current.isTyping then
		local selectedIndex = math.max(1, (current.selectedIndex :: number) - 1)
		local nextState: DialogState = {
			kind = current.kind,
			text = current.text,
			visibleText = current.visibleText,
			isTyping = current.isTyping,
			options = current.options,
			selectedIndex = selectedIndex,
		}
		publish(self, nextState)
	elseif actionName == NEXT_ACTION and current.kind == "question" and not current.isTyping then
		local selectedIndex = math.min(#current.options, (current.selectedIndex :: number) + 1)
		local nextState: DialogState = {
			kind = current.kind,
			text = current.text,
			visibleText = current.visibleText,
			isTyping = current.isTyping,
			options = current.options,
			selectedIndex = selectedIndex,
		}
		publish(self, nextState)
	end

	return Enum.ContextActionResult.Sink
end

local function bindActions(self: DialogueController): ()
	local callback = function(actionName, inputState, inputObject)
		return handleAction(self, actionName, inputState, inputObject)
	end
	ContextActionService:BindActionAtPriority(CONFIRM_ACTION, callback, false, ACTION_PRIORITY, Enum.KeyCode.F)
	ContextActionService:BindActionAtPriority(CANCEL_ACTION, callback, false, ACTION_PRIORITY, Enum.KeyCode.Escape)
	ContextActionService:BindActionAtPriority(PREVIOUS_ACTION, callback, false, ACTION_PRIORITY, Enum.KeyCode.A)
	ContextActionService:BindActionAtPriority(NEXT_ACTION, callback, false, ACTION_PRIORITY, Enum.KeyCode.D)
end

function DialogueController.new(dependencies: Dependencies): DialogueController
	local self = setmetatable({
		dependencies = dependencies,
		changed = (Signal.new() :: any) :: ChangedSignal,
		state = nil,
		activeCallback = nil,
		movementRelease = nil,
		started = false,
		generation = 0,
	}, DialogueController)
	return (self :: any) :: DialogueController
end

function DialogueController.start(self: DialogueController): ()
	if self.started then
		return
	end
	self.started = true
end

function DialogueController.stop(self: DialogueController): ()
	if not self.started and self.state == nil then
		unbindActions()
		return
	end

	self.started = false
	if self.state ~= nil then
		closeCurrent(self, nil, "cancelled")
	else
		unbindActions()
	end
end

function DialogueController.getState(self: DialogueController): DialogState?
	return self.state
end

function DialogueController.show(self: DialogueController, text: string, callback: ShowCallback?): ()
	if not self.started then
		return
	end

	local validatedText = validateText(text, "text")
	local hadState = self.state ~= nil
	local previousGeneration = self.generation
	closeCurrent(self, nil, "replaced")
	if (hadState and self.generation ~= previousGeneration + 1) or self.state ~= nil then
		return
	end

	self.activeCallback = callback :: any
	local dialogGeneration = self.generation
	self.movementRelease = self.dependencies.movement:acquireMovementLock()
	publish(self, {
		kind = "message",
		text = validatedText,
		visibleText = "",
		isTyping = true,
		options = {},
		selectedIndex = nil,
	})
	bindActions(self)
	startTyping(self, validatedText, dialogGeneration)
end

function DialogueController.ask(self: DialogueController, text: string, options: { DialogOption }, callback: AskCallback?): ()
	if not self.started then
		return
	end

	local validatedText = validateText(text, "text")
	local validatedOptions = validateOptions(options)
	local hadState = self.state ~= nil
	local previousGeneration = self.generation
	closeCurrent(self, nil, "replaced")
	if (hadState and self.generation ~= previousGeneration + 1) or self.state ~= nil then
		return
	end

	self.activeCallback = callback :: any
	local dialogGeneration = self.generation
	self.movementRelease = self.dependencies.movement:acquireMovementLock()
	publish(self, {
		kind = "question",
		text = validatedText,
		visibleText = "",
		isTyping = true,
		options = validatedOptions,
		selectedIndex = 1,
	})
	bindActions(self)
	startTyping(self, validatedText, dialogGeneration)
end

return DialogueController
