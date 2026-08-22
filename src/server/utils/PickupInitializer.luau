--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection") :: any
local Workspace = game:GetService("Workspace")

local catalog = require(ReplicatedStorage.Shared.inventory.catalog)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local function fail(message: string): never
	error(message, 2)
end

local function getSelectedPickup(): BasePart | Model
	if not RunService:IsStudio() then
		fail("PickupInitializer can only run in Roblox Studio")
	end

	local selected = Selection:Get()
	if #selected ~= 1 then
		fail("Select exactly one Part or Model before running the pickup initializer")
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

local function validateConfiguration(itemId: string, quantity: number?): ()
	if type(itemId) ~= "string" or itemId == "" then
		fail("ItemId must be a non-empty catalog item id")
	end

	local item = catalog[itemId]
	if item == nil then
		fail(string.format('Unknown pickup ItemId "%s"', itemId))
	end
	if quantity == nil then
		return
	end
	if type(quantity) ~= "number"
		or quantity ~= quantity
		or quantity == math.huge
		or quantity == -math.huge
		or quantity <= 0
		or quantity % 1 ~= 0
	then
		fail("Quantity must be a positive integer")
	end
	if not item.stackable then
		fail(string.format('Item "%s" does not support Quantity', itemId))
	end
end

local function initialize(itemId: string, quantity: number?): ()
	local target = getSelectedPickup()
	validateConfiguration(itemId, quantity)

	ChangeHistoryService:SetWaypoint("Before initializing pickup")
	target:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
	target:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
	target:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
	CollectionService:AddTag(target, interactionTypes.INTERACTABLE_TAG)
	ChangeHistoryService:SetWaypoint("Initialize pickup")
end

return {
	initialize = initialize,
}
