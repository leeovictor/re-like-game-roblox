--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)

type DoorDefinition = {
	name: string,
	locked: boolean,
	requiredItemId: string,
	position: Vector3,
	color: Color3,
	dialogue: { [string]: string }?,
}

local sceneName = "DoorTestScene"
local floorSize = Vector3.new(64, 1, 56)
local doorwaySize = Vector3.new(1, 8, 6)

local doorDefinitions: { DoorDefinition } = {
	{
		name = "MissingKeyDoor",
		locked = true,
		requiredItemId = "iron_key",
		position = Vector3.new(-18, 4, 0),
		color = Color3.fromRGB(190, 55, 45),
		dialogue = {
			["01_Locked"] = "A porta esta trancada.",
			["02_Hint"] = "Procure uma chave de ferro.",
		},
	},
	{
		name = "KeyDoor",
		locked = true,
		requiredItemId = "iron_key",
		position = Vector3.new(0, 4, 0),
		color = Color3.fromRGB(220, 170, 45),
		dialogue = {
			["01_Locked"] = "A porta exige uma chave de ferro.",
			["02_Hint"] = "Use F depois de encontrar a chave.",
		},
	},
	{
		name = "OpenDoor",
		locked = false,
		requiredItemId = "",
		position = Vector3.new(18, 4, 0),
		color = Color3.fromRGB(65, 175, 85),
	},
}

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function createDialogue(parent: Model, dialogue: { [string]: string }): ()
	local folder = Instance.new("Folder")
	folder.Name = doorTypes.LOCKED_DIALOGUE_NAME
	for name, text in dialogue do
		local message = Instance.new("StringValue")
		message.Name = name
		message.Value = text
		message.Parent = folder
	end
	folder.Parent = parent
end

local function createDoor(parent: Folder, definition: DoorDefinition): Model
	local door = Instance.new("Model")
	door.Name = definition.name
	door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, definition.locked)
	door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, definition.requiredItemId)
	CollectionService:AddTag(door, doorTypes.DOOR_TAG)

	local doorway = createPart(
		door,
		doorTypes.DOORWAY_NAME,
		doorwaySize,
		definition.position,
		definition.color,
		Enum.Material.SmoothPlastic
	)
	local center = Instance.new("Attachment")
	center.Name = doorTypes.CENTER_NAME
	center.Parent = doorway

	if definition.dialogue ~= nil then
		createDialogue(door, definition.dialogue)
	end

	door.Parent = parent
	return door
end

local function createSupports(parent: Folder): ()
	createPart(parent, "Floor", floorSize, Vector3.new(0, -0.5, 0), Color3.fromRGB(75, 75, 80), Enum.Material.Concrete)
	createPart(parent, "LeftWall", Vector3.new(64, 3, 1), Vector3.new(0, 1.5, -12), Color3.fromRGB(105, 105, 110), Enum.Material.Brick)
	createPart(parent, "RightWall", Vector3.new(64, 3, 1), Vector3.new(0, 1.5, 12), Color3.fromRGB(105, 105, 110), Enum.Material.Brick)
	createPart(parent, "BackWall", Vector3.new(1, 3, 24), Vector3.new(32, 1.5, 0), Color3.fromRGB(105, 105, 110), Enum.Material.Brick)
	for index, definition in doorDefinitions do
		createPart(
			parent,
			string.format("Support_%02d", index),
			Vector3.new(2, 1, 8),
			definition.position - Vector3.new(0, 4.5, 0),
			definition.color,
			Enum.Material.Concrete
		)
	end
end

local StudioDoorScene = {}

function StudioDoorScene.create(): ()
	local existing = Workspace:FindFirstChild(sceneName)
	if existing ~= nil and not existing:IsA("Folder") then
		error("Workspace.DoorTestScene must be a Folder")
	end

	if existing == nil then
		local scene = Instance.new("Folder")
		scene.Name = sceneName
		for _, definition in doorDefinitions do
			createDoor(scene, definition)
		end
		createSupports(scene)
		scene.Parent = Workspace
		return
	end

	local scene = existing :: Folder
	for _, definition in doorDefinitions do
		if scene:FindFirstChild(definition.name) == nil then
			createDoor(scene, definition)
		end
	end
end

return StudioDoorScene
