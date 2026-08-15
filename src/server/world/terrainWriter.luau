--!strict

local Types = require(script.Parent.types)

-- Tamanho padrão do chunk de escrita (células por eixo) quando a config
-- não informa writeChunkSizeCells.
local DEFAULT_CHUNK_SIZE = 64

-- Resolve o tamanho do chunk de escrita a partir da config.
local function resolveChunkSize(config: Types.WorldConfig): number
	return config.writeChunkSizeCells or DEFAULT_CHUNK_SIZE
end

-- Divide o intervalo [minCell..maxCell] em segmentos disjuntos de até
-- chunkSize células. Retorna lista de { min, max }.
local function splitRange(minCell: number, maxCell: number, chunkSize: number): { { min: number, max: number } }
	local segments: { { min: number, max: number } } = {}
	for start = minCell, maxCell, chunkSize do
		segments[#segments + 1] = {
			min = start,
			max = math.min(start + chunkSize - 1, maxCell),
		}
	end
	return segments
end

-- Converte uma sub-faixa do grid em canais de material + ocupação
-- (arrays 3D indexados de 1, na ordem x → y → z). Sem minCell/maxCell,
-- converte o grid inteiro.
local function buildVoxelChannels(
	grid: Types.Grid3D,
	minCell: Vector3int16?,
	maxCell: Vector3int16?
)
	local minX = if minCell ~= nil then minCell.X else 1
	local minY = if minCell ~= nil then minCell.Y else 1
	local minZ = if minCell ~= nil then minCell.Z else 1
	local maxX = if maxCell ~= nil then maxCell.X else grid.size.X
	local maxY = if maxCell ~= nil then maxCell.Y else grid.size.Y
	local maxZ = if maxCell ~= nil then maxCell.Z else grid.size.Z

	local materials = {}
	local occupancy = {}
	for x = minX, maxX do
		local materialPlane = {}
		local occupancyPlane = {}
		for y = minY, maxY do
			local materialRow = {}
			local occupancyRow = {}
			for z = minZ, maxZ do
				local cell = grid.cells[x][y][z]
				if cell == "Air" then
					materialRow[z - minZ + 1] = Enum.Material.Air
					occupancyRow[z - minZ + 1] = 0
				else
					materialRow[z - minZ + 1] = Enum.Material.Sand
					occupancyRow[z - minZ + 1] = 1
				end
			end
			materialPlane[y - minY + 1] = materialRow
			occupancyPlane[y - minY + 1] = occupancyRow
		end
		materials[x - minX + 1] = materialPlane
		occupancy[x - minX + 1] = occupancyPlane
	end
	return { materials = materials, occupancy = occupancy }
end

-- Escreve uma região do grid no Terrain via WriteVoxels em chunks.
-- Cada chunk cobre até chunkSize células por eixo (região disjunta e
-- alinhada à grade), evitando o erro "region too large".
-- Não chama Terrain:Clear() — serve para reescritas incrementais.
local function writeRegionToTerrain(
	grid: Types.Grid3D,
	minCell: Vector3int16,
	maxCell: Vector3int16,
	chunkSize: number
): (boolean, string?)
	local terrain = workspace.Terrain

	local segmentsX = splitRange(minCell.X, maxCell.X, chunkSize)
	local segmentsY = splitRange(minCell.Y, maxCell.Y, chunkSize)
	local segmentsZ = splitRange(minCell.Z, maxCell.Z, chunkSize)

	local totalChunks = #segmentsX * #segmentsY * #segmentsZ
	local chunkIndex = 0

	for _, segX in ipairs(segmentsX) do
		for _, segY in ipairs(segmentsY) do
			for _, segZ in ipairs(segmentsZ) do
				chunkIndex += 1
				task.wait(0)
				local chunkMin = Vector3int16.new(segX.min, segY.min, segZ.min)
				local chunkMax = Vector3int16.new(segX.max, segY.max, segZ.max)
				local chunkMinWorld = grid.worldMin + Vector3.new(
					(chunkMin.X - 1) * grid.resolution,
					(chunkMin.Y - 1) * grid.resolution,
					(chunkMin.Z - 1) * grid.resolution
				)
				local chunkMaxWorld = grid.worldMin + Vector3.new(
					chunkMax.X * grid.resolution,
					chunkMax.Y * grid.resolution,
					chunkMax.Z * grid.resolution
				)
				local region = Region3.new(chunkMinWorld, chunkMaxWorld):ExpandToGrid(grid.resolution)
				local channels = buildVoxelChannels(grid, chunkMin, chunkMax)
				local ok, err = pcall(
					terrain.WriteVoxels,
					terrain,
					region,
					grid.resolution,
					channels.materials,
					channels.occupancy
				)
				if not ok then
					return false, string.format("%s (chunk %d/%d)", tostring(err), chunkIndex, totalChunks)
				end
			end
		end
	end

	return true
end

-- Escreve o grid inteiro no Terrain, começando com Terrain:Clear().
local function writeGridToTerrain(grid: Types.Grid3D, chunkSize: number): (boolean, string?)
	local terrain = workspace.Terrain
	terrain:Clear()
	return writeRegionToTerrain(grid, grid.minCell, grid.size, chunkSize)
end

-- Escreve uma sub-região do grid (ex.: voxels removidos pela broca) no
-- Terrain, sem limpar o resto do mundo.
local function writeGridRegion(
	grid: Types.Grid3D,
	minCell: Vector3int16,
	maxCell: Vector3int16,
	chunkSize: number
): (boolean, string?)
	if not grid:inBounds(minCell) or not grid:inBounds(maxCell) then
		return false, "região fora dos limites do grid"
	end
	return writeRegionToTerrain(grid, minCell, maxCell, chunkSize)
end

return {
	writeGridToTerrain = writeGridToTerrain,
	writeGridRegion = writeGridRegion,
	resolveChunkSize = resolveChunkSize,
}
