--!strict

local WallWalkerMath = require(script.Parent.WallWalkerMath)

local WallWalkerSurfaceProbe = {}
WallWalkerSurfaceProbe.__index = WallWalkerSurfaceProbe

export type ProbeShape = "Sphere" | "Block"

export type SurfaceContact = {
	point: Vector3,
	normal: Vector3,
	distance: number,
	instance: Instance?,
	probeOffset: Vector3,
	probeDirection: Vector3,
}

export type ProbeResult = {
	contact: SurfaceContact?,
	contacts: { SurfaceContact },
	reason: string?,
}

export type ProbeConfig = {
	worldRoot: WorldRoot?,
	shape: ProbeShape?,
	radius: number?,
	size: Vector3?,
	surfaceOffset: number,
	clearanceMargin: number,
	probeDistance: number,
	contactTolerance: number,
	probeSpacing: number?,
	root: BasePart,
	exclude: { Instance }?,
}

export type SurfaceProbe = {
	find: (
		self: SurfaceProbe,
		position: Vector3,
		preferredNormal: Vector3,
		referenceDirection: Vector3,
		wide: boolean?
	) -> ProbeResult,
	sweep: (self: SurfaceProbe, position: Vector3, direction: Vector3) -> SurfaceContact?,
	centerOffset: (self: SurfaceProbe, normal: Vector3, orientation: CFrame?) -> number,
	destroy: (self: SurfaceProbe) -> (),
}

local EPSILON = 0.0001

local function makeRaycastParams(root: BasePart, exclude: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local instances: { Instance } = { root }
	if exclude ~= nil then
		for _, instance in exclude do
			table.insert(instances, instance)
		end
	end
	params.FilterDescendantsInstances = instances
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function contactFromHit(hit: RaycastResult, probeOffset: Vector3, probeDirection: Vector3): SurfaceContact?
	local normal = hit.Normal
	if normal.Magnitude <= EPSILON then
		return nil
	end
	return {
		point = hit.Position,
		normal = normal.Unit,
		distance = hit.Distance,
		instance = hit.Instance :: Instance?,
		probeOffset = probeOffset,
		probeDirection = probeDirection,
	}
end

local function translatedCFrame(root: BasePart, position: Vector3): CFrame
	return CFrame.fromMatrix(position, root.CFrame.RightVector, root.CFrame.UpVector, -root.CFrame.LookVector)
end

local function addDirection(directions: { Vector3 }, direction: Vector3): ()
	if direction.Magnitude > EPSILON then
		table.insert(directions, direction.Unit)
	end
end

local function makeDirections(preferredNormal: Vector3, referenceDirection: Vector3, wide: boolean): { Vector3 }
	local normal = WallWalkerMath.unitOr(preferredNormal, Vector3.yAxis)
	local first, second = WallWalkerMath.tangentBasis(normal, referenceDirection)
	local directions = { normal }
	if wide then
		addDirection(directions, -normal)
		addDirection(directions, first)
		addDirection(directions, -first)
		addDirection(directions, second)
		addDirection(directions, -second)
	end
	return directions
end

local function nearestContact(contacts: { SurfaceContact }): SurfaceContact?
	local nearest: SurfaceContact? = nil
	for _, contact in contacts do
		if nearest == nil or contact.distance < nearest.distance then
			nearest = contact
		end
	end
	return nearest
end

function WallWalkerSurfaceProbe.new(config: ProbeConfig): SurfaceProbe
	local shape = config.shape or "Sphere"
	local radius = config.radius or config.root.Size.X / 2
	local size = config.size or config.root.Size
	local self: any = setmetatable({
		worldRoot = config.worldRoot or workspace,
		root = config.root,
		shape = shape,
		radius = math.max(radius, 0.01),
		size = size,
		surfaceOffset = math.max(config.surfaceOffset, 0),
		clearanceMargin = math.max(config.clearanceMargin, 0),
		probeDistance = math.max(config.probeDistance, 0.01),
		contactTolerance = math.max(config.contactTolerance, 0),
		probeSpacing = math.max(
			config.probeSpacing
				or if shape == "Sphere" then radius * 0.65 else math.min(size.X, math.min(size.Y, size.Z)) * 0.35,
			0.25
		),
		params = makeRaycastParams(config.root, config.exclude),
	}, WallWalkerSurfaceProbe)
	return self
end

function WallWalkerSurfaceProbe:_cast(position: Vector3, outward: Vector3): RaycastResult?
	local direction = -outward * self.probeDistance
	if self.shape == "Block" then
		return self.worldRoot:Blockcast(translatedCFrame(self.root, position), self.size, direction, self.params)
	end
	return self.worldRoot:Spherecast(position, self.radius, direction, self.params)
end

function WallWalkerSurfaceProbe:sweep(position: Vector3, direction: Vector3): SurfaceContact?
	if direction.Magnitude <= EPSILON then
		return nil
	end

	local hit: RaycastResult?
	if self.shape == "Block" then
		hit = self.worldRoot:Blockcast(
			translatedCFrame(self.root, position),
			self.size,
			direction,
			self.params
		)
	else
		hit = self.worldRoot:Spherecast(position, self.radius, direction, self.params)
	end
	if hit == nil then
		return nil
	end
	return contactFromHit(hit, Vector3.zero, direction.Unit)
end

function WallWalkerSurfaceProbe:centerOffset(normal: Vector3, orientation: CFrame?): number
	if self.shape == "Sphere" then
		return self.radius + self.clearanceMargin
	end

	local frame = orientation or self.root.CFrame
	local unitNormal = WallWalkerMath.unitOr(normal, frame.UpVector)
	local support = math.abs(unitNormal:Dot(frame.RightVector)) * self.size.X / 2
		support += math.abs(unitNormal:Dot(frame.UpVector)) * self.size.Y / 2
		support += math.abs(unitNormal:Dot(frame.LookVector)) * self.size.Z / 2
	return support + self.clearanceMargin
end

function WallWalkerSurfaceProbe:find(
	position: Vector3,
	preferredNormal: Vector3,
	referenceDirection: Vector3,
	wide: boolean?
): ProbeResult
	local directions = makeDirections(preferredNormal, referenceDirection, wide == true)
	local contacts = {}
	local normal = WallWalkerMath.unitOr(preferredNormal, Vector3.yAxis)
	local originOffset = math.max(self.surfaceOffset - self:centerOffset(normal), 0) + 0.5
	local first, second = WallWalkerMath.tangentBasis(normal, referenceDirection)
	local offsets = {
		Vector3.zero,
		first * self.probeSpacing,
		-first * self.probeSpacing,
		second * self.probeSpacing,
		-second * self.probeSpacing,
	}

	for _, offset in offsets do
		for _, direction in directions do
			local hit = self:_cast(position + offset + direction * originOffset, direction)
			if hit ~= nil then
				local contact = contactFromHit(hit, offset, direction)
				if contact ~= nil and contact.distance <= self.probeDistance + self.contactTolerance then
					table.insert(contacts, contact)
				end
			end
		end
	end

	return {
		contact = nearestContact(contacts),
		contacts = contacts,
		reason = if #contacts == 0 then "NoSurface" else nil,
	}
end

function WallWalkerSurfaceProbe:destroy(): ()
	self.params.FilterDescendantsInstances = {}
end

return WallWalkerSurfaceProbe
