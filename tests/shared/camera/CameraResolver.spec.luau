--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CameraResolver = require(ReplicatedStorage.Shared.camera.CameraResolver)

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
	expect(ok).to.equal(false)
end

return function()
	describe("CameraResolver", function()
		it("retorna o shot de um ponto dentro do volume", function()
			local resolver = CameraResolver.new(newConfig())
			expect(resolver:resolve(Vector3.new(0, 0, 0))).to.equal("First")
		end)

		it("rejeita pontos fora em cada eixo", function()
			local resolver = CameraResolver.new(newConfig())
			expect(resolver:resolve(Vector3.new(5.01, 0, 0))).to.equal("Second")
			expect(resolver:resolve(Vector3.new(0, 5.01, 0))).to.equal(nil)
			expect(resolver:resolve(Vector3.new(0, 0, 5.01))).to.equal(nil)
		end)

		it("reconhece um ponto em um volume rotacionado", function()
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
			expect(resolver:resolve(pointInside)).to.equal("Rotated")
		end)

		it("retorna shots diferentes em zonas adjacentes", function()
			local resolver = CameraResolver.new(newConfig())
			expect(resolver:resolve(Vector3.new(-4.99, 0, 0))).to.equal("First")
			expect(resolver:resolve(Vector3.new(5.01, 0, 0))).to.equal("Second")
		end)

		it("retorna nil fora de todas as zonas", function()
			local resolver = CameraResolver.new(newConfig())
			expect(resolver:resolve(Vector3.new(0, 20, 0))).to.equal(nil)
		end)

		it("usa a primeira zona na fronteira compartilhada", function()
			local resolver = CameraResolver.new(newConfig())
			expect(resolver:resolve(Vector3.new(5, 0, 0))).to.equal("First")
		end)

		it("rejeita defaultShotId inexistente", function()
			local config = newConfig()
			config.defaultShotId = "Missing"
			assertInvalid(config)
		end)

		it("rejeita shot de zona inexistente", function()
			local config = newConfig()
			config.zones[1].shotId = "Missing"
			assertInvalid(config)
		end)

		it("rejeita FOV fora do intervalo", function()
			local config = newConfig()
			config.shots.First.fieldOfView = 0
			assertInvalid(config)

			config = newConfig()
			config.shots.First.fieldOfView = 121
			assertInvalid(config)
		end)

		it("rejeita dimensoes de volume nao positivas", function()
			local config = newConfig()
			config.zones[1].volume.size = Vector3.new(0, 10, 10)
			assertInvalid(config)

			config = newConfig()
			config.zones[1].volume.size = Vector3.new(10, -1, 10)
			assertInvalid(config)
		end)

		it("nao altera a configuracao recebida", function()
			local config = newConfig()
			local defaultShotId = config.defaultShotId
			local firstShot = config.shots.First
			local firstSize = config.zones[1].volume.size
			CameraResolver.new(config)
			expect(config.defaultShotId).to.equal(defaultShotId)
			expect(config.shots.First).to.equal(firstShot)
			expect(config.zones[1].volume.size).to.equal(firstSize)
		end)
	end)
end
