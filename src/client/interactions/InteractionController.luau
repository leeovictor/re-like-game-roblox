--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local ACTION_NAME = "DungeonInteraction"
local ACTION_PRIORITY = ActionPriorities.INTERACTION
local DEBUG_ENABLED = false
local DEFAULT_CONFIG: interactionTypes.ProbeConfig = {
	size = Vector3.new(3, 7, 2),
	forwardOffset = 2,
}

export type Dependencies = {}
type InteractionType = interactionTypes.InteractionType

export type InteractionController = {
	dependencies: Dependencies?,
	config: interactionTypes.ProbeConfig,
	started: boolean,
	enabled: boolean,
	target: Instance?,
	handlers: { [string]: interactionTypes.InteractionHandler },
	warned: { [Instance]: { [string]: boolean } },
	debugConnection: RBXScriptConnection?,
	debugPart: Part?,
	start: (self: InteractionController) -> (),
	stop: (self: InteractionController) -> (),
	register: (self: InteractionController, interactionType: InteractionType, handler: interactionTypes.InteractionHandler) -> (),
	setEnabled: (self: InteractionController, enabled: boolean) -> (),
	isEnabled: (self: InteractionController) -> boolean,
	getTarget: (self: InteractionController) -> Instance?,
	handleAction: (self: InteractionController, actionName: string, inputState: Enum.UserInputState, inputObject: InputObject?) -> Enum.ContextActionResult,
}

local InteractionController = {}
InteractionController.__index = InteractionController

local function parseInteractionType(value: any): string?
	if value == interactionTypes.DOOR_TYPE then
		return "Door"
	elseif value == interactionTypes.PICKUP_TYPE then
		return "Pickup"
	elseif value == interactionTypes.DIALOGUE_TYPE then
		return "Dialogue"
	end
	if value == interactionTypes.SWITCH_TYPE then
		return "Switch"
	end
	return nil
end

local function warnOnce(self: InteractionController, instance: Instance, code: string, message: string): ()
	local instanceWarnings = self.warned[instance]
	if instanceWarnings == nil then
		instanceWarnings = {}
		self.warned[instance] = instanceWarnings
	end
	if not instanceWarnings[code] then
		instanceWarnings[code] = true
		warn(message)
	end
end

local function resolveRoot(self: InteractionController, part: BasePart): (Instance?, string?)
	local current: Instance? = part
	while current ~= nil do
		local hasInteractable = CollectionService:HasTag(current, interactionTypes.INTERACTABLE_TAG)
		local interactionTypeAttribute = current:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE)
		local interactionType = parseInteractionType(interactionTypeAttribute)
		local itemId = current:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)
		local legacyDoor = CollectionService:HasTag(current, interactionTypes.DOOR_TYPE)

		if hasInteractable then
			if (current:IsA("Model") or current:IsA("BasePart")) and interactionType ~= nil then
				return current, interactionType
			elseif current:IsA("Model") or current:IsA("BasePart") then
				warnOnce(self, current, "invalid-type", string.format("Interactable has invalid InteractionType: %s", current:GetFullName()))
			end
		elseif interactionTypeAttribute ~= nil then
			warnOnce(self, current, "type-without-tag", string.format("InteractionType without Interactable tag: %s", current:GetFullName()))
		elseif itemId ~= nil then
			warnOnce(self, current, "item-without-tag", string.format("ItemId without Interactable tag: %s", current:GetFullName()))
		elseif legacyDoor then
			warnOnce(self, current, "legacy-door", string.format("Legacy Door tag without interaction contract: %s", current:GetFullName()))
		end

		current = current.Parent
	end
	return nil, nil
end

local function probe(self: InteractionController): (Instance?, string?)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end

	local probeCFrame = root.CFrame * CFrame.new(0, 0, -self.config.forwardOffset)
	local center = probeCFrame.Position
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local parts = Workspace:GetPartBoundsInBox(probeCFrame, self.config.size, params)
	local distances: { [Instance]: number } = {}
	local roots: { Instance } = {}
	local types: { [Instance]: string } = {}

	for _, part in parts do
		local resolved, interactionType = resolveRoot(self, part)
		if resolved ~= nil and interactionType ~= nil then
			local distance = (part.Position - center).Magnitude
			if distances[resolved] == nil then
				table.insert(roots, resolved)
				distances[resolved] = distance
				types[resolved] = interactionType
			elseif distance < (distances[resolved] :: number) then
				distances[resolved] = distance
			end
		end
	end

	local selected: Instance? = nil
	local selectedType: string? = nil
	local selectedDistance: number? = nil
	for _, rootInstance in roots do
		local distance = distances[rootInstance] :: number
		if selectedDistance == nil or distance < selectedDistance then
			selected = rootInstance
			selectedType = types[rootInstance]
			selectedDistance = distance
		end
	end
	return selected, selectedType
end

local function bind(self: InteractionController): ()
	if self.started and self.enabled then
		ContextActionService:BindActionAtPriority(
			ACTION_NAME,
			function(actionName, inputState, inputObject)
				return self:handleAction(actionName, inputState, inputObject)
			end,
			false,
			ACTION_PRIORITY,
			Enum.KeyCode.E
		)
	end
end

function InteractionController.new(
	dependencies: Dependencies?,
	probeConfig: interactionTypes.ProbeConfig?
): InteractionController
	local sourceConfig = probeConfig or DEFAULT_CONFIG
	local self = setmetatable({
		dependencies = dependencies,
		config = {
			size = sourceConfig.size,
			forwardOffset = sourceConfig.forwardOffset,
		},
		started = false,
		enabled = true,
		target = nil,
		handlers = {},
		warned = {},
		debugConnection = nil,
		debugPart = nil,
	}, InteractionController)
	return (self :: any) :: InteractionController
end

function InteractionController.handleAction(
	self: InteractionController,
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject?
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not self.enabled then
		return Enum.ContextActionResult.Sink
	end

	local selected, interactionType = probe(self)
	self.target = selected
	if selected == nil or interactionType == nil then
		return Enum.ContextActionResult.Sink
	end

	local handler = self.handlers[interactionType]
	if handler == nil then
		warnOnce(self, selected, "missing-handler", string.format("No handler for %s: %s", interactionType, selected:GetFullName()))
	else
		handler.interact(selected)
	end
	return Enum.ContextActionResult.Sink
end

function InteractionController.start(self: InteractionController): ()
	if self.started then
		return
	end
	self.started = true
	bind(self)
	if DEBUG_ENABLED then
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.8
		part.Size = self.config.size
		part.Parent = Workspace
		self.debugPart = part
		self.debugConnection = RunService.Heartbeat:Connect(function()
			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root ~= nil and root:IsA("BasePart") and self.debugPart ~= nil then
				self.debugPart.CFrame = root.CFrame * CFrame.new(0, 0, -self.config.forwardOffset)
			end
		end)
	end
end

function InteractionController.stop(self: InteractionController): ()
	self.started = false
	ContextActionService:UnbindAction(ACTION_NAME)
	self.target = nil
	self.warned = {}
	if self.debugConnection ~= nil then
		self.debugConnection:Disconnect()
		self.debugConnection = nil
	end
	if self.debugPart ~= nil then
		self.debugPart:Destroy()
		self.debugPart = nil
	end
end

function InteractionController.register(
	self: InteractionController,
	interactionType: InteractionType,
	handler: interactionTypes.InteractionHandler
): ()
	self.handlers[interactionType] = handler
end

function InteractionController.setEnabled(self: InteractionController, nextEnabled: boolean): ()
	self.enabled = nextEnabled
	if not self.enabled then
		ContextActionService:UnbindAction(ACTION_NAME)
		self.target = nil
	elseif self.started then
		bind(self)
	end
end

function InteractionController.isEnabled(self: InteractionController): boolean
	return self.enabled
end

function InteractionController.getTarget(self: InteractionController): Instance?
	return self.target
end

return InteractionController
