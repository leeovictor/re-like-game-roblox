--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

type Vector3Value = {
	X: number,
	Y: number,
	Z: number,
	Unit: any,
}

type LuneRoblox = {
	Vector3: {
		new: (number, number, number) -> Vector3Value,
		zero: Vector3Value,
	},
}

local roblox = require("@lune/roblox") :: LuneRoblox
local Vector3 = roblox.Vector3
local TankControlMath = loader.load("src/shared/player/TankControlMath.luau")

local function assertVectorNear(actual: Vector3Value, expected: Vector3Value): ()
	harness.assert.near(actual.X, expected.X, 0.0001)
	harness.assert.near(actual.Y, expected.Y, 0.0001)
	harness.assert.near(actual.Z, expected.Z, 0.0001)
end

harness.describe("TankControlMath", function()
	harness.it("move W na direcao horizontal do olhar", function()
		local motion = TankControlMath.calculate(Vector3.new(1, 5, 1), {
			forward = true,
			backward = false,
			left = false,
			right = false,
		}, 1 / 60)

		assertVectorNear(motion.moveDirection, Vector3.new(1, 0, 1).Unit)
	end)

	harness.it("move S na direcao oposta ao olhar", function()
		local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
			forward = false,
			backward = true,
			left = false,
			right = false,
		}, 1 / 60)

		assertVectorNear(motion.moveDirection, Vector3.new(0, 0, 1))
	end)

	harness.it("anula movimento quando W e S estao pressionados", function()
		local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
			forward = true,
			backward = true,
			left = false,
			right = false,
		}, 1 / 60)

		assertVectorNear(motion.moveDirection, Vector3.zero)
	end)

	harness.it("ignora o componente vertical do olhar", function()
		local motion = TankControlMath.calculate(Vector3.new(0, 10, -1), {
			forward = true,
			backward = false,
			left = false,
			right = false,
		}, 1 / 60)

		assertVectorNear(motion.moveDirection, Vector3.new(0, 0, -1))
	end)

	harness.it("gira para lados opostos a 120 graus por segundo", function()
		local leftMotion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
			forward = false,
			backward = false,
			left = true,
			right = false,
		}, 0.5)
		local rightMotion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
			forward = false,
			backward = false,
			left = false,
			right = true,
		}, 0.5)

		harness.assert.near(leftMotion.rotationRadians, math.rad(60), 0.0001)
		harness.assert.near(rightMotion.rotationRadians, -math.rad(60), 0.0001)
	end)

	harness.it("anula rotacao quando A e D estao pressionados", function()
		local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
			forward = false,
			backward = false,
			left = true,
			right = true,
		}, 1 / 60)

		harness.assert.equal(motion.rotationRadians, 0)
	end)
end)
