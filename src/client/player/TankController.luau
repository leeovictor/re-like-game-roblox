--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
local TankControlMath = require(ReplicatedStorage.Shared.player.TankControlMath)

local ACTION_FORWARD = "DungeonTankForward"
local ACTION_BACKWARD = "DungeonTankBackward"
local ACTION_LEFT = "DungeonTankLeft"
local ACTION_RIGHT = "DungeonTankRight"
local ACTION_RUN = "DungeonTankRun"
local WALK_SPEED = 5
local RUN_SPEED = 10
local ACTION_PRIORITY = ActionPriorities.MOVEMENT

export type InputState = TankControlMath.InputState & { running: boolean }

export type TankControllerConfig = {
	walkSpeed: number?,
	runSpeed: number?,
}

type InputField = "forward" | "backward" | "left" | "right" | "running"

type KeyBinding = {
	actionName: string,
	keyCode: Enum.KeyCode,
	field: InputField,
}

type BoundActionCallback = (
	actionName: string,
	inputState: Enum.UserInputState,
	inputObject: InputObject?
) -> Enum.ContextActionResult

-- Fonte unica do mapeamento tecla -> acao -> campo de InputState; binding,
-- unbinding e sincronizacao de entrada derivam daqui.
local KEY_BINDINGS: { KeyBinding } = {
	{ actionName = ACTION_FORWARD, keyCode = Enum.KeyCode.W, field = "forward" },
	{ actionName = ACTION_BACKWARD, keyCode = Enum.KeyCode.S, field = "backward" },
	{ actionName = ACTION_LEFT, keyCode = Enum.KeyCode.A, field = "left" },
	{ actionName = ACTION_RIGHT, keyCode = Enum.KeyCode.D, field = "right" },
	{ actionName = ACTION_RUN, keyCode = Enum.KeyCode.LeftShift, field = "running" },
}

export type TankController = {
	input: InputState,
	walkSpeed: number,
	runSpeed: number,
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
	setLookVector: (self: TankController, lookVector: Vector3) -> (),
	setCFrame: (self: TankController, cframe: CFrame) -> (),
}

export type MovementController = {
	acquireMovementLock: (self: MovementController) -> (() -> ()),
	setLookVector: (self: MovementController, lookVector: Vector3) -> (),
	setCFrame: (self: MovementController, cframe: CFrame) -> (),
}

local TankController = {}
TankController.__index = TankController

-- CFrame.lookAt exige uma direcao valida; o fallback e o olhar padrao do Roblox.
local DEFAULT_LOOK_VECTOR = Vector3.new(0, 0, -1)

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
	for _, binding in KEY_BINDINGS do
		self.input[binding.field] = UserInputService:IsKeyDown(binding.keyCode)
	end
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

	for _, binding in KEY_BINDINGS do
		if binding.actionName == actionName then
			self.input[binding.field] = isPressed
		end
	end

	return Enum.ContextActionResult.Sink
end

local function handleInputEnded(self: TankController, inputObject: InputObject): ()
	for _, binding in KEY_BINDINGS do
		if inputObject.KeyCode == binding.keyCode then
			self.input[binding.field] = false
		end
	end
end

type ResolvedCharacter = {
	humanoid: Humanoid,
	rootPart: BasePart,
}

local function resolveCharacter(self: TankController): ResolvedCharacter?
	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		releaseHumanoid(self)
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		releaseHumanoid(self)
		return nil
	end
	acquireHumanoid(self, humanoid)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end

	return { humanoid = humanoid, rootPart = rootPart }
end

local function update(self: TankController, deltaTime: number): ()
	if not self.started then
		return
	end

	local character = resolveCharacter(self)
	if character == nil then
		return
	end

	local humanoid = character.humanoid
	local rootPart = character.rootPart

	humanoid.WalkSpeed = if self.input.running then self.runSpeed else self.walkSpeed

	local lookVector = self.controlledLookVector
		or TankControlMath.horizontalUnit(rootPart.CFrame.LookVector, DEFAULT_LOOK_VECTOR)
	if not canMove(self) then
		-- O look vector fica congelado enquanto o movimento esta bloqueado;
		-- ao liberar o lock, o personagem retorna a orientacao anterior.
		self.controlledLookVector = lookVector
		rootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end

	local motion = TankControlMath.calculate(lookVector, self.input, deltaTime)
	if motion.rotationRadians ~= 0 then
		lookVector = TankControlMath.horizontalUnit(
			CFrame.Angles(0, motion.rotationRadians, 0):VectorToWorldSpace(lookVector),
			DEFAULT_LOOK_VECTOR
		)
	end
	self.controlledLookVector = lookVector
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector)
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:Move(motion.moveDirection, false)
end

local function bindActions(self: TankController): ()
	for _, binding in KEY_BINDINGS do
		local callback: BoundActionCallback = function(actionName, inputState, _inputObject)
			return updateInput(self, actionName, inputState)
		end
		((self :: any)._testBoundActionCallbacks :: { [string]: BoundActionCallback })[binding.actionName] = callback
		ContextActionService:BindActionAtPriority(
			binding.actionName,
			callback,
			false,
			ACTION_PRIORITY,
			binding.keyCode
		)
	end
end

local function unbindActions(): ()
	for _, binding in KEY_BINDINGS do
		ContextActionService:UnbindAction(binding.actionName)
	end
end

function TankController.new(config: TankControllerConfig?): TankController
	local walkSpeed = WALK_SPEED
	local runSpeed = RUN_SPEED
	if config ~= nil then
		if config.walkSpeed ~= nil then
			walkSpeed = config.walkSpeed
		end
		if config.runSpeed ~= nil then
			runSpeed = config.runSpeed
		end
	end

	local self = setmetatable({
		input = {
			forward = false,
			backward = false,
			left = false,
			right = false,
			running = false,
		},
		_testBoundActionCallbacks = {},
		walkSpeed = walkSpeed,
		runSpeed = runSpeed,
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

function TankController._testGetBoundActionCallback(
	self: TankController,
	actionName: string
): BoundActionCallback?
	return ((self :: any)._testBoundActionCallbacks :: { [string]: BoundActionCallback })[actionName]
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
		local internalSelf = self :: any
		internalSelf._testBoundActionCallbacks = {}
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
	local internalSelf = self :: any
	internalSelf._testBoundActionCallbacks = {}
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

function TankController.setLookVector(self: TankController, lookVector: Vector3): ()
	local horizontalLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontalLookVector.Magnitude == 0 then
		return
	end

	local controlledLookVector: Vector3 = horizontalLookVector.Unit
	self.controlledLookVector = controlledLookVector
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + controlledLookVector)
	end
end

function TankController.setCFrame(self: TankController, cframe: CFrame): ()
	local horizontalLookVector = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if horizontalLookVector.Magnitude > 0 then
		self.controlledLookVector = horizontalLookVector.Unit
	end

	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		rootPart.CFrame = cframe
	end
end

return TankController
