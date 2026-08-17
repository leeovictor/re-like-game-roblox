--!strict

local items = require(script.Parent.Parent.Parent.Parent.ReplicatedStorage.Shared.inventory.items)

type ItemAttribute = string | number | boolean
type ItemAttributes = { [string]: ItemAttribute }
type ItemInstance = {
	uid: string,
	itemId: string,
	quantity: number?,
	attributes: ItemAttributes?,
}
type InventoryState = {
	version: number,
	items: { ItemInstance },
	equipped: { [string]: string },
}

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

local function hexadecimalValue(character: string): number?
	local code = string.byte(character)
	if code == nil then return nil end
	if code >= string.byte("0") and code <= string.byte("9") then return code - string.byte("0") end
	if code >= string.byte("a") and code <= string.byte("f") then return code - string.byte("a") + 10 end
	if code >= string.byte("A") and code <= string.byte("F") then return code - string.byte("A") + 10 end
	return nil
end

local function encodeUtf8(code: number): string
	if code <= 0x7F then return string.char(code) end
	if code <= 0x7FF then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
	if code <= 0xFFFF then
		return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40, 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
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

local function escapeString(value: string): string
	local result = {}
	for index = 1, #value do
		local character = string.sub(value, index, index)
		local code = string.byte(character)
		if character == "\\" then table.insert(result, "\\\\")
		elseif character == '"' then table.insert(result, '\\"')
		elseif character == "\b" then table.insert(result, "\\b")
		elseif character == "\f" then table.insert(result, "\\f")
		elseif character == "\n" then table.insert(result, "\\n")
		elseif character == "\r" then table.insert(result, "\\r")
		elseif character == "\t" then table.insert(result, "\\t")
		elseif code < 32 then table.insert(result, string.format("\\u%04x", code))
		else
			table.insert(result, character)
		end
	end
	return table.concat(result)
end

local function jsonValue(value: any): string
	if type(value) == "string" then return '"' .. escapeString(value) .. '"' end
	if type(value) == "number" then return tostring(value) end
	if type(value) == "boolean" then return if value then "true" else "false" end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		table.insert(parts, jsonValue(key) .. ":" .. jsonValue(value[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function InventoryStore.serialize(state: InventoryState): string
	assert(validState(state), "invalid inventory state")
	local serializedItems = {}
	for index = 1, #state.items do
		local instance = state.items[index]
		local fields = { '"itemId":' .. jsonValue(instance.itemId) }
		if instance.attributes ~= nil then
			table.insert(fields, 1, '"attributes":' .. jsonValue(instance.attributes))
		end
		if instance.quantity ~= nil then
			table.insert(fields, '"quantity":' .. tostring(instance.quantity))
		end
		table.insert(fields, '"uid":' .. jsonValue(instance.uid))
		table.insert(serializedItems, "{" .. table.concat(fields, ",") .. "}")
	end
	return '{"version":2,"items":[' .. table.concat(serializedItems, ",") .. '],"equipped":' .. jsonValue(state.equipped) .. "}"
end

local function parseJson(source: string): any
	local position = 1
	local function isJsonWhitespace(character: string): boolean
		return character == " " or character == "\t" or character == "\n" or character == "\r"
	end
	local function whitespace(): ()
		while isJsonWhitespace(string.sub(source, position, position)) do
			position += 1
		end
	end
	local parseValue: () -> any
	local function parseString(): string?
		if string.sub(source, position, position) ~= '"' then return nil end
		position += 1
		local result = {}
		while position <= #source do
			local character = string.sub(source, position, position)
			if character == '"' then
				position += 1
				return table.concat(result)
			end
			if character == "\\" then
				position += 1
				local escaped = string.sub(source, position, position)
				local replacements = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				local replacement = replacements[escaped]
				if escaped == "u" then
					local code = 0
					for offset = 1, 4 do
						local digit = hexadecimalValue(string.sub(source, position + offset, position + offset))
						if digit == nil then return nil end
						code = code * 16 + digit
					end
					if code >= 0xD800 and code <= 0xDBFF then
						if string.sub(source, position + 5, position + 6) ~= "\\u" then return nil end
						local lowCode = 0
						for offset = 7, 10 do
							local digit = hexadecimalValue(string.sub(source, position + offset, position + offset))
							if digit == nil then return nil end
							lowCode = lowCode * 16 + digit
						end
						if lowCode < 0xDC00 or lowCode > 0xDFFF then return nil end
						code = 0x10000 + (code - 0xD800) * 0x400 + lowCode - 0xDC00
						position += 10
					elseif code >= 0xDC00 and code <= 0xDFFF then
						return nil
					else
						position += 4
					end
					table.insert(result, encodeUtf8(code))
				else
					if replacement == nil then return nil end
					table.insert(result, replacement)
				end
			else
				if string.byte(character) < 32 then return nil end
				table.insert(result, character)
			end
			position += 1
		end
		return nil
	end
	local function parseNumber(): number?
		local start = position
		if string.sub(source, position, position) == "-" then
			position += 1
		end
		local firstDigit = string.sub(source, position, position)
		if firstDigit == "0" then
			position += 1
			if string.match(string.sub(source, position, position), "%d") then return nil end
		elseif string.match(firstDigit, "[1-9]") then
			repeat
				position += 1
			until not string.match(string.sub(source, position, position), "%d")
		else
			return nil
		end
		if string.sub(source, position, position) == "." then
			position += 1
			local fractionStart = position
			while string.match(string.sub(source, position, position), "%d") do
				position += 1
			end
			if position == fractionStart then return nil end
		end
		if string.sub(source, position, position) == "e" or string.sub(source, position, position) == "E" then
			position += 1
			if string.sub(source, position, position) == "+" or string.sub(source, position, position) == "-" then
				position += 1
			end
			local exponentStart = position
			while string.match(string.sub(source, position, position), "%d") do
				position += 1
			end
			if position == exponentStart then return nil end
		end
		local value = tonumber(string.sub(source, start, position - 1))
		return if value ~= nil and isFinite(value) then value else nil
	end
	local function parseArray(): any?
		position += 1
		local result = {}
		whitespace()
		if string.sub(source, position, position) == "]" then
			position += 1
			return result
		end
		while true do
			local value = parseValue()
			if value == nil then return nil end
			table.insert(result, value)
			whitespace()
			local separator = string.sub(source, position, position)
			if separator == "]" then
				position += 1
				return result
			end
			if separator ~= "," then return nil end
			position += 1
			whitespace()
		end
	end
	local function parseObject(): any?
		position += 1
		local result = {}
		whitespace()
		if string.sub(source, position, position) == "}" then
			position += 1
			return result
		end
		while true do
			local key = parseString()
			if key == nil then return nil end
			whitespace()
			if string.sub(source, position, position) ~= ":" then return nil end
			position += 1
			whitespace()
			local value = parseValue()
			if value == nil then return nil end
			result[key] = value
			whitespace()
			local separator = string.sub(source, position, position)
			if separator == "}" then
				position += 1
				return result
			end
			if separator ~= "," then return nil end
			position += 1
			whitespace()
		end
	end
	parseValue = function(): any
		whitespace()
		local character = string.sub(source, position, position)
		if character == '"' then return parseString()
		elseif character == "[" then return parseArray()
		elseif character == "{" then return parseObject()
		elseif string.sub(source, position, position + 3) == "true" then
			position += 4
			return true
		elseif string.sub(source, position, position + 4) == "false" then
			position += 5
			return false
		else
			return parseNumber()
		end
	end
	local result = parseValue()
	whitespace()
	if position <= #source then return nil end
	return result
end

function InventoryStore.deserialize(serialized: string): InventoryState?
	local result = parseJson(serialized)
	if not validState(result) then return nil end
	return InventoryStore.copyState(result)
end

return InventoryStore
