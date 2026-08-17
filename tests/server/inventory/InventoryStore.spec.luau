--!strict

local harness = require("../../support/harness")
local loader = require("../../support/roblox-loader")
local InventoryStore = loader.load("src/server/inventory/InventoryStore.luau")
local items = loader.load("src/shared/inventory/items.luau")

harness.describe("InventoryStore", function()
	harness.it("creates an empty version two inventory", function()
		local state = InventoryStore.defaultInventory()
		harness.assert.equal(state.version, 2)
		harness.assert.equal(#state.items, 0)
		harness.assert.equal(next(state.equipped), nil)
	end)

	harness.it("adds an individual instance without mutating the source", function()
		local original = InventoryStore.defaultInventory()
		local updated = InventoryStore.addInstance(original, { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		harness.assert.falsy(updated == original)
		harness.assert.falsy(updated.items == original.items)
		harness.assert.equal(updated.items[1].uid, "handgun-001")
		harness.assert.equal(updated.items[1].attributes.loadedAmmo, 5)
		harness.assert.equal(#original.items, 0)
	end)

	harness.it("finds an instance by uid", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		harness.assert.equal(InventoryStore.findInstance(state, "handgun-001").itemId, "handgun")
		harness.assert.isNil(InventoryStore.findInstance(state, "missing"))
	end)

	harness.it("copies attributes and equipped entries deeply", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		state = InventoryStore.equip(state, "weapon", "handgun-001")
		local copied = InventoryStore.copyState(state)
		copied.items[1].attributes.loadedAmmo = 0
		copied.equipped.weapon = "changed"
		harness.assert.equal(state.items[1].attributes.loadedAmmo, 5)
		harness.assert.equal(state.equipped.weapon, "handgun-001")
	end)

	harness.it("removes only the requested instance", function()
		local first = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "first", itemId = "handgun" })
		local original = InventoryStore.addInstance(first, { uid = "second", itemId = "medkit" })
		local updated = InventoryStore.removeInstance(original, "first")
		harness.assert.equal(#updated.items, 1)
		harness.assert.equal(updated.items[1].uid, "second")
		harness.assert.equal(#original.items, 2)
	end)

	harness.it("updates instance attributes without sharing tables", function()
		local original = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		local attributes = { damage = 18, loadedAmmo = 5 }
		local updated = InventoryStore.updateAttributes(original, "handgun-001", attributes)
		attributes.damage = 99
		harness.assert.equal(updated.items[1].attributes.damage, 18)
		harness.assert.isNil(original.items[1].attributes)
		harness.assert.falsy(updated.items[1].attributes == attributes)
	end)

	harness.it("equips a known uid in a slot", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun" })
		local updated = InventoryStore.equip(state, "weapon", "handgun-001")
		harness.assert.equal(updated.equipped.weapon, "handgun-001")
		harness.assert.isNil(state.equipped.weapon)
	end)

	harness.it("rejects an unknown equipped uid", function()
		harness.assert.isNil(InventoryStore.equip(InventoryStore.defaultInventory(), "weapon", "missing"))
	end)

	harness.it("adds quantity to an existing compatible stack", function()
		local original = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		local updated = InventoryStore.addQuantity(original, "handgun_ammo", 8)
		harness.assert.equal(updated.items[1].quantity, 20)
		harness.assert.equal(original.items[1].quantity, 12)
	end)

	harness.it("creates a new stack when no compatible stack exists", function()
		local state = InventoryStore.defaultInventory()
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 8, "ammo-001")
		harness.assert.equal(updated.items[1].uid, "ammo-001")
		harness.assert.equal(updated.items[1].quantity, 8)
	end)

	harness.it("rejects negative and zero quantities", function()
		local state = InventoryStore.defaultInventory()
		harness.assert.isNil(InventoryStore.addQuantity(state, "handgun_ammo", 0))
		harness.assert.isNil(InventoryStore.addQuantity(state, "handgun_ammo", -1))
	end)

	harness.it("rejects non-finite quantities", function()
		local state = InventoryStore.defaultInventory()
		for _, quantity in { math.huge, -math.huge, 0 / 0 } do
			harness.assert.isNil(InventoryStore.addQuantity(state, "handgun_ammo", quantity))
			harness.assert.isNil(InventoryStore.removeQuantity(state, "missing", quantity))
		end
		local instance = InventoryStore.addInstance(state, { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1 })
		harness.assert.isNil(InventoryStore.addInstance(instance, { uid = "ammo-002", itemId = "handgun_ammo", quantity = math.huge }))
	end)

	harness.it("rejects stack quantity overflow", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 1e308 })
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 1e308)
		harness.assert.isNil(updated)
		harness.assert.equal(state.items[1].quantity, 1e308)
	end)

	harness.it("removes a stack when its quantity reaches zero", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		local updated = InventoryStore.removeQuantity(state, "ammo-001", 12)
		harness.assert.equal(#updated.items, 0)
		harness.assert.equal(#state.items, 1)
	end)

	harness.it("rejects quantity greater than the stack", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 12 })
		harness.assert.isNil(InventoryStore.removeQuantity(state, "ammo-001", 13))
		harness.assert.equal(state.items[1].quantity, 12)
	end)

	harness.it("rejects attribute updates for an unknown uid", function()
		harness.assert.isNil(InventoryStore.updateAttributes(InventoryStore.defaultInventory(), "missing", { damage = 1 }))
	end)

	harness.it("rejects equip requests with invalid state without throwing", function()
		local ok, result = pcall(function()
			return InventoryStore.equip({ version = 2, items = "invalid", equipped = {} }, "weapon", "missing")
		end)
		harness.assert.truthy(ok)
		harness.assert.isNil(result)
	end)

	harness.it("does not merge individual instances", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" })
		harness.assert.isNil(InventoryStore.addQuantity(state, "iron_key", 1))
	end)

	harness.it("does not merge stacks with different authored attributes", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "ammo-001", itemId = "handgun_ammo", quantity = 3, attributes = { quality = "old" } })
		local updated = InventoryStore.addQuantity(state, "handgun_ammo", 2, "ammo-002")
		harness.assert.equal(#updated.items, 2)
		harness.assert.equal(updated.items[1].quantity, 3)
	end)

	harness.it("preserves weapon loadedAmmo during an unrelated mutation", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5 } })
		local updated = InventoryStore.addInstance(state, { uid = "medkit-001", itemId = "medkit" })
		harness.assert.equal(updated.items[1].attributes.loadedAmmo, 5)
	end)

	harness.it("serializes schema two with deterministic keys", function()
		local state = { version = 2, items = {
			{ uid = "handgun-001", itemId = "handgun", attributes = { loadedAmmo = 5, damage = 18 } },
			{ uid = "ammo-001", itemId = "handgun_ammo", quantity = 24 },
		}, equipped = { z = "handgun-001", weapon = "handgun-001" } }
		harness.assert.equal(InventoryStore.serialize(state), '{"version":2,"items":[{"attributes":{"damage":18,"loadedAmmo":5},"itemId":"handgun","uid":"handgun-001"},{"itemId":"handgun_ammo","quantity":24,"uid":"ammo-001"}],"equipped":{"weapon":"handgun-001","z":"handgun-001"}}')
	end)

	harness.it("round-trips string number and boolean attributes", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { label = "old", used = false, strength = 2 } })
		local decoded = InventoryStore.deserialize(InventoryStore.serialize(state))
		harness.assert.equal(decoded.items[1].attributes.label, "old")
		harness.assert.equal(decoded.items[1].attributes.used, false)
		harness.assert.equal(decoded.items[1].attributes.strength, 2)
	end)

	harness.it("round-trips Unicode escapes produced for control characters", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { label = "a\1\31z" } })
		local serialized = InventoryStore.serialize(state)
		local decoded = InventoryStore.deserialize(serialized)
		harness.assert.equal(decoded.items[1].attributes.label, "a\1\31z")
		harness.assert.truthy(string.find(serialized, "\\u0001", 1, true) ~= nil)
	end)

	harness.it("round-trips valid surrogate pairs", function()
		local decoded = InventoryStore.deserialize('{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uD83D\\uDE00"}}],"equipped":{}}')
		harness.assert.equal(decoded.items[1].attributes.label, "\240\159\152\128")
	end)

	harness.it("rejects isolated Unicode surrogates", function()
		local invalid = {
			'{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uD83D"}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"key-001","itemId":"iron_key","attributes":{"label":"\\uDE00"}}],"equipped":{}}',
		}
		for _, serialized in invalid do
			harness.assert.isNil(InventoryStore.deserialize(serialized))
		end
	end)

	harness.it("rejects invalid JSON numbers", function()
		local invalid = {
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"}],"equipped":{},"extra":+1}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":01}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":1.}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"damage":1e999}}],"equipped":{}}',
		}
		for _, serialized in invalid do
			harness.assert.isNil(InventoryStore.deserialize(serialized))
		end
	end)

	harness.it("rejects JSON vertical tab and form feed whitespace", function()
		for _, invalidWhitespace in { string.char(11), string.char(12) } do
			local serialized = '{"version":2,' .. invalidWhitespace .. '"items":[],"equipped":{}}'
			harness.assert.isNil(InventoryStore.deserialize(serialized))
		end
	end)

	harness.it("rejects non-contiguous item arrays and malformed attributes", function()
		local malformed = {
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"nested":{}}}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","attributes":{"list":[]}}],"equipped":{}}',
		}
		for _, serialized in malformed do
			harness.assert.isNil(InventoryStore.deserialize(serialized))
		end
		local state = InventoryStore.defaultInventory()
		state.items[2] = { uid = "x", itemId = "handgun" }
		local ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		harness.assert.falsy(ok)
		state = InventoryStore.defaultInventory()
		state.items[0] = { uid = "x", itemId = "handgun" }
		ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		harness.assert.falsy(ok)
	end)

	harness.it("serializes item order by numeric index", function()
		local state = InventoryStore.defaultInventory()
		state.items[1] = { uid = "first", itemId = "handgun" }
		state.items[2] = { uid = "second", itemId = "medkit" }
		harness.assert.equal(InventoryStore.serialize(state), '{"version":2,"items":[{"itemId":"handgun","uid":"first"},{"itemId":"medkit","uid":"second"}],"equipped":{}}')
	end)

	harness.it("rejects non-finite attribute numbers", function()
		local state = InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key", attributes = { damage = math.huge } })
		local ok = pcall(function()
			InventoryStore.serialize(state)
		end)
		harness.assert.falsy(ok)
	end)

	harness.it("rejects missing uid duplicate uid unknown item invalid quantity and missing equipped instances", function()
		local invalid = {
			'{"version":2,"items":[{"itemId":"handgun"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"},{"uid":"x","itemId":"medkit"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"unknown"}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun","quantity":2}],"equipped":{}}',
			'{"version":2,"items":[{"uid":"x","itemId":"handgun"}],"equipped":{"weapon":"missing"}}',
		}
		for _, serialized in invalid do
			harness.assert.isNil(InventoryStore.deserialize(serialized))
		end
	end)

	harness.it("uses the equip capability from the shared catalog", function()
		harness.assert.truthy(items.handgun.capabilities[1] ~= nil)
		harness.assert.isNil(InventoryStore.equip(InventoryStore.addInstance(InventoryStore.defaultInventory(), { uid = "key-001", itemId = "iron_key" }), "weapon", "key-001"))
	end)
end)
