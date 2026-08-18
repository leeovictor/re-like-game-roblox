--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local InventoryStore = require(ServerScriptService.Server.inventory.InventoryStore)
local MemoryPersistence = require(ServerScriptService.Server.inventory.persistence.MemoryPersistence)

local function assertItems(assert: any, actual: { any }, expected: { any }, message: string)
	assert(#actual).to.equal(#expected, message .. " length")
	for index, expectedItem in expected do
		assert(actual[index].uid).to.equal(expectedItem.uid, message .. " item " .. index .. " uid")
		assert(actual[index].itemId).to.equal(expectedItem.itemId, message .. " item " .. index .. " itemId")
		assert(actual[index].quantity).to.equal(expectedItem.quantity, message .. " item " .. index .. " quantity")
	end
end

return function()
	describe("MemoryPersistence", function()
	it("starts a user with an empty state without sharing its tables", function()
		local persistence = MemoryPersistence.new()
		local state = persistence:load(42)
		local defaultState = InventoryStore.defaultInventory()

		expect(InventoryStore.serialize(state)).to.equal(InventoryStore.serialize(defaultState))
		expect(state == defaultState).to.equal(false)
		expect(state.items == defaultState.items).to.equal(false)
		expect(state.version).to.equal(2)
		expect(next(state.equipped)).to.equal(nil)
	end)

	it("returns a copy of saved state on every load", function()
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

		assertItems(expect, second.items, { { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 } }, "saved items")
		expect(second.items[1].attributes.quality).to.equal("old")
		expect(second.items == first.items).to.equal(false)
		expect(second.items[1] == first.items[1]).to.equal(false)
		expect(second.items[1].attributes == first.items[1].attributes).to.equal(false)
	end)

	it("saves a replacement independently for each user", function()
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

		assertItems(expect, saved.items, { { uid = "handgun-001", itemId = "handgun" } }, "replacement items")
		expect(saved.items[1].attributes.loadedAmmo).to.equal(5)
		expect(saved.equipped.weapon).to.equal("handgun-001")
		assertItems(expect, otherUser.items, {}, "other user items")
		expect(saved == replacement).to.equal(false)
		expect(saved.items == replacement.items).to.equal(false)
	end)
end)
end
