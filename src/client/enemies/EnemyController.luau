--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EnemyModule = require(script.Parent.Enemy)

export type EnemyController = {
	started: boolean,
	enemies: { EnemyModule.Enemy },
	heartbeatConnection: RBXScriptConnection?,
	start: (self: EnemyController) -> (),
	stop: (self: EnemyController) -> (),
}

type MarkerProperties = {
	transparency: number,
	canCollide: boolean,
}

type ControllerState = EnemyController & {
	markerProperties: { [BasePart]: MarkerProperties },
}

local EnemyController = {}
EnemyController.__index = EnemyController

function EnemyController.new(): EnemyController
	local self = setmetatable({
		started = false,
		enemies = {},
		heartbeatConnection = nil,
		markerProperties = {},
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

					local enemy = EnemyModule.new(clone)
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

return EnemyController
