--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local ItemBehaviorRegistry = require(ServerScriptService.Server.items.ItemBehaviorRegistry)
local ItemUseService = require(ServerScriptService.Server.items.ItemUseService)

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
type Player = { UserId: number, Name: string }
type Request = { capability: string, context: { [string]: Attribute }, itemUid: string? }
type Result = {
	success: boolean,
	reason: string?,
	itemUid: string?,
	consumed: boolean?,
	effect: { [string]: Attribute }?,
}

type BehaviorResult = {
	success: boolean,
	reason: string?,
	consumeInstance: boolean?,
	consumeQuantity: number?,
	updateAttributes: { [string]: Attribute }?,
	equipSlot: string?,
	effect: { [string]: Attribute }?,
}

type Behavior = {
	canUse: (player: any, instance: Instance, context: { [string]: Attribute }) -> (boolean, string?),
	use: (player: any, instance: Instance, context: { [string]: Attribute }) -> BehaviorResult,
}

type FakeInventory = {
	states: { [Player]: State },
	removedInstances: number,
	removedQuantities: number,
	updatedAttributes: number,
	equipped: number,
	failApply: boolean,
	failEquip: boolean,
	applyUseMutations: (self: FakeInventory, player: Player, uid: string, mutations: { [string]: any }) -> boolean,
	find: (self: FakeInventory, player: Player, uid: string) -> Instance?,
	getSnapshot: (self: FakeInventory, player: Player) -> State?,
	removeInstance: (self: FakeInventory, player: Player, uid: string) -> boolean,
	removeQuantity: (self: FakeInventory, player: Player, uid: string, quantity: number) -> boolean,
	updateAttributes: (self: FakeInventory, player: Player, uid: string, attributes: { [string]: Attribute }) -> boolean,
	equip: (self: FakeInventory, player: Player, slot: string, uid: string) -> boolean,
}

local function copyInstance(instance: Instance): Instance
	return {
		uid = instance.uid,
		itemId = instance.itemId,
		quantity = instance.quantity,
		attributes = if instance.attributes == nil then nil else table.clone(instance.attributes),
	}
end

local function newFakeInventory(items: { Instance }): (FakeInventory, Player)
	local player = { UserId = 1, Name = "Tester" }
	local inventory = {
		states = {
			[player] = { version = 2, items = items, equipped = {} },
		},
		removedInstances = 0,
		removedQuantities = 0,
		updatedAttributes = 0,
		equipped = 0,
		failApply = false,
		failEquip = false,
	} :: FakeInventory

	function inventory:find(owner: Player, uid: string): Instance?
		local state = self.states[owner]
		if state == nil then return nil end
		for _, instance in state.items do
			if instance.uid == uid then return copyInstance(instance) end
		end
		return nil
	end

	function inventory:getSnapshot(owner: Player): State?
		local state = self.states[owner]
		if state == nil then return nil end
		local result = { version = state.version, items = {}, equipped = table.clone(state.equipped) }
		for index, instance in state.items do
			result.items[index] = copyInstance(instance)
		end
		return result
	end

	function inventory:removeInstance(owner: Player, uid: string): boolean
		self.removedInstances += 1
		local state = self.states[owner]
		if state == nil then return false end
		for index, instance in state.items do
			if instance.uid == uid then
				table.remove(state.items, index)
				return true
			end
		end
		return false
	end

	function inventory:removeQuantity(owner: Player, uid: string, quantity: number): boolean
		self.removedQuantities += 1
		local instance = self:find(owner, uid)
		if instance == nil or instance.quantity == nil or quantity > instance.quantity then return false end
		if quantity == instance.quantity then return self:removeInstance(owner, uid) end
		for _, current in self.states[owner].items do
			if current.uid == uid then
				current.quantity = (current.quantity :: number) - quantity
				return true
			end
		end
		return false
	end

	function inventory:updateAttributes(owner: Player, uid: string, attributes: { [string]: Attribute }): boolean
		self.updatedAttributes += 1
		local state = self.states[owner]
		if state == nil then return false end
		for _, instance in state.items do
			if instance.uid == uid then
				instance.attributes = table.clone(attributes)
				return true
			end
		end
		return false
	end

	function inventory:equip(owner: Player, slot: string, uid: string): boolean
		self.equipped += 1
		local state = self.states[owner]
		if state == nil or self:find(owner, uid) == nil then return false end
		state.equipped[slot] = uid
		return true
	end

	function inventory:applyUseMutations(owner: Player, uid: string, mutations: { [string]: any }): boolean
		if self.failApply then return false end
		local state = self.states[owner]
		if state == nil then return false end
		local candidate: State = {
			version = state.version,
			items = {},
			equipped = table.clone(state.equipped),
		}
		for index, instance in state.items do
			candidate.items[index] = copyInstance(instance)
		end

		local function findCandidate(): (Instance?, number?)
			for index, instance in candidate.items do
				if instance.uid == uid then return instance, index end
			end
			return nil, nil
		end
		if mutations.consumeInstance then
			self.removedInstances += 1
			local _, index = findCandidate()
			if index == nil then return false end
			table.remove(candidate.items, index)
		elseif mutations.consumeQuantity ~= nil then
			self.removedQuantities += 1
			local instance = findCandidate()
			if instance == nil or instance.quantity == nil or mutations.consumeQuantity > instance.quantity then return false end
			if mutations.consumeQuantity == instance.quantity then
				local _, index = findCandidate()
				table.remove(candidate.items, index :: number)
			else
				instance.quantity -= mutations.consumeQuantity
			end
		end
		if mutations.updateAttributes ~= nil then
			self.updatedAttributes += 1
			local instance = findCandidate()
			if instance == nil then return false end
			instance.attributes = table.clone(mutations.updateAttributes)
		end
		if mutations.equipSlot ~= nil then
			self.equipped += 1
			if self.failEquip then return false end
			local instance = findCandidate()
			if instance == nil or instance.itemId ~= "handgun" then return false end
			candidate.equipped[mutations.equipSlot] = uid
		end
		self.states[owner] = candidate
		return true
	end

	return inventory, player
end

local function request(capability: string, context: { [string]: Attribute }, uid: string?): Request
	return { capability = capability, context = context, itemUid = uid }
end

local function behavior(canUse: (any, Instance, { [string]: Attribute }) -> (boolean, string?), use: (any, Instance, { [string]: Attribute }) -> BehaviorResult): Behavior
	return { canUse = canUse, use = use }
end

local function makeService(items: { Instance }, capability: string, itemBehavior: Behavior): (any, FakeInventory, Player)
	local inventory, player = newFakeInventory(items)
	local registry = ItemBehaviorRegistry.new()
	registry:register(capability, itemBehavior)
	return ItemUseService.new(inventory :: any, registry), inventory, player
end

local compatible = behavior(
	function(_player, _instance, context) return context.target == "self", "not_compatible" end,
	function(_player, _instance, _context)
		return { success = true, consumeInstance = true, effect = { amount = 25 } :: { [string]: Attribute } }
	end
)

return function()
	describe("Item use service", function()
	it("finds the first compatible instance by capability and context", function()
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" }, { uid = "b", itemId = "medkit" } }, "heal", compatible)
		local found = service:findCompatibleItem(player, request("heal", { target = "self" }, nil))
		expect(found.uid).to.equal("a")
	end)

	it("uses the first compatible instance after an incompatible first instance", function()
		local selective = behavior(
			function(_player, instance)
				return instance.uid == "b", "not_compatible"
			end,
			function() return { success = true, consumeInstance = true } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" }, { uid = "b", itemId = "medkit" } }, "heal", selective)
		local result: Result = service:use(player, request("heal", {}, nil))
		expect(result.success).to.equal(true)
		expect(result.itemUid).to.equal("b")
		expect(inventory.removedInstances).to.equal(1)
	end)

	it("does not mutate inventory during compatibility lookup", function()
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		service:findCompatibleItem(player, request("heal", { target = "self" }, nil))
		expect(inventory.removedInstances).to.equal(0)
		expect(inventory.removedQuantities).to.equal(0)
	end)

	it("uses the requested uid when it is compatible", function()
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" }, { uid = "b", itemId = "medkit" } }, "heal", compatible)
		expect(service:findCompatibleItem(player, request("heal", { target = "self" }, "b")).uid).to.equal("b")
	end)

	it("rejects a requested uid owned by another player", function()
		local service = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		expect(service:findCompatibleItem({ UserId = 2, Name = "Other" }, request("heal", { target = "self" }, "a"))).to.equal(nil)
	end)

	it("rejects an unknown capability", function()
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		expect(service:findCompatibleItem(player, request("unknown", {}, nil))).to.equal(nil)
	end)

	it("rejects malformed requests without calling behavior", function()
		local canUseCalls = 0
		local useCalls = 0
		local observed = behavior(
			function()
				canUseCalls += 1
				return true
			end,
			function()
				useCalls += 1
				return { success = true }
			end
		)
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", observed)
		local invalidRequests: { any } = {
			{ capability = "", context = {} },
			{ capability = "heal", context = {}, itemUid = "" },
			{ capability = "heal", context = { nested = {} } },
			{ capability = "heal", context = { callback = function() end } },
			{ capability = "heal", context = { amount = 0 / 0 } },
			{ capability = "heal", context = { amount = math.huge } },
		}
		for _, invalid in invalidRequests do
			expect(service:findCompatibleItem(player, invalid)).to.equal(nil)
			local result: Result = service:use(player, invalid)
			expect(result.reason).to.equal("invalid_request")
		end
		expect(canUseCalls).to.equal(0)
		expect(useCalls).to.equal(0)
	end)

	it("returns the handler reason when context is incompatible", function()
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		local result: Result = service:use(player, request("heal", { target = "other" }, nil))
		expect(result.reason).to.equal("not_compatible")
	end)

	it("consumes an individual instance after behavior success", function()
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		local result: Result = service:use(player, request("heal", { target = "self" }, "a"))
		expect(result.success).to.equal(true)
		expect(result.consumed).to.equal(true)
		expect(inventory.removedInstances).to.equal(1)
	end)

	it("reduces a stack by the behavior requested quantity", function()
		local stackBehavior = behavior(
			function() return true end,
			function() return { success = true, consumeQuantity = 2 } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "handgun_ammo", quantity = 5 } }, "reload-ammo", stackBehavior)
		local result: Result = service:use(player, request("reload-ammo", {}, "a"))
		expect(result.success).to.equal(true)
		expect(inventory.removedQuantities).to.equal(1)
		local instance = assert(inventory:find(player, "a"))
		expect(instance.quantity).to.equal(3)
	end)

	it("updates instance attributes after behavior success", function()
		local updateBehavior = behavior(
			function() return true end,
			function() return { success = true, updateAttributes = { charged = true } :: { [string]: Attribute } } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "iron_key" } }, "unlock", updateBehavior)
		service:use(player, request("unlock", {}, "a"))
		expect(inventory.updatedAttributes).to.equal(1)
		local instance = assert(inventory:find(player, "a"))
		expect(assert(instance.attributes).charged).to.equal(true)
	end)

	it("equips the requested uid in the returned mutation", function()
		local equipBehavior = behavior(
			function() return true end,
			function() return { success = true, equipSlot = "primary" } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "handgun" } }, "equip", equipBehavior)
		local result: Result = service:use(player, request("equip", {}, "a"))
		expect(result.success).to.equal(true)
		expect(inventory.equipped).to.equal(1)
		expect(inventory.states[player].equipped.primary).to.equal("a")
	end)

	it("does not mutate inventory after behavior failure", function()
		local failed = behavior(
			function() return true end,
			function() return { success = false, reason = "blocked", consumeInstance = true } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", failed)
		local result: Result = service:use(player, request("heal", {}, "a"))
		expect(result.reason).to.equal("blocked")
		expect(inventory.removedInstances).to.equal(0)
	end)

	it("two uses of the same uid cannot both consume it", function()
		local service, inventory, player
		local locked = behavior(function() return true end, function()
			local second: Result = service:use(player, request("heal", {}, "a"))
			expect(second.reason).to.equal("operation_in_progress")
			return { success = true, consumeInstance = true }
		end)
		service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", locked)
		service:use(player, request("heal", {}, "a"))
		expect(inventory.removedInstances).to.equal(1)
	end)

	it("client healAmount in context is ignored", function()
		local safe = behavior(function() return true end, function(_player, _instance, context)
			local serverHealAmount = 25
			return {
				success = true,
				effect = { amount = serverHealAmount, clientValueIgnored = context.healAmount ~= serverHealAmount } :: { [string]: Attribute },
			}
		end)
		local service, _, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", safe)
		local result: Result = service:use(player, request("heal", { healAmount = 999 }, "a"))
		local effect = assert(result.effect, "use effect")
		expect(effect.amount).to.equal(25)
		expect(effect.clientValueIgnored).to.equal(true)
	end)

	it("a stale compatibility result is revalidated by use", function()
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		expect(service:findCompatibleItem(player, request("heal", { target = "self" }, "a"))).to.be.ok()
		inventory:removeInstance(player, "a")
		local result: Result = service:use(player, request("heal", { target = "self" }, "a"))
		expect(result.success).to.equal(false)
		expect(inventory.removedInstances).to.equal(1)
	end)

	it("does not attempt a second consumption after a stale result", function()
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		service:findCompatibleItem(player, request("heal", { target = "self" }, "a"))
		inventory:removeInstance(player, "a")
		local result: Result = service:use(player, request("heal", { target = "self" }, "a"))
		expect(result.success).to.equal(false)
		expect(inventory.removedInstances).to.equal(1)
	end)

	it("a failed domain behavior leaves the original state intact", function()
		local failed = behavior(
			function()
				return false, "out_of_range"
			end,
			function() return { success = true, consumeInstance = true } end
		)
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", failed)
		service:use(player, request("heal", {}, "a"))
		expect(inventory:find(player, "a")).to.be.ok()
	end)

	it("returns mutation_failed when a confirmed mutation fails", function()
		local service, inventory, player = makeService({ { uid = "a", itemId = "medkit" } }, "heal", compatible)
		inventory.failApply = true
		local result: Result = service:use(player, request("heal", { target = "self" }, "a"))
		expect(result.success).to.equal(false)
		expect(result.reason).to.equal("mutation_failed")
	end)

	it("keeps state intact when the second mutation cannot be confirmed", function()
		local multi = behavior(function() return true end, function()
			return { success = true, updateAttributes = { charged = true } :: { [string]: Attribute }, equipSlot = "primary" }
		end)
		local service, inventory, player = makeService({ { uid = "a", itemId = "handgun" } }, "equip", multi)
		inventory.failEquip = true
		local result: Result = service:use(player, request("equip", {}, "a"))
		expect(result.success).to.equal(false)
		expect(result.reason).to.equal("mutation_failed")
		local after = assert(inventory:getSnapshot(player))
		expect(after.items[1].attributes).to.equal(nil)
		expect(after.equipped.primary).to.equal(nil)
	end)
end)
end
