--!strict

local HttpService = game:GetService("HttpService")

local VERSION = 1
local DATA_NAME = "Data"
local SHOTS_NAME = "Shots"
local ZONES_NAME = "Zones"
local DEFAULT_SHOT_ID = "DefaultShotId"
local FIELD_OF_VIEW = "FieldOfView"
local SHOT_ID = "ShotId"
local ORDER = "Order"

export type ShotData = {
	name: string,
	cframe: CFrame,
	fieldOfView: number,
}

export type ZoneData = {
	name: string,
	cframe: CFrame,
	size: Vector3,
	shotId: string,
	order: number,
}

export type Config = {
	defaultShotId: string,
	shots: { ShotData },
	zones: { ZoneData },
}

local CameraSystemData = {}

CameraSystemData.VERSION = VERSION
CameraSystemData.DATA_NAME = DATA_NAME

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isValidOrder(value: unknown): boolean
	return isFinite(value) and (value :: number) % 1 == 0 and (value :: number) >= 0
end

local function requireFolder(parent: Instance, name: string): Folder
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("Folder") then
		error(string.format('CameraSystem."%s" must be a Folder', name), 3)
	end
	return child :: Folder
end

local function attributeString(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	if type(value) == "string" then
		return value :: string
	end
	return ""
end

local function attributeFiniteNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	if isFinite(value) then
		return value :: number
	end
	return 0
end

function CameraSystemData.capture(root: Folder): Config
	local shotsFolder = requireFolder(root, SHOTS_NAME)
	local zonesFolder = requireFolder(root, ZONES_NAME)

	local shots: { BasePart } = {}
	for _, child in shotsFolder:GetChildren() do
		if not child:IsA("BasePart") then
			error(string.format("CameraSystem.%s.%s must be a BasePart", SHOTS_NAME, child.Name), 2)
		end
		table.insert(shots, child :: BasePart)
	end
	table.sort(shots, function(left, right)
		return left.Name < right.Name
	end)

	local shotData: { ShotData } = {}
	for _, shot in shots do
		table.insert(shotData, {
			name = shot.Name,
			cframe = shot.CFrame,
			fieldOfView = attributeFiniteNumber(shot, FIELD_OF_VIEW),
		})
	end

	local zones: { BasePart } = {}
	for _, child in zonesFolder:GetChildren() do
		if not child:IsA("BasePart") then
			error(string.format("CameraSystem.%s.%s must be a BasePart", ZONES_NAME, child.Name), 2)
		end
		table.insert(zones, child :: BasePart)
	end
	table.sort(zones, function(left, right)
		local leftOrder = left:GetAttribute(ORDER)
		local rightOrder = right:GetAttribute(ORDER)
		local leftHasValidOrder = isValidOrder(leftOrder)
		local rightHasValidOrder = isValidOrder(rightOrder)
		if leftHasValidOrder ~= rightHasValidOrder then
			return leftHasValidOrder
		end
		if leftHasValidOrder and leftOrder ~= rightOrder then
			return (leftOrder :: number) < (rightOrder :: number)
		end
		return left.Name < right.Name
	end)

	local zoneData: { ZoneData } = {}
	for _, zone in zones do
		table.insert(zoneData, {
			name = zone.Name,
			cframe = zone.CFrame,
			size = zone.Size,
			shotId = attributeString(zone, SHOT_ID),
			order = attributeFiniteNumber(zone, ORDER),
		})
	end

	return {
		defaultShotId = attributeString(root, DEFAULT_SHOT_ID),
		shots = shotData,
		zones = zoneData,
	}
end

local function assertFinite(value: number, label: string)
	if not isFinite(value) then
		error(string.format("CameraSystem.Data: %s must be a finite number", label))
	end
end

local function cframeToArray(cframe: CFrame, label: string): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local components = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
	for index, component in components do
		assertFinite(component, string.format("%s[%d]", label, index))
	end
	return components
end

local function vectorToArray(vector: Vector3, label: string): { number }
	for index, component in { vector.X, vector.Y, vector.Z } do
		assertFinite(component, string.format("%s[%d]", label, index))
	end
	return { vector.X, vector.Y, vector.Z }
end

function CameraSystemData.encode(config: Config): string
	local shots = table.clone(config.shots)
	table.sort(shots, function(left, right)
		return left.name < right.name
	end)

	local zones = table.clone(config.zones)
	table.sort(zones, function(left, right)
		if left.order == right.order then
			return left.name < right.name
		end
		return left.order < right.order
	end)

	local encodedShots = {}
	for index, shot in shots do
		assertFinite(shot.fieldOfView, string.format("shots[%d].fieldOfView", index))
		table.insert(encodedShots, {
			name = shot.name,
			cframe = cframeToArray(shot.cframe, string.format("shots[%d].cframe", index)),
			fieldOfView = shot.fieldOfView,
		})
	end

	local encodedZones = {}
	for index, zone in zones do
		assertFinite(zone.order, string.format("zones[%d].order", index))
		table.insert(encodedZones, {
			name = zone.name,
			cframe = cframeToArray(zone.cframe, string.format("zones[%d].cframe", index)),
			size = vectorToArray(zone.size, string.format("zones[%d].size", index)),
			shotId = zone.shotId,
			order = zone.order,
		})
	end

	local encoded = {
		version = VERSION,
		defaultShotId = config.defaultShotId,
		shots = encodedShots,
		zones = encodedZones,
	}
	return HttpService:JSONEncode(encoded)
end

local function requireString(value: unknown, label: string): string
	if type(value) ~= "string" then
		error(string.format("CameraSystem.Data: %s must be a string", label))
	end
	return value :: string
end

local function requireNonEmptyString(value: unknown, label: string): string
	local text = requireString(value, label)
	if text == "" then
		error(string.format("CameraSystem.Data: %s must not be empty", label))
	end
	return text
end

local function requireFiniteNumber(value: unknown, label: string): number
	if type(value) ~= "number" then
		error(string.format("CameraSystem.Data: %s must be a number", label))
	end
	local numberValue = value :: number
	if not isFinite(numberValue) then
		error(string.format("CameraSystem.Data: %s must be a finite number", label))
	end
	return numberValue
end

local function requireNumberArray(value: unknown, label: string, length: number): { number }
	if type(value) ~= "table" then
		error(string.format("CameraSystem.Data: %s must be an array", label))
	end
	local array = value :: { unknown }
	if #array ~= length then
		error(string.format("CameraSystem.Data: %s must have %d numbers", label, length))
	end
	local numbers: { number } = {}
	for index = 1, length do
		numbers[index] = requireFiniteNumber(array[index], string.format("%s[%d]", label, index))
	end
	return numbers
end

local function arrayToCframe(array: { number }): CFrame
	return CFrame.new(
		array[1],
		array[2],
		array[3],
		array[4],
		array[5],
		array[6],
		array[7],
		array[8],
		array[9],
		array[10],
		array[11],
		array[12]
	)
end

local function decodeShot(value: unknown, index: number, seenNames: { [string]: boolean }): ShotData
	if type(value) ~= "table" then
		error(string.format("CameraSystem.Data: shots[%d] must be a table", index))
	end
	local shot = value :: { [string]: unknown }
	local name = requireNonEmptyString(shot.name, string.format("shots[%d].name", index))
	if seenNames[name] then
		error(string.format("CameraSystem.Data: duplicated shot name %q", name))
	end
	seenNames[name] = true
	local cframeComponents = requireNumberArray(shot.cframe, string.format("shots[%d].cframe", index), 12)
	return {
		name = name,
		cframe = arrayToCframe(cframeComponents),
		fieldOfView = requireFiniteNumber(shot.fieldOfView, string.format("shots[%d].fieldOfView", index)),
	}
end

local function decodeZone(value: unknown, index: number, seenNames: { [string]: boolean }): ZoneData
	if type(value) ~= "table" then
		error(string.format("CameraSystem.Data: zones[%d] must be a table", index))
	end
	local zone = value :: { [string]: unknown }
	local name = requireNonEmptyString(zone.name, string.format("zones[%d].name", index))
	if seenNames[name] then
		error(string.format("CameraSystem.Data: duplicated zone name %q", name))
	end
	seenNames[name] = true
	local cframeComponents = requireNumberArray(zone.cframe, string.format("zones[%d].cframe", index), 12)
	local sizeComponents = requireNumberArray(zone.size, string.format("zones[%d].size", index), 3)
	return {
		name = name,
		cframe = arrayToCframe(cframeComponents),
		size = Vector3.new(sizeComponents[1], sizeComponents[2], sizeComponents[3]),
		shotId = requireString(zone.shotId, string.format("zones[%d].shotId", index)),
		order = requireFiniteNumber(zone.order, string.format("zones[%d].order", index)),
	}
end

function CameraSystemData.decode(value: string): Config
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(value)
	end)
	if not success then
		error(string.format("CameraSystem.Data: invalid JSON: %s", tostring(decoded)))
	end

	local raw: unknown = decoded
	if type(raw) ~= "table" then
		error("CameraSystem.Data: root must be a table")
	end
	local config = raw :: { [string]: unknown }

	local version = requireFiniteNumber(config.version, "version")
	if version ~= VERSION then
		error(string.format("CameraSystem.Data: unsupported version %s (expected %d)", tostring(version), VERSION))
	end

	local rawShots = config.shots
	if type(rawShots) ~= "table" then
		error("CameraSystem.Data: shots must be an array")
	end
	local rawZones = config.zones
	if type(rawZones) ~= "table" then
		error("CameraSystem.Data: zones must be an array")
	end

	local seenShotNames: { [string]: boolean } = {}
	local shots: { ShotData } = {}
	for index, shot in ipairs(rawShots :: { unknown }) do
		table.insert(shots, decodeShot(shot, index, seenShotNames))
	end

	local zones: { ZoneData } = {}
	local seenZoneNames: { [string]: boolean } = {}
	for index, zone in ipairs(rawZones :: { unknown }) do
		table.insert(zones, decodeZone(zone, index, seenZoneNames))
	end

	return {
		defaultShotId = requireString(config.defaultShotId, "defaultShotId"),
		shots = shots,
		zones = zones,
	}
end

return CameraSystemData
