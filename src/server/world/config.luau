--!strict

local Types = require(script.Parent.types)

-- Valida a config. Retorna string de erro ou nil.
local function validateConfig(config: Types.WorldConfig): string?
	if config.resolution <= 0 then
		return "resolution deve ser maior que 0"
	end

	local mapSize = config.mapSizeStuds
	if mapSize.X <= 0 or mapSize.Y <= 0 or mapSize.Z <= 0 then
		return "mapSizeStuds deve ter todos os eixos maiores que 0"
	end
	if mapSize.X % config.resolution ~= 0
		or mapSize.Y % config.resolution ~= 0
		or mapSize.Z % config.resolution ~= 0
	then
		return "mapSizeStuds deve ser múltiplo de resolution em todos os eixos"
	end

	if config.shellThicknessStuds < config.resolution
		or config.shellThicknessStuds % config.resolution ~= 0
	then
		return "shellThicknessStuds deve ser múltiplo de resolution e >= resolution"
	end

	local smallestSide = math.min(mapSize.X, mapSize.Y, mapSize.Z)
	if 2 * config.shellThicknessStuds >= smallestSide then
		return "2 * shellThicknessStuds deve ser menor que o menor lado do mapa"
	end

	if config.writeToTerrain then
		local worldMin = config.worldCenter - mapSize / 2
		local worldMax = config.worldCenter + mapSize / 2
		local expanded = Region3.new(worldMin, worldMax):ExpandToGrid(config.resolution)
		local expandedMin = expanded.CFrame.Position - expanded.Size / 2
		local expandedMax = expanded.CFrame.Position + expanded.Size / 2
		local extents = workspace.Terrain.MaxExtents
		if expandedMin.X < extents.Min.X
			or expandedMin.Y < extents.Min.Y
			or expandedMin.Z < extents.Min.Z
			or expandedMax.X > extents.Max.X
			or expandedMax.Y > extents.Max.Y
			or expandedMax.Z > extents.Max.Z
		then
			return "a região do mundo excede os MaxExtents do Terrain"
		end
	end

	if config.roomCount < 1 then
		return "roomCount deve ser >= 1"
	end
	if config.roomRadiusMin <= 0 then
		return "roomRadiusMin deve ser > 0"
	end
	if config.roomRadiusMax < config.roomRadiusMin then
		return "roomRadiusMax deve ser >= roomRadiusMin"
	end
	if config.roomMinSpacingStuds < 0 then
		return "roomMinSpacingStuds deve ser >= 0"
	end
	if config.roomPlacementAttempts < 1 then
		return "roomPlacementAttempts deve ser >= 1"
	end
	if config.roomVerticalScale <= 0 then
		return "roomVerticalScale deve ser > 0"
	end
	if config.roomNoiseAmplitude < 0 then
		return "roomNoiseAmplitude deve ser >= 0"
	end
	if config.roomNoiseFrequency <= 0 then
		return "roomNoiseFrequency deve ser > 0"
	end

	if config.pitProbability < 0 or config.pitProbability > 1 then
		return "pitProbability deve estar entre 0 e 1"
	end
	if config.pitRadiusStuds <= 0 then
		return "pitRadiusStuds deve ser > 0"
	end
	if config.pitNoiseAmplitude < 0 then
		return "pitNoiseAmplitude deve ser >= 0"
	end
	if config.pitNoiseFrequency <= 0 then
		return "pitNoiseFrequency deve ser > 0"
	end

	if config.tunnelRadiusStuds <= 0 then
		return "tunnelRadiusStuds deve ser > 0"
	end
	if config.tunnelConnectRatio < 0 or config.tunnelConnectRatio > 1 then
		return "tunnelConnectRatio deve estar entre 0 e 1"
	end
	if config.tunnelLoopProbability < 0 or config.tunnelLoopProbability > 1 then
		return "tunnelLoopProbability deve estar entre 0 e 1"
	end
	if config.tunnelStepStuds <= 0 then
		return "tunnelStepStuds deve ser > 0"
	end
	if config.tunnelJitterAmplitude < 0 then
		return "tunnelJitterAmplitude deve ser >= 0"
	end
	if config.tunnelNoiseAmplitude < 0 then
		return "tunnelNoiseAmplitude deve ser >= 0"
	end
	if config.tunnelNoiseFrequency <= 0 then
		return "tunnelNoiseFrequency deve ser > 0"
	end

	if config.writeChunkSizeCells ~= nil and config.writeChunkSizeCells < 1 then
		return "writeChunkSizeCells deve ser >= 1"
	end

	return nil
end

return {
	validateConfig = validateConfig,
}
