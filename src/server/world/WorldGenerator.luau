local Types = require(script.Parent.types)
local RockVolume = require(script.Parent.rockVolume)
local Rooms = require(script.Parent.rooms)
local Tunnels = require(script.Parent.tunnels)
local TerrainWriter = require(script.Parent.terrainWriter)

local WorldGenerator = {}
WorldGenerator.__index = WorldGenerator

export type WorldGenerator = {
	getSeed: (self: WorldGenerator) -> number,
	generateRockVolume: (self: WorldGenerator) -> Types.GenerationResult,
	generateRooms: (self: WorldGenerator, grid: Types.Grid3D) -> Types.RoomsResult,
	generateTunnels: (self: WorldGenerator, grid: Types.Grid3D, rooms: { Types.RoomData }) -> Types.TunnelsResult,
	writeGridToTerrain: (self: WorldGenerator, grid: Types.Grid3D) -> (boolean, string?),
}

-- Guarda a config, a seed e Random.new(seed).
function WorldGenerator.new(config: Types.WorldConfig)
	local self = setmetatable({
		config = config,
		seed = config.seed,
		random = Random.new(config.seed),
	}, WorldGenerator)
	return self
end

function WorldGenerator:getSeed(): number
	return self.seed
end

function WorldGenerator:generateRockVolume(): Types.GenerationResult
	return RockVolume.generateRockVolume(self.config)
end

function WorldGenerator:generateRooms(grid: Types.Grid3D): Types.RoomsResult
	return Rooms.generateRooms(grid, self.config, self.random)
end

function WorldGenerator:generateTunnels(
	grid: Types.Grid3D,
	rooms: { Types.RoomData }
): Types.TunnelsResult
	return Tunnels.generateTunnels(grid, self.config, self.random, rooms)
end

-- Expõe a escrita do grid no Terrain para reescrever depois do carve.
function WorldGenerator:writeGridToTerrain(grid: Types.Grid3D): (boolean, string?)
	return TerrainWriter.writeGridToTerrain(grid, TerrainWriter.resolveChunkSize(self.config))
end

return WorldGenerator