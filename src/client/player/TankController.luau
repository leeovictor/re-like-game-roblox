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
local ACTION_RUN = "DungeonTankRun"
local WALK_SPEED = 5
local RUN_SPEED = 10
local ACTIONS = {
	ACTION_FORWARD,
	ACTION_BACKWARD,
	ACTION_LEFT,
	ACTION_RIGHT,
	ACTION_RUN,
}

type InputState = {
	forward: boolean,
	backward: boolean,
	left: boolean,
	right: boolean,
	running: boolean,
}

export type TankController = {
	input: InputState,
	started: boolean,
	movementLockCount: number,
	movementLockGeneration: number,
	renderConnection: RBXScriptConnection?,
	inputEndedConnection: RBXScriptConnection?,
	activeHumanoid: Humanoid?,
	originalAutoRotate: boolean?,
	originalWalkSpeed: number?,
	controlledLookVector: Vector3?,
	start: (self: TankController) -> (),
	stop: (self: TankController) -> (),
	acquireMovementLock: (self: TankController) -> (() -> ()),
	handleInput: (self: TankController, actionName: string, inputState: Enum.UserInputState) -> Enum.ContextActionResult,
}

export type MovementController = {
	acquireMovementLock: (self: MovementController) -> (() -> ()),
}

local TankController = {}
TankController.__index = TankController

local function horizontalUnit(vector: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude == 0 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function resetInput(self: TankController): ()
	self.input.forward = false
	self.input.backward = false
	self.input.left = false
	self.input.right = false
	self.input.running = false
end

local function canMove(self: TankController): boolean
	return self.movementLockCount == 0
end

local function syncInput(self: TankController): ()
	self.input.forward = UserInputService:IsKeyDown(Enum.KeyCode.W)
	self.input.backward = UserInputService:IsKeyDown(Enum.KeyCode.S)
	self.input.left = UserInputService:IsKeyDown(Enum.KeyCode.A)
	self.input.right = UserInputService:IsKeyDown(Enum.KeyCode.D)
	self.input.running = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
end

local function releaseHumanoid(self: TankController): ()
	local humanoid = self.activeHumanoid
	if humanoid ~= nil and self.originalAutoRotate ~= nil then
		humanoid.AutoRotate = self.originalAutoRotate
	end
	if humanoid ~= nil and self.originalWalkSpeed ~= nil then
		humanoid.WalkSpeed = self.originalWalkSpeed
	end

	self.activeHumanoid = nil
	self.originalAutoRotate = nil
	self.originalWalkSpeed = nil
	self.controlledLookVector = nil
end

local function acquireHumanoid(self: TankController, humanoid: Humanoid): ()
	if self.activeHumanoid == humanoid then
		return
	end

	releaseHumanoid(self)
	self.activeHumanoid = humanoid
	self.originalAutoRotate = humanoid.AutoRotate
	self.originalWalkSpeed = humanoid.WalkSpeed
	humanoid.AutoRotate = false
end

local function updateInput(self: TankController, actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	local isPressed = if inputState == Enum.UserInputState.Begin then true elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel then false
		else nil

	if isPressed == nil then
		return Enum.ContextActionResult.Sink
	end

	if actionName == ACTION_FORWARD then
		self.input.forward = isPressed
	elseif actionName == ACTION_BACKWARD then
		self.input.backward = isPressed
	elseif actionName == ACTION_LEFT then
		self.input.left = isPressed
	elseif actionName == ACTION_RIGHT then
		self.input.right = isPressed
	elseif actionName == ACTION_RUN then
		self.input.running = isPressed
	end

	return Enum.ContextActionResult.Sink
end

local function handleInputEnded(self: TankController, inputObject: InputObject): ()
	if inputObject.KeyCode == Enum.KeyCode.W then
		self.input.forward = false
	elseif inputObject.KeyCode == Enum.KeyCode.S then
		self.input.backward = false
	elseif inputObject.KeyCode == Enum.KeyCode.A then
		self.input.left = false
	elseif inputObject.KeyCode == Enum.KeyCode.D then
		self.input.right = false
	elseif inputObject.KeyCode == Enum.KeyCode.LeftShift then
		self.input.running = false
	end
end

local function update(self: TankController, deltaTime: number): ()
	if not self.started then
		return
	end

	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		releaseHumanoid(self)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		releaseHumanoid(self)
		return
	end
	acquireHumanoid(self, humanoid)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	humanoid.WalkSpeed = if self.input.running then RUN_SPEED else WALK_SPEED
	
	local lookVector = self.controlledLookVector or horizontalUnit(rootPart.CFrame.LookVector)
	if not canMove(self) then
		self.controlledLookVector = lookVector
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end

	local motion = TankControlMath.calculate(lookVector, self.input, deltaTime)
	if motion.rotationRadians ~= 0 then
		lookVector = horizontalUnit(CFrame.Angles(0, motion.rotationRadians, 0):VectorToWorldSpace(lookVector))
	end
	self.controlledLookVector = lookVector
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector)
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:Move(motion.moveDirection, false)
end

local function bindActions(self: TankController): ()
	ContextActionService:BindActionAtPriority(
		ACTION_FORWARD,
		function(actionName, inputState)
			return self:handleInput(actionName, inputState)
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.W
	)
	ContextActionService:BindActionAtPriority(
		ACTION_BACKWARD,
		function(actionName, inputState)
			return self:handleInput(actionName, inputState)
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.S
	)
	ContextActionService:BindActionAtPriority(
		ACTION_LEFT,
		function(actionName, inputState)
			return self:handleInput(actionName, inputState)
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.A
	)
	ContextActionService:BindActionAtPriority(
		ACTION_RIGHT,
		function(actionName, inputState)
			return self:handleInput(actionName, inputState)
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.D
	)
	ContextActionService:BindActionAtPriority(
		ACTION_RUN,
		function(actionName, inputState)
			return self:handleInput(actionName, inputState)
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.LeftShift
	)
end

local function unbindActions(): ()
	for _, actionName in ACTIONS do
		ContextActionService:UnbindAction(actionName)
	end
end

function TankController.new(): TankController
	local self = setmetatable({
		input = {
			forward = false,
			backward = false,
			left = false,
			right = false,
			running = false,
		},
		started = false,
		movementLockCount = 0,
		movementLockGeneration = 0,
		renderConnection = nil,
		inputEndedConnection = nil,
		activeHumanoid = nil,
		originalAutoRotate = nil,
		originalWalkSpeed = nil,
		controlledLookVector = nil,
	}, TankController)
	return (self :: any) :: TankController
end

function TankController.start(self: TankController): ()
	if self.started then
		return
	end

	self.started = true
	resetInput(self)
	syncInput(self)
	self.inputEndedConnection = UserInputService.InputEnded:Connect(function(inputObject)
		handleInputEnded(self, inputObject)
	end)
	bindActions(self)
	self.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		update(self, deltaTime)
	end)
	update(self, 0)
end

function TankController.stop(self: TankController): ()
	if not self.started then
		self.movementLockCount = 0
		self.movementLockGeneration += 1
		resetInput(self)
		return
	end

	self.started = false
	if self.renderConnection ~= nil then
		self.renderConnection:Disconnect()
		self.renderConnection = nil
	end
	if self.inputEndedConnection ~= nil then
		self.inputEndedConnection:Disconnect()
		self.inputEndedConnection = nil
	end
	unbindActions()
	resetInput(self)
	releaseHumanoid(self)
	self.movementLockCount = 0
	self.movementLockGeneration += 1
end

function TankController.acquireMovementLock(self: TankController): () -> ()
	if self.movementLockCount == 0 then
		self.movementLockGeneration += 1
	end

	local acquiredGeneration = self.movementLockGeneration
	self.movementLockCount += 1

	local released = false
	return function(): ()
		if released then
			return
		end
		released = true

		if acquiredGeneration ~= self.movementLockGeneration then
			return
		end

		self.movementLockCount -= 1
		syncInput(self)
	end
end

function TankController.handleInput(
	self: TankController,
	actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	return updateInput(self, actionName, inputState)
end

return TankController
