--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection") :: any
local Workspace = game:GetService("Workspace")

local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local function fail(message: string): never
	error(message, 2)
end

local function getSelectedTarget(): BasePart | Model
	if not RunService:IsStudio() then
		fail("DialogueInitializer can only run in Roblox Studio")
	end

	local selected = Selection:Get()
	if #selected ~= 1 then
		fail("Select exactly one Part or Model before running the dialogue initializer")
	end

	local target = selected[1]
	if not target:IsA("BasePart") and not target:IsA("Model") then
		fail("The selected instance must be a BasePart or Model")
	end
	if not target:IsDescendantOf(Workspace) then
		fail("The selected instance must be inside Workspace")
	end

	return target
end

local function removeChildrenNamed(parent: Instance, name: string): ()
	for _, child in parent:GetChildren() do
		if child.Name == name then
			child:Destroy()
		end
	end
end

local function initialize(): ()
	local target = getSelectedTarget()

	ChangeHistoryService:SetWaypoint("Before initializing dialogue")
	removeChildrenNamed(target, interactionTypes.DIALOGUE_FOLDER_NAME)

	local dialogue = Instance.new("Folder")
	dialogue.Name = interactionTypes.DIALOGUE_FOLDER_NAME

	local message = Instance.new("StringValue")
	message.Name = "01"
	message.Value = ""
	message.Parent = dialogue

	dialogue.Parent = target
	target:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DIALOGUE_TYPE)
	CollectionService:AddTag(target, interactionTypes.INTERACTABLE_TAG)

	ChangeHistoryService:SetWaypoint("Initialize dialogue")
end

return {
	initialize = initialize,
}
