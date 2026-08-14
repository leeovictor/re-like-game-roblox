local Types = require(script.Parent.types)
local Stats = require(script.Parent.stats)

-- Seleção determinística do subconjunto conectado (sala 1 + fração via shuffle).
local function pickConnectedRooms(
	rooms: { Types.RoomData },
	config: Types.WorldConfig,
	random: Random
): { Types.RoomData }
	local connected: { Types.RoomData } = { rooms[1] }

	local rest: { Types.RoomData } = {}
	for i = 2, #rooms do
		rest[#rest + 1] = rooms[i]
	end
	random:Shuffle(rest)

	local target = 1 + math.floor((#rooms - 1) * config.tunnelConnectRatio)
	for i = 1, target - 1 do
		if rest[i] ~= nil then
			table.insert(connected, rest[i])
		end
	end

	return connected
end

-- MST (Prim's) + loops; retorna as arestas da rede.
local function buildTunnelGraph(
	rooms: { Types.RoomData },
	connected: { Types.RoomData },
	config: Types.WorldConfig,
	random: Random
): { Types.TunnelEdge }
	local edges: { Types.TunnelEdge } = {}
	local inEdges: { [string]: boolean } = {}

	local visited: { Types.RoomData } = { connected[1] }
	local unvisited: { Types.RoomData } = {}
	for i = 2, #connected do
		table.insert(unvisited, connected[i])
	end

	while #unvisited > 0 do
		local best: { a: Types.RoomData, b: Types.RoomData, dist: number }? = nil
		local bestDist = math.huge
		for _, a in ipairs(visited) do
			for _, b in ipairs(unvisited) do
				local d = (a.centerWorld - b.centerWorld).Magnitude
				if d < bestDist then
					bestDist = d
					best = { a = a, b = b, dist = d }
				end
			end
		end
		if best == nil then
			break
		end
		edges[#edges + 1] = { a = best.a, b = best.b }
		inEdges[string.format("%d-%d", best.a.index, best.b.index)] = true
		inEdges[string.format("%d-%d", best.b.index, best.a.index)] = true
		for i = #unvisited, 1, -1 do
			if unvisited[i] == best.b then
				table.remove(unvisited, i)
				table.insert(visited, best.b)
				break
			end
		end
	end

	for i = 1, #connected do
		for j = i + 1, #connected do
			local key = string.format("%d-%d", connected[i].index, connected[j].index)
			if not inEdges[key] and random:NextNumber() < config.tunnelLoopProbability then
				edges[#edges + 1] = { a = connected[i], b = connected[j] }
				inEdges[key] = true
				inEdges[string.format("%d-%d", connected[j].index, connected[i].index)] = true
			end
		end
	end

	return edges
end

-- Escava um túnel orgânico (random walk + tubo de raio com noise) entre dois pontos.
-- Não escreve Terrain; muta o grid recebido.
local function carveTube(
	grid: Types.Grid3D,
	from: Vector3,
	to: Vector3,
	config: Types.WorldConfig,
	random: Random
)
	local delta = to - from
	local dist = delta.Magnitude
	if dist <= 0 then
		return
	end
	local dir = delta / dist

	local axis = Vector3.new(1, 0, 0)
	if math.abs(dir.X) >= 0.9 then
		axis = Vector3.new(0, 1, 0)
	end
	local u = axis:Cross(dir).Unit
	local v = dir:Cross(u).Unit

	local steps = math.max(1, math.floor(dist / config.tunnelStepStuds))
	local jitter = Vector3.zero

	local freq = config.tunnelNoiseFrequency
	local amplitude = config.tunnelNoiseAmplitude
	local radius = config.tunnelRadiusStuds
	local minRadius = radius * 0.5
	local jitterClamp = config.tunnelJitterAmplitude
	local searchRadius = math.ceil(radius * (1 + amplitude) / grid.resolution) + 1

	for i = 0, steps do
		local t = i / steps
		jitter += Vector3.new(
			random:NextNumber(-1, 1),
			random:NextNumber(-1, 1),
			random:NextNumber(-1, 1)
		) * config.tunnelStepStuds * 0.5
		jitter = Vector3.new(
			math.clamp(jitter.X, -jitterClamp, jitterClamp),
			math.clamp(jitter.Y, -jitterClamp, jitterClamp),
			math.clamp(jitter.Z, -jitterClamp, jitterClamp)
		)

		local p = from:Lerp(to, t) + u * jitter.X + v * jitter.Y

		local centerCell = grid:worldToCell(p)
		if centerCell == nil then
			continue
		end

		for dx = -searchRadius, searchRadius do
			for dy = -searchRadius, searchRadius do
				for dz = -searchRadius, searchRadius do
					local cell = centerCell + Vector3int16.new(dx, dy, dz)
					if grid:getCell(cell) == "Rock" then
						local cw = grid:cellToWorld(cell)
						local n = math.noise(cw.X * freq, cw.Y * freq, cw.Z * freq)
						local rEff = math.max(radius * (1 + n * amplitude), minRadius)
						if (cw - p).Magnitude <= rEff then
							grid:setCell(cell, "Air")
						end
					end
				end
			end
		end
	end
end

-- Orquestra: pickConnectedRooms -> buildTunnelGraph -> carveTube por aresta.
-- Ao final, calcula isoladas e airCells = countStats(grid).airCells.
-- Retorna Types.TunnelsResult com timing.
local function generateTunnels(
	grid: Types.Grid3D,
	config: Types.WorldConfig,
	random: Random,
	rooms: { Types.RoomData }
): Types.TunnelsResult
	local startTime = os.clock()

	if #rooms == 0 then
		return {
			success = false,
			error = "nenhuma sala para conectar",
			elapsedSeconds = os.clock() - startTime,
		}
	end

	local connected = pickConnectedRooms(rooms, config, random)
	local edges = buildTunnelGraph(rooms, connected, config, random)

	for _, edge in ipairs(edges) do
		carveTube(grid, edge.a.centerWorld, edge.b.centerWorld, config, random)
	end

	local connectedSet: { [number]: boolean } = {}
	for _, room in ipairs(connected) do
		connectedSet[room.index] = true
	end
	local isolated: { Types.RoomData } = {}
	for _, room in ipairs(rooms) do
		if not connectedSet[room.index] then
			table.insert(isolated, room)
		end
	end

	return {
		success = true,
		edges = edges,
		connectedRooms = connected,
		isolatedRooms = isolated,
		airCells = Stats.countStats(grid).airCells,
		elapsedSeconds = os.clock() - startTime,
	}
end

return {
	generateTunnels = generateTunnels,
}
