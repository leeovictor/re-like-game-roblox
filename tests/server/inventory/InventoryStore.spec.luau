--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local InventoryStore = loader.load("src/server/inventory/InventoryStore.luau")
local items = loader.load("src/shared/inventory/items.luau")

local function hasCapability(capabilities: { string }, expected: string): boolean
	for _, capability in capabilities do
		if capability == expected then
			return true
		end
	end
	return false
end

local function assertItems(actual: { string }, expected: { string }, message: string)
	harness.assert.equal(#actual, #expected, message .. " length")
	for index, expectedId in expected do
		harness.assert.equal(actual[index], expectedId, message .. " item " .. index)
	end
end

harness.describe("InventoryStore", function()
	harness.it("constructs the version two instance schema", function()
		local state = {
			version = 2,
			items = {
				{
					uid = "handgun-001",
					itemId = "handgun",
					attributes = { damage = 18, loadedAmmo = 5 },
				},
				{
					uid = "ammo-001",
					itemId = "handgun_ammo",
					quantity = 24,
				},
			},
			equipped = { weapon = "handgun-001" },
		}

		harness.assert.equal(state.version, 2)
		harness.assert.equal(state.items[1].uid, "handgun-001")
		harness.assert.equal(state.items[1].attributes.damage, 18)
		harness.assert.equal(state.items[2].quantity, 24)
		harness.assert.equal(state.equipped.weapon, "handgun-001")
	end)

	harness.it("exposes static capabilities in the shared catalog", function()
		harness.assert.truthy(hasCapability(items.medkit.capabilities, "heal"))
		harness.assert.truthy(hasCapability(items.handgun.capabilities, "equip"))
		harness.assert.truthy(hasCapability(items.handgun_ammo.capabilities, "reload-ammo"))
		harness.assert.truthy(hasCapability(items.iron_key.capabilities, "unlock"))
		harness.assert.truthy(items.handgun.stackable == false)
		harness.assert.truthy(items.handgun_ammo.stackable)
	end)

	harness.it("creates an empty version two inventory", function()
		local inventory = InventoryStore.defaultInventory()

		harness.assert.equal(inventory.version, 2)
		harness.assert.equal(#inventory.items, 0)
		harness.assert.equal(next(inventory.equipped), nil)
	end)

	harness.it("serializes the schema in deterministic field and item order", function()
		local serialized = InventoryStore.serialize({ version = 2, items = { "handgun", "handgun_ammo" } })

		harness.assert.equal(serialized, '{"version":2,"items":["handgun","handgun_ammo"]}')
	end)

	harness.it("round-trips version and ordered item IDs", function()
		local original = { version = 2, items = { "handgun", "handgun_ammo" } }
		local deserialized = InventoryStore.deserialize(InventoryStore.serialize(original))

		harness.assert.truthy(deserialized)
		harness.assert.equal(deserialized.version, original.version)
		assertItems(deserialized.items, original.items, "round-trip items")
		harness.assert.equal(InventoryStore.serialize(deserialized), InventoryStore.serialize(original))
	end)

	harness.it("escapes quotes and backslashes in item IDs", function()
		local serialized = InventoryStore.serialize({ version = 2, items = { 'a"b', "a\\b" } })
		local quoteEscape = "\\" .. '"'
		local slashEscape = "\\\\"

		harness.assert.equal(
			serialized,
			'{"version":2,"items":["a' .. quoteEscape .. 'b","a' .. slashEscape .. 'b"]}'
		)
		local deserialized = InventoryStore.deserialize(serialized)
		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { 'a"b', "a\\b" }, "escaped items")
	end)

	harness.it("escapes and round-trips control characters in item IDs", function()
		local controlId = "a\b\f\n\r\t\1\31z"
		local serialized = InventoryStore.serialize({ version = 2, items = { controlId } })
		local deserialized = InventoryStore.deserialize(serialized)

		harness.assert.equal(serialized, '{"version":2,"items":["a\\b\\f\\n\\r\\t\\u0001\\u001fz"]}')
		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { controlId }, "control items")
	end)

	harness.it("rejects raw control characters in JSON strings", function()
		harness.assert.isNil(InventoryStore.deserialize('{"version":2,"items":["raw\n"]}'))
		harness.assert.isNil(InventoryStore.deserialize('{"version":2,"items":["raw\1"]}'))
	end)

	harness.it("decodes Unicode escapes above the Latin-1 range", function()
		local deserialized = InventoryStore.deserialize('{"version":2,"items":["\\u20AC"]}')

		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { "\226\130\172" }, "euro item")
	end)

	harness.it("decodes a valid surrogate pair as UTF-8", function()
		local deserialized = InventoryStore.deserialize('{"version":2,"items":["\\uD83D\\uDE00"]}')

		harness.assert.truthy(deserialized)
		assertItems(deserialized.items, { "\240\159\152\128" }, "surrogate pair item")
	end)

	harness.it("rejects invalid Unicode escapes and surrogate code points", function()
		local invalidValues = {
			'{"version":2,"items":["\\u12G4"]}',
			'{"version":2,"items":["\\uD83D"]}',
			'{"version":2,"items":["\\uDE00"]}',
			'{"version":2,"items":["\\uD83D\\u0041"]}',
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
			'{"version":"2","items":[]}',
			'{"version":1,"items":[]}',
			'{"version":2,"items":{}}',
			'{"version":2,"items":[1]}',
			'{"version":2,"items":[] trailing}',
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
		local original = { version = 2, items = { "handgun", "handgun_ammo" } }
		local updated = InventoryStore.addItem(original, "medkit")

		harness.assert.truthy(updated)
		harness.assert.falsy(updated == original)
		harness.assert.falsy(updated.items == original.items)
		assertItems(updated.items, { "handgun", "handgun_ammo", "medkit" }, "updated items")
		assertItems(original.items, { "handgun", "handgun_ammo" }, "original items")
	end)

	harness.it("rejects an unknown item without changing the source state", function()
		local original = { version = 2, items = { "handgun" } }
		local updated = InventoryStore.addItem(original, "unknown-item")

		harness.assert.isNil(updated)
		assertItems(original.items, { "handgun" }, "original items")
	end)
end)
