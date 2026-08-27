--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection") :: any

local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local LOCKED_ITEM_ID = "access_card"
local LOCKED_MESSAGE = "A porta esta trancada."
local LOCKED_HINT = "Procure um cartao de acesso."

local function fail(message: string): never
	error(message, 2)
end

local function getSelectedModel(): Model
	if not RunService:IsStudio() then
		fail("DoorModelInitializer can only run in Roblox Studio")
	end

	local selected = Selection:Get()
	if #selected ~= 1 then
		fail("Select exactly one door Model before running the initializer")
	end

	local selectedInstance = selected[1]
	if not selectedInstance:IsA("Model") then
		fail("The selected instance must be a Model")
	end

	return selectedInstance
end

local function getDoorway(model: Model): BasePart
	local doorways: { Instance } = {}
	for _, child in model:GetChildren() do
		if child.Name == doorTypes.DOORWAY_NAME then
			table.insert(doorways, child)
		end
	end

	if #doorways ~= 1 or not doorways[1]:IsA("BasePart") then
		fail("The selected Model must contain exactly one BasePart named Doorway")
	end

	return doorways[1] :: BasePart
end

local function createCenter(): Attachment
	local center = Instance.new("Attachment")
	center.Name = doorTypes.CENTER_NAME
	center.Position = Vector3.zero
	center.Orientation = Vector3.zero
	return center
end

local function createLockedDialogue(): Folder
	local folder = Instance.new("Folder")
	folder.Name = doorTypes.LOCKED_DIALOGUE_NAME

	local lockedMessage = Instance.new("StringValue")
	lockedMessage.Name = "01_Locked"
	lockedMessage.Value = LOCKED_MESSAGE
	lockedMessage.Parent = folder

	local hint = Instance.new("StringValue")
	hint.Name = "02_Hint"
	hint.Value = LOCKED_HINT
	hint.Parent = folder

	return folder
end

local function createSealedDialogue(): Folder
	local folder = Instance.new("Folder")
	folder.Name = doorTypes.SEALED_DIALOGUE_NAME
	local message = Instance.new("StringValue")
	message.Name = "01_Sealed"
	message.Value = doorTypes.FALLBACK_SEALED_MESSAGE
	message.Parent = folder
	return folder
end

local function removeChildrenNamed(parent: Instance, name: string): ()
	for _, child in parent:GetChildren() do
		if child.Name == name then
			child:Destroy()
		end
	end
end

local function initialize(model: Model): ()
	local doorway = getDoorway(model)
	local center = createCenter()
	local lockedDialogue = createLockedDialogue()
	local sealedDialogue = createSealedDialogue()

	ChangeHistoryService:SetWaypoint("Before initializing door model")

	removeChildrenNamed(doorway, doorTypes.CENTER_NAME)
	removeChildrenNamed(model, doorTypes.LOCKED_DIALOGUE_NAME)
	removeChildrenNamed(model, doorTypes.SEALED_DIALOGUE_NAME)

	center.Parent = doorway
	lockedDialogue.Parent = model
	sealedDialogue.Parent = model
	model:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, true)
	model:SetAttribute(doorTypes.SEALED_ATTRIBUTE, false)
	model:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, LOCKED_ITEM_ID)
	local existingDoorKey = model:GetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE)
	if type(existingDoorKey) ~= "string" or existingDoorKey == "" then
		model:SetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE, model.Name)
	end
	model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
	CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
	CollectionService:AddTag(model, doorTypes.DOOR_TAG)

	ChangeHistoryService:SetWaypoint("Initialize door model")
end

local DoorModelInitializer = {}

function DoorModelInitializer.initialize(): ()
	local model = getSelectedModel()
	initialize(model)
end

return DoorModelInitializer
