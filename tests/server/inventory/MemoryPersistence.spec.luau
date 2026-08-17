--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local InventoryStore = loader.load("src/server/inventory/InventoryStore.luau")
local MemoryPersistence = loader.load("src/server/inventory/persistence/MemoryPersistence.luau")

local function assertItems(actual: { string }, expected: { string }, message: string)
	harness.assert.equal(#actual, #expected, message .. " length")
	for index, expectedId in expected do
		harness.assert.equal(actual[index], expectedId, message .. " item " .. index)
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
	end)

	harness.it("returns the saved map value instead of reseeding on a second load", function()
		local persistence = MemoryPersistence.new()
		local first = persistence:load(42)
		first.items[1] = "saved-item"

		local second = persistence:load(42)

		assertItems(second.items, { "saved-item" }, "saved items")
	end)

	harness.it("saves a replacement independently for each user", function()
		local persistence = MemoryPersistence.new()
		local replacement = {
			version = 2,
			items = { "replacement" },
			equipped = { weapon = "handgun-001" },
		}

		persistence:save(42, replacement)
		replacement.items[1] = "mutated-after-save"

		local saved = persistence:load(42)
		local otherUser = persistence:load(7)

		assertItems(saved.items, { "replacement" }, "replacement items")
		harness.assert.equal(saved.equipped.weapon, "handgun-001")
		assertItems(otherUser.items, {}, "other user items")
		harness.assert.falsy(saved == replacement)
		harness.assert.falsy(saved.items == replacement.items)
	end)
end)
