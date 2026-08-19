--!strict

local behaviorTypes = require(script.Parent.Parent.items.ItemBehaviorRegistry)

type ItemBehavior = behaviorTypes.ItemBehavior

local DoorUnlockBehavior = {}

function DoorUnlockBehavior.create(): ItemBehavior
	return {
		canUse = function(_player: any, instance: any, context: any): (boolean, string?)
			if type(context) ~= "table" or type(context.requiredItemId) ~= "string" or context.requiredItemId == "" then
				return false, "missing_item"
			end
			if type(instance) ~= "table" or instance.itemId ~= context.requiredItemId then
				return false, "missing_item"
			end
			return true, nil
		end,
		use = function(_player: any, _instance: any, _context: any): behaviorTypes.ItemBehaviorResult
			return { success = true }
		end,
	}
end

return DoorUnlockBehavior
