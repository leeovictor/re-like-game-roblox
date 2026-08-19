--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

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

local CHARACTER_DELAY = 0.01
local CONFIRM_ACTION = "DungeonDialogueConfirm"
local CANCEL_ACTION = "DungeonDialogueCancel"
local PREVIOUS_ACTION = "DungeonDialoguePrevious"
local NEXT_ACTION = "DungeonDialogueNext"
local ACTIONS = { CONFIRM_ACTION, CANCEL_ACTION, PREVIOUS_ACTION, NEXT_ACTION }
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1

local changed = (Signal.new() :: any) :: ChangedSignal
local state: DialogState? = nil
local activeCallback: ActiveCallback? = nil
local started = false
local generation = 0

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

local function publish(nextState: DialogState?): ()
	state = nextState
	changed:Fire(nextState)
end

local function unbindActions(): ()
	for _, actionName in ACTIONS do
		ContextActionService:UnbindAction(actionName)
	end
end

local function closeCurrent(optionId: string?, reason: DialogReason): ()
	if state == nil then
		return
	end

	generation += 1
	local callback = activeCallback
	activeCallback = nil
	unbindActions()
	publish(nil)
	if callback ~= nil then
		callback(optionId, reason)
	end
end

local function reveal(): ()
	local current = state
	if current == nil or not current.isTyping then
		return
	end

	publish({
		kind = current.kind,
		text = current.text,
		visibleText = current.text,
		isTyping = false,
		options = current.options,
		selectedIndex = current.selectedIndex,
	})
end

local function startTyping(text: string, dialogGeneration: number): ()
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
			local current = state
			if generation ~= dialogGeneration or current == nil or not current.isTyping then
				return
			end
			local visibleText = string.sub(text, 1, boundaries[index] - 1)
			local isTyping = index < #boundaries
			publish({
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

local function handleAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end

	local current = state
	if current == nil then
		return Enum.ContextActionResult.Sink
	end

	if actionName == CONFIRM_ACTION then
		if current.isTyping then
			reveal()
		elseif current.kind == "message" then
			closeCurrent(nil, "completed")
		else
			local selected = current.options[current.selectedIndex :: number]
			closeCurrent(selected.id, "completed")
		end
	elseif actionName == CANCEL_ACTION then
		closeCurrent(nil, "cancelled")
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
		publish(nextState)
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
		publish(nextState)
	end

	return Enum.ContextActionResult.Sink
end

local function bindActions(): ()
	ContextActionService:BindActionAtPriority(CONFIRM_ACTION, handleAction, false, ACTION_PRIORITY, Enum.KeyCode.F)
	ContextActionService:BindActionAtPriority(CANCEL_ACTION, handleAction, false, ACTION_PRIORITY, Enum.KeyCode.Escape)
	ContextActionService:BindActionAtPriority(PREVIOUS_ACTION, handleAction, false, ACTION_PRIORITY, Enum.KeyCode.A)
	ContextActionService:BindActionAtPriority(NEXT_ACTION, handleAction, false, ACTION_PRIORITY, Enum.KeyCode.D)
end

export type DialogueController = {
	start: () -> (),
	stop: () -> (),
	getState: () -> DialogState?,
	show: (text: string, callback: ShowCallback?) -> (),
	ask: (text: string, options: { DialogOption }, callback: AskCallback?) -> (),
	changed: typeof(changed),
}

local controller = { changed = changed } :: DialogueController

function controller.start(): ()
	if started then
		return
	end
	started = true
end

function controller.stop(): ()
	if not started and state == nil then
		unbindActions()
		return
	end

	started = false
	if state ~= nil then
		closeCurrent(nil, "cancelled")
	else
		unbindActions()
	end
end

function controller.getState(): DialogState?
	return state
end

function controller.show(text: string, callback: ShowCallback?): ()
	if not started then
		return
	end

	local validatedText = validateText(text, "text")
	local hadState = state ~= nil
	local previousGeneration = generation
	closeCurrent(nil, "replaced")
	if (hadState and generation ~= previousGeneration + 1) or state ~= nil then
		return
	end

	activeCallback = callback :: any
	local dialogGeneration = generation
	publish({
		kind = "message",
		text = validatedText,
		visibleText = "",
		isTyping = true,
		options = {},
		selectedIndex = nil,
	})
	bindActions()
	startTyping(validatedText, dialogGeneration)
end

function controller.ask(text: string, options: { DialogOption }, callback: AskCallback?): ()
	if not started then
		return
	end

	local validatedText = validateText(text, "text")
	local validatedOptions = validateOptions(options)
	local hadState = state ~= nil
	local previousGeneration = generation
	closeCurrent(nil, "replaced")
	if (hadState and generation ~= previousGeneration + 1) or state ~= nil then
		return
	end

	activeCallback = callback :: any
	local dialogGeneration = generation
	publish({
		kind = "question",
		text = validatedText,
		visibleText = "",
		isTyping = true,
		options = validatedOptions,
		selectedIndex = 1,
	})
	bindActions()
	startTyping(validatedText, dialogGeneration)
end

return controller
