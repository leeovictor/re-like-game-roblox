--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local ACTION_NAME = "DungeonInteraction"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
local DEBUG_ENABLED = true
local DEFAULT_CONFIG: interactionTypes.ProbeConfig = {
	radius = 3,
	forwardOffset = 2.5,
}

type ControllerState = interactionTypes.Controller & {
	interact: (actionName: string, inputState: Enum.UserInputState, inputObject: InputObject?) -> Enum.ContextActionResult,
	_debugConnection: RBXScriptConnection?,
	_debugPart: Part?,
}

local function createController(probeConfig: interactionTypes.ProbeConfig?): interactionTypes.Controller
	local config = {
		radius = if probeConfig then probeConfig.radius else DEFAULT_CONFIG.radius,
		forwardOffset = if probeConfig then probeConfig.forwardOffset else DEFAULT_CONFIG.forwardOffset,
	}
	local started = false
	local enabled = true
	local target: Instance? = nil
	local handlers: { [string]: interactionTypes.InteractionHandler } = {}
	local warned: { [Instance]: { [string]: boolean } } = {}
	local debugConnection: RBXScriptConnection? = nil
	local debugPart: Part? = nil

		local function warnOnce(instance: Instance, code: string, message: string): ()
			local instanceWarnings = warned[instance]
			if instanceWarnings == nil then
				instanceWarnings = {}
				warned[instance] = instanceWarnings
			end
			if not instanceWarnings[code] then
				instanceWarnings[code] = true
				warn(message)
			end
		end

		local function resolveRoot(part: BasePart): (Instance?, string?)
			local current: Instance? = part
			while current ~= nil do
				local hasInteractable = CollectionService:HasTag(current, interactionTypes.INTERACTABLE_TAG)
				local interactionType = current:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE)
				local itemId = current:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)
				local legacyDoor = CollectionService:HasTag(current, interactionTypes.DOOR_TYPE)

				if hasInteractable then
					if current:IsA("Model") or current:IsA("BasePart") then
						if interactionType == interactionTypes.DOOR_TYPE or interactionType == interactionTypes.PICKUP_TYPE then
							return current, interactionType :: string
						end
						warnOnce(current, "invalid-type", string.format("Interactable has invalid InteractionType: %s", current:GetFullName()))
					end
				elseif interactionType ~= nil then
					warnOnce(current, "type-without-tag", string.format("InteractionType without Interactable tag: %s", current:GetFullName()))
				elseif itemId ~= nil then
					warnOnce(current, "item-without-tag", string.format("ItemId without Interactable tag: %s", current:GetFullName()))
				elseif legacyDoor then
					warnOnce(current, "legacy-door", string.format("Legacy Door tag without interaction contract: %s", current:GetFullName()))
				end

				current = current.Parent
			end
			return nil, nil
		end

		local function probe(): (Instance?, string?)
			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if character == nil or root == nil or not root:IsA("BasePart") then
				return nil, nil
			end

			local center = root.Position + root.CFrame.LookVector * config.forwardOffset
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local parts = Workspace:GetPartBoundsInRadius(center, config.radius, params)
			local distances: { [Instance]: number } = {}
			local roots: { Instance } = {}
			local types: { [Instance]: string } = {}

			for _, part in parts do
				local resolved, interactionType = resolveRoot(part)
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

		local function handleAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject?): Enum.ContextActionResult
			if inputState ~= Enum.UserInputState.Begin or not enabled then
				return Enum.ContextActionResult.Sink
			end

			local selected, interactionType = probe()
			target = selected
			if selected == nil or interactionType == nil then
				return Enum.ContextActionResult.Sink
			end

			local handler = handlers[interactionType]
			if handler == nil then
				warnOnce(selected, "missing-handler", string.format("No handler for %s: %s", interactionType, selected:GetFullName()))
			else
				handler.interact(selected)
			end
			return Enum.ContextActionResult.Sink
		end

		local function bind(): ()
			if started and enabled then
				ContextActionService:BindActionAtPriority(ACTION_NAME, handleAction, false, ACTION_PRIORITY, Enum.KeyCode.F)
			end
		end

		local controller = {} :: ControllerState
		function controller.start(): ()
			if started then
				return
			end
			started = true
			bind()
			if DEBUG_ENABLED then
				local part = Instance.new("Part")
				part.Shape = Enum.PartType.Ball
				part.Anchored = true
				part.CanCollide = false
				part.Transparency = 0.8
				part.Size = Vector3.new(config.radius * 2, config.radius * 2, config.radius * 2)
				part.Parent = Workspace
				debugPart = part
				debugConnection = RunService.Heartbeat:Connect(function()
					local character = Players.LocalPlayer.Character
					local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
					if root ~= nil and root:IsA("BasePart") and debugPart ~= nil then
						debugPart.Position = root.Position + root.CFrame.LookVector * config.forwardOffset
					end
				end)
			end
		end

		-- Expose the callback for tests because GetAllBoundActionInfo omits it.
		controller.interact = handleAction

		function controller.stop(): ()
			started = false
			ContextActionService:UnbindAction(ACTION_NAME)
			target = nil
			warned = {}
			if debugConnection ~= nil then
				debugConnection:Disconnect()
				debugConnection = nil
			end
			if debugPart ~= nil then
				debugPart:Destroy()
				debugPart = nil
			end
		end

		function controller.register(interactionType: string, handler: interactionTypes.InteractionHandler): ()
			handlers[interactionType] = handler
		end

		function controller.setEnabled(nextEnabled: boolean): ()
			enabled = nextEnabled
			if not enabled then
				ContextActionService:UnbindAction(ACTION_NAME)
				target = nil
			elseif started then
				bind()
			end
		end

		function controller.isEnabled(): boolean
			return enabled
		end

		function controller.getTarget(): Instance?
			return target
		end

		return controller
end

local defaultController = createController(nil)

return {
	new = createController,
	start = defaultController.start,
	stop = defaultController.stop,
	register = defaultController.register,
	setEnabled = defaultController.setEnabled,
	isEnabled = defaultController.isEnabled,
	getTarget = defaultController.getTarget,
}
