--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

type Vector3Value = {
	X: number,
	Y: number,
	Z: number,
}

type LuneRoblox = {
	Vector3: {
		new: (number, number, number) -> Vector3Value,
	},
	CFrame: {
		new: (...any) -> any,
		Angles: (number, number, number) -> any,
	},
}

local roblox = require("@lune/roblox") :: LuneRoblox
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local CameraResolver = loader.load("src/shared/camera/CameraResolver.luau")

local function newConfig(): any
	return {
		defaultShotId = "Default",
		shots = {
			Default = { cframe = CFrame.new(), fieldOfView = 55 },
			First = { cframe = CFrame.new(), fieldOfView = 55 },
			Second = { cframe = CFrame.new(), fieldOfView = 60 },
			Rotated = { cframe = CFrame.new(), fieldOfView = 65 },
		},
		zones = {
			{
				id = "FirstZone",
				volume = { cframe = CFrame.new(0, 0, 0), size = Vector3.new(10, 10, 10) },
				shotId = "First",
			},
			{
				id = "SecondZone",
				volume = { cframe = CFrame.new(10, 0, 0), size = Vector3.new(10, 10, 10) },
				shotId = "Second",
			},
		},
	}
end

local function assertInvalid(config: any): ()
	local ok = pcall(function()
		CameraResolver.new(config)
	end)
	harness.assert.falsy(ok)
end

harness.describe("CameraResolver", function()
	harness.it("retorna o shot de um ponto dentro do volume", function()
		local resolver = CameraResolver.new(newConfig())
		harness.assert.equal(resolver:resolve(Vector3.new(0, 0, 0)), "First")
	end)

	harness.it("rejeita pontos fora em cada eixo", function()
		local resolver = CameraResolver.new(newConfig())
		harness.assert.equal(resolver:resolve(Vector3.new(5.01, 0, 0)), "Second")
		harness.assert.equal(resolver:resolve(Vector3.new(0, 5.01, 0)), "Default")
		harness.assert.equal(resolver:resolve(Vector3.new(0, 0, 5.01)), "Default")
	end)

	harness.it("reconhece um ponto em um volume rotacionado", function()
		local config = newConfig()
		local rotatedCFrame = CFrame.new(0, 0, 20) * CFrame.Angles(0, math.rad(45), 0)
		config.zones = {
			{
				id = "RotatedZone",
				volume = { cframe = rotatedCFrame, size = Vector3.new(10, 10, 4) },
				shotId = "Rotated",
			},
		}
		local resolver = CameraResolver.new(config)
		local pointInside = rotatedCFrame:PointToWorldSpace(Vector3.new(0, 0, 1))
		harness.assert.equal(resolver:resolve(pointInside), "Rotated")
	end)

	harness.it("retorna shots diferentes em zonas adjacentes", function()
		local resolver = CameraResolver.new(newConfig())
		harness.assert.equal(resolver:resolve(Vector3.new(-4.99, 0, 0)), "First")
		harness.assert.equal(resolver:resolve(Vector3.new(5.01, 0, 0)), "Second")
	end)

	harness.it("usa o shot padrao fora de todas as zonas", function()
		local resolver = CameraResolver.new(newConfig())
		harness.assert.equal(resolver:resolve(Vector3.new(0, 20, 0)), "Default")
	end)

	harness.it("usa a primeira zona na fronteira compartilhada", function()
		local resolver = CameraResolver.new(newConfig())
		harness.assert.equal(resolver:resolve(Vector3.new(5, 0, 0)), "First")
	end)

	harness.it("rejeita defaultShotId inexistente", function()
		local config = newConfig()
		config.defaultShotId = "Missing"
		assertInvalid(config)
	end)

	harness.it("rejeita shot de zona inexistente", function()
		local config = newConfig()
		config.zones[1].shotId = "Missing"
		assertInvalid(config)
	end)

	harness.it("rejeita FOV fora do intervalo", function()
		local config = newConfig()
		config.shots.First.fieldOfView = 0
		assertInvalid(config)

		config = newConfig()
		config.shots.First.fieldOfView = 121
		assertInvalid(config)
	end)

	harness.it("rejeita dimensoes de volume nao positivas", function()
		local config = newConfig()
		config.zones[1].volume.size = Vector3.new(0, 10, 10)
		assertInvalid(config)

		config = newConfig()
		config.zones[1].volume.size = Vector3.new(10, -1, 10)
		assertInvalid(config)
	end)

	harness.it("nao altera a configuracao recebida", function()
		local config = newConfig()
		local defaultShotId = config.defaultShotId
		local firstShot = config.shots.First
		local firstSize = config.zones[1].volume.size
		CameraResolver.new(config)
		harness.assert.equal(config.defaultShotId, defaultShotId)
		harness.assert.equal(config.shots.First, firstShot)
		harness.assert.equal(config.zones[1].volume.size, firstSize)
	end)
end)
