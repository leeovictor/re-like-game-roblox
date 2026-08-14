local Types = require(script.Parent.types)

local Grid3D = {}
Grid3D.__index = Grid3D

local function makeCells(size: Vector3int16): { { { Types.GridCell } } }
	local cells: { { { Types.GridCell } } } = {}
	for x = 1, size.X do
		local plane: { { Types.GridCell } } = {}
		for y = 1, size.Y do
			local row: { Types.GridCell } = {}
			for z = 1, size.Z do
				row[z] = "Rock"
			end
			plane[y] = row
		end
		cells[x] = plane
	end
	return cells
end

-- Cria um Grid3D com todas as células preenchidas como "Rock".
function Grid3D.new(resolution: number, worldMin: Vector3, sizeStuds: Vector3): Types.Grid3D
	local size = Vector3int16.new(
		math.round(sizeStuds.X / resolution),
		math.round(sizeStuds.Y / resolution),
		math.round(sizeStuds.Z / resolution)
	)

	local self = setmetatable({
		resolution = resolution,
		minCell = Vector3int16.new(1, 1, 1),
		size = size,
		worldMin = worldMin,
		worldMax = worldMin + sizeStuds,
		center = worldMin + sizeStuds / 2,
		cells = makeCells(size),
	}, Grid3D)

	return self
end

-- Converte posição em studs para célula. Retorna nil se fora dos limites.
function Grid3D:worldToCell(position: Vector3): Vector3int16?
	local cell = Vector3int16.new(
		math.floor((position.X - self.worldMin.X) / self.resolution) + 1,
		math.floor((position.Y - self.worldMin.Y) / self.resolution) + 1,
		math.floor((position.Z - self.worldMin.Z) / self.resolution) + 1
	)
	if not self:inBounds(cell) then
		return nil
	end
	return cell
end

-- Converte célula para o CENTRO da célula em studs.
function Grid3D:cellToWorld(cell: Vector3int16): Vector3
	local half = self.resolution / 2
	return Vector3.new(
		self.worldMin.X + (cell.X - 1) * self.resolution + half,
		self.worldMin.Y + (cell.Y - 1) * self.resolution + half,
		self.worldMin.Z + (cell.Z - 1) * self.resolution + half
	)
end

-- true se 1 <= x <= size.X (e idem y, z).
function Grid3D:inBounds(cell: Vector3int16): boolean
	return cell.X >= 1 and cell.X <= self.size.X
		and cell.Y >= 1 and cell.Y <= self.size.Y
		and cell.Z >= 1 and cell.Z <= self.size.Z
end

-- Define o material de uma célula. Ignora células fora de bounds.
function Grid3D:setCell(cell: Vector3int16, value: Types.GridCell): ()
	if not self:inBounds(cell) then
		return
	end
	self.cells[cell.X][cell.Y][cell.Z] = value
end

-- Retorna o material da célula. Fora de bounds retorna "Outside" (defensivo).
function Grid3D:getCell(cell: Vector3int16): Types.GridCell
	if not self:inBounds(cell) then
		return "Outside"
	end
	return self.cells[cell.X][cell.Y][cell.Z]
end

-- Itera todas as células na ordem x → y → z.
function Grid3D:forEachCell(callback: (cell: Vector3int16, value: Types.GridCell) -> ()): ()
	for x = 1, self.size.X do
		for y = 1, self.size.Y do
			for z = 1, self.size.Z do
				callback(Vector3int16.new(x, y, z), self.cells[x][y][z])
			end
		end
	end
end

-- Resumo legível, ex.: "Grid 32x16x32 | Rock 6760 | Outside 9624".
function Grid3D:toDebugString(): string
	local rockCount = 0
	local airCount = 0
	local outsideCount = 0
	for x = 1, self.size.X do
		for y = 1, self.size.Y do
			for z = 1, self.size.Z do
				local value = self.cells[x][y][z]
				if value == "Rock" then
					rockCount += 1
				elseif value == "Air" then
					airCount += 1
				else
					outsideCount += 1
				end
			end
		end
	end

	local parts = { string.format("Grid %dx%dx%d", self.size.X, self.size.Y, self.size.Z) }
	table.insert(parts, string.format("Rock %d", rockCount))
	if airCount > 0 then
		table.insert(parts, string.format("Air %d", airCount))
	end
	if outsideCount > 0 then
		table.insert(parts, string.format("Outside %d", outsideCount))
	end
	return table.concat(parts, " | ")
end

return Grid3D
