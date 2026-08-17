--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local InventoryStore = loader.load("src/server/inventory/InventoryStore.luau")
local items = loader.load("src/shared/inventory/items.luau")

local function assertItems(actual: { string }, expected: { string }, message: string)
	harness.assert.equal(#actual, #expected, message .. " length")
	for index, expectedId in expected do
		harness.assert.equal(actual[index], expectedId, message .. " item " .. index)
	end
end

harness.describe("InventoryStore", function()
	harness.it("creates the fixed catalog-backed default seed", function()
		local inventory = InventoryStore.defaultInventory()

		harness.assert.equal(inventory.version, 1)
		assertItems(inventory.items, { "torch", "ration", "crystal" }, "default items")
		for _, itemId in inventory.items do
			harness.assert.truthy(items[itemId], "default item must exist in catalog")
		end
	end)

	harness.it("serializes the schema in deterministic field and item order", function()
		local serialized = InventoryStore.serialize({ version = 1, items = { "torch", "ration" } })

		harness.assert.equal(serialized, '{"version":1,"items":["torch","ration"]}')
	end)

	harness.it("round-trips version and ordered item IDs", function()
		local original = { version = 1, items = { "torch", "ration" } }
		local deserialized = InventoryStore.deserialize(InventoryStore.serialize(original))

		harness.assert.truthy(deserialized)
		harness.assert.equal(deserialized.version, original.version)
		assertItems(deserialized.items, original.items, "round-trip items")
		harness.assert.equal(InventoryStore.serialize(deserialized), InventoryStore.serialize(original))
	end)

	harness.it("escapes quotes and backslashes in item IDs", function()
		local serialized = InventoryStore.serialize({ version = 1, items = { 'a"b', "a\\b" } })
		local quoteEscape = "\\" .. '"'
		local slashEscape = "\\\\"

		harness.assert.equal(
			serialized,
			'{"version":1,"items":["a' .. quoteEscape .. 'b","a' .. slashEscape .. 'b"]}'
		)
		local deserialized = InventoryStore.deserialize(serialized)
		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { 'a"b', "a\\b" }, "escaped items")
	end)

	harness.it("escapes and round-trips control characters in item IDs", function()
		local controlId = "a\b\f\n\r\t\1\31z"
		local serialized = InventoryStore.serialize({ version = 1, items = { controlId } })
		local deserialized = InventoryStore.deserialize(serialized)

		harness.assert.equal(serialized, '{"version":1,"items":["a\\b\\f\\n\\r\\t\\u0001\\u001fz"]}')
		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { controlId }, "control items")
	end)

	harness.it("rejects raw control characters in JSON strings", function()
		harness.assert.isNil(InventoryStore.deserialize('{"version":1,"items":["raw\n"]}'))
		harness.assert.isNil(InventoryStore.deserialize('{"version":1,"items":["raw\1"]}'))
	end)

	harness.it("decodes Unicode escapes above the Latin-1 range", function()
		local deserialized = InventoryStore.deserialize('{"version":1,"items":["\\u20AC"]}')

		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { "\226\130\172" }, "euro item")
	end)

	harness.it("decodes a valid surrogate pair as UTF-8", function()
		local deserialized = InventoryStore.deserialize('{"version":1,"items":["\\uD83D\\uDE00"]}')

		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { "\240\159\152\128" }, "surrogate pair item")
	end)

	harness.it("rejects invalid Unicode escapes and surrogate code points", function()
		local invalidValues = {
			'{"version":1,"items":["\\u12G4"]}',
			'{"version":1,"items":["\\uD83D"]}',
			'{"version":1,"items":["\\uDE00"]}',
			'{"version":1,"items":["\\uD83D\\u0041"]}',
		}

		for _, serialized in invalidValues do
			harness.assert.isNil(InventoryStore.deserialize(serialized), "invalid Unicode must be rejected")
		end
	end)

	harness.it("rejects malformed and unsupported inventory data", function()
		local invalidValues = {
			"not json",
			"[]",
			"[1]",
			'"text"',
			"1",
			'{"version":"1","items":[]}',
			'{"version":2,"items":[]}',
			'{"version":1,"items":{}}',
			'{"version":1,"items":[1]}',
			'{"version":1,"items":[] trailing}',
		}

		for _, serialized in invalidValues do
			harness.assert.isNil(InventoryStore.deserialize(serialized), "invalid inventory must be rejected")
		end
	end)

	harness.it("returns a fresh default inventory table", function()
		local first = InventoryStore.defaultInventory()
		local second = InventoryStore.defaultInventory()

		harness.assert.falsy(first == second)
		harness.assert.falsy(first.items == second.items)
	end)

	harness.it("adds a valid catalog item without mutating the source state", function()
		local original = { version = 1, items = { "torch", "ration" } }
		local updated = InventoryStore.addItem(original, "crystal")

		harness.assert.truthy(updated)
		harness.assert.falsy(updated == original)
		harness.assert.falsy(updated.items == original.items)
		assertItems(updated.items, { "torch", "ration", "crystal" }, "updated items")
		assertItems(original.items, { "torch", "ration" }, "original items")
	end)

	harness.it("rejects an unknown item without changing the source state", function()
		local original = { version = 1, items = { "torch" } }
		local updated = InventoryStore.addItem(original, "unknown-item")

		harness.assert.isNil(updated)
		assertItems(original.items, { "torch" }, "original items")
	end)
end)
