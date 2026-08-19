--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryStore = require(ServerScriptService.Server.inventory.InventoryStore)
local items = require(ReplicatedStorage.Shared.inventory.items)

type Attribute = items.ItemAttribute
type Instance = items.ItemInstance
type State = items.InventoryState

return function()
	describe("InventoryStore", function()
	it("creates an empty version two inventory", function()
		local state = InventoryStore.defaultInventory()
		expect(state.version).to.equal(2)
		expect(#state.items).to.equal(0)
		expect((next(state.equipped))).to.equal(nil)
	end)

	it("adds an individual instance without mutating the source", function()
		local original = InventoryStore.defaultInventory()
		local updated: State = InventoryStore.addInstance(original, { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } } :: any) :: State
		expect(updated == original).to.equal(false)
		expect(updated.items == original.items).to.equal(false)
		expect(updated.items[1].uid).to.equal("handgun-001")
		expect(assert(updated.items[1].attributes).loadedAmmo).to.equal(5)
		expect(#original.items).to.equal(0)
	end)

	it("finds an instance by uid", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" } :: any) :: State
		expect(assert(InventoryStore.findInstance(state, "handgun-001")).itemId).to.equal("handgun")
		expect(InventoryStore.findInstance(state, "missing")).to.equal(nil)
	end)

	it("copies attributes and equipped entries deeply", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } } :: any) :: State
		state = InventoryStore.equip(state, "weapon", "handgun-001") :: State
		local copied = InventoryStore.copyState(state)
		assert(copied.items[1].attributes).loadedAmmo = 0
		copied.equipped.weapon = "changed"
		expect(assert(state.items[1].attributes).loadedAmmo).to.equal(5)
		expect(state.equipped.weapon).to.equal("handgun-001")
	end)

	it("removes only the requested instance", function()
		local first: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "first", itemId = "handgun" } :: any) :: State
		local original: State = InventoryStore.addInstance(first, { uid = "second", itemId = "medkit" } :: any) :: State
		local updated: State = InventoryStore.removeInstance(original, "first") :: State
		expect(#updated.items).to.equal(1)
		expect(updated.items[1].uid).to.equal("second")
		expect(#original.items).to.equal(2)
	end)

	it("updates instance attributes without sharing tables", function()
		local original: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" } :: any) :: State
		local attributes: { [string]: Attribute } = { damage = 18, loadedAmmo = 5 }
		local updated: State = InventoryStore.updateAttributes(original, "handgun-001", attributes) :: State
		attributes.damage = 99
		expect(assert(updated.items[1].attributes).damage).to.equal(18)
		expect(original.items[1].attributes).to.equal(nil)
		expect(updated.items[1].attributes == attributes).to.equal(false)
	end)

	it("equips a known uid in a slot", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" } :: any) :: State
		local updated: State = InventoryStore.equip(state, "weapon", "handgun-001") :: State
		expect(updated.equipped.weapon).to.equal("handgun-001")
		expect(state.equipped.weapon).to.equal(nil)
	end)

	it("rejects an unknown equipped uid", function()
		expect(InventoryStore.equip(InventoryStore.defaultInventory(), "weapon", "missing")).to.equal(nil)
	end)

	it("adds quantity to an existing compatible stack", function()
		local original: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 } :: any) :: State
		local updated: State = InventoryStore.addQuantity(original, "handgun_ammo", 8) :: State
		expect(updated.items[1].quantity).to.equal(20)
		expect(original.items[1].quantity).to.equal(12)
	end)

	it("creates a new stack when no compatible stack exists", function()
		local state = InventoryStore.defaultInventory()
		local updated: State = InventoryStore.addQuantity(state, "handgun_ammo", 8, "ammo-001") :: State
		expect(updated.items[1].uid).to.equal("ammo-001")
		expect(updated.items[1].quantity).to.equal(8)
	end)

	it("rejects negative and zero quantities", function()
		local state = InventoryStore.defaultInventory()
		expect(InventoryStore.addQuantity(state, "handgun_ammo", 0)).to.equal(nil)
		expect(InventoryStore.addQuantity(state, "handgun_ammo", -1)).to.equal(nil)
	end)

	it("rejects non-finite quantities", function()
		local state = InventoryStore.defaultInventory()
		for _, quantity in { math.huge, -math.huge, 0 / 0 } do
			expect(InventoryStore.addQuantity(state, "handgun_ammo", quantity)).to.equal(nil)
			expect(InventoryStore.removeQuantity(state, "missing", quantity)).to.equal(nil)
		end
		local instance: State = InventoryStore.addInstance(state, { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1 } :: any) :: State
		expect(InventoryStore.addInstance(instance, { uid = "ammo-002", itemId = "handgun_ammo", quantity = math.huge } :: any)).to.equal(nil)
	end)

	it("rejects stack quantity overflow", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1e308 } :: any) :: State
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 1e308)
		expect(updated).to.equal(nil)
		expect(state.items[1].quantity).to.equal(1e308)
	end)

	it("removes a stack when its quantity reaches zero", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 } :: any) :: State
		local updated: State = InventoryStore.removeQuantity(state, "ammo-001", 12) :: State
		expect(#updated.items).to.equal(0)
		expect(#state.items).to.equal(1)
	end)

	it("rejects quantity greater than the stack", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 } :: any) :: State
		expect(InventoryStore.removeQuantity(state, "ammo-001", 13)).to.equal(nil)
		expect(state.items[1].quantity).to.equal(12)
	end)

	it("rejects attribute updates for an unknown uid", function()
		expect(InventoryStore.updateAttributes(InventoryStore.defaultInventory(), "missing", { damage = 1 })).to.equal(nil)
	end)

	it("rejects equip requests with invalid state without throwing", function()
		local ok, result = pcall(function()
			return InventoryStore.equip(({ version = 2, items = "invalid", equipped = {} } :: any), "weapon", "missing")
		end)
		expect(ok).to.equal(true)
		expect(result).to.equal(nil)
	end)

	it("does not merge individual instances", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" } :: any) :: State
		expect(InventoryStore.addQuantity(state, "iron_key", 1)).to.equal(nil)
	end)

	it("does not merge stacks with different authored attributes", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 3, attributes = { quality = "old" } } :: any) :: State
		local updated: State = InventoryStore.addQuantity(state, "handgun_ammo", 2, "ammo-002") :: State
		expect(#updated.items).to.equal(2)
		expect(updated.items[1].quantity).to.equal(3)
	end)

	it("preserves weapon loadedAmmo during an unrelated mutation", function()
		local state: State = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } } :: any) :: State
		local updated: State = InventoryStore.addInstance(state, { uid = "medkit-001", itemId = "medkit" } :: any) :: State
		expect(assert(updated.items[1].attributes).loadedAmmo).to.equal(5)
	end)

	it("does not expose persistence serialization", function()
		local store = InventoryStore :: any
		expect(store.serialize).to.equal(nil)
		expect(store.deserialize).to.equal(nil)
	end)

	it("uses the equip capability from the shared catalog", function()
		expect(items.handgun.capabilities[1] ~= nil).to.equal(true)
		expect(InventoryStore.equip((InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" } :: any) :: State), "weapon", "key-001")).to.equal(nil)
	end)
end)
end
