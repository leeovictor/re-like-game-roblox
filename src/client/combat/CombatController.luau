--!strict

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local ActionPriorities = require(game:GetService("ReplicatedStorage").Shared.input.ActionPriorities)
local CombatServiceModule = require(script.Parent.CombatService)

export type Dependencies = {
	combat: CombatServiceModule.CombatService,
}

export type CombatController = {
	started: boolean,
	leftDown: boolean,
	rightDown: boolean,
	renderConnection: RBXScriptConnection?,
	dependencies: Dependencies,
	start: (self: CombatController) -> (),
	stop: (self: CombatController) -> (),
}

local ACTION_MOUSE_RIGHT = "DungeonCombatMouseRight"
local ACTION_MOUSE_LEFT = "DungeonCombatMouseLeft"
local ACTION_RELOAD = "DungeonCombatReload"
local ACTION_TURN_LEFT = "DungeonCombatTurnLeft"
local ACTION_TURN_RIGHT = "DungeonCombatTurnRight"
local ACTION_PRIORITY = ActionPriorities.COMBAT

local CombatController = {}
CombatController.__index = CombatController

local function isTransition(inputState: Enum.UserInputState): boolean
	return inputState == Enum.UserInputState.Begin
		or inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
end

local function resultForCapture(captured: boolean): Enum.ContextActionResult
	return if captured then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

function CombatController.new(dependencies: Dependencies): CombatController
	local self = setmetatable({
		started = false,
		leftDown = false,
		rightDown = false,
		renderConnection = nil,
		dependencies = dependencies,
	}, CombatController)
	return (self :: any) :: CombatController
end

function CombatController.start(self: CombatController): ()
	if self.started then
		return
	end
	self.started = true
	self.leftDown = false
	self.rightDown = false

	ContextActionService:BindActionAtPriority(
		ACTION_MOUSE_RIGHT,
		function(_, inputState)
			if not self.started then
				return Enum.ContextActionResult.Sink
			end
			if inputState == Enum.UserInputState.Begin then
				self.dependencies.combat:beginAim()
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				self.dependencies.combat:endAim()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_MOUSE_LEFT,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self.dependencies.combat:shoot()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1
	)
	ContextActionService:BindActionAtPriority(
		ACTION_RELOAD,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self.dependencies.combat:requestReload()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.R
	)
	ContextActionService:BindActionAtPriority(
		ACTION_TURN_LEFT,
		function(_, inputState)
			if not isTransition(inputState) then
				return resultForCapture(self.dependencies.combat:setTurnInput(self.leftDown, self.rightDown))
			end
			self.leftDown = inputState == Enum.UserInputState.Begin
			if inputState == Enum.UserInputState.Cancel or inputState == Enum.UserInputState.End then
				self.leftDown = false
			end
			return resultForCapture(self.dependencies.combat:setTurnInput(self.leftDown, self.rightDown))
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.A
	)
	ContextActionService:BindActionAtPriority(
		ACTION_TURN_RIGHT,
		function(_, inputState)
			if not isTransition(inputState) then
				return resultForCapture(self.dependencies.combat:setTurnInput(self.leftDown, self.rightDown))
			end
			self.rightDown = inputState == Enum.UserInputState.Begin
			if inputState == Enum.UserInputState.Cancel or inputState == Enum.UserInputState.End then
				self.rightDown = false
			end
			return resultForCapture(self.dependencies.combat:setTurnInput(self.leftDown, self.rightDown))
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.D
	)

	self.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		self.dependencies.combat:update(deltaTime)
	end)
end

function CombatController.stop(self: CombatController): ()
	if not self.started then
		return
	end
	self.started = false
	if self.renderConnection ~= nil then
		self.renderConnection:Disconnect()
		self.renderConnection = nil
	end
	ContextActionService:UnbindAction(ACTION_MOUSE_RIGHT)
	ContextActionService:UnbindAction(ACTION_MOUSE_LEFT)
	ContextActionService:UnbindAction(ACTION_RELOAD)
	ContextActionService:UnbindAction(ACTION_TURN_LEFT)
	ContextActionService:UnbindAction(ACTION_TURN_RIGHT)
	self.leftDown = false
	self.rightDown = false
	self.dependencies.combat:setTurnInput(false, false)
end

return CombatController
