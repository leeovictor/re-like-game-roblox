--!strict

local WallWalkerMath = require(script.Parent.WallWalkerMath)
local WallWalkerSurfaceProbe = require(script.Parent.WallWalkerSurfaceProbe)

local WallWalkerController = {}
WallWalkerController.__index = WallWalkerController

local EPSILON = 0.0001
local DEFAULT_MAX_DELTA_TIME = 0.1

export type Waypoint = {
	position: Vector3,
	normal: Vector3?,
	arrivalRadius: number?,
	id: string?,
}

export type WallWalkerDiagnostics = {
	lastMeasuredNormal: Vector3?,
	lastProbeDistance: number?,
	framesWithoutSurface: number,
	lastAcceptedPoint: Vector3?,
	lastRejectedPoint: Vector3?,
	lastRejectionReason: WallWalkerMath.RejectionReason?,
	tangentMagnitude: number,
	timeSinceSurfaceChange: number,
	state: WallWalkerMath.State,
	recoveryAttempts: number,
	consecutiveRejectedMoves: number,
	lastCorrectionDistance: number,
	lastTravelDistance: number,
	lastSweepDistance: number?,
	lastSweepNormal: Vector3?,
}

export type WallWalkerConfig = {
	targetProvider: () -> Vector3?,
	initialNormal: Vector3?,
	speed: number?,
	surfaceOffset: number?,
	probeDistance: number?,
	normalSmoothing: number?,
	maxDeltaTime: number?,
	maxFrameTravel: number?,
	maxCorrectionDistance: number?,
	clearanceMargin: number?,
	contactTolerance: number?,
	maximumContactAngle: number?,
	maximumTransitionAngle: number?,
	cornerAngle: number?,
	maximumOrientationAngle: number?,
	blockedFrameLimit: number?,
		recoverySpeedMultiplier: number?,
		minimumRecoveryStep: number?,
	maxRecoveryDistance: number?,
	shape: WallWalkerSurfaceProbe.ProbeShape?,
	bodyRadius: number?,
	bodySize: Vector3?,
	worldRoot: WorldRoot?,
	excludeInstances: { Instance }?,
	onStateChanged: ((WallWalkerMath.State, WallWalkerMath.State) -> ())?,
}

export type WallWalker = {
	start: (self: WallWalker) -> (),
	stop: (self: WallWalker) -> (),
	step: (self: WallWalker, deltaTime: number) -> (),
	setWaypoints: (self: WallWalker, waypoints: { Waypoint }) -> (),
	clearWaypoints: (self: WallWalker) -> (),
	getCurrentWaypoint: (self: WallWalker) -> Waypoint?,
	getState: (self: WallWalker) -> WallWalkerMath.State,
	getDiagnostics: (self: WallWalker) -> WallWalkerDiagnostics,
	destroy: (self: WallWalker) -> (),
}

type Candidate = {
	position: Vector3,
	contactNormal: Vector3,
	orientationNormal: Vector3,
	forward: Vector3,
	travelDistance: number,
	correctionDistance: number,
}

local function finiteOr(value: number, fallback: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function copyDiagnostics(diagnostics: WallWalkerDiagnostics): WallWalkerDiagnostics
	return {
		lastMeasuredNormal = diagnostics.lastMeasuredNormal,
		lastProbeDistance = diagnostics.lastProbeDistance,
		framesWithoutSurface = diagnostics.framesWithoutSurface,
		lastAcceptedPoint = diagnostics.lastAcceptedPoint,
		lastRejectedPoint = diagnostics.lastRejectedPoint,
		lastRejectionReason = diagnostics.lastRejectionReason,
		tangentMagnitude = diagnostics.tangentMagnitude,
		timeSinceSurfaceChange = diagnostics.timeSinceSurfaceChange,
		state = diagnostics.state,
		recoveryAttempts = diagnostics.recoveryAttempts,
		consecutiveRejectedMoves = diagnostics.consecutiveRejectedMoves,
		lastCorrectionDistance = diagnostics.lastCorrectionDistance,
		lastTravelDistance = diagnostics.lastTravelDistance,
		lastSweepDistance = diagnostics.lastSweepDistance,
		lastSweepNormal = diagnostics.lastSweepNormal,
	}
end

local function targetFor(self: any): (Vector3?, Waypoint?)
	local waypoint = self.waypoints[self.waypointIndex]
	if waypoint ~= nil then
		return waypoint.position, waypoint
	end
	return self.targetProvider(), nil
end

local function selectContact(
	contacts: { WallWalkerSurfaceProbe.SurfaceContact },
	preferredNormal: Vector3,
	maximumAngle: number,
	allowTransition: boolean,
	referenceDirection: Vector3,
	maximumTransitionAngle: number
): WallWalkerSurfaceProbe.SurfaceContact?
	local best: WallWalkerSurfaceProbe.SurfaceContact? = nil
	local bestScore = math.huge
	local reference = WallWalkerMath.unitOr(referenceDirection, Vector3.zAxis)
	for _, contact in contacts do
		local angle = WallWalkerMath.normalAngle(preferredNormal, contact.normal)
		local allowedAngle = if allowTransition then maximumTransitionAngle else maximumAngle
		if angle <= allowedAngle then
			local forwardProbe = math.max(contact.probeOffset:Dot(reference), 0)
			local forwardBias = if allowTransition then forwardProbe * 0.75 else 0
			local score = angle * 1.5 + contact.distance * 0.1 + contact.probeOffset.Magnitude - forwardBias
			if score < bestScore then
				best = contact
				bestScore = score
			end
		end
	end
	return best
end

local function makeOrientation(position: Vector3, forward: Vector3, normal: Vector3): CFrame
	return CFrame.lookAt(position, position + forward, normal)
end

function WallWalkerController.new(root: BasePart, config: WallWalkerConfig): WallWalker
	assert(config ~= nil, "WallWalkerController precisa de uma configuração")
	assert(config.targetProvider ~= nil, "targetProvider não pode ser nil")

	local initialNormal = WallWalkerMath.unitOr(config.initialNormal or root.CFrame.UpVector, Vector3.yAxis)
	local speed = math.max(config.speed or 12, 0)
	local surfaceOffset = math.max(config.surfaceOffset or root.Size.X / 2, 0)
	local clearanceMargin = math.max(config.clearanceMargin or 0, 0)
	local probeDistance = math.max(config.probeDistance or 12, 0.1)
	local maximumContactAngle = math.max(config.maximumContactAngle or math.rad(100), 0)
	local shape: WallWalkerSurfaceProbe.ProbeShape = config.shape or "Sphere"
	local bodyRadius = config.bodyRadius or root.Size.X / 2
	local bodySize = config.bodySize or root.Size

	local self: any = setmetatable({
		root = root,
		targetProvider = config.targetProvider,
		speed = speed,
		maxDeltaTime = math.max(config.maxDeltaTime or DEFAULT_MAX_DELTA_TIME, 0.001),
		maxFrameTravel = math.max(config.maxFrameTravel or math.max(speed * DEFAULT_MAX_DELTA_TIME, 2), 0),
		maxCorrectionDistance = math.max(config.maxCorrectionDistance or math.max(surfaceOffset, 2), 0),
		normalSmoothing = math.clamp(config.normalSmoothing or 0.35, 0, 1),
		maximumContactAngle = maximumContactAngle,
		maximumTransitionAngle = math.max(config.maximumTransitionAngle or math.rad(125), 0),
		cornerAngle = math.max(config.cornerAngle or math.rad(35), 0),
		maximumOrientationAngle = math.max(config.maximumOrientationAngle or math.rad(25), 0),
		blockedFrameLimit = math.max(math.floor(config.blockedFrameLimit or 8), 1),
		recoverySpeedMultiplier = math.clamp(config.recoverySpeedMultiplier or 0.35, 0.05, 1),
		minimumRecoveryStep = math.max(config.minimumRecoveryStep or 0.5, 0),
		maxRecoveryDistance = math.max(config.maxRecoveryDistance or 4, 0),
		contactNormal = initialNormal,
		probeNormal = initialNormal,
		orientationNormal = initialNormal,
		state = "Stable" :: WallWalkerMath.State,
		blockedFrames = 0,
		framesWithoutSurface = 0,
		recoveryAttempts = 0,
		waypoints = {} :: { Waypoint },
		waypointIndex = 1,
		connection = nil,
		wasAnchored = root.Anchored,
		onStateChanged = config.onStateChanged,
	}, WallWalkerController)

	self.probe = WallWalkerSurfaceProbe.new({
		worldRoot = config.worldRoot,
		shape = shape,
		radius = bodyRadius,
		size = bodySize,
		surfaceOffset = surfaceOffset,
		clearanceMargin = clearanceMargin,
		probeDistance = probeDistance,
		contactTolerance = math.max(config.contactTolerance or 0.5, 0),
		probeSpacing = math.max(root.Size.X * 0.325, 0.25),
		root = root,
		exclude = config.excludeInstances,
	})

	self.diagnostics = {
		lastMeasuredNormal = nil,
		lastProbeDistance = nil,
		framesWithoutSurface = 0,
		lastAcceptedPoint = root.Position,
		lastRejectedPoint = nil,
		lastRejectionReason = nil,
		tangentMagnitude = 0,
		timeSinceSurfaceChange = 0,
		state = "Stable" :: WallWalkerMath.State,
		recoveryAttempts = 0,
		consecutiveRejectedMoves = 0,
		lastCorrectionDistance = 0,
		lastTravelDistance = 0,
		lastSweepDistance = nil,
		lastSweepNormal = nil,
	}

	root.Anchored = true
	self:_publishDiagnostics()
	return self
end

function WallWalkerController:_setState(nextState: WallWalkerMath.State): ()
	local previousState = self.state
	self.state = nextState
	self.diagnostics.state = nextState
	self:_publishDiagnostics()
	if previousState ~= nextState and self.onStateChanged ~= nil then
		self.onStateChanged(previousState, nextState)
	end
end

function WallWalkerController:_publishDiagnostics(): ()
	if self.root.Parent == nil then
		return
	end
	self.root:SetAttribute("WallWalkerCurrentPosition", self.root.Position)
	self.root:SetAttribute("WallWalkerState", self.diagnostics.state)
	self.root:SetAttribute("WallWalkerLastRejection", self.diagnostics.lastRejectionReason)
	self.root:SetAttribute("WallWalkerFramesWithoutSurface", self.diagnostics.framesWithoutSurface)
	self.root:SetAttribute("WallWalkerTangentMagnitude", self.diagnostics.tangentMagnitude)
	self.root:SetAttribute("WallWalkerRecoveryAttempts", self.diagnostics.recoveryAttempts)
	self.root:SetAttribute("WallWalkerLastProbeDistance", self.diagnostics.lastProbeDistance)
	self.root:SetAttribute("WallWalkerLastCorrectionDistance", self.diagnostics.lastCorrectionDistance)
	self.root:SetAttribute("WallWalkerLastTravelDistance", self.diagnostics.lastTravelDistance)
	self.root:SetAttribute("WallWalkerLastSweepDistance", self.diagnostics.lastSweepDistance)
	self.root:SetAttribute("WallWalkerLastSweepNormal", self.diagnostics.lastSweepNormal)
	self.root:SetAttribute("WallWalkerLastMeasuredNormal", self.diagnostics.lastMeasuredNormal)
	self.root:SetAttribute("WallWalkerLastAcceptedPoint", self.diagnostics.lastAcceptedPoint)
	self.root:SetAttribute("WallWalkerLastRejectedPoint", self.diagnostics.lastRejectedPoint)
end

function WallWalkerController:_reject(position: Vector3, reason: WallWalkerMath.RejectionReason): ()
	self.blockedFrames += 1
	self.diagnostics.lastRejectedPoint = position
	self.diagnostics.lastRejectionReason = reason
	self.diagnostics.consecutiveRejectedMoves = self.blockedFrames
	self:_publishDiagnostics()
	self:_setState(
		WallWalkerMath.classifyState(
			self.state,
			false,
			false,
			false,
			self.blockedFrames,
			self.blockedFrameLimit
		)
	)
end

function WallWalkerController:_accept(candidate: Candidate): ()
	self.root.CFrame = makeOrientation(candidate.position, candidate.forward, candidate.orientationNormal)
	self.diagnostics.lastAcceptedPoint = candidate.position
	self.diagnostics.lastCorrectionDistance = candidate.correctionDistance
	self.diagnostics.lastTravelDistance = candidate.travelDistance
	self.diagnostics.consecutiveRejectedMoves = 0
	self.blockedFrames = 0
	self:_publishDiagnostics()
	self.contactNormal = candidate.contactNormal
	self.probeNormal = candidate.contactNormal
	self:_setState(if self.state == "Reacquiring" or self.state == "Blocked" then "Recovered" else "Stable")
	end

function WallWalkerController:_candidate(
	position: Vector3,
	referenceDirection: Vector3,
	deltaTime: number,
	allowTransition: boolean,
	plannedTravel: number,
	preferredNormal: Vector3?,
	surfaceHint: WallWalkerSurfaceProbe.SurfaceContact?
): (Candidate?, WallWalkerMath.RejectionReason?)
	local probeNormal = preferredNormal or self.probeNormal
	local result = self.probe:find(position, probeNormal, referenceDirection, allowTransition)
	self.diagnostics.lastProbeDistance = nil
	if result.contact == nil and surfaceHint == nil then
		return nil, "NoSurface"
	end

	local contact = if surfaceHint ~= nil
		then surfaceHint
		elseif #result.contacts > 0
		then selectContact(
			result.contacts,
			probeNormal,
			self.maximumContactAngle,
			allowTransition,
			referenceDirection,
			self.maximumTransitionAngle
		)
		else nil
	if contact == nil then
		contact = surfaceHint
	end
	if contact == nil then
		return nil, "NormalIncompatible"
	end

	self.diagnostics.lastProbeDistance = contact.distance
	if contact.normal.Magnitude <= EPSILON then
		return nil, "InvalidNormal"
	end

	local measuredNormal = contact.normal.Unit
	local normalAngle = WallWalkerMath.normalAngle(self.contactNormal, measuredNormal)
	if not allowTransition and normalAngle > self.maximumContactAngle then
		return nil, "NormalIncompatible"
	end

	local orientationNormal = WallWalkerMath.smoothNormal(
		self.orientationNormal,
		measuredNormal,
		self.normalSmoothing,
		deltaTime,
		self.maximumOrientationAngle
	)
	local forward = WallWalkerMath.projectOnTangent(referenceDirection, orientationNormal)
	if forward.Magnitude <= EPSILON then
		forward = WallWalkerMath.projectOnTangent(self.root.CFrame.LookVector, orientationNormal)
	end
	forward = WallWalkerMath.unitOr(forward, WallWalkerMath.tangentFallback(orientationNormal))

	local orientation = makeOrientation(contact.point, forward, orientationNormal)
	local nextPosition = contact.point + measuredNormal * self.probe:centerOffset(measuredNormal, orientation)
	local correctionDistance = (nextPosition - position).Magnitude
	if correctionDistance > self.maxCorrectionDistance then
		return nil, "CorrectionTooLarge"
	end

	local travelDistance = (nextPosition - self.root.Position).Magnitude
	local maximumTravel = math.max(plannedTravel, 0) + self.maxCorrectionDistance
	if travelDistance > maximumTravel then
		return nil, "CorrectionTooLarge"
	end

	return {
		position = nextPosition,
		contactNormal = measuredNormal,
		orientationNormal = orientationNormal,
		forward = forward,
		travelDistance = travelDistance,
		correctionDistance = correctionDistance,
	}, nil
end

function WallWalkerController:_tryRecovery(deltaTime: number): boolean
	self.recoveryAttempts += 1
	self.diagnostics.recoveryAttempts = self.recoveryAttempts
	local first, second = WallWalkerMath.tangentBasis(self.probeNormal, self.root.CFrame.LookVector)
	local directions = { first, -first, second, -second }
	local recoveryDistance = math.min(
		self.maxRecoveryDistance,
		math.max(
			self.speed * deltaTime * self.recoverySpeedMultiplier,
			self.minimumRecoveryStep
		)
	)

	for _, direction in directions do
		local sweep = self.probe:sweep(self.root.Position, direction * recoveryDistance)
		local candidate, reason = self:_candidate(
			self.root.Position + direction * recoveryDistance,
			direction,
			deltaTime,
			true,
			recoveryDistance,
			if sweep ~= nil then sweep.normal else self.probeNormal,
			sweep
		)
		if candidate ~= nil and candidate.correctionDistance <= self.maxRecoveryDistance then
			self.orientationNormal = candidate.orientationNormal
			self:_accept(candidate)
			return true
		end
		if reason ~= nil then
			self.diagnostics.lastRejectionReason = reason
		end
	end

	self:_reject(self.root.Position, "RecoveryFailed")
	return false
end

function WallWalkerController:_advanceWaypoint(position: Vector3, waypoint: Waypoint?): ()
	if waypoint == nil then
		return
	end
	local radius = math.max(waypoint.arrivalRadius or 2, 0)
	if (waypoint.position - position).Magnitude <= radius then
		self.waypointIndex += 1
	end
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

	local safeDeltaTime = math.min(math.max(finiteOr(deltaTime, 0), 0), self.maxDeltaTime)
	self.diagnostics.timeSinceSurfaceChange += safeDeltaTime
	local activeWaypoint = self.waypoints[self.waypointIndex]
	local preferredProbeNormal = self.probeNormal
	if activeWaypoint ~= nil
		and activeWaypoint.normal ~= nil
		and (self.state == "Reacquiring" or self.state == "Blocked")
	then
		preferredProbeNormal = WallWalkerMath.unitOr(activeWaypoint.normal, preferredProbeNormal)
	end

	local currentResult = self.probe:find(
		root.Position,
		preferredProbeNormal,
		root.CFrame.LookVector,
		self.state == "Reacquiring" or self.state == "Blocked" or self.state == "ApproachingCorner"
	)
	local currentContact = selectContact(
		currentResult.contacts,
		preferredProbeNormal,
		self.maximumContactAngle,
		self.state == "Reacquiring" or self.state == "Blocked" or self.state == "ApproachingCorner",
		root.CFrame.LookVector,
		self.maximumTransitionAngle
	)
	if currentContact ~= nil then
		local expectedPosition = currentContact.point
			+ currentContact.normal * self.probe:centerOffset(currentContact.normal, root.CFrame)
		if (expectedPosition - root.Position).Magnitude > self.maxCorrectionDistance then
			currentContact = nil
		end
	end

	if currentContact == nil then
		self.framesWithoutSurface += 1
		self.diagnostics.framesWithoutSurface = self.framesWithoutSurface
		self:_setState("Reacquiring")
		self:_tryRecovery(safeDeltaTime)
		return
	end

	self.framesWithoutSurface = 0
	self.diagnostics.framesWithoutSurface = 0
	self.diagnostics.lastMeasuredNormal = currentContact.normal
	self.diagnostics.lastProbeDistance = currentContact.distance
	local normalChange = WallWalkerMath.normalAngle(self.contactNormal, currentContact.normal)
	if normalChange > self.cornerAngle then
		self.diagnostics.timeSinceSurfaceChange = 0
	end
	self.contactNormal = currentContact.normal
	self.probeNormal = currentContact.normal
	self.orientationNormal = WallWalkerMath.smoothNormal(
		self.orientationNormal,
		currentContact.normal,
		self.normalSmoothing,
		safeDeltaTime,
		self.maximumOrientationAngle
	)

	local targetPosition, waypoint = targetFor(self)
	local tangentDirection = Vector3.zero
	if targetPosition ~= nil then
		tangentDirection = WallWalkerMath.projectOnTangent(targetPosition - root.Position, self.contactNormal)
	end
	self.diagnostics.tangentMagnitude = tangentDirection.Magnitude

	local arrivalRadius = if waypoint ~= nil then math.max(waypoint.arrivalRadius or 2, 0) else 0
	if targetPosition == nil or (waypoint ~= nil and (targetPosition - root.Position).Magnitude <= arrivalRadius) then
		self:_advanceWaypoint(root.Position, waypoint)
		local candidate, reason = self:_candidate(
			root.Position,
			root.CFrame.LookVector,
			safeDeltaTime,
			normalChange > self.cornerAngle,
			0,
			self.probeNormal,
			nil
		)
		if candidate ~= nil then
			self.orientationNormal = candidate.orientationNormal
			self:_accept(candidate)
		end
		if reason ~= nil and candidate == nil then
			self:_reject(root.Position, reason)
		end
		return
	end

	if tangentDirection.Magnitude <= EPSILON then
		self:_reject(root.Position, "TangentialDirectionTooSmall")
		if self.state == "Blocked" then
			self:_tryRecovery(safeDeltaTime)
		end
		return
	end

	local movement = WallWalkerMath.clampTravel(
		tangentDirection,
		math.min(self.speed * safeDeltaTime, self.maxFrameTravel),
		tangentDirection.Magnitude
	)
	local sweepHit = self.probe:sweep(root.Position, movement)
	self.diagnostics.lastSweepDistance = if sweepHit ~= nil then sweepHit.distance else nil
	self.diagnostics.lastSweepNormal = if sweepHit ~= nil then sweepHit.normal else nil
	self:_publishDiagnostics()
	local sweepIsAhead = sweepHit ~= nil and sweepHit.distance < movement.Magnitude - 0.01
	local sweepIsTransition = sweepIsAhead
		and WallWalkerMath.normalAngle(self.contactNormal, sweepHit.normal) > self.cornerAngle
	local transition = normalChange > self.cornerAngle or self.state == "ApproachingCorner" or sweepIsTransition
	local preferredCandidateNormal = self.probeNormal
	if sweepIsTransition then
		preferredCandidateNormal = sweepHit.normal
	end
	local candidate, reason = self:_candidate(
		root.Position + movement,
		movement,
		safeDeltaTime,
		transition,
		movement.Magnitude,
		preferredCandidateNormal,
		if sweepIsTransition then sweepHit else nil
	)
	if candidate == nil then
		self:_reject(
			root.Position + movement,
			if sweepIsAhead then "InsufficientClearance" else reason or "MovementBlocked"
		)
		if self.state == "Blocked" then
			self:_tryRecovery(safeDeltaTime)
		end
		return
	end

	self.orientationNormal = candidate.orientationNormal
	self:_accept(candidate)
	self:_advanceWaypoint(candidate.position, waypoint)
	if normalChange > self.cornerAngle then
		self:_setState("ApproachingCorner")
	end
end

function WallWalkerController:setWaypoints(waypoints: { Waypoint }): ()
	self.waypoints = {}
	for _, waypoint in waypoints do
		table.insert(self.waypoints, {
			position = waypoint.position,
			normal = waypoint.normal,
			arrivalRadius = waypoint.arrivalRadius,
			id = waypoint.id,
		})
	end
	self.waypointIndex = 1
end

function WallWalkerController:clearWaypoints(): ()
	self.waypoints = {}
	self.waypointIndex = 1
end

function WallWalkerController:getCurrentWaypoint(): Waypoint?
	return self.waypoints[self.waypointIndex]
end

function WallWalkerController:getState(): WallWalkerMath.State
	return self.state
end

function WallWalkerController:getDiagnostics(): WallWalkerDiagnostics
	return copyDiagnostics(self.diagnostics)
end

function WallWalkerController:destroy(): ()
	self:stop()
	self.probe:destroy()
	if self.root.Parent ~= nil then
		self.root.Anchored = self.wasAnchored
	end
end

return WallWalkerController
