--!strict

local Workspace = game:GetService("Workspace")

local ROW_COUNT = 10
local COLUMN_COUNT = 20
local SPACING = 4
local SPHERE_DIAMETER = 2
local HEIGHT = 1
local CONTAINER_NAME = "ClientSphereGrid"

local random = Random.new()
local started = false

local SphereGridController = {}

local function randomColor(): Color3
	return Color3.new(random:NextNumber(), random:NextNumber(), random:NextNumber())
end

local function getOrCreateContainer(): Folder
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end

		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace
	return container
end

local function clearContainer(container: Folder)
	for _, child in container:GetChildren() do
		child:Destroy()
	end
end

local function createSphere(container: Folder, row: number, column: number): BasePart
	local x = (column - 10.5) * SPACING
	local z = (row - 5.5) * SPACING

	local sphere = Instance.new("Part")
	sphere.Name = string.format("Sphere_%02d_%02d", row, column)
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(SPHERE_DIAMETER, SPHERE_DIAMETER, SPHERE_DIAMETER)
	sphere.Position = Vector3.new(x, HEIGHT, z)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.Color = randomColor()
	sphere.Parent = container

	return sphere
end

local function createGrid(container: Folder): { BasePart }
	local spheres: { BasePart } = {}

	for row = 1, ROW_COUNT do
		for column = 1, COLUMN_COUNT do
			table.insert(spheres, createSphere(container, row, column))
		end
	end

	return spheres
end

local function updateColors(spheres: { BasePart })
	for _, sphere in spheres do
		sphere.Color = randomColor()
	end
end

function SphereGridController.start()
	if started then
		return
	end
	started = true

	local container = getOrCreateContainer()
	clearContainer(container)
	local spheres = createGrid(container)

	task.spawn(function()
		while container.Parent ~= nil do
			task.wait(1)
			updateColors(spheres)
		end
	end)
end

return SphereGridController
