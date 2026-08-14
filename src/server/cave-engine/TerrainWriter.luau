local Types = require(script.Parent.Parent.world.types)

-- Opções de escrita.
export type WriteOptions = {
	chunkSizeCells: number?, -- células por eixo em cada WriteVoxels (default 64)
	clear: boolean?, -- se true, Terrain:Clear() antes de escrever (default true)
}

local TerrainWriter = {}

-- Converte um chunk do grid em arrays de material/occupancy [x][y][z] (1-based).
-- "Rock"/"Outside" -> Enum.Material.Rock, occ=1; "Air" -> Enum.Material.Air, occ=0.
local function buildVoxelChannels(
	grid: Types.Grid3D,
	minCell: Vector3int16,
	maxCell: Vector3int16
): { materials: { { { Enum.Material } } }, occupancy: { { { number } } } }
	local sx = maxCell.X - minCell.X + 1
	local sy = maxCell.Y - minCell.Y + 1
	local sz = maxCell.Z - minCell.Z + 1

	local materials: { { { Enum.Material } } } = {}
	local occupancy: { { { number } } } = {}

	for x = 1, sx do
		local matPlane: { { Enum.Material } } = {}
		local occPlane: { { number } } = {}
		for y = 1, sy do
			local matRow: { Enum.Material } = {}
			local occRow: { number } = {}
			for z = 1, sz do
				local cell = Vector3int16.new(
					minCell.X + x - 1,
					minCell.Y + y - 1,
					minCell.Z + z - 1
				)
				if grid:getCell(cell) == "Air" then
					matRow[z] = Enum.Material.Air
					occRow[z] = 0
				else
					matRow[z] = Enum.Material.Rock
					occRow[z] = 1
				end
			end
			matPlane[y] = matRow
			occPlane[y] = occRow
		end
		materials[x] = matPlane
		occupancy[x] = occPlane
	end

	return { materials = materials, occupancy = occupancy }
end

-- Divide [1..size] em segmentos de até chunkSize células.
local function splitAxis(size: number, chunkSize: number): { { start: number, stop: number } }
	local segments: { { start: number, stop: number } } = {}
	local start = 1
	while start <= size do
		local stop = math.min(start + chunkSize - 1, size)
		table.insert(segments, { start = start, stop = stop })
		start = stop + 1
	end
	return segments
end

-- Escreve um Grid3D no Terrain em chunks (evita "region too large").
function TerrainWriter.write(grid: Types.Grid3D, opts: WriteOptions?): (boolean, string?)
	local options: WriteOptions = opts or {}
	local chunkSize = options.chunkSizeCells or 64
	local clear = if options.clear == nil then true else options.clear

	local terrain = workspace.Terrain

	-- pré-validação contra MaxExtents
	local ext = terrain.MaxExtents
	if grid.worldMin.X < ext.Min.X or grid.worldMin.Y < ext.Min.Y or grid.worldMin.Z < ext.Min.Z then
		return false, "grid.worldMin fora de Terrain.MaxExtents"
	end
	if grid.worldMax.X > ext.Max.X or grid.worldMax.Y > ext.Max.Y or grid.worldMax.Z > ext.Max.Z then
		return false, "grid.worldMax fora de Terrain.MaxExtents"
	end

	if clear then
		terrain:Clear()
	end

	local res = grid.resolution

	local segsX = splitAxis(grid.size.X, chunkSize)
	local segsY = splitAxis(grid.size.Y, chunkSize)
	local segsZ = splitAxis(grid.size.Z, chunkSize)

	local total = #segsX * #segsY * #segsZ
	local i = 0

	for _, segX in ipairs(segsX) do
		for _, segY in ipairs(segsY) do
			for _, segZ in ipairs(segsZ) do
				i += 1

				local minCell = Vector3int16.new(segX.start, segY.start, segZ.start)
				local maxCell = Vector3int16.new(segX.stop, segY.stop, segZ.stop)

				local chunkMinWorld = grid.worldMin
					+ (minCell - Vector3int16.new(1, 1, 1)) * res
				local chunkMaxWorld = grid.worldMin + maxCell * res
				local region = Region3.new(chunkMinWorld, chunkMaxWorld):ExpandToGrid(res)

				local channels = buildVoxelChannels(grid, minCell, maxCell)

				local ok, err = pcall(
					terrain.WriteVoxels,
					terrain,
					region,
					res,
					channels.materials,
					channels.occupancy
				)
				if not ok then
					return false, string.format("%s (chunk %d/%d)", tostring(err), i, total)
				end
			end
		end
	end

	return true
end

return TerrainWriter
