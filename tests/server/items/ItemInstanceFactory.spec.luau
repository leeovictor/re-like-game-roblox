--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local ItemInstanceFactory = loader.load("src/server/items/ItemInstanceFactory.luau")

local function newFactory(): any
	local nextId = 0
	return ItemInstanceFactory.new(function(): string
		nextId += 1
		return string.format("test-uid-%02d", nextId)
	end)
end

local function assertRejected(callback: () -> any): ()
	local ok, result = pcall(callback)
	harness.assert.truthy(ok, "invalid item input should not throw")
	harness.assert.isNil(result, "expected invalid item input to return nil")
end

harness.describe("Item instance factory", function()
	harness.it("creates a unique individual instance", function()
		local factory = newFactory()
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		harness.assert.equal(first.uid, "test-uid-01")
		harness.assert.equal(second.uid, "test-uid-02")
		harness.assert.equal(first.itemId, "handgun")
		harness.assert.falsy(first.quantity)
		harness.assert.truthy(first ~= second)
	end)

	harness.it("rejects a uid that the factory has already emitted", function()
		local factory = ItemInstanceFactory.new(function(): string
			return "repeated-uid"
		end)
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		harness.assert.truthy(first)
		harness.assert.isNil(second)
	end)

	harness.it("preserves authored numeric string and boolean attributes", function()
		local factory = newFactory()
		local instance = factory:create("handgun", {
			damage = 18,
			quality = "museum",
			loaded = false,
		})

		harness.assert.equal(instance.attributes.damage, 18)
		harness.assert.equal(instance.attributes.quality, "museum")
		harness.assert.equal(instance.attributes.loaded, false)
	end)

	harness.it("accepts a valid authored pickup definition", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo", { quality = "map-authored" }, 3)

		harness.assert.equal(instance.itemId, "handgun_ammo")
		harness.assert.equal(instance.quantity, 3)
		harness.assert.equal(instance.attributes.quality, "map-authored")
	end)

	harness.it("creates a positive stack quantity for stackable items", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo", nil, 24)

		harness.assert.equal(instance.quantity, 24)
	end)

	harness.it("defaults stackable instances to a positive quantity", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo")

		harness.assert.equal(instance.quantity, 1)
	end)

	harness.it("rejects non-finite numeric attributes", function()
		local factory = newFactory()
		for _, value in { math.huge, -math.huge, 0 / 0 } do
			assertRejected(function(): any
				return factory:create("handgun", { damage = value })
			end)
		end
	end)

	harness.it("rejects unknown item ids", function()
		local factory = newFactory()
		assertRejected(function(): any
			return factory:create("unknown-item")
		end)
	end)

	harness.it("rejects quantity for non-stackable items", function()
		local factory = newFactory()
		assertRejected(function(): any
			return factory:create("handgun", nil, 2)
		end)
	end)

	harness.it("rejects non-positive quantity", function()
		local factory = newFactory()
		assertRejected(function(): any
			return factory:create("handgun_ammo", nil, 0)
		end)
	end)

	harness.it("returns independent attribute tables", function()
		local factory = newFactory()
		local first = factory:create("iron_key", { label = "old" })
		local second = factory:create("iron_key", { label = "new" })

		first.attributes.label = "changed"
		harness.assert.equal(second.attributes.label, "new")
		harness.assert.truthy(first.attributes ~= second.attributes)
	end)
end)
