--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local items = require(ReplicatedStorage.Shared.inventory.items)

type ItemAttribute = string | number | boolean
type ItemInstance = {
	uid: string,
	itemId: string,
	quantity: number?,
	attributes: { [string]: ItemAttribute }?,
}
type InventoryState = {
	version: number,
	items: { ItemInstance },
	equipped: { [string]: string },
}

local function hasCapability(capabilities: { string }, expected: string): boolean
	for _, capability in capabilities do
		if capability == expected then
			return true
		end
	end
	return false
end

return function()
	describe("Shared inventory items", function()
		it("constructs the version two instance schema", function()
			local state: InventoryState = {
				version = 2,
				items = {
					{
						uid = "handgun-001",
						itemId = "handgun",
						attributes = { damage = 18, loadedAmmo = 5 } :: { [string]: ItemAttribute },
					},
					{
						uid = "ammo-001",
						itemId = "handgun_ammo",
						quantity = 24,
					},
				},
				equipped = { weapon = "handgun-001" },
			}

			expect(state.version).to.equal(2)
			expect(state.items[1].uid).to.equal("handgun-001")
			local attributes = assert(state.items[1].attributes, "handgun attributes")
			expect(attributes.damage).to.equal(18)
			local quantity = assert(state.items[2].quantity, "ammo quantity")
			expect(quantity).to.equal(24)
			expect(state.equipped.weapon).to.equal("handgun-001")
		end)

		it("exposes static catalog capabilities", function()
			expect(hasCapability(items.medkit.capabilities, "heal")).to.be.ok()
			expect(hasCapability(items.handgun.capabilities, "equip")).to.be.ok()
			expect(hasCapability(items.handgun_ammo.capabilities, "reload-ammo")).to.be.ok()
			expect(hasCapability(items.access_card.capabilities, "unlock")).to.be.ok()
		end)
	end)
end
