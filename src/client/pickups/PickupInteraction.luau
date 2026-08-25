--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local GameplayEvents = require(script.Parent.Parent.events.GameplayEvents)

local PickupManager = require(script.Parent.PickupManager)

export type Dependencies = {
	manager: PickupManager.PickupManager,
}

export type PickupInteraction = interactionTypes.InteractionHandler & {
	manager: PickupManager.PickupManager,
}

local PickupInteraction = {}

function PickupInteraction.new(dependencies: Dependencies): PickupInteraction
	assert(type(dependencies) == "table", "PickupInteraction dependencies are required")
	assert(type(dependencies.manager.collect) == "function", "PickupInteraction manager.collect is required")

	local interaction = {
		manager = dependencies.manager,
	} :: PickupInteraction

	function interaction.interact(target: Instance): ()
		if not target:IsA("BasePart") and not target:IsA("Model") then
			return
		end
		local result = dependencies.manager:collect(target)
		if result.success then
			GameplayEvents.emit({ name = "item_collected", itemId = result.itemId })
		end
	end

	return interaction
end

return PickupInteraction
