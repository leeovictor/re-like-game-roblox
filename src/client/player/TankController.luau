--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local TankControlMath = require(ReplicatedStorage.Shared.player.TankControlMath)

local WALK_SPEED = 5
local RUN_SPEED = 9

export type InputState = TankControlMath.InputState & { running: boolean }

export type TankControllerConfig = {
	walkSpeed: number?,
	runSpeed: number?,
}

export type TankController = {
	input: InputState,
	walkSpeed: number,
	runSpeed: number,
	started: boolean,
	renderConnection: RBXScriptConnection?,
	inputConnections: { RBXScriptConnection },
	activeHumanoid: Humanoid?,
	originalAutoRotate: boolean?,
	originalWalkSpeed: number?,
	controlledLookVector: Vector3?,
	start: (self: TankController) -> (),
	stop: (self: TankController) -> (),
	setLookVector: (self: TankController, lookVector: Vector3) -> (),
	setCFrame: (self: TankController, cframe: CFrame) -> (),
}

export type MovementController = {
	setLookVector: (self: MovementController, lookVector: Vector3) -> (),
	setCFrame: (self: MovementController, cframe: CFrame) -> (),
}

local TankController = {}
TankController.__index = TankController

-- CFrame.lookAt exige uma direcao valida; o fallback e o olhar padrao do Roblox.
local DEFAULT_LOOK_VECTOR = Vector3.new(0, 0, -1)

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

local function updateMoveInput(self: TankController, state: any): ()
	local value = state :: number
	self.input.forward = value < 0
	self.input.backward = value > 0
end

local function updateRotateInput(self: TankController, state: any): ()
	local value = state :: number
	self.input.left = value < 0
	self.input.right = value > 0
end

local function updateSprintInput(self: TankController, state: any): ()
	self.input.running = state :: boolean
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

	local playContext = InputManager.Contexts.PlayContext :: InputManager.Context
	
	updateMoveInput(self, playContext.GetActionState('Move'))
	updateRotateInput(self, playContext.GetActionState('Rotate'))
	updateSprintInput(self, playContext.GetActionState('Sprint'))

	local humanoid = character.humanoid
	local rootPart = character.rootPart

	humanoid.WalkSpeed = TankControlMath.resolveSpeed(self.input, self.walkSpeed, self.runSpeed)

	local lookVector = self.controlledLookVector
		or TankControlMath.horizontalUnit(rootPart.CFrame.LookVector, DEFAULT_LOOK_VECTOR)

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
		walkSpeed = walkSpeed,
		runSpeed = runSpeed,
		started = false,
		renderConnection = nil,
		inputConnections = {},
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
	self.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		update(self, deltaTime)
	end)
	update(self, 0)
end

function TankController.stop(self: TankController): ()
	if not self.started then
		return
	end

	self.started = false
	if self.renderConnection ~= nil then
		self.renderConnection:Disconnect()
		self.renderConnection = nil
	end
	releaseHumanoid(self)
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
