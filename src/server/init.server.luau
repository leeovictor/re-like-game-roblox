-- local WorldGenerator = require(script.world.WorldGenerator)

-- local generator = WorldGenerator.new({
-- 	seed = 3333,
-- 	resolution = 4,
-- 	mapSizeStuds = Vector3.new(128 * 5, 64 * 5, 128 * 5), -- 640x320x640
-- 	worldCenter = Vector3.new(0, -52, 0),
-- 	shellThicknessStuds = 12,
-- 	writeToTerrain = false, -- escrever UMA vez, depois dos túneis
-- 	writeChunkSizeCells = 64, -- células por eixo em cada WriteVoxels
-- 	roomCount = 20,
-- 	roomRadiusMin = 40,
-- 	roomRadiusMax = 100,
-- 	roomMinSpacingStuds = 120,
-- 	roomPlacementAttempts = 200,
-- 	roomVerticalScale = 0.7,
-- 	roomNoiseAmplitude = 0.15,
-- 	roomNoiseFrequency = 0.04,
-- 	pitProbability = 0.15,
-- 	pitRadiusStuds = 45,
-- 	pitNoiseAmplitude = 0.18,
-- 	pitNoiseFrequency = 0.08,
-- 	tunnelRadiusStuds = 16,
-- 	tunnelConnectRatio = 0.75,
-- 	tunnelLoopProbability = 0.2,
-- 	tunnelStepStuds = 8,
-- 	tunnelJitterAmplitude = 20,
-- 	tunnelNoiseAmplitude = 0.25,
-- 	tunnelNoiseFrequency = 0.06,
-- })

-- print("seed:", generator:getSeed())

-- local result = generator:generateRockVolume()
-- if not result.success then
-- 	warn("Falha no bloco de rocha:", result.error)
-- 	return
-- end

-- print("Bloco de rocha em", result.elapsedSeconds, "s")
-- print(result.grid:toDebugString())

-- local rooms = generator:generateRooms(result.grid)
-- if rooms.success then
-- 	print("Salas geradas:", #rooms.rooms, "de", 8)
-- 	print("Células de ar:", rooms.airCells)
-- 	print("Carve em", rooms.elapsedSeconds, "s")
-- 	print(result.grid:toDebugString())
-- 	for _, room in ipairs(rooms.rooms) do
-- 		print(string.format(
-- 			"Sala %d: centro %d,%d,%d raio %.1f tipo %s",
-- 			room.index,
-- 			room.centerCell.X,
-- 			room.centerCell.Y,
-- 			room.centerCell.Z,
-- 			room.radiusStuds,
-- 			room.kind
-- 		))
-- 	end
-- else
-- 	warn("Falha nas salas:", rooms.error)
-- 	return
-- end

-- local tunnels = generator:generateTunnels(result.grid, rooms.rooms)
-- if tunnels.success then
-- 	print("Túneis:", #tunnels.edges, "arestas")
-- 	print("Salas conectadas:", #tunnels.connectedRooms, "de", #rooms.rooms)
-- 	print("Salas isoladas:", #tunnels.isolatedRooms)
-- 	print("Células de ar (após túneis):", tunnels.airCells)
-- 	for _, edge in ipairs(tunnels.edges) do
-- 		print(string.format(
-- 			"Aresta sala %d -> sala %d",
-- 			edge.a.index,
-- 			edge.b.index
-- 		))
-- 	end
-- 	print("Túneis em", tunnels.elapsedSeconds, "s")
-- 	print(result.grid:toDebugString())
-- else
-- 	warn("Falha nos túneis:", tunnels.error)
-- 	return
-- end

-- local ok, err = generator:writeGridToTerrain(result.grid)
-- if not ok then
-- 	warn("Falha na escrita:", err)
-- else
-- 	print("Terrain escrito")
-- end

-- ---------------------------------------------------------------------------
-- Protótipo cave-engine: caverna por SDF (cilindros + plano) + math.noise
-- ---------------------------------------------------------------------------
local CaveEngine = require(script["cave-engine"].CaveEngine)
local TerrainWriter = require(script["cave-engine"].TerrainWriter)

local engine = CaveEngine.new({
	seed = 1337,
	resolution = 4,
	shellThicknessStuds = 12,
})

local template: CaveEngine.CaveTemplate = {
	bounds = {
		min = Vector3.new(-116, -120, -68),
		max = Vector3.new(116, 16, 68),
	},
	innerCylinder = {
		kind = "cylinder",
		center = Vector3.new(0, -52, 0),
		lengthStuds = 120,
		radiusStuds = 18,
	},
	outerCylinder = {
		kind = "cylinder",
		center = Vector3.new(0, -52, 0),
		lengthStuds = 200,
		radiusStuds = 52,
	},
	rooms = {},
	floorPlane = {
		yStuds = -72,
		noiseAmplitudeStuds = 4,
		noiseFrequency = 0.035,
	},
	wallNoise = {
		amplitudeStuds = 30,
		frequency = 0.045,
	},
}

print("seed:", engine:getSeed())

local result = engine:generate(template)
if not result.success then
	warn("Falha na caverna:", result.error)
	return
end

print("Caverna gerada em", result.elapsedSeconds, "s")
print("Rock:", result.stats.rockCells)
print("Air:", result.stats.airCells)
print("Outside:", result.stats.outsideCells)
print(result.grid:toDebugString())

local ok, err = TerrainWriter.write(result.grid, {
	chunkSizeCells = 64,
	clear = true,
})
if not ok then
	warn("Falha na escrita:", err)
else
	print("Terrain escrito")
end
