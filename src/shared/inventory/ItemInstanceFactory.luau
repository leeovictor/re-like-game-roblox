--!strict

local items = require(script.Parent.items)

type ItemId = items.ItemId
type ItemAttributes = items.ItemAttributes
type ItemInstance = items.ItemInstance
type UidGenerator = () -> string

export type Factory = {
	create: (self: Factory, itemId: ItemId, attributes: ItemAttributes?, quantity: number?) -> ItemInstance?,
}

local ItemInstanceFactory = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function copyAttributes(attributes: ItemAttributes?): ItemAttributes?
	if attributes == nil then
		return nil
	end
	if type(attributes) ~= "table" then
		return nil
	end

	local copy: ItemAttributes = {}
	for key, value in attributes do
		if
			type(key) ~= "string"
			or (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean")
			or (type(value) == "number" and not isFinite(value))
		then
			return nil
		end
		copy[key] = value
	end
	return copy
end

function ItemInstanceFactory.new(uidGenerator: UidGenerator): Factory
	local issuedUids: { [string]: boolean } = {}
	local service = {} :: Factory

	function service:create(itemId: ItemId, attributes: ItemAttributes?, quantity: number?): ItemInstance?
		local item = items[itemId]
		if type(itemId) ~= "string" or item == nil then
			return nil
		end
		if quantity ~= nil and (type(quantity) ~= "number" or not isFinite(quantity) or quantity <= 0 or quantity % 1 ~= 0) then
			return nil
		end
		if quantity ~= nil and not item.stackable then
			return nil
		end
		if item.stackable and quantity == nil then
			quantity = 1
		end

		local copiedAttributes = copyAttributes(attributes)
		if attributes ~= nil and copiedAttributes == nil then
			return nil
		end
		local uid = uidGenerator()
		if type(uid) ~= "string" or uid == "" or issuedUids[uid] then
			return nil
		end
		issuedUids[uid] = true

		return {
			uid = uid,
			itemId = itemId,
			quantity = quantity,
			attributes = copiedAttributes,
		}
	end

	return service
end

return ItemInstanceFactory
