--!strict

local CameraConfig = require(script.Parent.CameraConfig)
local CameraSystemData = require(script.Parent.CameraSystemData)

local CameraMapReader = {}

export type CameraMapReader = {
	read: (rootName: string) -> CameraConfig.Config,
}

type PendingZone = {
	name: string,
	order: number,
	zone: CameraConfig.Zone,
}

local function fail(instanceType: string, instanceName: string, problem: string): never
	error(string.format('CameraSystem: %s "%s" %s', instanceType, instanceName, problem), 3)
end

local function requireFolder(parent: Instance, name: string): Folder
	local child = parent:WaitForChild(name)
	if not child:IsA("Folder") then
		fail("Folder", parent.Name, string.format('deve conter a pasta "%s"', name))
	end
	return child :: Folder
end

local function requireNonEmptyString(instanceName: string, value: string, attributeName: string): string
	if value == "" then
		fail("Instance", instanceName, string.format("deve ter o atributo %s como string nao vazia", attributeName))
	end
	return value
end

local function folderHasBasePart(folder: Folder): boolean
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			return true
		end
	end
	return false
end

local function toRuntimeConfig(raw: CameraSystemData.Config, rootFolder: Folder): CameraConfig.Config
	local shots: { [CameraConfig.ShotId]: CameraConfig.Shot } = {}
	for _, shot in raw.shots do
		if shot.fieldOfView < 1 or shot.fieldOfView > 120 then
			fail("Shot", shot.name, "deve ter FieldOfView entre 1 e 120")
		end
		shots[shot.name] = {
			cframe = shot.cframe,
			fieldOfView = shot.fieldOfView,
		}
	end

	local defaultShotId = raw.defaultShotId
	if defaultShotId == "" or shots[defaultShotId] == nil then
		fail("Folder", rootFolder.Name, string.format('DefaultShotId "%s" nao existe em Shots', defaultShotId))
	end

	local pendingZones: { PendingZone } = {}
	for _, zone in raw.zones do
		local shotId = requireNonEmptyString(zone.name, zone.shotId, "ShotId")
		if zone.order % 1 ~= 0 then
			fail("Zone", zone.name, "deve ter Order como numero inteiro")
		end
		if zone.size.X <= 0 or zone.size.Y <= 0 or zone.size.Z <= 0 then
			fail("Zone", zone.name, "deve ter Size com todos os eixos maiores que zero")
		end

		table.insert(pendingZones, {
			name = zone.name,
			order = zone.order,
			zone = {
				id = zone.name,
				volume = {
					cframe = zone.cframe,
					size = zone.size,
				},
				shotId = shotId,
			},
		})
	end

	table.sort(pendingZones, function(left, right)
		if left.order == right.order then
			return left.name < right.name
		end
		return left.order < right.order
	end)

	local zones: { CameraConfig.Zone } = {}
	for _, pending in pendingZones do
		if shots[pending.zone.shotId] == nil then
			fail("Zone", pending.name, string.format('ShotId "%s" nao existe em Shots', pending.zone.shotId))
		end
		table.insert(zones, pending.zone)
	end

	return {
		defaultShotId = defaultShotId,
		shots = shots,
		zones = zones,
	}
end

function CameraMapReader.read(rootName: string): CameraConfig.Config
	local cameraSystem = workspace:WaitForChild(rootName)
	if not cameraSystem:IsA("Folder") then
		fail("Instance", cameraSystem.Name, "deve ser uma Folder")
	end
	local rootFolder = cameraSystem :: Folder

	local shotsFolder = requireFolder(rootFolder, "Shots")
	local zonesFolder = requireFolder(rootFolder, "Zones")

	local raw: CameraSystemData.Config
	if folderHasBasePart(shotsFolder) or folderHasBasePart(zonesFolder) then
		raw = CameraSystemData.capture(rootFolder)
	else
		local data = rootFolder:WaitForChild(CameraSystemData.DATA_NAME)
		if not data:IsA("StringValue") then
			fail("Instance", string.format("%s.%s", rootFolder.Name, data.Name), "deve ser um StringValue")
		end
		raw = CameraSystemData.decode((data :: StringValue).Value)
	end

	return toRuntimeConfig(raw, rootFolder)
end

return CameraMapReader
