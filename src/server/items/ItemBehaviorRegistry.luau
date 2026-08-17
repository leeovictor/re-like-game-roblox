--!strict

local items = require(script.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.items)

export type ItemAttribute = items.ItemAttribute
export type ItemAttributes = items.ItemAttributes
export type ItemInstance = items.ItemInstance
export type UseContext = items.UseContext

export type ItemBehaviorResult = {
	success: boolean,
	reason: string?,
	consumeInstance: boolean?,
	consumeQuantity: number?,
	updateAttributes: ItemAttributes?,
	equipSlot: string?,
	effect: { [string]: ItemAttribute }?,
}

export type ItemBehavior = {
	canUse: (player: any, instance: ItemInstance, context: UseContext) -> (boolean, string?),
	-- Must return data only; domain mutation occurs after inventory confirmation.
	use: (player: any, instance: ItemInstance, context: UseContext) -> ItemBehaviorResult,
}

export type Registry = {
	register: (self: Registry, capability: string, behavior: ItemBehavior) -> boolean,
	get: (self: Registry, capability: string) -> ItemBehavior?,
}

local ItemBehaviorRegistry = {}

function ItemBehaviorRegistry.new(): Registry
	local behaviors: { [string]: ItemBehavior } = {}
	local registry = {} :: Registry

	function registry:register(capability: string, behavior: ItemBehavior): boolean
		if type(capability) ~= "string" or capability == "" then
			return false
		end
		if behaviors[capability] ~= nil then
			return false
		end
		behaviors[capability] = behavior
		return true
	end

	function registry:get(capability: string): ItemBehavior?
		return behaviors[capability]
	end

	return registry
end

return ItemBehaviorRegistry
