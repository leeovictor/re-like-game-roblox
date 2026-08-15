--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

type Vector3Value = {
	X: number,
	Y: number,
	Z: number,
}

type Vector3int16Value = Vector3Value

type LuneRoblox = {
	Vector3: { new: (number, number, number) -> Vector3Value },
	Vector3int16: { new: (number, number, number) -> Vector3int16Value },
}

local roblox = require("@lune/roblox") :: LuneRoblox
local Vector3 = roblox.Vector3
local Vector3int16 = roblox.Vector3int16
local Grid3D = loader.load("src/server/world/grid.luau")

local resolution = 4
local worldMin = Vector3.new(-4, -8, -12)
local sizeStuds = Vector3.new(8, 12, 16)

local function newGrid()
	return Grid3D.new(resolution, worldMin, sizeStuds)
end

local function assertVector3(actual: any, expected: any, message: string)
	harness.assert.near(actual.X, expected.X, 1e-6, message .. " X")
	harness.assert.near(actual.Y, expected.Y, 1e-6, message .. " Y")
	harness.assert.near(actual.Z, expected.Z, 1e-6, message .. " Z")
end

local function assertVector3int16(actual: any, expected: any, message: string)
	harness.assert.equal(actual.X, expected.X, message .. " X")
	harness.assert.equal(actual.Y, expected.Y, message .. " Y")
	harness.assert.equal(actual.Z, expected.Z, message .. " Z")
end

harness.describe("Grid3D", function()
	harness.it("cria metadados e inicializa todas as celulas como Rock", function()
		local grid = newGrid()
		harness.assert.equal(grid.resolution, resolution)
		assertVector3int16(grid.size, Vector3int16.new(2, 3, 4), "size")
		assertVector3int16(grid.minCell, Vector3int16.new(1, 1, 1), "minCell")
		assertVector3(grid.worldMin, Vector3.new(-4, -8, -12), "worldMin")
		assertVector3(grid.worldMax, Vector3.new(4, 4, 4), "worldMax")
		assertVector3(grid.center, Vector3.new(0, -2, -4), "center")

		local count = 0
		grid:forEachCell(function(_, value)
			count += 1
			harness.assert.equal(value, "Rock")
		end)
		harness.assert.equal(count, 24)
	end)

	harness.it("converte pontos e celulas nos limites e centros", function()
		local grid = newGrid()
		assertVector3int16(grid:worldToCell(worldMin), Vector3int16.new(1, 1, 1), "worldMin cell")
		assertVector3int16(
			grid:worldToCell(Vector3.new(3.999, 3.999, 3.999)),
			Vector3int16.new(2, 3, 4),
			"upper interior cell"
		)
		harness.assert.isNil(grid:worldToCell(Vector3.new(4, 4, 4)), "worldMax must be outside")
		harness.assert.isNil(grid:worldToCell(Vector3.new(-4.001, -8, -12)), "lower outside point")

		assertVector3(grid:cellToWorld(Vector3int16.new(1, 1, 1)), Vector3.new(-2, -6, -10), "first cell center")
		assertVector3(grid:cellToWorld(Vector3int16.new(2, 3, 4)), Vector3.new(2, 2, 2), "last cell center")
	end)

	harness.it("respeita limites ao ler e escrever celulas", function()
		local grid = newGrid()
		local validCell = Vector3int16.new(2, 3, 4)
		local invalidCell = Vector3int16.new(3, 1, 1)

		harness.assert.truthy(grid:inBounds(validCell))
		harness.assert.falsy(grid:inBounds(invalidCell))
		grid:setCell(validCell, "Air")
		harness.assert.equal(grid:getCell(validCell), "Air")
		grid:setCell(invalidCell, "Air")
		harness.assert.equal(grid:getCell(invalidCell), "Outside")
	end)

	harness.it("visita as 24 celulas na ordem x, y, z", function()
		local grid = newGrid()
		local visited = {}
		grid:forEachCell(function(cell)
			table.insert(visited, cell)
		end)

		harness.assert.equal(#visited, 24)
		assertVector3int16(visited[1], Vector3int16.new(1, 1, 1), "first visited cell")
		assertVector3int16(visited[#visited], Vector3int16.new(2, 3, 4), "last visited cell")
		assertVector3int16(visited[2], Vector3int16.new(1, 1, 2), "second visited cell")
		assertVector3int16(visited[5], Vector3int16.new(1, 2, 1), "fifth visited cell")
	end)

	harness.it("gera resumo com contagens de materiais", function()
		local grid = newGrid()
		grid:setCell(Vector3int16.new(1, 1, 1), "Air")
		grid:setCell(Vector3int16.new(2, 3, 4), "Outside")

		harness.assert.equal(grid:toDebugString(), "Grid 2x3x4 | Rock 22 | Air 1 | Outside 1")
	end)
end)
