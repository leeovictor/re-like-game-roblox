--!strict

local TankControlMath = {}

local ROTATION_RADIANS_PER_SECOND = math.rad(120)

export type InputState = {
	forward: boolean,
	backward: boolean,
	left: boolean,
	right: boolean,
}

export type Motion = {
	moveDirection: Vector3,
	rotationRadians: number,
}

local function horizontalUnit(vector: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude == 0 then
		return Vector3.zero
	end
	return horizontal.Unit
end

function TankControlMath.calculate(lookVector: Vector3, input: InputState, deltaTime: number): Motion
	local moveAmount = (if input.forward then 1 else 0) - (if input.backward then 1 else 0)
	local rotationAmount = (if input.left then 1 else 0) - (if input.right then 1 else 0)

	return {
		moveDirection = horizontalUnit(lookVector) * moveAmount,
		rotationRadians = ROTATION_RADIANS_PER_SECOND * rotationAmount * deltaTime,
	}
end

return TankControlMath
