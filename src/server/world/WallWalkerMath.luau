--!strict

local WallWalkerMath = {}

local EPSILON = 0.0001
local DEFAULT_FRAME_RATE = 60

export type State = "Stable" | "ApproachingCorner" | "Reacquiring" | "Blocked" | "Recovered"

export type RejectionReason =
    "NoSurface"
    | "InvalidNormal"
    | "InsufficientClearance"
    | "TangentialDirectionTooSmall"
    | "MovementBlocked"
    | "CorrectionTooLarge"
    | "NormalIncompatible"
    | "RecoveryFailed"

local function clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

function WallWalkerMath.unitOr(value: Vector3, fallback: Vector3): Vector3
	if value.Magnitude <= EPSILON then
		if fallback.Magnitude <= EPSILON then
			return Vector3.yAxis
		end
		return fallback.Unit
	end
	return value.Unit
end

function WallWalkerMath.projectOnTangent(direction: Vector3, normal: Vector3): Vector3
	local unitNormal = WallWalkerMath.unitOr(normal, Vector3.yAxis)
	return direction - unitNormal * direction:Dot(unitNormal)
end

function WallWalkerMath.tangentFallback(normal: Vector3): Vector3
	local unitNormal = WallWalkerMath.unitOr(normal, Vector3.yAxis)
	local reference = if math.abs(unitNormal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return WallWalkerMath.unitOr(WallWalkerMath.projectOnTangent(reference, unitNormal), Vector3.zAxis)
end

function WallWalkerMath.tangentBasis(normal: Vector3, reference: Vector3): (Vector3, Vector3)
	local unitNormal = WallWalkerMath.unitOr(normal, Vector3.yAxis)
	local first = WallWalkerMath.projectOnTangent(reference, unitNormal)
	if first.Magnitude <= EPSILON then
		first = WallWalkerMath.tangentFallback(unitNormal)
	else
		first = first.Unit
	end

	local second = unitNormal:Cross(first)
	return first, WallWalkerMath.unitOr(second, Vector3.zAxis)
end

function WallWalkerMath.normalAngle(first: Vector3, second: Vector3): number
	local firstUnit = WallWalkerMath.unitOr(first, Vector3.yAxis)
	local secondUnit = WallWalkerMath.unitOr(second, Vector3.yAxis)
	return math.acos(clamp(firstUnit:Dot(secondUnit), -1, 1))
end

function WallWalkerMath.normalCompatible(first: Vector3, second: Vector3, maximumAngle: number): boolean
	return WallWalkerMath.normalAngle(first, second) <= math.max(maximumAngle, 0)
end

function WallWalkerMath.smoothingAlpha(smoothing: number, deltaTime: number): number
	local clampedSmoothing = clamp(smoothing, 0, 1)
	local safeDeltaTime = math.max(deltaTime, 0)
	if clampedSmoothing >= 1 then
		return 1
	end
	if clampedSmoothing <= 0 or safeDeltaTime <= 0 then
		return 0
	end

	-- Keep the configured value equivalent to the old per-frame alpha at 60 Hz.
	return 1 - (1 - clampedSmoothing) ^ (safeDeltaTime * DEFAULT_FRAME_RATE)
end

function WallWalkerMath.smoothNormal(
	current: Vector3,
	measured: Vector3,
	smoothing: number,
	deltaTime: number,
	maximumAngle: number?
): Vector3
	local currentUnit = WallWalkerMath.unitOr(current, measured)
	local measuredUnit = WallWalkerMath.unitOr(measured, currentUnit)
	local alpha = WallWalkerMath.smoothingAlpha(smoothing, deltaTime)
	local angle = WallWalkerMath.normalAngle(currentUnit, measuredUnit)
	if maximumAngle ~= nil and maximumAngle >= 0 and angle > maximumAngle then
		alpha = math.min(alpha, maximumAngle / angle)
	end
	return WallWalkerMath.unitOr(currentUnit:Lerp(measuredUnit, alpha), measuredUnit)
end

function WallWalkerMath.clampTravel(direction: Vector3, maximumDistance: number, remainingDistance: number?): Vector3
	local magnitude = direction.Magnitude
	if magnitude <= EPSILON then
		return Vector3.zero
	end

	local distance = math.max(maximumDistance, 0)
	if remainingDistance ~= nil then
		distance = math.min(distance, math.max(remainingDistance, 0))
	end
	return direction.Unit * math.min(magnitude, distance)
end

function WallWalkerMath.classifyState(
	previous: State,
	contactFound: boolean,
	normalChangedQuickly: boolean,
	movementAccepted: boolean,
	blockedFrames: number,
	blockedFrameLimit: number
): State
	if previous == "Blocked" then
		if contactFound and movementAccepted then
			return "Recovered"
		end
		return "Blocked"
	end

	if blockedFrames >= blockedFrameLimit and not movementAccepted then
		return "Blocked"
	end
	if not contactFound then
		return "Reacquiring"
	end
	if normalChangedQuickly then
		return "ApproachingCorner"
	end
	if previous == "Reacquiring" then
		return "Recovered"
	end
	return "Stable"
end

return WallWalkerMath
