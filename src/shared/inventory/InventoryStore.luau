--!strict

local items = require(script.Parent.items)

type ItemAttributes = items.ItemAttributes
type ItemInstance = items.ItemInstance
type InventoryState = items.InventoryState

local InventoryStore = {}

local function copyAttributes(attributes: ItemAttributes?): ItemAttributes?
	if attributes == nil then
		return nil
	end
	return table.clone(attributes)
end

local function copyInstance(instance: ItemInstance): ItemInstance
	return {
		uid = instance.uid,
		itemId = instance.itemId,
		quantity = instance.quantity,
		attributes = copyAttributes(instance.attributes),
	}
end

function InventoryStore.copyState(state: InventoryState): InventoryState
	local result: InventoryState = {
		version = state.version,
		items = {},
		equipped = {},
	}
	for index, instance in state.items do
		result.items[index] = copyInstance(instance)
	end
	for slot, uid in state.equipped do
		result.equipped[slot] = uid
	end
	return result
end

function InventoryStore.defaultInventory(): InventoryState
	return { version = 2, items = {}, equipped = {} }
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: number): boolean
	return isFinite(value) and value > 0 and value == math.floor(value)
end

local function hasCapability(itemId: string, capability: string): boolean
	local definition = items[itemId]
	if definition == nil then
		return false
	end
	for _, value in definition.capabilities do
		if value == capability then
			return true
		end
	end
	return false
end

local function validAttributes(attributes: any): boolean
	if attributes == nil then
		return true
	end
	if type(attributes) ~= "table" then
		return false
	end
	for key, value in attributes do
		if type(key) ~= "string" or (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean") then
			return false
		end
		if type(value) == "number" and not isFinite(value) then return false end
	end
	return true
end

local function validInstance(instance: any, seen: { [string]: boolean }): boolean
	if type(instance) ~= "table" or type(instance.uid) ~= "string" or instance.uid == "" or seen[instance.uid] then
		return false
	end
	if type(instance.itemId) ~= "string" or items[instance.itemId] == nil or not validAttributes(instance.attributes) then
		return false
	end
	local definition = items[instance.itemId]
	if instance.quantity ~= nil and (type(instance.quantity) ~= "number" or not isInteger(instance.quantity)) then
		return false
	end
	if not definition.stackable and instance.quantity ~= nil and instance.quantity ~= 1 then
		return false
	end
	if definition.stackable and instance.quantity == nil then
		return false
	end
	seen[instance.uid] = true
	return true
end

local function validState(state: any): boolean
	if type(state) ~= "table" or state.version ~= 2 or type(state.items) ~= "table" or type(state.equipped) ~= "table" then
		return false
	end
	local seen: { [string]: boolean } = {}
	local length = 0
	for index, instance in state.items do
		if type(index) ~= "number" or index < 1 or index ~= math.floor(index) or not validInstance(instance, seen) then
			return false
		end
		length = math.max(length, index)
	end
	for index = 1, length do
		if state.items[index] == nil then
			return false
		end
	end
	for slot, uid in state.equipped do
		if type(slot) ~= "string" or type(uid) ~= "string" or not seen[uid] then
			return false
		end
	end
	return true
end

function InventoryStore.findInstance(state: InventoryState, uid: string): ItemInstance?
	for _, instance in state.items do
		if instance.uid == uid then
			return copyInstance(instance)
		end
	end
	return nil
end

function InventoryStore.addInstance(state: InventoryState, instance: ItemInstance): InventoryState?
	if not validState(state) or not validInstance(instance, (function()
		local seen: { [string]: boolean } = {}
		for _, existing in state.items do
			seen[existing.uid] = true
		end
		return seen
	end)()) then
		return nil
	end
	local result = InventoryStore.copyState(state)
	table.insert(result.items, copyInstance(instance))
	return result
end

function InventoryStore.removeInstance(state: InventoryState, uid: string): InventoryState?
	if not validState(state) then return nil end
	local result = InventoryStore.copyState(state)
	for index, instance in result.items do
		if instance.uid == uid then
			table.remove(result.items, index)
			for slot, equippedUid in result.equipped do
				if equippedUid == uid then
					result.equipped[slot] = nil
				end
			end
			return result
		end
	end
	return nil
end

function InventoryStore.addQuantity(state: InventoryState, itemId: string, quantity: number, uid: string?): InventoryState?
	if not validState(state) or items[itemId] == nil or not items[itemId].stackable or type(quantity) ~= "number" or not isInteger(quantity) then return nil end
	local result = InventoryStore.copyState(state)
	for _, instance in result.items do
		if instance.itemId == itemId and instance.attributes == nil then
			local updatedQuantity = (instance.quantity :: number) + quantity
			if not isFinite(updatedQuantity) then return nil end
			instance.quantity = updatedQuantity
			return result
		end
	end
	local newUid = uid or itemId .. "-stack-" .. tostring(#result.items + 1)
	return InventoryStore.addInstance(result, { uid = newUid, itemId = itemId, quantity = quantity })
end

function InventoryStore.removeQuantity(state: InventoryState, uid: string, quantity: number): InventoryState?
	if not validState(state) or type(quantity) ~= "number" or not isInteger(quantity) then return nil end
	local instance = InventoryStore.findInstance(state, uid)
	if instance == nil or instance.quantity == nil or quantity > instance.quantity then return nil end
	if quantity == instance.quantity then return InventoryStore.removeInstance(state, uid) end
	local result = InventoryStore.copyState(state)
	local updated = InventoryStore.findInstance(result, uid) :: ItemInstance
	local currentQuantity = updated.quantity :: number
	updated.quantity = currentQuantity - quantity
	return result
end

function InventoryStore.updateAttributes(state: InventoryState, uid: string, attributes: ItemAttributes): InventoryState?
	if not validState(state) or not validAttributes(attributes) or InventoryStore.findInstance(state, uid) == nil then return nil end
	local result = InventoryStore.copyState(state)
	for _, instance in result.items do
		if instance.uid == uid then
			instance.attributes = copyAttributes(attributes)
			break
		end
	end
	return result
end

function InventoryStore.equip(state: InventoryState, slot: string, uid: string): InventoryState?
	if not validState(state) or type(slot) ~= "string" then return nil end
	local instance = InventoryStore.findInstance(state, uid)
	if instance == nil or not hasCapability(instance.itemId, "equip") then return nil end
	local result = InventoryStore.copyState(state)
	result.equipped[slot] = uid
	return result
end

return InventoryStore
