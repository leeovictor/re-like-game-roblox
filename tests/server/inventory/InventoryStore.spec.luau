--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryStore = require(ServerScriptService.Server.inventory.InventoryStore)
local items = require(ReplicatedStorage.Shared.inventory.items)

type Attribute = string | number | boolean
type Instance = {
	uid: string,
	itemId: string,
	quantity: number?,
	attributes: { [string]: Attribute }?,
}
type State = {
	version: number,
	items: { Instance },
	equipped: { [string]: string },
}

return function()
	describe("InventoryStore", function()
	it("creates an empty version two inventory", function()
		local state = InventoryStore.defaultInventory()
		expect(state.version).to.equal(2)
		expect(#state.items).to.equal(0)
		expect(next(state.equipped)).to.equal(nil)
	end)

	it("adds an individual instance without mutating the source", function()
		local original = InventoryStore.defaultInventory()
		local updated = InventoryStore.addInstance(original, { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		expect(updated == original).to.equal(false)
		expect(updated.items == original.items).to.equal(false)
		expect(updated.items[1].uid).to.equal("handgun-001")
		expect(updated.items[1].attributes.loadedAmmo).to.equal(5)
		expect(#original.items).to.equal(0)
	end)

	it("finds an instance by uid", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		expect(InventoryStore.findInstance(state, "handgun-001").itemId).to.equal("handgun")
		expect(InventoryStore.findInstance(state, "missing")).to.equal(nil)
	end)

	it("copies attributes and equipped entries deeply", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		state = InventoryStore.equip(state, "weapon", "handgun-001")
		local copied = InventoryStore.copyState(state)
		copied.items[1].attributes.loadedAmmo = 0
		copied.equipped.weapon = "changed"
		expect(state.items[1].attributes.loadedAmmo).to.equal(5)
		expect(state.equipped.weapon).to.equal("handgun-001")
	end)

	it("removes only the requested instance", function()
		local first = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "first", itemId = "handgun" })
		local original = InventoryStore.addInstance(first, { uid = "second", itemId = "medkit" })
		local updated = InventoryStore.removeInstance(original, "first")
		expect(#updated.items).to.equal(1)
		expect(updated.items[1].uid).to.equal("second")
		expect(#original.items).to.equal(2)
	end)

	it("updates instance attributes without sharing tables", function()
		local original = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		local attributes = { damage = 18, loadedAmmo = 5 }
		local updated = InventoryStore.updateAttributes(original, "handgun-001", attributes)
		attributes.damage = 99
		expect(updated.items[1].attributes.damage).to.equal(18)
		expect(original.items[1].attributes).to.equal(nil)
		expect(updated.items[1].attributes == attributes).to.equal(false)
	end)

	it("equips a known uid in a slot", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		local updated = InventoryStore.equip(state, "weapon", "handgun-001")
		expect(updated.equipped.weapon).to.equal("handgun-001")
		expect(state.equipped.weapon).to.equal(nil)
	end)

	it("rejects an unknown equipped uid", function()
		expect(InventoryStore.equip(InventoryStore.defaultInventory(), "weapon", "missing")).to.equal(nil)
	end)

	it("adds quantity to an existing compatible stack", function()
		local original = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		local updated = InventoryStore.addQuantity(original, "handgun_ammo", 8)
		expect(updated.items[1].quantity).to.equal(20)
		expect(original.items[1].quantity).to.equal(12)
	end)

	it("creates a new stack when no compatible stack exists", function()
		local state = InventoryStore.defaultInventory()
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 8, "ammo-001")
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
		local instance = InventoryStore.addInstance(state, { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1 })
		expect(InventoryStore.addInstance(instance, { uid = "ammo-002", itemId = "handgun_ammo", quantity = math.huge })).to.equal(nil)
	end)

	it("rejects stack quantity overflow", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1e308 })
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 1e308)
		expect(updated).to.equal(nil)
		expect(state.items[1].quantity).to.equal(1e308)
	end)

	it("removes a stack when its quantity reaches zero", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		local updated = InventoryStore.removeQuantity(state, "ammo-001", 12)
		expect(#updated.items).to.equal(0)
		expect(#state.items).to.equal(1)
	end)

	it("rejects quantity greater than the stack", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		expect(InventoryStore.removeQuantity(state, "ammo-001", 13)).to.equal(nil)
		expect(state.items[1].quantity).to.equal(12)
	end)

	it("rejects attribute updates for an unknown uid", function()
		expect(InventoryStore.updateAttributes(InventoryStore.defaultInventory(), "missing", { damage = 1 })).to.equal(nil)
	end)

	it("rejects equip requests with invalid state without throwing", function()
		local ok, result = pcall(function()
			return InventoryStore.equip({ version = 2, items = "invalid", equipped = {} }, "weapon", "missing")
		end)
		expect(ok).to.equal(true)
		expect(result).to.equal(nil)
	end)

	it("does not merge individual instances", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" })
		expect(InventoryStore.addQuantity(state, "iron_key", 1)).to.equal(nil)
	end)

	it("does not merge stacks with different authored attributes", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 3, attributes = { quality = "old" } })
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 2, "ammo-002")
		expect(#updated.items).to.equal(2)
		expect(updated.items[1].quantity).to.equal(3)
	end)

	it("preserves weapon loadedAmmo during an unrelated mutation", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		local updated = InventoryStore.addInstance(state, { uid = "medkit-001", itemId = "medkit" })
		expect(updated.items[1].attributes.loadedAmmo).to.equal(5)
	end)

	it("serializes schema two with deterministic keys", function()
		local state: State = { version = 2, items = {
			{ uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5, damage = 18 } :: { [string]: Attribute } },
			{ uid = "ammo-001", itemId = "handgun_ammo", quantity = 24, attributes = nil },
		}, equipped = { z = "handgun-001", weapon = "handgun-001" } }
		expect(InventoryStore.serialize(state)).to.equal('{"version":2,"items":[{"attributes":{"damage":18,"loadedAmmo":5},"itemId":"handgun","uid":"handgun-001"},{"itemId":"handgun_ammo","quantity":24,"uid":"ammo-001"}],"equipped":{"weapon":"handgun-001","z":"handgun-001"}}')
	end)

	it("round-trips string number and boolean attributes", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { label = "old", used = false, strength = 2 } })
		local decoded = InventoryStore.deserialize(InventoryStore.serialize(state))
		expect(decoded.items[1].attributes.label).to.equal("old")
		expect(decoded.items[1].attributes.used).to.equal(false)
		expect(decoded.items[1].attributes.strength).to.equal(2)
	end)

	it("round-trips Unicode escapes produced for control characters", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { label = "a\1\31z" } })
		local serialized = InventoryStore.serialize(state)
		local decoded = InventoryStore.deserialize(serialized)
		expect(decoded.items[1].attributes.label).to.equal("a\1\31z")
		expect(string.find(serialized, "\\u0001", 1, true) ~= nil).to.equal(true)
	end)

	it("round-trips valid surrogate pairs", function()
		local decoded = InventoryStore.deserialize('{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uD83D\\uDE00"}}],"equipped":{}}')
		expect(decoded.items[1].attributes.label).to.equal("\240\159\152\128")
	end)

	it("rejects isolated Unicode surrogates", function()
		local invalid = {
			'{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uD83D"}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uDE00"}}],"equipped":{}}',
		}
		for _, serialized in invalid do
			expect(InventoryStore.deserialize(serialized)).to.equal(nil)
		end
	end)

	it("rejects invalid JSON numbers", function()
		local invalid = {
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"}],"equipped":{},"extra":+1}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":01}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":1.}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":1e999}}],"equipped":{}}',
		}
		for _, serialized in invalid do
			expect(InventoryStore.deserialize(serialized)).to.equal(nil)
		end
	end)

	it("rejects JSON vertical tab and form feed whitespace", function()
		for _, invalidWhitespace in { string.char(11), string.char(12) } do
			local serialized = '{"version":2,' .. invalidWhitespace .. '"items":[],"equipped":{}}'
			expect(InventoryStore.deserialize(serialized)).to.equal(nil)
		end
	end)

	it("rejects non-contiguous item arrays and malformed attributes", function()
		local malformed = {
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"nested":{}}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"list":[]}}],"equipped":{}}',
		}
		for _, serialized in malformed do
			expect(InventoryStore.deserialize(serialized)).to.equal(nil)
		end
		local state = InventoryStore.defaultInventory()
		state.items[2] = { uid = "x", itemId = "handgun", attributes = nil }
		local ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		expect(ok).to.equal(false)
		state = InventoryStore.defaultInventory()
		state.items[0] = { uid = "x", itemId = "handgun", attributes = nil }
		ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		expect(ok).to.equal(false)
	end)

	it("serializes item order by numeric index", function()
		local state = InventoryStore.defaultInventory()
		state.items[1] = { uid = "first", itemId = "handgun", attributes = nil }
		state.items[2] = { uid = "second", itemId = "medkit", attributes = nil }
		expect(InventoryStore.serialize(state)).to.equal('{"version":2,"items":[{"itemId":"handgun","uid":"first"},{"itemId":"medkit","uid":"second"}],"equipped":{}}')
	end)

	it("rejects non-finite attribute numbers", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { damage = math.huge } })
		local ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		expect(ok).to.equal(false)
	end)

	it("rejects missing uid duplicate uid unknown item invalid quantity and missing equipped instances", function()
		local invalid = {
			'{"version":2,"items":[{"itemId":"handgun"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"},{"uid":"x","itemId":"medkit"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"unknown"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","quantity":2}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"}],"equipped":{"weapon":"missing"}}',
		}
		for _, serialized in invalid do
			expect(InventoryStore.deserialize(serialized)).to.equal(nil)
		end
	end)

	it("uses the equip capability from the shared catalog", function()
		expect(items.handgun.capabilities[1] ~= nil).to.equal(true)
		expect(InventoryStore.equip(InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" }), "weapon", "key-001")).to.equal(nil)
	end)
end)
end
