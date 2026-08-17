--!strict

local CameraConfig = require(script.Parent.CameraConfig)

local CameraResolver = {}
CameraResolver.__index = CameraResolver

export type CameraResolver = {
	config: CameraConfig.Config,
	resolve: (self: CameraResolver, position: Vector3) -> CameraConfig.ShotId,
}

local function validateConfig(config: CameraConfig.Config): ()
	if config.shots[config.defaultShotId] == nil then
		error(string.format("defaultShotId invalido: %s", config.defaultShotId), 3)
	end

	for index, zone in ipairs(config.zones) do
		if config.shots[zone.shotId] == nil then
			error(string.format("zones[%d].shotId inexistente: %s", index, zone.shotId), 3)
		end
	end

	for shotId, shot in pairs(config.shots) do
		if shot.fieldOfView < 1 or shot.fieldOfView > 120 then
			error(
				string.format("shots.%s.fieldOfView deve estar entre 1 e 120", shotId),
				3
			)
		end
	end

	for index, zone in ipairs(config.zones) do
		local size = zone.volume.size
		if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
			error(
				string.format("zones[%d].volume.size deve ter todos os eixos maiores que zero", index),
				3
			)
		end
	end
end

function CameraResolver.new(config: CameraConfig.Config): CameraResolver
	validateConfig(config)

	local self = setmetatable({
		config = config,
	}, CameraResolver)
	return (self :: any) :: CameraResolver
end

function CameraResolver:resolve(position: Vector3): CameraConfig.ShotId
	local config = self.config :: CameraConfig.Config
	for _, zone in ipairs(config.zones) do
		local localPosition = zone.volume.cframe:PointToObjectSpace(position)
		local halfSize = zone.volume.size / 2

		if math.abs(localPosition.X) <= halfSize.X
			and math.abs(localPosition.Y) <= halfSize.Y
			and math.abs(localPosition.Z) <= halfSize.Z
		then
			return zone.shotId
		end
	end

	return config.defaultShotId
end

return CameraResolver
