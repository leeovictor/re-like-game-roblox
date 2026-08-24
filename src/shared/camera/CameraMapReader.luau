--!strict

local CameraConfig = require(script.Parent.CameraConfig)

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

local function requireString(instance: Instance, attributeName: string): string
	local value = instance:GetAttribute(attributeName)
	if type(value) ~= "string" or value == "" then
		fail("Instance", instance.Name, string.format("deve ter o atributo %s como string nao vazia", attributeName))
	end
	return value :: string
end

function CameraMapReader.read(rootName: string): CameraConfig.Config
	local cameraSystem = workspace:WaitForChild(rootName)
	if not cameraSystem:IsA("Folder") then
		fail("Instance", cameraSystem.Name, "deve ser uma Folder")
	end
	local rootFolder = cameraSystem :: Folder

	local shotsFolder = requireFolder(rootFolder, "Shots")
	local zonesFolder = requireFolder(rootFolder, "Zones")
	local defaultShotId = requireString(rootFolder, "DefaultShotId")
	local shots: { [CameraConfig.ShotId]: CameraConfig.Shot } = {}

	for _, shotInstance in shotsFolder:GetChildren() do
		if not shotInstance:IsA("BasePart") then
			fail("Shot", shotInstance.Name, "deve ser uma BasePart")
		end
		local shot = shotInstance :: BasePart

		local fieldOfView = shot:GetAttribute("FieldOfView")
		if type(fieldOfView) ~= "number" or fieldOfView < 1 or fieldOfView > 120 then
			fail("Shot", shot.Name, "deve ter FieldOfView entre 1 e 120")
		end
		shots[shot.Name] = {
			cframe = shot.CFrame,
			fieldOfView = fieldOfView :: number,
		}
	end

	if shots[defaultShotId] == nil then
		fail("Folder", rootFolder.Name, string.format('DefaultShotId "%s" nao existe em Shots', defaultShotId))
	end

	local pendingZones: { PendingZone } = {}
	for _, zoneInstance in zonesFolder:GetChildren() do
		if not zoneInstance:IsA("BasePart") then
			fail("Zone", zoneInstance.Name, "deve ser uma BasePart")
		end
		local zone = zoneInstance :: BasePart

		local shotId = requireString(zone, "ShotId")
		local order = zone:GetAttribute("Order")
		if type(order) ~= "number" or order % 1 ~= 0 then
			fail("Zone", zone.Name, "deve ter Order como numero inteiro")
		end

		local size = zone.Size
		if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
			fail("Zone", zone.Name, "deve ter Size com todos os eixos maiores que zero")
		end

		table.insert(pendingZones, {
			name = zone.Name,
			order = order :: number,
			zone = {
				id = zone.Name,
				volume = {
					cframe = zone.CFrame,
					size = size,
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

return CameraMapReader
