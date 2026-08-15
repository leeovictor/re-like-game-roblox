--!strict

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
local WallWalkerController = require(script.world.WallWalkerController)

local engine = CaveEngine.new({
	seed = 1337,
	resolution = 4,
	shellThicknessStuds = 12,
})

local template: CaveEngine.CaveTemplate = {
	bounds = {
		min = Vector3.new(-220, -140, -160),
		max = Vector3.new(220, 60, 160),
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
	rooms = {
		{
			inner = {
				kind = "sphere",
				center = Vector3.new(0, -40, 60),
				radiusStuds = 8,
			},
			outer = {
				kind = "sphere",
				center = Vector3.new(0, -40, 60),
				radiusStuds = 40,
			},
		},
		{
			inner = {
				kind = "cylinder",
				center = Vector3.new(118, -40, 0),
				lengthStuds = 32,
				radiusStuds = 8,
			},
			outer = {
				kind = "cylinder",
				center = Vector3.new(118, -40, 0),
				lengthStuds = 96,
				radiusStuds = 40,
			},
		},
		{
			inner = {
				kind = "sphere",
				center = Vector3.new(-120, -40, 0),
				radiusStuds = 8,
			},
			outer = {
				kind = "sphere",
				center = Vector3.new(-120, -40, 0),
				radiusStuds = 40,
			},
		},
		{
			inner = {
				kind = "sphere",
				center = Vector3.new(0, -40, -80),
				radiusStuds = 10,
			},
			outer = {
				kind = "sphere",
				center = Vector3.new(0, -40, -80),
				radiusStuds = 44,
			},
		},
		{
			inner = {
				kind = "cylinder",
				center = Vector3.new(-120, -40, 80),
				lengthStuds = 32,
				radiusStuds = 8,
			},
			outer = {
				kind = "cylinder",
				center = Vector3.new(-120, -40, 80),
				lengthStuds = 96,
				radiusStuds = 40,
			},
		},
		{
			inner = {
				kind = "cylinder",
				center = Vector3.new(120, -40, -80),
				lengthStuds = 40,
				radiusStuds = 10,
			},
			outer = {
				kind = "cylinder",
				center = Vector3.new(120, -40, -80),
				lengthStuds = 112,
				radiusStuds = 44,
			},
		},
	},
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
print("Salas extras:", #template.rooms)

local result = engine:generate(template)
if not result.success then
	warn("Falha na caverna:", result.error)
	return
end

print("Caverna gerada em", result.elapsedSeconds, "s")
local stats = result.stats
local grid = result.grid
if stats == nil or grid == nil then
	error("CaveEngine retornou sucesso sem grid ou estatísticas", 0)
end
print("Rock:", stats.rockCells)
print("Air:", stats.airCells)
print("Outside:", stats.outsideCells)
print(grid:toDebugString())

local ok, err = TerrainWriter.write(grid, {
	chunkSizeCells = 64,
	clear = true,
})
if not ok then
	warn("Falha na escrita:", err)
else
	print("Terrain escrito")

	-- -----------------------------------------------------------------------
	-- Protótipo técnico: movimento cinemático aderido à superfície via raycast
	-- -----------------------------------------------------------------------
	local previousPrototype = workspace:FindFirstChild("WallWalkerPrototype")
	if previousPrototype ~= nil then
		previousPrototype:Destroy()
	end

	local prototypeFolder = Instance.new("Folder")
	prototypeFolder.Name = "WallWalkerPrototype"
	prototypeFolder.Parent = workspace

	local targetMarker = Instance.new("Part")
	targetMarker.Name = "TargetMarker"
	targetMarker.Shape = Enum.PartType.Ball
	targetMarker.Size = Vector3.new(3, 3, 3)
	targetMarker.Color = Color3.fromRGB(70, 255, 120)
	targetMarker.Material = Enum.Material.Neon
	targetMarker.Anchored = true
	targetMarker.CanCollide = false
	targetMarker.Position = Vector3.new(0, -68, 0)
	targetMarker.Parent = prototypeFolder

	local walker = Instance.new("Part")
	walker.Name = "RaycastWallWalker"
	walker.Shape = Enum.PartType.Ball
	walker.Size = Vector3.new(3, 3, 3)
	walker.Color = Color3.fromRGB(255, 80, 80)
	walker.Material = Enum.Material.Neon
	walker.Anchored = true
	walker.CanCollide = false
	walker.Parent = prototypeFolder

	local spawnParams = RaycastParams.new()
	spawnParams.FilterType = Enum.RaycastFilterType.Exclude
	spawnParams.FilterDescendantsInstances = { prototypeFolder }
	spawnParams.IgnoreWater = true

	local function findInitialSurface(): RaycastResult?
		local origin = Vector3.new(0, -52, 0)
		local directions = {
			Vector3.zAxis,
			-Vector3.zAxis,
			Vector3.xAxis,
			-Vector3.xAxis,
			Vector3.yAxis,
			-Vector3.yAxis,
		}

		-- WriteVoxels pode terminar antes da colisão do Terrain estar consultável.
		for _attempt = 1, 10 do
			for _, direction in directions do
				local hit = workspace:Raycast(origin, direction * 160, spawnParams)
				if hit ~= nil then
					return hit
				end
			end
			task.wait()
		end
		return nil
	end

	local wallHit = findInitialSurface()
	if wallHit == nil then
		warn("WallWalker: não foi possível encontrar uma superfície inicial após 10 tentativas")
	else
		local initialNormal = wallHit.Normal
		walker.Position = wallHit.Position + initialNormal * (walker.Size.X / 2 + 0.1)

		local Players = game:GetService("Players")
		local controller = WallWalkerController.new(walker, {
			targetProvider = function(): Vector3?
				local player = Players:GetPlayers()[1]
				local character = if player then player.Character else nil
				local playerRoot = if character
					then character:FindFirstChild("HumanoidRootPart")
					else nil
				if playerRoot ~= nil and playerRoot:IsA("BasePart") then
					return playerRoot.Position
				end
				return targetMarker.Position
			end,
			initialNormal = initialNormal,
			speed = 12,
			surfaceOffset = walker.Size.X / 2 + 0.1,
			probeDistance = 12,
			normalSmoothing = 0.35,
		})
		controller:start()
	end
end
