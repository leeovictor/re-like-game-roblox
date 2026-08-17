--!strict

local catalog = require(script.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.catalog)
local inventoryTypes = require(script.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.items)
local behaviorTypes = require(script.Parent.ItemBehaviorRegistry)

type ItemInstance = inventoryTypes.ItemInstance
type InventoryState = inventoryTypes.InventoryState
type UseRequest = inventoryTypes.UseRequest
type UseResult = inventoryTypes.UseResult
type UseContext = inventoryTypes.UseContext
type ItemAttributes = inventoryTypes.ItemAttributes
type ItemBehavior = behaviorTypes.ItemBehavior
type UseMutations = {
	consumeInstance: boolean?,
	consumeQuantity: number?,
	updateAttributes: ItemAttributes?,
	equipSlot: string?,
}

type InventoryService = {
	find: (self: InventoryService, player: Player, uid: string) -> ItemInstance?,
	getSnapshot: (self: InventoryService, player: Player) -> InventoryState?,
	removeInstance: (self: InventoryService, player: Player, uid: string) -> boolean,
	removeQuantity: (self: InventoryService, player: Player, uid: string, quantity: number) -> boolean,
	updateAttributes: (self: InventoryService, player: Player, uid: string, attributes: ItemAttributes) -> boolean,
	equip: (self: InventoryService, player: Player, slot: string, uid: string) -> boolean,
	applyUseMutations: (self: InventoryService, player: Player, uid: string, mutations: UseMutations) -> boolean,
}

type Registry = {
	get: (self: Registry, capability: string) -> ItemBehavior?,
}

export type Service = {
	findCompatibleItem: (self: Service, player: Player, request: UseRequest) -> ItemInstance?,
	use: (self: Service, player: Player, request: UseRequest) -> UseResult,
	bind: (self: Service, remote: RemoteFunction) -> (),
}

local ItemUseService = {}

local function hasCapability(itemId: string, capability: string): boolean
	local definition = catalog[itemId]
	if definition == nil then
		return false
	end
	for _, itemCapability in definition.capabilities do
		if itemCapability == capability then
			return true
		end
	end
	return false
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function validContext(context: any): boolean
	if type(context) ~= "table" then return false end
	for key, value in context do
		if type(key) ~= "string" then return false end
		local valueType = type(value)
		if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then return false end
		if valueType == "number" and not finite(value) then return false end
	end
	return true
end

local function validRequest(request: any): boolean
	if type(request) ~= "table" or type(request.capability) ~= "string" or request.capability == "" then
		return false
	end
	if request.itemUid ~= nil and (type(request.itemUid) ~= "string" or request.itemUid == "") then
		return false
	end
	return validContext(request.context)
end

function ItemUseService.new(inventory: InventoryService, registry: Registry): Service
	local busy: { [Player]: boolean } = {}
	local service = {} :: Service

	local function getBehavior(request: UseRequest): ItemBehavior?
		return registry:get(request.capability)
	end

	local function checkCompatibility(player: Player, instance: ItemInstance, request: UseRequest, behavior: ItemBehavior): (boolean, string?)
		if not hasCapability(instance.itemId, request.capability) then
			return false, nil
		end
		local ok, canUse, reason = pcall(function(): (boolean, string?)
			return behavior.canUse(player, instance, request.context)
		end)
		if not ok then
			return false, nil
		end
		return canUse == true, reason
	end

	local function findCompatible(player: Player, request: UseRequest, behavior: ItemBehavior): (ItemInstance?, string?)
		if request.itemUid ~= nil then
			local instance = inventory:find(player, request.itemUid)
			if instance == nil then return nil, nil end
			local canUse, reason = checkCompatibility(player, instance, request, behavior)
			if canUse then
				return instance
			end
			return nil, reason
		end
		local snapshot = inventory:getSnapshot(player)
		if snapshot == nil then return nil, nil end
		local firstReason: string? = nil
		for _, instance in snapshot.items do
			local canUse, reason = checkCompatibility(player, instance, request, behavior)
			if canUse then
				return instance
			end
			if firstReason == nil and reason ~= nil then
				firstReason = reason
			end
		end
		return nil, firstReason
	end

	function service:findCompatibleItem(player: Player, request: UseRequest): ItemInstance?
		if not validRequest(request) then
			return nil
		end
		local behavior = getBehavior(request)
		if behavior == nil then
			return nil
		end

		local instance = findCompatible(player, request, behavior)
		return instance
	end

	local function failure(reason: string): UseResult
		return { success = false, reason = reason }
	end

	function service:use(player: Player, request: UseRequest): UseResult
		if busy[player] then
			return failure("operation_in_progress")
		end
		if not validRequest(request) then
			return failure("invalid_request")
		end
		local behavior = getBehavior(request)
		if behavior == nil then
			return failure("unknown_capability")
		end

		busy[player] = true
		local result: UseResult = failure("item_not_found")
		local ok = pcall(function(): ()
			local compatibleInstance, compatibilityReason = findCompatible(player, request, behavior)
			if compatibleInstance == nil then
				if compatibilityReason ~= nil then
					result = failure(compatibilityReason)
				end
				return
			end
			local instance = inventory:find(player, compatibleInstance.uid)
			if instance == nil then
				return
			end
			local canUse, reason = checkCompatibility(player, instance, request, behavior)
			if not canUse then
				if reason ~= nil then
					result = failure(reason)
				else
					result = failure("not_compatible")
				end
				return
			end

			local useOk, behaviorResult = pcall(function(): behaviorTypes.ItemBehaviorResult
				return behavior.use(player, instance :: ItemInstance, request.context)
			end)
			if not useOk then
				result = failure("use_failed")
				return
			end
			if not behaviorResult.success then
				result = failure(behaviorResult.reason or "use_failed")
				return
			end

			local mutations: UseMutations = {
				consumeInstance = behaviorResult.consumeInstance,
				consumeQuantity = behaviorResult.consumeQuantity,
				updateAttributes = behaviorResult.updateAttributes,
				equipSlot = behaviorResult.equipSlot,
			}
			if not inventory:applyUseMutations(player, instance.uid, mutations) then
				result = failure("mutation_failed")
				return
			end
			result = {
				success = true,
				itemUid = instance.uid,
				consumed = mutations.consumeInstance == true or mutations.consumeQuantity ~= nil,
				effect = behaviorResult.effect,
			}
		end)
		busy[player] = nil
		if not ok then
			return failure("use_failed")
		end
		return result
	end

	function service:bind(remote: RemoteFunction): ()
		remote.OnServerInvoke = function(player: Player, request: any): UseResult
			if not validRequest(request) then
				return failure("invalid_request")
			end
			return service:use(player, request :: UseRequest)
		end
	end

	return service
end

return ItemUseService
