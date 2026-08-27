--!strict

local TankControlMath = {}

local ROTATION_RADIANS_PER_SECOND = math.rad(200)
local BACKWARD_SPEED_RATIO = 0.7

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

-- Projeta o vetor no plano horizontal e normaliza; usa o fallback quando a
-- projecao e nula (vetor puramente vertical).
function TankControlMath.horizontalUnit(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude == 0 then
		return fallback
	end
	return horizontal.Unit
end

function TankControlMath.resolveSpeed(
	input: InputState & { running: boolean },
	walkSpeed: number,
	runSpeed: number
): number
	if input.backward and not input.forward then
		return walkSpeed * BACKWARD_SPEED_RATIO
	end

	return if input.running then runSpeed else walkSpeed
end

function TankControlMath.calculate(lookVector: Vector3, input: InputState, deltaTime: number): Motion
	local moveAmount = (if input.forward then 1 else 0) - (if input.backward then 1 else 0)
	local rotationAmount = (if input.left then 1 else 0) - (if input.right then 1 else 0)

	return {
		moveDirection = TankControlMath.horizontalUnit(lookVector, Vector3.zero) * moveAmount,
		rotationRadians = ROTATION_RADIANS_PER_SECOND * rotationAmount * deltaTime,
	}
end

return TankControlMath
