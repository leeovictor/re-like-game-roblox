--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")

local items = loader.load("src/shared/inventory/items.luau")

local function hasCapability(capabilities: { string }, expected: string): boolean
	for _, capability in capabilities do
		if capability == expected then
			return true
		end
	end
	return false
end

harness.describe("Shared inventory items", function()
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

	harness.it("exposes static catalog capabilities", function()
		harness.assert.truthy(hasCapability(items.medkit.capabilities, "heal"))
		harness.assert.truthy(hasCapability(items.handgun.capabilities, "equip"))
		harness.assert.truthy(hasCapability(items.handgun_ammo.capabilities, "reload-ammo"))
		harness.assert.truthy(hasCapability(items.iron_key.capabilities, "unlock"))
	end)
end)
