--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local ItemInstanceFactory = require(ServerScriptService.Server.items.ItemInstanceFactory)

local function newFactory(): any
	local nextId = 0
	return ItemInstanceFactory.new(function(): string
		nextId += 1
		return string.format("test-uid-%02d", nextId)
	end)
end

local function assertRejected(assert: any, callback: () -> any): ()
	local ok, result = pcall(callback)
	assert(ok).to.equal(true, "invalid item input should not throw")
	assert(result).to.equal(nil, "expected invalid item input to return nil")
end

return function()
	describe("Item instance factory", function()
	it("creates a unique individual instance", function()
		local factory = newFactory()
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		expect(first.uid).to.equal("test-uid-01")
		expect(second.uid).to.equal("test-uid-02")
		expect(first.itemId).to.equal("handgun")
		expect(first.quantity).to.equal(nil)
		expect(first == second).to.equal(false)
	end)

	it("rejects a uid that the factory has already emitted", function()
		local factory = ItemInstanceFactory.new(function(): string
			return "repeated-uid"
		end)
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		expect(first).to.be.ok()
		expect(second).to.equal(nil)
	end)

	it("preserves authored numeric string and boolean attributes", function()
		local factory = newFactory()
		local instance = factory:create("handgun", {
			damage = 18,
			quality = "museum",
			loaded = false,
		})

		expect(instance.attributes.damage).to.equal(18)
		expect(instance.attributes.quality).to.equal("museum")
		expect(instance.attributes.loaded).to.equal(false)
	end)

	it("accepts a valid authored pickup definition", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo", { quality = "map-authored" }, 3)

		expect(instance.itemId).to.equal("handgun_ammo")
		expect(instance.quantity).to.equal(3)
		expect(instance.attributes.quality).to.equal("map-authored")
	end)

	it("creates a positive stack quantity for stackable items", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo", nil, 24)

		expect(instance.quantity).to.equal(24)
	end)

	it("defaults stackable instances to a positive quantity", function()
		local factory = newFactory()
		local instance = factory:create("handgun_ammo")

		expect(instance.quantity).to.equal(1)
	end)

	it("rejects non-finite numeric attributes", function()
		local factory = newFactory()
		for _, value in { math.huge, -math.huge, 0 / 0 } do
			assertRejected(expect, function(): any
				return factory:create("handgun", { damage = value })
			end)
		end
	end)

	it("rejects unknown item ids", function()
		local factory = newFactory()
		assertRejected(expect, function(): any
			return factory:create("unknown-item")
		end)
	end)

	it("rejects quantity for non-stackable items", function()
		local factory = newFactory()
		assertRejected(expect, function(): any
			return factory:create("handgun", nil, 2)
		end)
	end)

	it("rejects non-positive quantity", function()
		local factory = newFactory()
		assertRejected(expect, function(): any
			return factory:create("handgun_ammo", nil, 0)
		end)
	end)

	it("returns independent attribute tables", function()
		local factory = newFactory()
		local first = factory:create("iron_key", { label = "old" })
		local second = factory:create("iron_key", { label = "new" })

		first.attributes.label = "changed"
		expect(second.attributes.label).to.equal("new")
		expect(first.attributes == second.attributes).to.equal(false)
	end)
end)
end
