local Types = require(script.Parent.types)
local Stats = require(script.Parent.stats)

-- Faixa de células do interior em cada eixo (exclui a casca).
-- Retorna (minX, maxX, minY, maxY, minZ, maxZ), todos em células (1-based).
-- min = shellCells + 1; max = size - shellCells.
local function interiorBounds(grid: Types.Grid3D, shellCells: number)
	local minX = shellCells + 1
	local maxX = grid.size.X - shellCells
	local minY = shellCells + 1
	local maxY = grid.size.Y - shellCells
	local minZ = shellCells + 1
	local maxZ = grid.size.Z - shellCells
	return minX, maxX, minY, maxY, minZ, maxZ
end

-- Escava uma sala orgânica no grid.
-- centerCell: centro da sala; radiusStuds: raio base.
-- config: usado para roomVerticalScale, roomNoiseAmplitude, roomNoiseFrequency.
-- random: Random do gerador (determinismo).
-- Não escreve Terrain; muta o grid recebido.
local function carveRoom(
	grid: Types.Grid3D,
	centerCell: Vector3int16,
	radiusStuds: number,
	config: Types.WorldConfig,
	random: Random
)
	local centerWorld = grid:cellToWorld(centerCell)

	local blobCount = random:NextInteger(3, 6)
	local blobs = {}
	for i = 1, blobCount do
		local offset = Vector3.new(
			random:NextNumber(-0.5, 0.5) * radiusStuds,
			random:NextNumber(-0.5, 0.5) * radiusStuds,
			random:NextNumber(-0.5, 0.5) * radiusStuds
		)
		local subRadius = radiusStuds * random:NextNumber(0.45, 0.85)
		blobs[i] = { pos = centerWorld + offset, radius = subRadius }
	end

	local radiusInCells = math.ceil(radiusStuds / grid.resolution) + 2
	local freq = config.roomNoiseFrequency
	local amplitude = config.roomNoiseAmplitude
	local verticalScale = config.roomVerticalScale

	for dx = -radiusInCells, radiusInCells do
		for dy = -radiusInCells, radiusInCells do
			for dz = -radiusInCells, radiusInCells do
				local cell = centerCell + Vector3int16.new(dx, dy, dz)
				if grid:getCell(cell) == "Rock" then
					local p = grid:cellToWorld(cell)
					for _, blob in ipairs(blobs) do
						local n = math.noise(p.X * freq, p.Y * freq, p.Z * freq)
						local rEff = blob.radius * (1 + n * amplitude) * verticalScale
						if (p - blob.pos).Magnitude <= rEff then
							grid:setCell(cell, "Air")
							break
						end
					end
				end
			end
		end
	end
end

-- Escava um fosso vertical irregular no grid.
-- centerCell: centro do fosso; a coluna atravessa o grid inteiro em Y.
-- config: usado para pitRadiusStuds, pitNoiseAmplitude, pitNoiseFrequency.
-- O poço mantém a sensação de "fosso" (vertical e sem fundo visível), mas com
-- paredes irregulares: perfil de raio variável ao longo da altura, leve
-- serpenteio do eixo em X/Z e rugosidade de superfície por noise.
-- A proteção via getCell/setCell ("Outside" = casca) faz o fosso parar no
-- teto e no chão do interior.
-- Não escreve Terrain; muta o grid recebido.
local function carvePit(
	grid: Types.Grid3D,
	centerCell: Vector3int16,
	config: Types.WorldConfig
)
	local centerWorld = grid:cellToWorld(centerCell)
	local radius = config.pitRadiusStuds
	local amplitude = config.pitNoiseAmplitude
	local freq = config.pitNoiseFrequency

	-- Expansão máxima do fosso para dimensionar a caixa de busca em X/Z:
	-- serpenteio do eixo (0.25 * raio) + perfil (até 1.65 * raio) * rugosidade.
	local maxExpand = 1.65 * (1 + amplitude) + 0.25
	local radiusCells = math.ceil(radius * maxExpand / grid.resolution) + 1

	-- Frequência baixa do perfil vertical (bandas largas de alargamento/afunilamento).
	local profileFreq = freq * 0.35

	for dx = -radiusCells, radiusCells do
		for dz = -radiusCells, radiusCells do
			for dy = 1 - centerCell.Y, grid.size.Y - centerCell.Y do
				local cell = centerCell + Vector3int16.new(dx, dy, dz)
				if grid:getCell(cell) == "Rock" then
					local p = grid:cellToWorld(cell)

					-- Eixo com leve serpenteio em X/Z conforme a altura.
					local ax = centerWorld.X + math.noise(p.Y * profileFreq) * radius * 0.25
					local az = centerWorld.Z + math.noise(p.Y * profileFreq + 7.31) * radius * 0.25
					local horizDist = math.sqrt((p.X - ax) ^ 2 + (p.Z - az) ^ 2)

					-- Perfil irregular do raio ao longo da altura (bandas + detalhe).
					local profile = math.noise(p.Y * profileFreq, 3.14) * 0.4
						+ math.noise(p.Y * profileFreq * 2.37, 1.61) * 0.25
					local rBase = radius * (1 + profile)

					-- Rugosidade da superfície da parede.
					local surface = math.noise(p.X * freq, p.Y * freq, p.Z * freq) * amplitude
					local rEff = rBase * (1 + surface)

					if horizDist <= rEff then
						grid:setCell(cell, "Air")
					end
				end
			end
		end
	end
end

-- Amostragem com rejeição dos centros das salas.
-- Sala 1: centro do mapa (grid.center). Demais: sorteadas dentro do interior,
-- recolhido por radiusMax (mantém a sala visualmente centralizada) e
-- respeitando roomMinSpacingStuds de todas as anteriores.
-- Se estourar roomPlacementAttempts, a sala é pulada.
-- Retorna a lista de RoomData (pode ter menos que config.roomCount).
local function pickRoomCenters(
	grid: Types.Grid3D,
	config: Types.WorldConfig,
	random: Random
): { Types.RoomData }
	local shellCells = config.shellThicknessStuds / config.resolution
	local minX, maxX, minY, maxY, minZ, maxZ = interiorBounds(grid, shellCells)

	local radiusCells = math.ceil(config.roomRadiusMax / grid.resolution)
	local mMinX = minX + radiusCells
	local mMaxX = maxX - radiusCells
	local mMinY = minY + radiusCells
	local mMaxY = maxY - radiusCells
	local mMinZ = minZ + radiusCells
	local mMaxZ = maxZ - radiusCells

	if mMinX > mMaxX or mMinY > mMaxY or mMinZ > mMaxZ then
		error("Config inválida: espaço interior insuficiente para roomRadiusMax", 0)
	end

	local rooms: { Types.RoomData } = {}

	local centerCell = grid:worldToCell(grid.center)
	local room = {
		index = 1,
		centerCell = centerCell,
		centerWorld = grid:cellToWorld(centerCell),
		radiusStuds = random:NextNumber(config.roomRadiusMin, config.roomRadiusMax),
		kind = "standard",
	}
	rooms[1] = room

	local spacing = config.roomMinSpacingStuds
	for index = 2, config.roomCount do
		local attempts = 0
		while attempts < config.roomPlacementAttempts do
			attempts += 1
			local candidate = Vector3int16.new(
				random:NextInteger(mMinX, mMaxX),
				random:NextInteger(mMinY, mMaxY),
				random:NextInteger(mMinZ, mMaxZ)
			)
			local posCandidate = grid:cellToWorld(candidate)
			local farEnough = true
			for _, previous in ipairs(rooms) do
				if (posCandidate - previous.centerWorld).Magnitude < spacing then
					farEnough = false
					break
				end
			end
			if farEnough then
				local isPit = random:NextNumber() < config.pitProbability
				local newRoom = {
					index = index,
					centerCell = candidate,
					centerWorld = posCandidate,
					radiusStuds = if isPit
						then config.pitRadiusStuds
						else random:NextNumber(config.roomRadiusMin, config.roomRadiusMax),
					kind = if isPit then "pit" else "standard",
				}
				table.insert(rooms, newRoom)
				break
			end
		end
	end

	return rooms
end

-- Orquestra pickRoomCenters + carveRoom/carvePit.
-- Retorna Types.RoomsResult com timing e airCells após o carve.
local function generateRooms(
	grid: Types.Grid3D,
	config: Types.WorldConfig,
	random: Random
): Types.RoomsResult
	local startTime = os.clock()

	local ok, err = pcall(pickRoomCenters, grid, config, random)
	if not ok then
		return {
			success = false,
			error = tostring(err),
			elapsedSeconds = os.clock() - startTime,
		}
	end
	local rooms = err

	for _, room in ipairs(rooms) do
		if room.kind == "pit" then
			carvePit(grid, room.centerCell, config)
		else
			carveRoom(grid, room.centerCell, room.radiusStuds, config, random)
		end
	end

	return {
		success = true,
		rooms = rooms,
		airCells = Stats.countStats(grid).airCells,
		elapsedSeconds = os.clock() - startTime,
	}
end

return {
	generateRooms = generateRooms,
}
