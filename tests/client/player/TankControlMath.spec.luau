--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TankControlMath = require(ReplicatedStorage.Shared.player.TankControlMath)

return function()
	local testExpect = expect

	local function assertVectorNear(actual: Vector3, expected: Vector3): ()
		testExpect(actual.X).to.be.near(expected.X, 0.0001)
		testExpect(actual.Y).to.be.near(expected.Y, 0.0001)
		testExpect(actual.Z).to.be.near(expected.Z, 0.0001)
	end

	describe("TankControlMath", function()
		it("move W na direcao horizontal do olhar", function()
			local motion = TankControlMath.calculate(Vector3.new(1, 5, 1), {
				forward = true,
				backward = false,
				left = false,
				right = false,
			}, 1 / 60)

			assertVectorNear(motion.moveDirection, Vector3.new(1, 0, 1).Unit)
		end)

		it("move S na direcao oposta ao olhar", function()
			local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
				forward = false,
				backward = true,
				left = false,
				right = false,
			}, 1 / 60)

			assertVectorNear(motion.moveDirection, Vector3.new(0, 0, 1))
		end)

		it("anula movimento quando W e S estao pressionados", function()
			local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
				forward = true,
				backward = true,
				left = false,
				right = false,
			}, 1 / 60)

			assertVectorNear(motion.moveDirection, Vector3.zero)
		end)

		it("ignora o componente vertical do olhar", function()
			local motion = TankControlMath.calculate(Vector3.new(0, 10, -1), {
				forward = true,
				backward = false,
				left = false,
				right = false,
			}, 1 / 60)

			assertVectorNear(motion.moveDirection, Vector3.new(0, 0, -1))
		end)

		it("gira para lados opostos a 200 graus por segundo", function()
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

			expect(leftMotion.rotationRadians).to.be.near(math.rad(100), 0.0001)
			expect(rightMotion.rotationRadians).to.be.near(-math.rad(100), 0.0001)
		end)

		it("anula rotacao quando A e D estao pressionados", function()
			local motion = TankControlMath.calculate(Vector3.new(0, 0, -1), {
				forward = false,
				backward = false,
				left = true,
				right = true,
			}, 1 / 60)

			expect(motion.rotationRadians).to.equal(0)
		end)

		it("usa o fallback quando a projecao horizontal e nula", function()
			local direction = TankControlMath.horizontalUnit(Vector3.new(0, 5, 0), Vector3.new(0, 0, -1))

			assertVectorNear(direction, Vector3.new(0, 0, -1))
		end)

		it("descarta o componente vertical antes de normalizar", function()
			local direction = TankControlMath.horizontalUnit(Vector3.new(3, 10, -4), Vector3.zero)

			assertVectorNear(direction, Vector3.new(3, 0, -4).Unit)
		end)
	end)
end
