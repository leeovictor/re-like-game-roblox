--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local ItemBehaviorRegistry = loader.load("src/server/items/ItemBehaviorRegistry.luau")

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

harness.describe("Item behavior registry", function()
	harness.it("registers and retrieves a behavior", function()
		local registry = ItemBehaviorRegistry.new()
		local behavior = newFakeBehavior()

		harness.assert.truthy(registry:register("healing", behavior))
		harness.assert.equal(registry:get("healing"), behavior)
	end)

	harness.it("rejects an empty capability", function()
		local registry = ItemBehaviorRegistry.new()

		harness.assert.falsy(registry:register("", newFakeBehavior()))
	end)

	harness.it("rejects duplicate registration", function()
		local registry = ItemBehaviorRegistry.new()

		harness.assert.truthy(registry:register("healing", newFakeBehavior()))
		harness.assert.falsy(registry:register("healing", newFakeBehavior()))
	end)

	harness.it("returns nil for an unknown capability", function()
		local registry = ItemBehaviorRegistry.new()

		harness.assert.isNil(registry:get("unknown"))
	end)

	harness.it("keeps behavior identity without mutating it", function()
		local registry = ItemBehaviorRegistry.new()
		local behavior = newFakeBehavior()

		registry:register("healing", behavior)

		harness.assert.equal(registry:get("healing"), behavior)
		harness.assert.equal(
			behavior.canUse(nil, { uid = "test", itemId = "medkit" }, { target = "other" }),
			false,
			"fake behavior remains unchanged"
		)
		local result = behavior.use(nil, { uid = "test", itemId = "medkit" }, { target = "self" })
		harness.assert.truthy(result.effect)
		if result.effect ~= nil then
			harness.assert.equal(result.effect.amount, 25)
		end
	end)
end)
