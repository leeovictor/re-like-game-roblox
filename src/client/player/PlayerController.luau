--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local CombatServiceModule = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatService)
local PlayerTypes = require(StarterPlayer.StarterPlayerScripts.Client.player.types)
local FreeState = require(StarterPlayer.StarterPlayerScripts.Client.player.states.Free)
local AimingState = require(StarterPlayer.StarterPlayerScripts.Client.player.states.Aiming)
local ReloadingState = require(StarterPlayer.StarterPlayerScripts.Client.player.states.Reloading)
local TankControlMath = require(ReplicatedStorage.Shared.player.TankControlMath)

local WALK_SPEED = 5
local RUN_SPEED = 9
local AIM_TARGET_SMOOTHING = 20
local DEFAULT_LOOK_VECTOR = Vector3.new(0, 0, -1)

export type Dependencies = {
	combat: CombatServiceModule.CombatService,
}

export type PlayerControllerConfig = {
	walkSpeed: number?,
	runSpeed: number?,
}

export type MovementController = PlayerTypes.MovementController
export type TransformOverride = PlayerTypes.TransformOverride

export type PlayerController = PlayerTypes.PlayerController

type ResolvedCharacter = {
	humanoid: Humanoid,
	rootPart: BasePart,
}

type ActiveOverride = {
	attackId: number,
	generation: number,
	cframe: CFrame,
}

type Controller = PlayerController & {
	input: PlayerTypes.InputState,
	walkSpeed: number,
	runSpeed: number,
	renderConnection: RBXScriptConnection?,
	inputConnections: { any },
	activeHumanoid: Humanoid?,
	originalAutoRotate: boolean?,
	originalWalkSpeed: number?,
	controlledLookVector: Vector3?,
	aimTargetLookVector: Vector3?,
	currentState: PlayerTypes.StateObject,
	stateContext: PlayerTypes.StateContext,
	transformOverride: ActiveOverride?,
	transformOverrideGeneration: number,
	dependencies: Dependencies,
}

local PlayerController = {}
PlayerController.__index = PlayerController

local states: { [PlayerTypes.PlayerState]: PlayerTypes.StateObject } = {
	Free = FreeState,
	Aiming = AimingState,
	Reloading = ReloadingState,
}

local function releaseHumanoid(self: Controller): ()
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

local function acquireHumanoid(self: Controller, humanoid: Humanoid): ()
	if self.activeHumanoid == humanoid then
		return
	end

	releaseHumanoid(self)
	self.activeHumanoid = humanoid
	self.originalAutoRotate = humanoid.AutoRotate
	self.originalWalkSpeed = humanoid.WalkSpeed
	humanoid.AutoRotate = false
end

local function resolveCharacter(self: Controller): ResolvedCharacter?
	local character = Players.LocalPlayer.Character
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

local function applyCFrame(self: Controller, cframe: CFrame): ()
	local horizontalLookVector = Vector3.new(cframe.LookVector.X, 0, cframe.LookVector.Z)
	if horizontalLookVector.Magnitude > 0 then
		self.controlledLookVector = horizontalLookVector.Unit
	end

	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		rootPart.CFrame = cframe
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

local function updateFreeMovement(self: Controller, deltaTime: number): ()
	local character = resolveCharacter(self)
	if character == nil then
		return
	end

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
	applyCFrame(self, CFrame.lookAt(rootPart.Position, rootPart.Position + lookVector))
	humanoid:Move(motion.moveDirection, false)
end

local function updateAimRotation(self: Controller, deltaTime: number): ()
	local character = resolveCharacter(self)
	if character == nil then
		return
	end

	local lookVector = self.controlledLookVector
		or TankControlMath.horizontalUnit(character.rootPart.CFrame.LookVector, DEFAULT_LOOK_VECTOR)
	local targetLookVector = self.aimTargetLookVector
	if targetLookVector ~= nil then
		local currentCFrame = CFrame.lookAt(character.rootPart.Position, character.rootPart.Position + lookVector)
		local targetCFrame = CFrame.lookAt(character.rootPart.Position, character.rootPart.Position + targetLookVector)
		local progress = math.clamp(deltaTime * AIM_TARGET_SMOOTHING, 0, 1)
		local nextCFrame = currentCFrame:Lerp(targetCFrame, progress)
		local nextLookVector = TankControlMath.horizontalUnit(nextCFrame.LookVector, targetLookVector)
		if nextLookVector:Dot(targetLookVector) >= 0.9995 then
			nextLookVector = targetLookVector
			self.aimTargetLookVector = nil
		end
		applyCFrame(self, CFrame.lookAt(character.rootPart.Position, character.rootPart.Position + nextLookVector))
		lookVector = nextLookVector
	end

	local turnSpeed = self.dependencies.combat:getAimTurnSpeed()
	if turnSpeed == nil then
		return
	end
	local sign = if self.input.right then -1 elseif self.input.left then 1 else 0
	if sign == 0 then
		return
	end

	local nextLookVector = TankControlMath.horizontalUnit(
		CFrame.Angles(0, sign * turnSpeed * deltaTime, 0):VectorToWorldSpace(lookVector),
		DEFAULT_LOOK_VECTOR
	)
	applyCFrame(self, CFrame.lookAt(character.rootPart.Position, character.rootPart.Position + nextLookVector))
end

local function stopMovement(self: Controller): ()
	if self.activeHumanoid ~= nil then
		self.activeHumanoid:Move(Vector3.zero, false)
		local rootPart = self.activeHumanoid.RootPart
		if rootPart ~= nil then
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function readInput(self: Controller): ()
	local playContext = InputManager.Contexts.PlayContext :: InputManager.Context
	local move = playContext:GetActionState("Move") :: number
	local rotate = playContext:GetActionState("Rotate") :: number
	local aiming = playContext:GetActionState("Aim") :: boolean
	self.input.forward = move < 0
	self.input.backward = move > 0
	self.input.left = rotate < 0
	self.input.right = rotate > 0
	self.input.running = playContext:GetActionState("Sprint") :: boolean

	local aimingChanged = self.input.aiming ~= aiming
	self.input.aiming = aiming
	if aimingChanged then
		local callback = self.currentState.onAimChanged
		if callback ~= nil then
			callback(self.stateContext, aiming)
		end
	end
end

local function transition(self: Controller, nextState: PlayerTypes.PlayerState): ()
	if self.state == nextState then
		return
	end
	local previousState = self.currentState
	if previousState.onEnd ~= nil then
		previousState.onEnd(self.stateContext)
	end
	self.state = nextState
	self.currentState = states[nextState]
	if self.currentState.onBegin ~= nil then
		self.currentState.onBegin(self.stateContext)
	end
end

local function update(self: Controller, deltaTime: number): ()
	if not self.started then
		return
	end

	readInput(self)
	self.dependencies.combat:update(deltaTime)
	local override = self.transformOverride
	if override ~= nil then
		resolveCharacter(self)
		stopMovement(self)
		applyCFrame(self, override.cframe)
		return
	end

	self.currentState.update(self.stateContext, deltaTime)
end

function PlayerController.new(
	dependencies: Dependencies,
	config: PlayerControllerConfig?
): PlayerController
	local walkSpeed = if config ~= nil and config.walkSpeed ~= nil then config.walkSpeed else WALK_SPEED
	local runSpeed = if config ~= nil and config.runSpeed ~= nil then config.runSpeed else RUN_SPEED
	local self = setmetatable({
		state = "Free",
		started = false,
		input = {
			forward = false,
			backward = false,
			left = false,
			right = false,
			running = false,
			aiming = false,
		},
		walkSpeed = walkSpeed,
		runSpeed = runSpeed,
		renderConnection = nil,
		inputConnections = {},
		activeHumanoid = nil,
		originalAutoRotate = nil,
		originalWalkSpeed = nil,
		controlledLookVector = nil,
		aimTargetLookVector = nil,
		currentState = states["Free" :: PlayerTypes.PlayerState],
		transformOverride = nil,
		transformOverrideGeneration = 0,
		dependencies = dependencies,
	}, PlayerController) :: any

	self.stateContext = {
		input = self.input,
		combat = dependencies.combat,
		transition = function(nextState)
			transition(self, nextState)
		end,
		beginAim = function()
			return dependencies.combat:beginAim()
		end,
		endAim = function()
			self.aimTargetLookVector = nil
			dependencies.combat:endAim()
		end,
		shoot = function()
			return dependencies.combat:shoot()
		end,
		requestReload = function()
			return dependencies.combat:requestReload()
		end,
		updateFreeMovement = function(deltaTime)
			updateFreeMovement(self, deltaTime)
		end,
		updateAimRotation = function(deltaTime)
			updateAimRotation(self, deltaTime)
		end,
		stopMovement = function()
			stopMovement(self)
		end,
		setLookVector = function(lookVector)
			self:setLookVector(lookVector)
		end,
		setAimTarget = function(lookVector)
			if lookVector == nil then
				self.aimTargetLookVector = nil
				return
			end
			local horizontalLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)
			if horizontalLookVector.Magnitude > 0 then
				self.aimTargetLookVector = horizontalLookVector.Unit
			else
				self.aimTargetLookVector = nil
			end
		end,
	} :: PlayerTypes.StateContext

	return self :: PlayerController
end

function PlayerController.start(self: PlayerController): ()
	local controller = self :: Controller
	if controller.started then
		return
	end
	controller.started = true
	controller.dependencies.combat:start()

	local playContext = InputManager.Contexts.PlayContext :: InputManager.Context
	table.insert(controller.inputConnections, playContext:BindActionStateChanged("Aim", function(value): ()
		controller.input.aiming = value :: boolean
		local callback = controller.currentState.onAimChanged
		if callback ~= nil then
			callback(controller.stateContext, controller.input.aiming)
		end
	end))
	table.insert(controller.inputConnections, playContext:BindActionStateChanged("Shoot", function(value): ()
		if value :: boolean then
			local callback = controller.currentState.onShoot
			if callback ~= nil then
				callback(controller.stateContext)
			end
		end
	end))
	table.insert(controller.inputConnections, playContext:BindActionStateChanged("Reload", function(value): ()
		if value :: boolean then
			local callback = controller.currentState.onReload
			if callback ~= nil then
				callback(controller.stateContext)
			end
		end
	end))

	readInput(controller)

	controller.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		update(controller, deltaTime)
	end)
end

function PlayerController.stop(self: PlayerController): ()
	local controller = self :: Controller
	if not controller.started then
		return
	end
	controller.started = false
	for _, connection in controller.inputConnections do
		connection:Disconnect()
	end
	table.clear(controller.inputConnections)
	if controller.renderConnection ~= nil then
		controller.renderConnection:Disconnect()
		controller.renderConnection = nil
	end
	controller.transformOverride = nil
	controller.transformOverrideGeneration += 1
	controller.dependencies.combat:stop()
	controller.input.forward = false
	controller.input.backward = false
	controller.input.left = false
	controller.input.right = false
	controller.input.running = false
	controller.input.aiming = false
	controller.aimTargetLookVector = nil
	releaseHumanoid(controller)
	controller.currentState = states["Free" :: PlayerTypes.PlayerState]
	controller.state = "Free"
end

function PlayerController.setLookVector(self: PlayerController, lookVector: Vector3): ()
	local controller = self :: Controller
	local horizontalLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontalLookVector.Magnitude == 0 then
		return
	end
	local controlledLookVector = horizontalLookVector.Unit
	controller.controlledLookVector = controlledLookVector
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + controlledLookVector)
	end
end

function PlayerController.setCFrame(self: PlayerController, cframe: CFrame): ()
	applyCFrame(self :: Controller, cframe)
end

function PlayerController.beginTransformOverride(self: PlayerController, attackId: number): TransformOverride?
	local controller = self :: Controller
	if not controller.started or controller.transformOverride ~= nil then
		return nil
	end

	local generation = controller.transformOverrideGeneration
	controller.transformOverride = {
		attackId = attackId,
		generation = generation,
		cframe = CFrame.identity,
	}
	local handle = {} :: any
	function handle.setCFrame(_handleSelf: PlayerTypes.TransformOverride, cframe: CFrame): boolean
		local active = controller.transformOverride
		if active == nil or active.generation ~= generation then
			return false
		end
		active.cframe = cframe
		return true
	end
	function handle.release(_handleSelf: PlayerTypes.TransformOverride): ()
		local active = controller.transformOverride
		if active == nil or active.generation ~= generation then
			return
		end
		controller.transformOverride = nil
		controller.transformOverrideGeneration += 1
	end
	return handle
end

return PlayerController
