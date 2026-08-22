--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TankControlMath = require(ReplicatedStorage.Shared.player.TankControlMath)

local ACTION_FORWARD = "DungeonTankForward"
local ACTION_BACKWARD = "DungeonTankBackward"
local ACTION_LEFT = "DungeonTankLeft"
local ACTION_RIGHT = "DungeonTankRight"
local ACTIONS = {
	ACTION_FORWARD,
	ACTION_BACKWARD,
	ACTION_LEFT,
	ACTION_RIGHT,
}

type InputState = {
	forward: boolean,
	backward: boolean,
	left: boolean,
	right: boolean,
}

local input: InputState = {
	forward = false,
	backward = false,
	left = false,
	right = false,
}

local started = false
local movementEnabled = true
local renderConnection: RBXScriptConnection? = nil
local inputEndedConnection: RBXScriptConnection? = nil
local activeHumanoid: Humanoid? = nil
local originalAutoRotate: boolean? = nil
local controlledLookVector: Vector3? = nil

local function horizontalUnit(vector: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude == 0 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function resetInput(): ()
	input.forward = false
	input.backward = false
	input.left = false
	input.right = false
end

local function syncInput(): ()
	input.forward = UserInputService:IsKeyDown(Enum.KeyCode.W)
	input.backward = UserInputService:IsKeyDown(Enum.KeyCode.S)
	input.left = UserInputService:IsKeyDown(Enum.KeyCode.A)
	input.right = UserInputService:IsKeyDown(Enum.KeyCode.D)
end

local function releaseHumanoid(): ()
	local humanoid = activeHumanoid
	if humanoid ~= nil and originalAutoRotate ~= nil then
		humanoid.AutoRotate = originalAutoRotate
	end

	activeHumanoid = nil
	originalAutoRotate = nil
	controlledLookVector = nil
end

local function acquireHumanoid(humanoid: Humanoid): ()
	if activeHumanoid == humanoid then
		return
	end

	releaseHumanoid()
	activeHumanoid = humanoid
	originalAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
end

local function updateInput(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not movementEnabled then
		return Enum.ContextActionResult.Sink
	end

	local isPressed = if inputState == Enum.UserInputState.Begin then true elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel then false
		else nil

	if isPressed == nil then
		return Enum.ContextActionResult.Sink
	end

	if actionName == ACTION_FORWARD then
		input.forward = isPressed
	elseif actionName == ACTION_BACKWARD then
		input.backward = isPressed
	elseif actionName == ACTION_LEFT then
		input.left = isPressed
	elseif actionName == ACTION_RIGHT then
		input.right = isPressed
	end

	return Enum.ContextActionResult.Sink
end

local function handleInputEnded(inputObject: InputObject): ()
	if inputObject.KeyCode == Enum.KeyCode.W then
		input.forward = false
	elseif inputObject.KeyCode == Enum.KeyCode.S then
		input.backward = false
	elseif inputObject.KeyCode == Enum.KeyCode.A then
		input.left = false
	elseif inputObject.KeyCode == Enum.KeyCode.D then
		input.right = false
	end
end

local function update(deltaTime: number): ()
	if not started then
		return
	end

	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		releaseHumanoid()
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		releaseHumanoid()
		return
	end
	acquireHumanoid(humanoid)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local lookVector = controlledLookVector or horizontalUnit(rootPart.CFrame.LookVector)
	if not movementEnabled then
		controlledLookVector = lookVector
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end

	if UserInputService:GetFocusedTextBox() then
		controlledLookVector = lookVector
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector)
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end

	local motion = TankControlMath.calculate(lookVector, input, deltaTime)
	if motion.rotationRadians ~= 0 then
		lookVector = horizontalUnit(CFrame.Angles(0, motion.rotationRadians, 0):VectorToWorldSpace(lookVector))
	end
	controlledLookVector = lookVector
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector)
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:Move(motion.moveDirection, false)
end

local function bindActions(): ()
	ContextActionService:BindActionAtPriority(
		ACTION_FORWARD,
		updateInput,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.W
	)
	ContextActionService:BindActionAtPriority(
		ACTION_BACKWARD,
		updateInput,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.S
	)
	ContextActionService:BindActionAtPriority(
		ACTION_LEFT,
		updateInput,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.A
	)
	ContextActionService:BindActionAtPriority(
		ACTION_RIGHT,
		updateInput,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.D
	)
end

local function unbindActions(): ()
	for _, actionName in ACTIONS do
		ContextActionService:UnbindAction(actionName)
	end
end

export type TankController = {
	start: () -> (),
	stop: () -> (),
	setMovementEnabled: (enabled: boolean) -> (),
}

local controller = {} :: TankController

function controller.start(): ()
	if started then
		return
	end

	started = true
	resetInput()
	inputEndedConnection = UserInputService.InputEnded:Connect(handleInputEnded)
	bindActions()
	renderConnection = RunService.PreRender:Connect(update)
	update(0)
end

function controller.stop(): ()
	if not started then
		return
	end

	started = false
	if renderConnection ~= nil then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if inputEndedConnection ~= nil then
		inputEndedConnection:Disconnect()
		inputEndedConnection = nil
	end
	unbindActions()
	resetInput()
	releaseHumanoid()
end

function controller.setMovementEnabled(enabled: boolean): ()
	movementEnabled = enabled
	if enabled then
		syncInput()
	else
		resetInput()
	end
end

return controller
