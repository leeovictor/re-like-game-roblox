--!strict

local CAMERA_SYSTEM_NAME = "CameraSystem"
local SHOTS_NAME = "Shots"
local ZONES_NAME = "Zones"
local DEFAULT_SHOT_ID = "DefaultShotId"
local FIELD_OF_VIEW = "FieldOfView"
local SHOT_ID = "ShotId"
local ORDER = "Order"
local EDITOR_SHOT_TRANSPARENCY = 0
local EDITOR_ZONE_TRANSPARENCY = 0.75

type Hierarchy = {
	root: Folder,
	shots: Folder,
	zones: Folder,
}

local CameraSystemModel = {}
CameraSystemModel.__index = CameraSystemModel

type ChangeHistoryServiceLike = ChangeHistoryService & {
	SetWaypoint: (self: ChangeHistoryService, label: string) -> (),
}

type SelectionLike = Selection & {
	Set: (self: Selection, instances: { Instance }) -> (),
}

export type Model = typeof(setmetatable({} :: {
	workspace: Workspace,
	selection: Selection,
	changeHistoryService: ChangeHistoryService,
}, CameraSystemModel))

local function requireNonEmptyName(name: string): string
	assert(type(name) == "string" and name ~= "", "name must be a non-empty string")
	return name
end

local function requireFolder(parent: Instance, name: string): Folder
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("Folder") then
		error(string.format('%s must contain Folder "%s"', parent:GetFullName(), name), 3)
	end
	return child :: Folder
end

local function setWaypoint(service: ChangeHistoryService, label: string)
	local serviceWithWaypoint = service :: ChangeHistoryServiceLike
	serviceWithWaypoint:SetWaypoint(label)
end

local function selectInstance(selection: Selection, instance: Instance)
	local selectionWithSet = selection :: SelectionLike
	selectionWithSet:Set({ instance })
end

local function isValidFieldOfView(value: unknown): boolean
	return type(value) == "number" and value >= 1 and value <= 120
end

local function isValidOrder(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value >= 0
end

function CameraSystemModel.new(
	workspace: Workspace,
	selection: Selection,
	changeHistoryService: ChangeHistoryService
): Model
	return setmetatable({
		workspace = workspace,
		selection = selection,
		changeHistoryService = changeHistoryService,
	}, CameraSystemModel) :: Model
end

function CameraSystemModel.ensureHierarchy(self: Model): Hierarchy
	local root = self.workspace:FindFirstChild(CAMERA_SYSTEM_NAME)
	if root ~= nil and not root:IsA("Folder") then
		error('Workspace.CameraSystem must be a Folder', 2)
	end

	local rootFolder = if root == nil then nil else root :: Folder
	local existingShots = if rootFolder == nil then nil else rootFolder:FindFirstChild(SHOTS_NAME)
	local existingZones = if rootFolder == nil then nil else rootFolder:FindFirstChild(ZONES_NAME)
	if existingShots ~= nil and not existingShots:IsA("Folder") then
		error('CameraSystem.Shots must be a Folder', 2)
	end
	if existingZones ~= nil and not existingZones:IsA("Folder") then
		error('CameraSystem.Zones must be a Folder', 2)
	end

	if rootFolder ~= nil and existingShots ~= nil and existingZones ~= nil then
		return {
			root = rootFolder,
			shots = existingShots :: Folder,
			zones = existingZones :: Folder,
		}
	end

	setWaypoint(self.changeHistoryService, "Camera System: Begin hierarchy")
	local success, result = pcall(function(): Hierarchy
		local rootToUse: Folder
		if rootFolder == nil then
			rootToUse = Instance.new("Folder")
			rootToUse.Name = CAMERA_SYSTEM_NAME
			rootToUse.Parent = self.workspace
		else
			rootToUse = rootFolder
		end

		local shots = existingShots
		if shots == nil then
			local folder = Instance.new("Folder")
			folder.Name = SHOTS_NAME
			folder.Parent = rootToUse
			shots = folder
		end

		local zones = existingZones
		if zones == nil then
			local folder = Instance.new("Folder")
			folder.Name = ZONES_NAME
			folder.Parent = rootToUse
			zones = folder
		end

		return {
			root = rootToUse,
			shots = shots :: Folder,
			zones = zones :: Folder,
		}
	end)
	setWaypoint(self.changeHistoryService, "Camera System: End hierarchy")
	if not success then
		error(result, 2)
	end
	return result :: Hierarchy
end

function CameraSystemModel._hierarchy(self: Model): Hierarchy
	local root = self.workspace:FindFirstChild(CAMERA_SYSTEM_NAME)
	assert(root ~= nil and root:IsA("Folder"), "Workspace.CameraSystem must be a Folder")
	local rootFolder = root :: Folder
	return {
		root = rootFolder,
		shots = requireFolder(rootFolder, SHOTS_NAME),
		zones = requireFolder(rootFolder, ZONES_NAME),
	}
end

function CameraSystemModel.listShots(self: Model): { BasePart }
	local hierarchy = self:_hierarchy()
	local shots: { BasePart } = {}
	for _, child in hierarchy.shots:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(shots, child :: BasePart)
		end
	end
	table.sort(shots, function(left, right)
		return left.Name < right.Name
	end)
	return shots
end

function CameraSystemModel.listZones(self: Model): { BasePart }
	local hierarchy = self:_hierarchy()
	local zones = {}
	for _, child in hierarchy.zones:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(zones, child :: BasePart)
		end
	end
	table.sort(zones, function(left, right)
		local leftOrder = left:GetAttribute(ORDER)
		local rightOrder = right:GetAttribute(ORDER)
		local leftHasValidOrder = isValidOrder(leftOrder)
		local rightHasValidOrder = isValidOrder(rightOrder)
		if leftHasValidOrder ~= rightHasValidOrder then
			return leftHasValidOrder
		end
		if leftHasValidOrder and leftOrder ~= rightOrder then
			return (leftOrder :: number) < (rightOrder :: number)
		end
		return left.Name < right.Name
	end)
	return zones
end

function CameraSystemModel.createShot(self: Model, name: string, camera: Camera): Part
	local shotName = requireNonEmptyName(name)
	local hierarchy = self:ensureHierarchy()
	assert(hierarchy.shots:FindFirstChild(shotName) == nil, string.format('Shot "%s" already exists', shotName))

	setWaypoint(self.changeHistoryService, "Camera System: Begin create shot")
	local shot = Instance.new("Part")
	shot.Name = shotName
	shot.CFrame = camera.CFrame
	shot.Anchored = true
	shot.CanCollide = false
	shot.CanTouch = false
	shot.CanQuery = false
	shot.Transparency = 1
	shot.Locked = false
	shot:SetAttribute(FIELD_OF_VIEW, camera.FieldOfView)
	shot.Parent = hierarchy.shots
	selectInstance(self.selection, shot)
	setWaypoint(self.changeHistoryService, "Camera System: End create shot")
	return shot
end

function CameraSystemModel.captureCamera(self: Model, shot: Part, camera: Camera)
	local ownedShot = self:_ownedShot(shot)
	setWaypoint(self.changeHistoryService, "Camera System: Begin capture camera")
	ownedShot.CFrame = camera.CFrame
	ownedShot:SetAttribute(FIELD_OF_VIEW, camera.FieldOfView)
	setWaypoint(self.changeHistoryService, "Camera System: End capture camera")
end

function CameraSystemModel.applyShot(self: Model, shot: Part, camera: Camera)
	local ownedShot = self:_ownedShot(shot)
	local fieldOfView = ownedShot:GetAttribute(FIELD_OF_VIEW)
	assert(isValidFieldOfView(fieldOfView), string.format('Shot "%s" has an invalid FieldOfView', ownedShot.Name))
	setWaypoint(self.changeHistoryService, "Camera System: Begin apply shot")
	camera.CFrame = ownedShot.CFrame
	camera.FieldOfView = fieldOfView :: number
	setWaypoint(self.changeHistoryService, "Camera System: End apply shot")
end

function CameraSystemModel.setFieldOfView(self: Model, shot: Part, fieldOfView: number)
	local ownedShot = self:_ownedShot(shot)
	assert(isValidFieldOfView(fieldOfView), "FieldOfView must be between 1 and 120")
	setWaypoint(self.changeHistoryService, "Camera System: Begin set FieldOfView")
	ownedShot:SetAttribute(FIELD_OF_VIEW, fieldOfView)
	setWaypoint(self.changeHistoryService, "Camera System: End set FieldOfView")
end

function CameraSystemModel.setDefaultShot(self: Model, shot: Part)
	local ownedShot = self:_ownedShot(shot)
	local hierarchy = self:_hierarchy()
	setWaypoint(self.changeHistoryService, "Camera System: Begin set default shot")
	hierarchy.root:SetAttribute(DEFAULT_SHOT_ID, ownedShot.Name)
	setWaypoint(self.changeHistoryService, "Camera System: End set default shot")
end

function CameraSystemModel.createZone(self: Model, name: string, cframe: CFrame, size: Vector3): Part
	local zoneName = requireNonEmptyName(name)
	local hierarchy = self:ensureHierarchy()
	assert(hierarchy.zones:FindFirstChild(zoneName) == nil, string.format('Zone "%s" already exists', zoneName))
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "Zone size must be positive on every axis")

	local nextOrder = 1
	for _, zone in self:listZones() do
		local order = zone:GetAttribute(ORDER)
		if isValidOrder(order) then
			nextOrder = math.max(nextOrder, (order :: number) + 1)
		end
	end

	setWaypoint(self.changeHistoryService, "Camera System: Begin create zone")
	local zone = Instance.new("Part")
	zone.Name = zoneName
	zone.CFrame = cframe
	zone.Size = size
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.Transparency = 1
	zone.Locked = false
	zone:SetAttribute(ORDER, nextOrder)

	local defaultShotId = hierarchy.root:GetAttribute(DEFAULT_SHOT_ID)
	local defaultShot = if type(defaultShotId) == "string" then hierarchy.shots:FindFirstChild(defaultShotId) else nil
	if defaultShot ~= nil and defaultShot:IsA("BasePart") then
		zone:SetAttribute(SHOT_ID, defaultShotId)
	end
	zone.Parent = hierarchy.zones
	selectInstance(self.selection, zone)
	setWaypoint(self.changeHistoryService, "Camera System: End create zone")
	return zone
end

function CameraSystemModel.assignShot(self: Model, zone: Part, shot: Part)
	local ownedZone = self:_ownedZone(zone)
	local ownedShot = self:_ownedShot(shot)
	setWaypoint(self.changeHistoryService, "Camera System: Begin assign shot")
	ownedZone:SetAttribute(SHOT_ID, ownedShot.Name)
	setWaypoint(self.changeHistoryService, "Camera System: End assign shot")
end

function CameraSystemModel.reorderZone(self: Model, zone: Part, delta: number)
	local ownedZone = self:_ownedZone(zone)
	assert(delta == -1 or delta == 1, "Zone reorder delta must be -1 or 1")
	local zones = self:listZones()
	local index = table.find(zones, ownedZone)
	assert(index ~= nil, "Zone is not in the Zones folder")
	local targetIndex = (index :: number) + delta
	if targetIndex < 1 or targetIndex > #zones then
		return
	end

	local orders = {}
	for _, candidate in zones do
		local order = candidate:GetAttribute(ORDER)
		assert(type(order) == "number" and order % 1 == 0 and order >= 0, string.format('Zone "%s" has an invalid Order', candidate.Name))
		assert(orders[order :: number] == nil, "Zone orders must be unique")
		orders[order :: number] = candidate
	end

	local otherZone = zones[targetIndex]
	local currentOrder = ownedZone:GetAttribute(ORDER)
	local otherOrder = otherZone:GetAttribute(ORDER)
	setWaypoint(self.changeHistoryService, "Camera System: Begin reorder zone")
	ownedZone:SetAttribute(ORDER, otherOrder)
	otherZone:SetAttribute(ORDER, currentOrder)
	setWaypoint(self.changeHistoryService, "Camera System: End reorder zone")
end

function CameraSystemModel.setPartsVisible(self: Model, visible: boolean)
	local hierarchy = self:_hierarchy()
	setWaypoint(self.changeHistoryService, "Camera System: Begin set visibility")
	local shotTransparency = if visible then EDITOR_SHOT_TRANSPARENCY else 1
	local zoneTransparency = if visible then EDITOR_ZONE_TRANSPARENCY else 1
	for _, child in hierarchy.shots:GetChildren() do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			part.Transparency = shotTransparency
			part.Locked = not visible
		end
	end
	for _, child in hierarchy.zones:GetChildren() do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			part.Transparency = zoneTransparency
			part.Locked = not visible
		end
	end
	setWaypoint(self.changeHistoryService, "Camera System: End set visibility")
end

function CameraSystemModel._ownedShot(self: Model, shot: Part): Part
	local hierarchy = self:_hierarchy()
	assert(shot:IsA("BasePart") and shot.Parent == hierarchy.shots, string.format('Shot "%s" is not owned by CameraSystem.Shots', shot.Name))
	return shot
end

function CameraSystemModel._ownedZone(self: Model, zone: Part): Part
	local hierarchy = self:_hierarchy()
	assert(zone:IsA("BasePart") and zone.Parent == hierarchy.zones, string.format('Zone "%s" is not owned by CameraSystem.Zones', zone.Name))
	return zone
end

function CameraSystemModel.validate(self: Model): { string }
	local errors = {}
	local function add(message: string)
		table.insert(errors, message)
	end

	local root = self.workspace:FindFirstChild(CAMERA_SYSTEM_NAME)
	if root == nil then
		add("CameraSystem folder is missing")
		return errors
	end
	if not root:IsA("Folder") then
		add("CameraSystem must be a Folder")
		return errors
	end
	local rootFolder = root :: Folder
	local shotsInstance = rootFolder:FindFirstChild(SHOTS_NAME)
	local zonesInstance = rootFolder:FindFirstChild(ZONES_NAME)
	if shotsInstance == nil or not shotsInstance:IsA("Folder") then
		add("CameraSystem.Shots folder is missing")
	end
	if zonesInstance == nil or not zonesInstance:IsA("Folder") then
		add("CameraSystem.Zones folder is missing")
	end
	if shotsInstance == nil or not shotsInstance:IsA("Folder") or zonesInstance == nil or not zonesInstance:IsA("Folder") then
		return errors
	end

	local shotsFolder = shotsInstance :: Folder
	local zonesFolder = zonesInstance :: Folder
	local shots: { [string]: BasePart? } = {}
	for _, child in shotsFolder:GetChildren() do
		if not child:IsA("BasePart") then
			add(string.format('Shot "%s" must be a BasePart', child.Name))
		else
			local shot = child :: BasePart
			shots[shot.Name] = shot
			if not isValidFieldOfView(shot:GetAttribute(FIELD_OF_VIEW)) then
				add(string.format('Shot "%s" must have FieldOfView between 1 and 120', shot.Name))
			end
		end
	end

	local defaultShotId = rootFolder:GetAttribute(DEFAULT_SHOT_ID)
	local seenOrders: { [number]: BasePart? } = {}
	if type(defaultShotId) ~= "string" or defaultShotId == "" or shots[defaultShotId] == nil then
		add("CameraSystem DefaultShotId must reference an existing shot")
	end

	for _, child in zonesFolder:GetChildren() do
		if not child:IsA("BasePart") then
			add(string.format('Zone "%s" must be a BasePart', child.Name))
		else
			local zone = child :: BasePart
			local shotId = zone:GetAttribute(SHOT_ID)
			if type(shotId) ~= "string" or shotId == "" then
				add(string.format('Zone "%s" must have a non-empty ShotId', zone.Name))
			elseif shots[shotId] == nil then
				add(string.format('Zone "%s" references missing ShotId "%s"', zone.Name, shotId))
			end
			local order = zone:GetAttribute(ORDER)
			if not isValidOrder(order) then
				add(string.format('Zone "%s" must have an integer Order', zone.Name))
			elseif seenOrders[order :: number] ~= nil then
				add(string.format('Zone "%s" has a duplicate Order %d', zone.Name, order :: number))
			else
				seenOrders[order :: number] = zone
			end
			local size = zone.Size
			if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
				add(string.format('Zone "%s" must have positive Size', zone.Name))
			end
		end
	end
	return errors
end

return CameraSystemModel
