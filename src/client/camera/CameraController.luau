--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage.Shared.camera.CameraConfig)
local CameraResolver = require(ReplicatedStorage.Shared.camera.CameraResolver)

local CameraController = {}
CameraController.__index = CameraController

export type CameraController = {
	config: CameraConfig.Config,
	resolver: CameraResolver.CameraResolver,
	player: Player?,
	camera: Camera?,
	renderConnection: RBXScriptConnection?,
	currentShotId: CameraConfig.ShotId?,
	started: boolean,
	start: (self: CameraController) -> (),
	stop: (self: CameraController) -> (),
	getCurrentShotId: (self: CameraController) -> CameraConfig.ShotId?,
}

local function update(self: CameraController): ()
	if not self.started then
		return
	end

	local player = self.player
	local camera = self.camera
	if player == nil or camera == nil then
		return
	end

	-- O PlayerModule pode restaurar Custom durante o spawn ou um respawn.
	-- Reafirmar o modo em cada frame mantém este controller como autoridade.
	camera.CameraType = Enum.CameraType.Scriptable

	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local position = rootPart.Position
	local zoneShotId = self.resolver:resolve(position)
	local desiredShotId = zoneShotId or self.currentShotId or self.config.defaultShotId
	if desiredShotId ~= self.currentShotId then
		local shot = self.config.shots[desiredShotId]
		if shot == nil then
			return
		end

		self.currentShotId = desiredShotId
		camera.CFrame = shot.cframe
		camera.FieldOfView = shot.fieldOfView
	end

	camera.Focus = CFrame.new(position)
end

function CameraController.new(config: CameraConfig.Config): CameraController
	local self = setmetatable({
		config = config,
		resolver = CameraResolver.new(config),
		player = nil,
		camera = nil,
		renderConnection = nil,
		currentShotId = nil,
		started = false,
	}, CameraController)
	return (self :: any) :: CameraController
end

function CameraController.start(self: CameraController): ()
	if self.started then
		return
	end

	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	self.player = player
	self.camera = camera
	self.started = true
	camera.CameraType = Enum.CameraType.Scriptable
	self.renderConnection = RunService.PreRender:Connect(function(_deltaTime: number)
		update(self)
	end)

	update(self)
end

function CameraController.stop(self: CameraController): ()
	local renderConnection = self.renderConnection
	if renderConnection ~= nil then
		renderConnection:Disconnect()
		self.renderConnection = nil
	end

	local camera = self.camera
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom

		local player = self.player
		local character = if player ~= nil then player.Character else nil
		if character ~= nil then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				camera.CameraSubject = humanoid
			end
		end
	end

	self.currentShotId = nil
	self.started = false
end

function CameraController.getCurrentShotId(self: CameraController): CameraConfig.ShotId?
	return self.currentShotId
end

return CameraController
