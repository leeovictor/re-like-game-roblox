--!strict

local WallWalkerController = {}
WallWalkerController.__index = WallWalkerController

local EPSILON = 0.0001

export type WallWalkerConfig = {
	targetProvider: () -> Vector3?,
	initialNormal: Vector3?,
	speed: number?,
	surfaceOffset: number?,
	probeDistance: number?,
	normalSmoothing: number?,
}

export type WallWalker = {
	start: (self: WallWalker) -> (),
	stop: (self: WallWalker) -> (),
	step: (self: WallWalker, deltaTime: number) -> (),
	destroy: (self: WallWalker) -> (),
}

local function unitOr(value: Vector3, fallback: Vector3): Vector3
	if value.Magnitude <= EPSILON then
		return fallback
	end
	return value.Unit
end

local function projectOnTangent(direction: Vector3, normal: Vector3): Vector3
	return direction - normal * direction:Dot(normal)
end

local function tangentFallback(normal: Vector3): Vector3
	local reference = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return unitOr(projectOnTangent(reference, normal), Vector3.zAxis)
end

local function makeRaycastParams(root: BasePart): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function castSurface(
	position: Vector3,
	normal: Vector3,
	probeDistance: number,
	params: RaycastParams
): RaycastResult?
	local origin = position + normal * 0.5
	return workspace:Raycast(origin, -normal * probeDistance, params)
end

local function findSurface(
	position: Vector3,
	preferredNormal: Vector3,
	probeDistance: number,
	params: RaycastParams
): RaycastResult?
	local preferredHit = castSurface(position, preferredNormal, probeDistance, params)
	if preferredHit ~= nil then
		return preferredHit
	end

	-- Fallback used when a corner changes the surface normal abruptly.
	local candidates = {
		Vector3.xAxis,
		-Vector3.xAxis,
		Vector3.yAxis,
		-Vector3.yAxis,
		Vector3.zAxis,
		-Vector3.zAxis,
	}
	local closestHit: RaycastResult? = nil
	for _, normal in candidates do
		local hit = castSurface(position, normal, probeDistance, params)
		if hit ~= nil and (closestHit == nil or hit.Distance < closestHit.Distance) then
			closestHit = hit
		end
	end
	return closestHit
end

function WallWalkerController.new(root: BasePart, config: WallWalkerConfig): WallWalker
	assert(config ~= nil, "WallWalkerController precisa de uma configuração")
	assert(config.targetProvider ~= nil, "targetProvider não pode ser nil")

	local initialNormal = unitOr(config.initialNormal or root.CFrame.UpVector, Vector3.yAxis)
	local self: any = setmetatable({
		root = root,
		targetProvider = config.targetProvider,
		speed = config.speed or 12,
		surfaceOffset = config.surfaceOffset or 1,
		probeDistance = config.probeDistance or 12,
		normalSmoothing = math.clamp(config.normalSmoothing or 0.35, 0, 1),
		normal = initialNormal,
		params = makeRaycastParams(root),
		connection = nil,
		wasAnchored = root.Anchored,
	}, WallWalkerController)

	-- PivotTo seria afetado pela simulação física; o protótipo é cinemático.
	root.Anchored = true
	return self
end

function WallWalkerController:start(): ()
	if self.connection ~= nil then
		return
	end

	local RunService = game:GetService("RunService")
	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		self:step(deltaTime)
	end)
end

function WallWalkerController:stop(): ()
	if self.connection == nil then
		return
	end
	self.connection:Disconnect()
	self.connection = nil
end

function WallWalkerController:step(deltaTime: number): ()
	local root = self.root
	if root.Parent == nil then
		self:stop()
		return
	end

	local surfaceHit = findSurface(root.Position, self.normal, self.probeDistance, self.params)
	if surfaceHit == nil then
		return
	end

	local measuredNormal = unitOr(surfaceHit.Normal, self.normal)
	self.normal = unitOr(self.normal:Lerp(measuredNormal, self.normalSmoothing), measuredNormal)

	local targetPosition = self.targetProvider()
	local tangentDirection = Vector3.zero
	if targetPosition ~= nil then
		tangentDirection = projectOnTangent(targetPosition - root.Position, self.normal)
	end

	local movement = Vector3.zero
	if tangentDirection.Magnitude > EPSILON then
		local travelDistance = math.min(math.max(deltaTime, 0) * self.speed, tangentDirection.Magnitude)
		movement = tangentDirection.Unit * travelDistance
	end

	local nextPosition = root.Position + movement
	local nextRoot = root.Position
	local nextNormal = self.normal
	local nextSurfaceHit = findSurface(nextPosition, self.normal, self.probeDistance, self.params)
	if nextSurfaceHit ~= nil then
		nextRoot = nextSurfaceHit.Position + nextSurfaceHit.Normal * self.surfaceOffset
		nextNormal = unitOr(
			self.normal:Lerp(nextSurfaceHit.Normal, self.normalSmoothing),
			self.normal
		)
	end

	local forward = projectOnTangent(tangentDirection, nextNormal)
	if forward.Magnitude <= EPSILON then
		forward = projectOnTangent(root.CFrame.LookVector, nextNormal)
	end
	forward = unitOr(forward, tangentFallback(nextNormal))

	root.CFrame = CFrame.lookAt(nextRoot, nextRoot + forward, nextNormal)
end

function WallWalkerController:destroy(): ()
	self:stop()
	if self.root.Parent ~= nil then
		self.root.Anchored = self.wasAnchored
	end
end

return WallWalkerController
