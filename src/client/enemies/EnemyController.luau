--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StarterPlayer = game:GetService("StarterPlayer")

local Enemy = require(StarterPlayer.StarterPlayerScripts.Client.enemies.Enemy)
local types = require(StarterPlayer.StarterPlayerScripts.Client.enemies.types)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type EnemyController = {
	started: boolean,
	enemies: { types.Enemy },
	heartbeatConnection: RBXScriptConnection?,
	start: (self: EnemyController) -> (),
	stop: (self: EnemyController) -> (),
	getActiveEnemies: (self: EnemyController) -> { types.Enemy },
	applyDamage: (self: EnemyController, enemy: types.Enemy, amount: number) -> boolean,
	playerAttackStarted: types.PlayerAttackStartedSignal,
	playerAttackEnded: types.PlayerAttackEndedSignal,
}

type MarkerProperties = {
	transparency: number,
	canCollide: boolean,
}

type ControllerState = EnemyController & {
	markerProperties: { [BasePart]: MarkerProperties },
	playerAttackStarted: types.PlayerAttackStartedSignal,
	playerAttackEnded: types.PlayerAttackEndedSignal,
}

export type Dependencies = {}

local EnemyController = {}
EnemyController.__index = EnemyController

local function isActive(enemy: types.Enemy): boolean
	local humanoid = enemy.humanoid
	local root = enemy.root
	return not enemy.destroyed
		and enemy.model.Parent ~= nil
		and humanoid ~= nil
		and root ~= nil
		and root:IsDescendantOf(enemy.model)
		and humanoid.Health > 0
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function EnemyController.new(): EnemyController
	local self = setmetatable({
		started = false,
		enemies = {},
		heartbeatConnection = nil,
		markerProperties = {},
		playerAttackStarted = Signal.new(),
		playerAttackEnded = Signal.new(),
	}, EnemyController)
	return (self :: any) :: EnemyController
end

local function findTemplate(): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	local template = if models ~= nil then models:FindFirstChild("Enemy") else nil
	if template == nil or not template:IsA("Model") then
		warn("[EnemyController] ReplicatedStorage.Models.Enemy must be a Model")
		return nil
	end
	return template
end

local function findEnemiesFolder(): Folder?
	local existing = Workspace:FindFirstChild("Enemies")
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end
		warn("[EnemyController] Workspace.Enemies must be a Folder")
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	return folder
end

function EnemyController.start(self: EnemyController): ()
	if self.started then
		return
	end

	local state = self :: ControllerState
	state.started = true

	local markers = Workspace:FindFirstChild("EnemiesMarkers")
	if markers ~= nil then
		for _, child in markers:GetChildren() do
			if child:IsA("BasePart") then
				state.markerProperties[child] = {
					transparency = child.Transparency,
					canCollide = child.CanCollide,
				}
				child.Transparency = 1
				child.CanCollide = false
			end
		end
	end

	local template = findTemplate()
	if template == nil then
		return
	end

	local enemiesFolder = findEnemiesFolder()
	if enemiesFolder == nil then
		return
	end

	if markers ~= nil then
		for _, child in markers:GetChildren() do
			if child:IsA("BasePart") then
				local clone = template:Clone()
				local root = clone:FindFirstChild("HumanoidRootPart")
				local humanoid = clone:FindFirstChildOfClass("Humanoid")
				if root == nil or not root:IsA("BasePart") or humanoid == nil then
					clone:Destroy()
				else
					local currentRoot = root.CFrame
					local rootRotation = currentRoot - currentRoot.Position
					local targetRoot = CFrame.new(child.Position) * rootRotation
					local delta = targetRoot * currentRoot:Inverse()
					clone:PivotTo(delta * clone:GetPivot())
					clone.Name = "Enemy_" .. child.Name
					clone.Parent = enemiesFolder

					local enemy = Enemy.new(clone, {
						playerAttackStarted = state.playerAttackStarted,
						playerAttackEnded = state.playerAttackEnded,
					})
					table.insert(state.enemies, enemy)
				end
			end
		end
	end

	state.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		for _, enemy in state.enemies do
			enemy:update(deltaTime)
		end
	end)
end

function EnemyController.stop(self: EnemyController): ()
	if not self.started then
		return
	end

	local state = self :: ControllerState
	state.started = false

	local heartbeatConnection = state.heartbeatConnection
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		state.heartbeatConnection = nil
	end

	for _, enemy in state.enemies do
		enemy:destroy()
	end
	table.clear(state.enemies)

	for marker, properties in state.markerProperties do
		if marker.Parent ~= nil then
			marker.Transparency = properties.transparency
			marker.CanCollide = properties.canCollide
		end
	end
	table.clear(state.markerProperties)
end

function EnemyController.getActiveEnemies(self: EnemyController): { types.Enemy }
	local activeEnemies: { types.Enemy } = {}
	for _, enemy in self.enemies do
		if isActive(enemy) then
			table.insert(activeEnemies, enemy)
		end
	end
	return activeEnemies
end

function EnemyController.applyDamage(self: EnemyController, enemy: types.Enemy, amount: number): boolean
	if not isFinite(amount) or amount <= 0 or not isActive(enemy) then
		return false
	end
	local isRegistered = false
	for _, currentEnemy in self.enemies do
		if currentEnemy == enemy then
			isRegistered = true
			break
		end
	end
	if not isRegistered then
		return false
	end
	local humanoid = enemy.humanoid
	if humanoid == nil then
		return false
	end
	local ok = pcall(function()
		humanoid:TakeDamage(amount)
	end)
	return ok
end

return EnemyController
