--!strict

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local items = require(ReplicatedStorage.Shared.inventory.items)

type ItemId = string
type InventoryState = {
	version: number,
	items: { ItemId },
}

local InventoryStore = {}
local objectMarker = {}
local defaultItemIds = { "torch", "ration", "crystal" }

local function isWhitespace(character: string): boolean
	return character == " " or character == "\t" or character == "\n" or character == "\r"
end

local function isDigit(character: string): boolean
	local code = string.byte(character)
	return code ~= nil and code >= string.byte("0") and code <= string.byte("9")
end

local function hexadecimalValue(character: string): number?
	local code = string.byte(character)
	if code == nil then
		return nil
	elseif code >= string.byte("0") and code <= string.byte("9") then
		return code - string.byte("0")
	elseif code >= string.byte("a") and code <= string.byte("f") then
		return code - string.byte("a") + 10
	elseif code >= string.byte("A") and code <= string.byte("F") then
		return code - string.byte("A") + 10
	end
	return nil
end

local function parseUnicodeCodeUnit(source: string, position: number): number?
	local code = 0
	for offset = 2, 5 do
		local digit = hexadecimalValue(string.sub(source, position + offset, position + offset))
		if digit == nil then
			return nil
		end
		code = code * 16 + digit
	end
	return code
end

local function encodeUtf8(code: number): string
	if code <= 0x7F then
		return string.char(code)
	elseif code <= 0x7FF then
		return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
	elseif code <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(code / 0x1000),
			0x80 + math.floor(code / 0x40) % 0x40,
			0x80 + code % 0x40
		)
	else
		return string.char(
			0xF0 + math.floor(code / 0x40000),
			0x80 + math.floor(code / 0x1000) % 0x40,
			0x80 + math.floor(code / 0x40) % 0x40,
			0x80 + code % 0x40
		)
	end
end

local function escapeString(value: string): string
	local escaped = {}
	for index = 1, #value do
		local character = string.sub(value, index, index)
		local code = string.byte(character)
		if character == "\\" then
			table.insert(escaped, "\\\\")
		elseif character == '"' then
			table.insert(escaped, '\\"')
		elseif character == "\b" then
			table.insert(escaped, "\\b")
		elseif character == "\f" then
			table.insert(escaped, "\\f")
		elseif character == "\n" then
			table.insert(escaped, "\\n")
		elseif character == "\r" then
			table.insert(escaped, "\\r")
		elseif character == "\t" then
			table.insert(escaped, "\\t")
		elseif code < 32 then
			table.insert(escaped, string.format("\\u%04x", code))
		else
			table.insert(escaped, character)
		end
	end
	return table.concat(escaped)
end

local function skipWhitespace(source: string, position: number): number
	while position <= #source and isWhitespace(string.sub(source, position, position)) do
		position += 1
	end
	return position
end

local function parseString(source: string, position: number): (string?, number)
	if string.sub(source, position, position) ~= '"' then
		return nil, position
	end

	local result = {}
	position += 1
	while position <= #source do
		local character = string.sub(source, position, position)
		if character == '"' then
			return table.concat(result), position + 1
		elseif character == "\\" then
			local escaped = string.sub(source, position + 1, position + 1)
			local replacements = {
				['"'] = '"',
				["\\"] = "\\",
				["/"] = "/",
				["b"] = "\b",
				["f"] = "\f",
				["n"] = "\n",
				["r"] = "\r",
				["t"] = "\t",
			}
			local replacement = replacements[escaped]
			if escaped == "u" then
				local code = parseUnicodeCodeUnit(source, position)
				if code == nil then
					return nil, position
				end
				if code >= 0xD800 and code <= 0xDBFF then
					if string.sub(source, position + 6, position + 7) ~= "\\u" then
						return nil, position
					end
					local lowCode = parseUnicodeCodeUnit(source, position + 6)
					if lowCode == nil or lowCode < 0xDC00 or lowCode > 0xDFFF then
						return nil, position
					end
					code = 0x10000 + (code - 0xD800) * 0x400 + (lowCode - 0xDC00)
					if code > 0x10FFFF then
						return nil, position
					end
					replacement = encodeUtf8(code)
					position += 10
				elseif code >= 0xDC00 and code <= 0xDFFF then
					return nil, position
				else
					replacement = encodeUtf8(code)
					position += 4
				end
			elseif replacement == nil then
				return nil, position
			end
			table.insert(result, replacement)
			position += 2
		else
			if string.byte(character) < 32 then
				return nil, position
			end
			table.insert(result, character)
			position += 1
		end
	end

	return nil, position
end

local function parseNumber(source: string, position: number): (number?, number)
	local start = position
	local character = string.sub(source, position, position)
	if character == "-" then
		position += 1
	end

	local firstDigit = string.sub(source, position, position)
	if firstDigit == "0" then
		position += 1
	elseif isDigit(firstDigit) and firstDigit ~= "0" then
		repeat
			position += 1
			character = string.sub(source, position, position)
		until not isDigit(character)
	else
		return nil, start
	end

	if string.sub(source, position, position) == "." then
		position += 1
		local fractionStart = position
		while isDigit(string.sub(source, position, position)) do
			position += 1
		end
		if position == fractionStart then
			return nil, start
		end
	end

	character = string.sub(source, position, position)
	if character == "e" or character == "E" then
		position += 1
		local exponentSign = string.sub(source, position, position)
		if exponentSign == "+" or exponentSign == "-" then
			position += 1
		end
		local exponentStart = position
		while isDigit(string.sub(source, position, position)) do
			position += 1
		end
		if position == exponentStart then
			return nil, start
		end
	end

	local number = tonumber(string.sub(source, start, position - 1))
	if number == nil then
		return nil, start
	end
	return number, position
end

local parseValue

local function parseArray(source: string, position: number): (any?, number)
	local values = {}
	position = skipWhitespace(source, position + 1)
	if string.sub(source, position, position) == "]" then
		return values, position + 1
	end

	while true do
		local value
		value, position = parseValue(source, position)
		if value == nil then
			return nil, position
		end
		table.insert(values, value)
		position = skipWhitespace(source, position)
		local separator = string.sub(source, position, position)
		if separator == "]" then
			return values, position + 1
		elseif separator ~= "," then
			return nil, position
		end
		position = skipWhitespace(source, position + 1)
	end
end

local function parseObject(source: string, position: number): (any?, number)
	local object = setmetatable({}, { __index = objectMarker })
	position = skipWhitespace(source, position + 1)
	if string.sub(source, position, position) == "}" then
		return object, position + 1
	end

	while true do
		local key
		key, position = parseString(source, position)
		if key == nil then
			return nil, position
		end
		position = skipWhitespace(source, position)
		if string.sub(source, position, position) ~= ":" then
			return nil, position
		end
		position = skipWhitespace(source, position + 1)
		local value
		value, position = parseValue(source, position)
		if value == nil then
			return nil, position
		end
		object[key] = value
		position = skipWhitespace(source, position)
		local separator = string.sub(source, position, position)
		if separator == "}" then
			return object, position + 1
		elseif separator ~= "," then
			return nil, position
		end
		position = skipWhitespace(source, position + 1)
	end
end

parseValue = function(source: string, position: number): (any?, number)
	position = skipWhitespace(source, position)
	local character = string.sub(source, position, position)
	if character == '"' then
		return parseString(source, position)
	elseif character == "[" then
		return parseArray(source, position)
	elseif character == "{" then
		return parseObject(source, position)
	else
		return parseNumber(source, position)
	end
end

function InventoryStore.defaultInventory(): InventoryState
	for _, itemId in defaultItemIds do
		assert(items[itemId] ~= nil, "default inventory item is missing from catalog")
	end
	return {
		version = 1,
		items = table.clone(defaultItemIds),
	}
end

function InventoryStore.addItem(state: InventoryState, itemId: string): InventoryState?
	if items[itemId] == nil then
		return nil
	end

	local updated = {
		version = state.version,
		items = table.clone(state.items),
	}
	table.insert(updated.items, itemId)
	return updated
end

function InventoryStore.serialize(state: InventoryState): string
	local serializedItems = {}
	for _, itemId in state.items do
		table.insert(serializedItems, '"' .. escapeString(itemId) .. '"')
	end
	return '{"version":' .. tostring(state.version) .. ',"items":[' .. table.concat(serializedItems, ",") .. "]}"
end

function InventoryStore.deserialize(serialized: string): InventoryState?
	local value, position = parseValue(serialized, 1)
	position = skipWhitespace(serialized, position)
	if value == nil or position <= #serialized or type(value) ~= "table" then
		return nil
	end
	local metatable = getmetatable(value)
	if metatable == nil or metatable.__index ~= objectMarker then
		return nil
	end

	if value.version ~= 1 or type(value.version) ~= "number" or type(value.items) ~= "table" or getmetatable(value.items) ~= nil then
		return nil
	end
	local parsedItems = {}
	for index, itemId in value.items do
		if type(index) ~= "number" or type(itemId) ~= "string" then
			return nil
		end
		parsedItems[index] = itemId
	end
	return {
		version = 1,
		items = parsedItems,
	}
end

return InventoryStore
