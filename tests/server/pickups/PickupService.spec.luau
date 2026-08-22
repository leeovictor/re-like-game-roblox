--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemInstanceFactory = require(ServerScriptService.Server.items.ItemInstanceFactory)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local remotes = require(ReplicatedStorage.Shared.remotes)
local actualCollectPickup = remotes.CollectPickup :: any
local capturedCallback: any = nil
local collectPickup: any = setmetatable({}, {
	__index = function(_proxy: any, key: string): any
		if key == "OnServerInvoke" then
			return capturedCallback
		end
		return actualCollectPickup[key]
	end,
	__newindex = function(_proxy: any, key: string, value: any): ()
		if key == "OnServerInvoke" then
			capturedCallback = value
			actualCollectPickup.OnServerInvoke = value
			return
		end
		actualCollectPickup[key] = value
	end,
})
remotes.CollectPickup = collectPickup

local PickupService = require(ServerScriptService.Server.pickups.PickupService)

type FakePlayer = {
	Character: Model?,
}

type FakeInventory = {
	addCalls: number,
	added: any,
	fail: boolean,
	onAdd: (() -> ())?,
	addInstance: (self: FakeInventory, player: any, itemInstance: any) -> boolean,
}

local roots: { Instance } = {}
local services: { any } = {}
local createdPickupsFolder: Instance? = nil

local function track(instance: Instance): Instance
	table.insert(roots, instance)
	return instance
end

local function createPart(itemId: any, quantity: any, withPrompt: boolean?): Part
	local part = track(Instance.new("Part")) :: Part
	part.Name = "AuthoredPickup"
	part.Anchored = true
	part.Size = Vector3.new(2, 2, 2)
	if itemId ~= nil then
		part:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
	end
	if quantity ~= nil then
		part:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
	end
	part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
	if withPrompt == true then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Parent = part
	end
	part.Parent = Workspace
	CollectionService:AddTag(part, interactionTypes.INTERACTABLE_TAG)
	return part
end

local function createModel(itemId: any, quantity: any): Model
	local model = track(Instance.new("Model")) :: Model
	model.Name = "AuthoredPickupModel"
	local part = Instance.new("Part")
	part.Name = "Visual"
	part.Anchored = true
	part.Size = Vector3.new(2, 2, 2)
	part.Parent = model
	if itemId ~= nil then
		model:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
	end
	if quantity ~= nil then
		model:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
	end
	model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
	model.Parent = Workspace
	CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
	return model
end

local function createPlayer(position: Vector3, withRoot: boolean?): FakePlayer
	local player: FakePlayer = {}
	if withRoot ~= false then
		local character = track(Instance.new("Model")) :: Model
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.Position = position
		root.Parent = character
		character.PrimaryPart = root
		character.Parent = Workspace
		player.Character = character
	end
	return player
end

local function newFactory(): any
	local nextUid = 0
	return ItemInstanceFactory.new(function(): string
		nextUid += 1
		return string.format("test-pickup-%02d", nextUid)
	end)
end

local function newInventory(): FakeInventory
	local inventory = {
		addCalls = 0,
		added = nil,
		fail = false,
		onAdd = nil,
	} :: FakeInventory
	function inventory:addInstance(_player: any, itemInstance: any): boolean
		self.addCalls += 1
		self.added = itemInstance
		if self.onAdd ~= nil then
			self.onAdd()
		end
		return not self.fail
	end
	return inventory
end

local function newService(
	inventory: FakeInventory,
	definitions: { any }?,
	notify: ((any, string) -> ())?
): any
	local testNotifier = if notify == nil then function(_player: any, _itemId: string): () end else notify
	local service = PickupService.new(inventory, newFactory(), definitions, testNotifier)
	table.insert(services, service)
	return service
end

local function invoke(service: any, player: FakePlayer, pickup: any): any
	return service:invoke(player :: any, { pickup = pickup })
end

return function()
	describe("Pickup service", function()
		beforeEach(function()
			remotes.CollectPickup = collectPickup
			collectPickup.OnServerInvoke = nil
			createdPickupsFolder = Workspace:FindFirstChild("Pickups")
		end)

		afterEach(function()
			for _, service in services do
				service:stop()
			end
			table.clear(services)
			collectPickup.OnServerInvoke = nil
			remotes.CollectPickup = actualCollectPickup
			for _, root in roots do
				root:Destroy()
			end
			table.clear(roots)
			if createdPickupsFolder == nil then
				local folder = Workspace:FindFirstChild("Pickups")
				if folder ~= nil then
					folder:Destroy()
				end
			end
			createdPickupsFolder = nil
		end)

		it("registers an authored Part before collection", function()
			local pickup = createPart("handgun")
			local inventory = newInventory()
			local service = newService(inventory)
			service:start()

			local result = invoke(service, createPlayer(pickup.Position), pickup)

			expect(result.success).to.equal(true)
			expect(inventory.added.itemId).to.equal("handgun")
		end)

		it("registers an authored Model from its tagged root", function()
			local pickup = createModel("handgun_ammo", 3)
			local inventory = newInventory()
			local service = newService(inventory)
			service:start()

			local result = invoke(service, createPlayer(pickup:GetPivot().Position), pickup)

			expect(result.success).to.equal(true)
			expect(inventory.added.itemId).to.equal("handgun_ammo")
			expect(inventory.added.quantity).to.equal(3)
		end)

		it("registers a pickup tagged after start", function()
			local pickup = createPart("handgun", nil, false)
			local inventory = newInventory()
			local service = newService(inventory)
			service:start()
			CollectionService:AddTag(pickup, interactionTypes.INTERACTABLE_TAG)

			expect(invoke(service, createPlayer(pickup.Position), pickup).success).to.equal(true)
		end)

		it("does not duplicate registration after repeated start", function()
			local pickup = createPart("handgun")
			local inventory = newInventory()
			local service = newService(inventory)
			service:start()
			service:start()

			invoke(service, createPlayer(pickup.Position), pickup)

			expect(inventory.addCalls).to.equal(1)
		end)

		it("does not register an unknown item", function()
			local pickup = createPart("unknown-item")
			local service = newService(newInventory())
			service:start()

			expect(invoke(service, createPlayer(pickup.Position), pickup).reason).to.equal("not_registered")
		end)

		it("rejects invalid authored quantities without partial state", function()
			local invalidQuantities: { any } = { 0, -1, 1.5, "3" }
			local service = newService(newInventory())
			service:start()

			for _, quantity in invalidQuantities do
				local pickup = createPart("handgun_ammo", quantity)
				expect(invoke(service, createPlayer(pickup.Position), pickup).reason).to.equal("not_registered")
			end
		end)

		it("rejects a quantity on a non-stackable item", function()
			local pickup = createPart("handgun", 2)
			local service = newService(newInventory())
			service:start()

			expect(invoke(service, createPlayer(pickup.Position), pickup).reason).to.equal("not_registered")
		end)

		it("creates independent server instances for generated definitions", function()
			local inventory = newInventory()
			local service = newService(inventory, { { itemId = "handgun" }, { itemId = "handgun" } })
			service:start()
			task.wait()

			local folder = assert(Workspace:FindFirstChild("Pickups"), "generated pickup folder")
			local generated = folder:GetChildren()
			expect(#generated).to.equal(2)
			expect(generated[1]:GetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE)).to.equal("handgun")
			expect(generated[1]:GetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE)).to.equal(interactionTypes.PICKUP_TYPE)
			expect(generated[1] ~= generated[2]).to.equal(true)
		end)

		it("rejects malformed requests and unregistered targets", function()
			local service = newService(newInventory())
			service:start()
			local result = service:invoke(createPlayer(Vector3.zero) :: any, {} :: any)

			expect(result.reason).to.equal("invalid_request")
			expect(service:invoke(createPlayer(Vector3.zero) :: any, { pickup = "not-instance" }).reason).to.equal("invalid_request")
		end)

		it("revalidates the target contract on collection", function()
			local pickup = createPart("handgun")
			local service = newService(newInventory())
			service:start()

			CollectionService:RemoveTag(pickup, interactionTypes.INTERACTABLE_TAG)
			expect(invoke(service, createPlayer(pickup.Position), pickup).reason).to.equal("invalid_pickup")
		end)

		it("revalidates ItemId and Quantity on collection", function()
			local pickup = createPart("handgun_ammo", 2)
			local service = newService(newInventory())
			service:start()

			pickup:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, "handgun")
			expect(invoke(service, createPlayer(pickup.Position), pickup).reason).to.equal("invalid_pickup")
		end)

		it("rejects a detached pickup and a player without a root", function()
			local pickup = createPart("handgun")
			local service = newService(newInventory())
			service:start()
			pickup.Parent = nil
			expect(invoke(service, createPlayer(Vector3.zero), pickup).reason).to.equal("invalid_pickup")

			pickup.Parent = Workspace
			local playerWithoutRoot: FakePlayer = {}
			expect(invoke(service, playerWithoutRoot, pickup).reason).to.equal("invalid_pickup")
		end)

		it("rejects a player beyond the pickup distance", function()
			local pickup = createPart("handgun")
			local service = newService(newInventory())
			service:start()

			expect(invoke(service, createPlayer(Vector3.new(7, 0, 0)), pickup).reason).to.equal("too_far")
		end)

		it("keeps the pickup available when inventory insertion fails", function()
			local pickup = createPart("handgun", nil, true)
			local inventory = newInventory()
			inventory.fail = true
			local service = newService(inventory)
			service:start()

			local player = createPlayer(pickup.Position)
			expect(invoke(service, player, pickup).reason).to.equal("inventory_failed")
			expect(pickup.Parent).to.equal(Workspace)
			expect((pickup:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt).Enabled).to.equal(false)

			inventory.fail = false
			expect(invoke(service, player, pickup).success).to.equal(true)
		end)

		it("destroys the pickup before notifying after inventory success", function()
			local pickup = createPart("handgun")
			local inventory = newInventory()
			local events: { string } = {}
			local notifiedPlayer: any = nil
			local notifiedItemId: string? = nil
			local service = newService(inventory, nil, function(player: any, itemId: string): ()
				table.insert(events, "notify")
				notifiedPlayer = player
				notifiedItemId = itemId
				expect(pickup.Parent).to.equal(nil)
			end)
			inventory.onAdd = function(): ()
				table.insert(events, "add")
				expect(pickup.Parent).to.equal(Workspace)
			end
			service:start()
			local player = createPlayer(pickup.Position)

			expect(invoke(service, player, pickup).success).to.equal(true)
			expect(notifiedPlayer).to.equal(player)
			expect(notifiedItemId).to.equal("handgun")
			expect(events[1]).to.equal("add")
			expect(events[2]).to.equal("notify")
		end)

		it("returns busy for a reentrant collection of the same pickup", function()
			local pickup = createPart("handgun")
			local inventory = newInventory()
			local service = newService(inventory)
			local player = createPlayer(pickup.Position)
			local nested: any = nil
			inventory.onAdd = function(): ()
				nested = invoke(service, player, pickup)
			end
			service:start()

			expect(invoke(service, player, pickup).success).to.equal(true)
			expect(nested.reason).to.equal("busy")
			expect(inventory.addCalls).to.equal(1)
		end)

		it("binds and unbinds CollectPickup idempotently", function()
			local service = newService(newInventory())
			service:start()
			local callback = collectPickup.OnServerInvoke
			expect(callback).to.be.ok()
			service:start()
			expect(collectPickup.OnServerInvoke).to.equal(callback)

			service:stop()
			service:stop()
			expect(collectPickup.OnServerInvoke).to.equal(nil)
		end)

		it("disables authored and generated prompts without prompt collection", function()
			local pickup = createPart("handgun", nil, true)
			local service = newService(newInventory(), { { itemId = "handgun" } })
			service:start()
			task.wait()

			local authoredPrompt = pickup:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
			expect(authoredPrompt.Enabled).to.equal(false)
			local folder = assert(Workspace:FindFirstChild("Pickups"), "generated pickup folder")
			local generatedPrompt = folder:GetChildren()[1]:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
			expect(generatedPrompt.Enabled).to.equal(false)
		end)
	end)
end
