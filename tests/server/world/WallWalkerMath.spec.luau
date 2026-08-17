--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

type Vector3Value = {
	X: number,
	Y: number,
	Z: number,
	Magnitude: number,
	Unit: Vector3Value,
	Dot: (self: Vector3Value, other: Vector3Value) -> number,
}

type LuneRoblox = {
	Vector3: {
		new: (number, number, number) -> Vector3Value,
		yAxis: Vector3Value,
		xAxis: Vector3Value,
		zAxis: Vector3Value,
		zero: Vector3Value,
	},
}

local roblox = require("@lune/roblox") :: LuneRoblox
local Vector3 = roblox.Vector3
local WallWalkerMath = loader.load("src/server/world/WallWalkerMath.luau")

local function assertVector3(actual: Vector3Value, expected: Vector3Value, message: string)
	harness.assert.near(actual.X, expected.X, 1e-5, message .. " X")
	harness.assert.near(actual.Y, expected.Y, 1e-5, message .. " Y")
	harness.assert.near(actual.Z, expected.Z, 1e-5, message .. " Z")
end

harness.describe("WallWalkerMath", function()
	harness.it("projeta a direcao no plano tangente", function()
		local projected = WallWalkerMath.projectOnTangent(Vector3.new(3, 4, -2), Vector3.yAxis)
		assertVector3(projected, Vector3.new(3, 0, -2), "projected")
	end)

	harness.it("produz uma tangente ortogonal para uma normal valida", function()
		local tangent = WallWalkerMath.tangentFallback(Vector3.yAxis)
		harness.assert.near(tangent.Magnitude, 1, 1e-5, "fallback magnitude")
		harness.assert.near(tangent:Dot(Vector3.yAxis), 0, 1e-5, "fallback orthogonality")
	end)

	harness.it("constroi uma base tangente ortogonal", function()
		local first, second = WallWalkerMath.tangentBasis(Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))
		harness.assert.near(first.Magnitude, 1, 1e-5, "first magnitude")
		harness.assert.near(second.Magnitude, 1, 1e-5, "second magnitude")
		harness.assert.near(first:Dot(Vector3.yAxis), 0, 1e-5, "first normal")
		harness.assert.near(second:Dot(Vector3.yAxis), 0, 1e-5, "second normal")
		harness.assert.near(first:Dot(second), 0, 1e-5, "basis orthogonality")
	end)

	harness.it("limita o deslocamento pela distancia maxima", function()
		local movement = WallWalkerMath.clampTravel(Vector3.new(10, 0, 0), 2, nil)
		assertVector3(movement, Vector3.new(2, 0, 0), "clamped movement")
		local remaining = WallWalkerMath.clampTravel(Vector3.new(10, 0, 0), 5, 1.5)
		assertVector3(remaining, Vector3.new(1.5, 0, 0), "remaining movement")
	end)

	harness.it("calcula suavizacao equivalente a uma constante de tempo", function()
		local alpha = WallWalkerMath.smoothingAlpha(0.35, 1 / 60)
		harness.assert.near(alpha, 0.35, 1e-5, "60 Hz alpha")
		local smoothed = WallWalkerMath.smoothNormal(
			Vector3.yAxis,
			Vector3.xAxis,
			1,
			1,
			math.pi / 2
		)
		harness.assert.near(smoothed.Magnitude, 1, 1e-5, "smoothed magnitude")
		harness.assert.near(WallWalkerMath.normalAngle(smoothed, Vector3.yAxis), math.pi / 2, 1e-5, "angle cap")
	end)

	harness.it("classifica perda, bloqueio e recuperacao", function()
	harness.assert.equal(
		WallWalkerMath.classifyState("Stable", false, false, false, 1, 3),
		"Reacquiring"
	)
	harness.assert.equal(
		WallWalkerMath.classifyState("Reacquiring", false, false, false, 3, 3),
		"Blocked"
	)
	harness.assert.equal(
		WallWalkerMath.classifyState("Blocked", true, false, true, 0, 3),
		"Recovered"
	)
	harness.assert.equal(
		WallWalkerMath.classifyState("Stable", true, true, true, 0, 3),
		"ApproachingCorner"
	)
	end)
end)
