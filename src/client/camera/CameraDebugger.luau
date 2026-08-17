--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage.Shared.camera.CameraConfig)

local CameraDebugger = {}
CameraDebugger.__index = CameraDebugger

export type CameraDebugger = {
	config: CameraConfig.Config,
	folder: Folder?,
	started: boolean,
	start: (self: CameraDebugger) -> (),
	stop: (self: CameraDebugger) -> (),
}

local ZONE_TRANSPARENCY = 0.75
local SHOT_COLOR = Color3.fromRGB(255, 221, 87)
local SHOT_TRANSPARENCY = 0.1
local SHOT_THICKNESS = 0.3
local SHOT_LENGTH = 12
local ARROW_HEAD_LENGTH = 3
local ARROW_HEAD_WIDTH = 2

local function configurePart(part: Part, color: Color3, transparency: number): ()
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
end

local function createSegment(
	parent: Folder,
	name: string,
	startPosition: Vector3,
	endPosition: Vector3,
	upVector: Vector3,
	color: Color3
): Part
	local direction = endPosition - startPosition
	local length = direction.Magnitude
	if length <= 0 then
		error("CameraDebugger nao pode criar um segmento de comprimento zero", 2)
	end

	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(SHOT_THICKNESS, SHOT_THICKNESS, length)
	part.CFrame = CFrame.lookAt((startPosition + endPosition) / 2, endPosition, upVector)
	configurePart(part, color, SHOT_TRANSPARENCY)
	part.Parent = parent
	return part
end

local function zoneColor(index: number, zoneCount: number): Color3
	local hue = (index - 1) / math.max(zoneCount, 1)
	return Color3.fromHSV(hue, 0.8, 1)
end

local function createZoneMarkers(config: CameraConfig.Config, parent: Folder): ()
	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "Zones"
	zoneFolder.Parent = parent

	local zoneCount = #config.zones
	for index, zone in ipairs(config.zones) do
		local marker = Instance.new("Part")
		marker.Name = string.format("Zone_%s", zone.id)
		marker.CFrame = zone.volume.cframe
		marker.Size = zone.volume.size
		configurePart(marker, zoneColor(index, zoneCount), ZONE_TRANSPARENCY)
		marker.Parent = zoneFolder
	end
end

local function createShotMarkers(config: CameraConfig.Config, parent: Folder): ()
	local shotFolder = Instance.new("Folder")
	shotFolder.Name = "Shots"
	shotFolder.Parent = parent

	for shotId, shot in pairs(config.shots) do
		local shotCFrame = shot.cframe
		local origin = shotCFrame.Position
		local direction = shotCFrame.LookVector
		local right = shotCFrame.RightVector
		local up = shotCFrame.UpVector
		local tip = origin + direction * SHOT_LENGTH
		local headBase = tip - direction * ARROW_HEAD_LENGTH

		createSegment(shotFolder, string.format("Shot_%s_Shaft", shotId), origin, tip, up, SHOT_COLOR)
		createSegment(
			shotFolder,
			string.format("Shot_%s_HeadLeft", shotId),
			tip,
			headBase + right * ARROW_HEAD_WIDTH,
			up,
			SHOT_COLOR
		)
		createSegment(
			shotFolder,
			string.format("Shot_%s_HeadRight", shotId),
			tip,
			headBase - right * ARROW_HEAD_WIDTH,
			up,
			SHOT_COLOR
		)
	end
end

local function createDebugFolder(config: CameraConfig.Config): Folder
	local folder = Instance.new("Folder")
	folder.Name = "CameraDebugger"
	createZoneMarkers(config, folder)
	createShotMarkers(config, folder)
	return folder
end

function CameraDebugger.new(config: CameraConfig.Config): CameraDebugger
	local self = setmetatable({
		config = config,
		folder = nil,
		started = false,
	}, CameraDebugger)
	return (self :: any) :: CameraDebugger
end

function CameraDebugger.start(self: CameraDebugger): ()
	if self.started or not RunService:IsStudio() then
		return
	end

	local folder = createDebugFolder(self.config)
	folder.Parent = Workspace
	self.folder = folder
	self.started = true
end

function CameraDebugger.stop(self: CameraDebugger): ()
	local folder = self.folder
	if folder ~= nil then
		folder:Destroy()
		self.folder = nil
	end

	self.started = false
end

return CameraDebugger
