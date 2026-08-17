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
local renderConnection: RBXScriptConnection? = nil
local activeHumanoid: Humanoid? = nil
local originalAutoRotate: boolean? = nil

local function resetInput(): ()
	input.forward = false
	input.backward = false
	input.left = false
	input.right = false
end

local function releaseHumanoid(): ()
	local humanoid = activeHumanoid
	if humanoid ~= nil and originalAutoRotate ~= nil then
		humanoid.AutoRotate = originalAutoRotate
	end

	activeHumanoid = nil
	originalAutoRotate = nil
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

	if UserInputService:GetFocusedTextBox() then
		humanoid:Move(Vector3.zero, false)
		return
	end

	local motion = TankControlMath.calculate(rootPart.CFrame.LookVector, input, deltaTime)
	if motion.rotationRadians ~= 0 then
		rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, motion.rotationRadians, 0)
	end
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
}

local controller = {} :: TankController

function controller.start(): ()
	if started then
		return
	end

	started = true
	resetInput()
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
	unbindActions()
	resetInput()
	releaseHumanoid()
end

return controller
