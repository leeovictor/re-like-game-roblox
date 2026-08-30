--!strict

local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local EnemyTypes = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local PlayerControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.player.PlayerController)

export type Dependencies = {
	player: PlayerControllerModule.PlayerController,
	attackStarted: EnemyTypes.PlayerAttackStartedSignal,
	attackEnded: EnemyTypes.PlayerAttackEndedSignal,
}

export type PlayerAttackController = {
	started: boolean,
	start: (self: PlayerAttackController) -> (),
	stop: (self: PlayerAttackController) -> (),
}

type ActiveAttack = {
	event: EnemyTypes.PlayerAttackStartedEvent,
	override: PlayerControllerModule.TransformOverride,
	elapsed: number,
}

type Controller = PlayerAttackController & {
	inputConnections: { EnemyTypes.SignalConnection },
	renderConnection: RBXScriptConnection?,
	activeAttack: ActiveAttack?,
	inputDisabledBySelf: boolean,
	dependencies: Dependencies,
}

local PlayerAttackController = {}
PlayerAttackController.__index = PlayerAttackController

local function releaseAttack(self: Controller, cancelled: boolean): ()
	local activeAttack = self.activeAttack
	if activeAttack == nil then
		return
	end

	if not cancelled then
		activeAttack.override:setCFrame(activeAttack.event.targetCFrame)
	end
	activeAttack.override:release()
	self.activeAttack = nil
	if self.inputDisabledBySelf then
		self.inputDisabledBySelf = false
		InputManager.enable()
	end
end

local function onAttackStarted(self: Controller, event: EnemyTypes.PlayerAttackStartedEvent): ()
	if not self.started or self.activeAttack ~= nil then
		return
	end

	local override = self.dependencies.player:beginTransformOverride(event.attackId)
	if override == nil then
		return
	end

	InputManager.disable()
	self.inputDisabledBySelf = true
	self.activeAttack = {
		event = event,
		override = override,
		elapsed = 0,
	}
	override:setCFrame(event.startCFrame)
end

local function onAttackEnded(self: Controller, event: EnemyTypes.PlayerAttackEndedEvent): ()
	local activeAttack = self.activeAttack
	if activeAttack == nil or activeAttack.event.enemy ~= event.enemy or activeAttack.event.attackId ~= event.attackId then
		return
	end
	releaseAttack(self, event.cancelled)
end

local function update(self: Controller, deltaTime: number): ()
	local activeAttack = self.activeAttack
	if activeAttack == nil then
		return
	end

	activeAttack.elapsed += deltaTime
	local event = activeAttack.event
	local progress = math.clamp(activeAttack.elapsed / event.turnDuration, 0, 1)
	activeAttack.override:setCFrame(event.startCFrame:Lerp(event.targetCFrame, progress))
	if activeAttack.elapsed >= event.duration then
		releaseAttack(self, false)
	end
end

function PlayerAttackController.new(dependencies: Dependencies): PlayerAttackController
	local self = setmetatable({
		started = false,
		inputConnections = {},
		renderConnection = nil,
		activeAttack = nil,
		inputDisabledBySelf = false,
		dependencies = dependencies,
	}, PlayerAttackController)
	return (self :: any) :: PlayerAttackController
end

function PlayerAttackController.start(self: PlayerAttackController): ()
	local controller = self :: Controller
	if controller.started then
		return
	end
	controller.started = true
	table.insert(controller.inputConnections, controller.dependencies.attackStarted:Connect(function(event)
		onAttackStarted(controller, event)
	end))
	table.insert(controller.inputConnections, controller.dependencies.attackEnded:Connect(function(event)
		onAttackEnded(controller, event)
	end))
	controller.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		update(controller, deltaTime)
	end)
end

function PlayerAttackController.stop(self: PlayerAttackController): ()
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
	releaseAttack(controller, true)
end

return PlayerAttackController
