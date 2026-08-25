--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)

local function newFactory(): any
	return ItemInstanceFactory.new()
end

local function assertRejected(assert: any, callback: () -> any): ()
	local ok, result = pcall(callback)
	assert(ok).to.equal(true)
	assert(result).to.equal(nil)
end

return function()
	describe("Item instance factory", function()
	it("creates a unique individual instance", function()
		local factory = newFactory()
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		expect(type(first.uid)).to.equal("string")
		expect(first.uid ~= "").to.equal(true)
		expect(first.uid ~= second.uid).to.equal(true)
		expect(first.itemId).to.equal("handgun")
		expect(first.quantity).to.equal(nil)
		expect(first == second).to.equal(false)
	end)

	it("generates unique uids for each instance", function()
		local factory = newFactory()
		local first = factory:create("handgun")
		local second = factory:create("handgun")

		expect(first.uid ~= second.uid).to.equal(true)
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
		local first = factory:create("access_card", { label = "old" })
		local second = factory:create("access_card", { label = "new" })

		first.attributes.label = "changed"
		expect(second.attributes.label).to.equal("new")
		expect(first.attributes == second.attributes).to.equal(false)
	end)
end)
end
