--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage.Shared.camera.CameraConfig)
local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local CameraResolver = require(ReplicatedStorage.Shared.camera.CameraResolver)

local CameraController = {}
CameraController.__index = CameraController

export type CameraController = {
	config: CameraConfig.Config,
	resolver: CameraResolver.CameraResolver,
	player: Player?,
	camera: Camera?,
	renderConnection: RBXScriptConnection?,
	playerShotId: CameraConfig.ShotId?,
	cinematicShotId: CameraConfig.ShotId?,
	currentShotId: CameraConfig.ShotId?,
	started: boolean,
	start: (self: CameraController) -> (),
	stop: (self: CameraController) -> (),
	getCurrentShotId: (self: CameraController) -> CameraConfig.ShotId?,
	hasShot: (self: CameraController, shotId: CameraConfig.ShotId) -> boolean,
	setCinematicShot: (self: CameraController, shotId: CameraConfig.ShotId) -> boolean,
	clearCinematicShot: (self: CameraController) -> (),
}

local function ensureScriptableCamera(camera: Camera)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

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
	-- Reafirmar o modo em cada frame mantém este controller como autoridade
	ensureScriptableCamera(camera)
	
	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local humanoidPos = rootPart.Position
	local zoneShotId = self.resolver:resolve(humanoidPos)
	if zoneShotId ~= nil then
		self.playerShotId = zoneShotId
	elseif self.playerShotId == nil then
		self.playerShotId = self.config.defaultShotId
	end

	local desiredShotId = self.cinematicShotId or self.playerShotId
	if desiredShotId == nil then
		return
	end

	if desiredShotId ~= self.currentShotId then
		local shot = self.config.shots[desiredShotId]
		if shot == nil then
			return
		end

		self.currentShotId = desiredShotId
		camera.CFrame = shot.cframe
		camera.FieldOfView = shot.fieldOfView
		
		-- isso é necessário para o roblox priorizar a renderizar de tudo que está próximo à câmera, ao contrário do player.
		-- em cinematics por exemplo um shot processador pode estar distante do player e mesmo assim a renderização do terreno e modelos
		-- deve ser consistente. apesar de poder gerar alguns artefatos no sistema de renderização (exibir terreno ainda não atualizado por um instante)
		-- é bom o suficiente
		camera.Focus = shot.cframe
	end
end

function CameraController.new(cameraMapReader: CameraMapReader.CameraMapReader): CameraController
	local config = cameraMapReader.read("CameraSystem")
	local self = setmetatable({
		config = config,
		resolver = CameraResolver.new(config),
		player = nil,
		camera = nil,
		renderConnection = nil,
		playerShotId = nil,
		cinematicShotId = nil,
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

	self.playerShotId = nil
	self.cinematicShotId = nil
	self.currentShotId = nil
	self.started = false
end

function CameraController.getCurrentShotId(self: CameraController): CameraConfig.ShotId?
	return self.currentShotId
end

function CameraController.hasShot(self: CameraController, shotId: CameraConfig.ShotId): boolean
	return self.config.shots[shotId] ~= nil
end

function CameraController.setCinematicShot(self: CameraController, shotId: CameraConfig.ShotId): boolean
	if not self:hasShot(shotId) then
		return false
	end

	self.cinematicShotId = shotId
	update(self)
	return true
end

function CameraController.clearCinematicShot(self: CameraController): ()
	self.cinematicShotId = nil
	update(self)
end

return CameraController
