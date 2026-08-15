--!strict

local Types = require(script.Parent.types)
local Grid3D = require(script.Parent.grid)
local Config = require(script.Parent.config)
local Stats = require(script.Parent.stats)
local TerrainWriter = require(script.Parent.terrainWriter)

-- Cria o grid 100% "Rock" a partir da config.
local function buildGrid(config: Types.WorldConfig): Types.Grid3D
	local worldMin = config.worldCenter - config.mapSizeStuds / 2
	return Grid3D.new(config.resolution, worldMin, config.mapSizeStuds)
end

-- Marca a casca externa como "Outside".
local function applyShell(grid: Types.Grid3D, shellCellsCount: number)
	grid:forEachCell(function(cell)
		if cell.X <= shellCellsCount
			or cell.X >= grid.size.X - shellCellsCount + 1
			or cell.Y <= shellCellsCount
			or cell.Y >= grid.size.Y - shellCellsCount + 1
			or cell.Z <= shellCellsCount
			or cell.Z >= grid.size.Z - shellCellsCount + 1
		then
			grid:setCell(cell, "Outside")
		end
	end)
end

-- Orquestra as etapas acima (pipeline do passo 1).
local function generateRockVolume(config: Types.WorldConfig): Types.GenerationResult
	local startTime = os.clock()

	local errorMessage = Config.validateConfig(config)
	if errorMessage ~= nil then
		return {
			success = false,
			error = errorMessage,
			elapsedSeconds = os.clock() - startTime,
		}
	end

	local grid = buildGrid(config)
	local shellCellsCount = config.shellThicknessStuds / config.resolution
	applyShell(grid, shellCellsCount)
	local stats = Stats.countStats(grid)

	local writeSeconds = 0
	if config.writeToTerrain then
		local writeStart = os.clock()
		local ok, err = TerrainWriter.writeGridToTerrain(grid, TerrainWriter.resolveChunkSize(config))
		writeSeconds = os.clock() - writeStart
		if not ok then
			return {
				success = false,
				error = err,
				elapsedSeconds = os.clock() - startTime,
				writeSeconds = writeSeconds,
			}
		end
	end

	return {
		success = true,
		grid = grid,
		stats = stats,
		elapsedSeconds = os.clock() - startTime,
		writeSeconds = writeSeconds,
	}
end

return {
	generateRockVolume = generateRockVolume,
}
