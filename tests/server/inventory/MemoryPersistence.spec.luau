--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local InventoryStore = loader.load("src/server/inventory/InventoryStore.luau")
local MemoryPersistence = loader.load("src/server/inventory/persistence/MemoryPersistence.luau")

local function assertItems(actual: { any }, expected: { any }, message: string)
	harness.assert.equal(#actual, #expected, message .. " length")
	for index, expectedItem in expected do
		harness.assert.equal(actual[index].uid, expectedItem.uid, message .. " item " .. index .. " uid")
		harness.assert.equal(actual[index].itemId, expectedItem.itemId, message .. " item " .. index .. " itemId")
		harness.assert.equal(actual[index].quantity, expectedItem.quantity, message .. " item " .. index .. " quantity")
	end
end

harness.describe("MemoryPersistence", function()
	harness.it("starts a user with an empty state without sharing its tables", function()
		local persistence = MemoryPersistence.new()
		local state = persistence:load(42)
		local defaultState = InventoryStore.defaultInventory()

		harness.assert.equal(InventoryStore.serialize(state), InventoryStore.serialize(defaultState))
		harness.assert.falsy(state == defaultState)
		harness.assert.falsy(state.items == defaultState.items)
		harness.assert.equal(state.version, 2)
		harness.assert.equal(next(state.equipped), nil)
	end)

	harness.it("returns a copy of saved state on every load", function()
		local persistence = MemoryPersistence.new()
		persistence:save(42, {
			version = 2,
			items = { { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12, attributes = { quality = "old" } } },
			equipped = {},
		})
		local first = persistence:load(42)
		first.items[1].quantity = 99
		first.items[1].attributes.quality = "new"

		local second = persistence:load(42)

		assertItems(second.items, { { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 } }, "saved items")
		harness.assert.equal(second.items[1].attributes.quality, "old")
		harness.assert.falsy(second.items == first.items)
		harness.assert.falsy(second.items[1] == first.items[1])
		harness.assert.falsy(second.items[1].attributes == first.items[1].attributes)
	end)

	harness.it("saves a replacement independently for each user", function()
		local persistence = MemoryPersistence.new()
		local replacement = {
			version = 2,
			items = { { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } } },
			equipped = { weapon = "handgun-001" },
		}

		persistence:save(42, replacement)
		replacement.items[1].attributes.loadedAmmo = 0

		local saved = persistence:load(42)
		local otherUser = persistence:load(7)

		assertItems(saved.items, { { uid = "handgun-001", itemId = "handgun" } }, "replacement items")
		harness.assert.equal(saved.items[1].attributes.loadedAmmo, 5)
		harness.assert.equal(saved.equipped.weapon, "handgun-001")
		assertItems(otherUser.items, {}, "other user items")
		harness.assert.falsy(saved == replacement)
		harness.assert.falsy(saved.items == replacement.items)
	end)
end)
