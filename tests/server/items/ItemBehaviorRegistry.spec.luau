--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local ItemBehaviorRegistry = require(ServerScriptService.Server.items.ItemBehaviorRegistry)

type TestAttributes = { [string]: string | number | boolean }
type TestInstance = {
	uid: string,
	itemId: string,
	quantity: number?,
	attributes: TestAttributes?,
}
type TestContext = { target: string }
type TestBehaviorResult = {
	success: boolean,
	reason: string?,
	consumeInstance: boolean?,
	effect: TestAttributes?,
}
type TestBehavior = {
	canUse: (player: any, instance: TestInstance, context: TestContext) -> (boolean, string?),
	use: (player: any, instance: TestInstance, context: TestContext) -> TestBehaviorResult,
}

local function newFakeBehavior(): TestBehavior
	return {
		canUse = function(_player: any, _instance: TestInstance, context: TestContext): (boolean, string?)
			if context.target ~= "self" then
				return false, "not_compatible"
			end
			return true, nil
		end,
		use = function(_player: any, _instance: TestInstance, context: TestContext): TestBehaviorResult
			if context.target ~= "self" then
				return {
					success = false,
					reason = "not_compatible",
				}
			end
			local effect: TestAttributes = { amount = 25 }
			return {
				success = true,
				consumeInstance = true,
				effect = effect,
			}
		end,
	}
end

return function()
	describe("Item behavior registry", function()
	it("registers and retrieves a behavior", function()
		local registry = ItemBehaviorRegistry.new()
		local behavior = newFakeBehavior()

		expect(registry:register("healing", behavior :: any)).to.equal(true)
		expect(registry:get("healing")).to.equal(behavior)
	end)

	it("rejects an empty capability", function()
		local registry = ItemBehaviorRegistry.new()

		expect(registry:register("", newFakeBehavior() :: any)).to.equal(false)
	end)

	it("rejects duplicate registration", function()
		local registry = ItemBehaviorRegistry.new()

		expect(registry:register("healing", newFakeBehavior() :: any)).to.equal(true)
		expect(registry:register("healing", newFakeBehavior() :: any)).to.equal(false)
	end)

	it("returns nil for an unknown capability", function()
		local registry = ItemBehaviorRegistry.new()

		expect(registry:get("unknown")).to.equal(nil)
	end)

	it("keeps behavior identity without mutating it", function()
		local registry = ItemBehaviorRegistry.new()
		local behavior = newFakeBehavior()

		registry:register("healing", behavior :: any)

		expect(registry:get("healing")).to.equal(behavior)
		expect((
			behavior.canUse(nil, { uid = "test", itemId = "medkit" }, { target = "other" })
		)).to.equal(false)
		local result = behavior.use(nil, { uid = "test", itemId = "medkit" }, { target = "self" })
		expect(result.effect).to.be.ok()
		if result.effect ~= nil then
			expect(result.effect.amount).to.equal(25)
		end
	end)
end)
end
