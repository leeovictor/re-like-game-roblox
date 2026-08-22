--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemBehaviorRegistry = require(ServerScriptService.Server.items.ItemBehaviorRegistry)
local ItemUseService = require(ServerScriptService.Server.items.ItemUseService)
local DoorUnlockBehavior = require(ServerScriptService.Server.doors.DoorUnlockBehavior)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local remotes = require(ReplicatedStorage.Shared.remotes)
local actualInteractDoor = remotes.InteractDoor :: any
local capturedCallback: any = nil
-- RemoteFunction.OnServerInvoke is write-only, so observe assignments while forwarding them to the real remote.
local interactDoor: any = setmetatable({} :: any, {
	__index = function(_proxy: any, key: string): any
		if key == "OnServerInvoke" then return capturedCallback end
		return actualInteractDoor[key]
	end,
	__newindex = function(_proxy: any, key: string, value: any): ()
		if key == "OnServerInvoke" then
			capturedCallback = value
			actualInteractDoor.OnServerInvoke = value
			return
		end
		actualInteractDoor[key] = value
	end,
})
remotes.InteractDoor = interactDoor
local DoorService = require(ServerScriptService.Server.doors.DoorService)

type Door = Model
type FakePlayer = { Character: Model }
type Item = { uid: string, itemId: string, quantity: number? }
type InventoryState = { version: number, items: { Item }, equipped: { [string]: string } }
type FakeItemService = {
	result: { success: boolean, reason: string? },
	lastRequest: any,
	useCalls: number,
	use: (self: FakeItemService, player: any, request: any) -> { success: boolean, reason: string? },
}

local roots: { Instance } = {}
local services: { any } = {}

local function track(instance: Instance): Instance
	table.insert(roots, instance)
	return instance
end

local function createDoor(options: {
	parent: Instance?,
	interactableTagged: boolean?,
	hasInteractionType: boolean?,
	interactionType: any?,
	legacyTagged: boolean?,
	doorway: boolean?,
	center: boolean?,
	locked: any?,
	requiredItemId: any?,
}): Door
	local door = track(Instance.new("Model")) :: Model
	door.Name = "TestDoor"
	if options.interactableTagged ~= false then
		CollectionService:AddTag(door, interactionTypes.INTERACTABLE_TAG)
	end
	if options.hasInteractionType ~= false then
		door:SetAttribute(
			interactionTypes.INTERACTION_TYPE_ATTRIBUTE,
			if options.interactionType == nil then interactionTypes.DOOR_TYPE else options.interactionType
		)
	end
	if options.legacyTagged == true then
		CollectionService:AddTag(door, doorTypes.DOOR_TAG)
	end
	if options.locked ~= nil then
		door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, options.locked)
	end
	if options.requiredItemId ~= nil then
		door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, options.requiredItemId)
	end
	if options.doorway ~= false then
		local doorway = Instance.new("Part")
		doorway.Name = doorTypes.DOORWAY_NAME
		doorway.Size = Vector3.new(1, 8, 6)
		doorway.Position = Vector3.new(0, 4, 0)
		doorway.Anchored = true
		doorway.Parent = door
		if options.center ~= false then
			local center = Instance.new("Attachment")
			center.Name = doorTypes.CENTER_NAME
			center.Parent = doorway
		end
	end
	if options.parent ~= nil then
		door.Parent = options.parent
	end
	return door
end

local function createPlayer(position: Vector3): FakePlayer
	local character = track(Instance.new("Model")) :: Model
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.Position = position
	root.Parent = character
	character.PrimaryPart = root
	character.Parent = Workspace
	return { Character = character }
end

local function newFakeItemService(result: { success: boolean, reason: string? }): FakeItemService
	local service = {
		result = result,
		lastRequest = nil,
		useCalls = 0,
	} :: FakeItemService
	function service:use(_player: any, request: any): { success: boolean, reason: string? }
		self.useCalls += 1
		self.lastRequest = request
		return self.result
	end
	return service
end

local function createRealItemService(item: Item): (any, any, FakePlayer)
	local player = createPlayer(Vector3.new(2, 4, 0))
	local state: InventoryState = { version = 1, items = { item }, equipped = {} }
	local inventory = {} :: any
	function inventory:find(owner: any, uid: string): Item?
		if owner ~= player then return nil end
		for _, current in state.items do
			if current.uid == uid then return table.clone(current) end
		end
		return nil
	end
	function inventory:getSnapshot(owner: any): InventoryState?
		if owner ~= player then return nil end
		return { version = state.version, items = table.clone(state.items), equipped = table.clone(state.equipped) }
	end
	function inventory:applyUseMutations(owner: any, uid: string, mutations: any): boolean
		if owner ~= player or mutations.consumeInstance or mutations.consumeQuantity ~= nil then return false end
		if self:find(owner, uid) == nil then return false end
		return true
	end
	function inventory:removeInstance()
		return false
	end
	function inventory:removeQuantity()
		return false
	end
	function inventory:updateAttributes()
		return false
	end
	function inventory:equip()
		return false
	end
	local registry = ItemBehaviorRegistry.new()
	assert(registry:register("unlock", DoorUnlockBehavior.create()))
	return ItemUseService.new(inventory, registry), inventory, player
end

local function invoke(service: any, player: FakePlayer, door: Door, action: "unlock" | "enter"): any
	return service:invoke(player :: any, { door = door, action = action })
end

return function()
		describe("Door service", function()
		beforeEach(function()
			remotes.InteractDoor = interactDoor
			interactDoor.OnServerInvoke = nil
		end)

		afterEach(function()
			for _, service in services do
				service:stop()
			end
			table.clear(services)
			interactDoor.OnServerInvoke = nil
			remotes.InteractDoor = actualInteractDoor
			for _, root in roots do
				root:Destroy()
			end
			table.clear(roots)
		end)

		it("start binds once and stop removes the InteractDoor callback", function()
			local itemService = newFakeItemService({ success = false, reason = "missing_item" })
			local service = DoorService.new(itemService :: any)
			table.insert(services, service)
			local player = createPlayer(Vector3.zero)
			service:start()
			local callback = interactDoor.OnServerInvoke
			expect(callback).to.be.ok()
			service:start()
			expect(interactDoor.OnServerInvoke).to.equal(callback)
			expect(service:invoke(player :: any, {} :: any).success).to.equal(false)
			service:stop()
			expect(interactDoor.OnServerInvoke).to.equal(nil)
			service:stop()
			expect(interactDoor.OnServerInvoke).to.equal(nil)
		end)

		it("accepts a common-contract door with the required Doorway and Center", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local player = createPlayer(Vector3.new(2, 4, 0))
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, player, door, "enter")
			expect(result.success).to.equal(true)
		end)

		it("revalidates the interaction contract for every request", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local player = createPlayer(Vector3.new(2, 4, 0))
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()

			expect(invoke(service, player, door, "enter").success).to.equal(true)

			CollectionService:RemoveTag(door, interactionTypes.INTERACTABLE_TAG)
			expect(invoke(service, player, door, "enter").reason).to.equal("invalid_door")

			CollectionService:AddTag(door, interactionTypes.INTERACTABLE_TAG)
			door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
			expect(invoke(service, player, door, "enter").reason).to.equal("invalid_door")

			door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
			door.Parent = nil
			expect(invoke(service, player, door, "enter").reason).to.equal("invalid_door")
		end)

		it("rejects doors that do not satisfy the shared interaction contract", function()
			local cases = {
				{
					door = createDoor({
						parent = Workspace,
						interactableTagged = false,
						legacyTagged = true,
						locked = false,
						requiredItemId = "",
					}),
					reason = "invalid_door",
				},
				{
					door = createDoor({
						parent = Workspace,
						interactableTagged = false,
						locked = false,
						requiredItemId = "",
					}),
					reason = "invalid_door",
				},
				{
					door = createDoor({
						parent = Workspace,
						interactionType = interactionTypes.PICKUP_TYPE,
						locked = false,
						requiredItemId = "",
					}),
					reason = "invalid_door",
				},
				{
					door = createDoor({
						parent = Workspace,
						hasInteractionType = false,
						locked = false,
						requiredItemId = "",
					}),
					reason = "invalid_door",
				},
			}
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			for _, case in cases do
				local result = invoke(service, createPlayer(Vector3.new(2, 4, 0)), case.door, "enter")
				expect(result.success).to.equal(false)
				expect(result.reason).to.equal(case.reason)
			end
		end)

		it("rejects untagged, malformed, detached, and wrongly typed doors", function()
			local cases = {
				{ door = createDoor({ parent = Workspace, interactableTagged = false, locked = false, requiredItemId = "" }), reason = "invalid_door" },
				{ door = createDoor({ parent = Workspace, doorway = false, locked = false, requiredItemId = "" }), reason = "invalid_door" },
				{ door = createDoor({ parent = Workspace, center = false, locked = false, requiredItemId = "" }), reason = "invalid_door" },
				{ door = createDoor({ locked = false, requiredItemId = "" }), reason = "invalid_door" },
				{ door = createDoor({ parent = Workspace, locked = "yes", requiredItemId = "" }), reason = "invalid_config" },
			}
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			for _, case in cases do
				local result = invoke(service, createPlayer(Vector3.new(0, 4, 2)), case.door, "enter")
				expect(result.success).to.equal(false)
				expect(result.reason).to.equal(case.reason)
			end
		end)

		it("rejects invalid locked-door configuration before item use", function()
			local cases = {
				{ door = createDoor({ parent = Workspace, requiredItemId = "" }), reason = "invalid_config" },
				{ door = createDoor({ parent = Workspace, locked = true }), reason = "invalid_config" },
				{ door = createDoor({ parent = Workspace, locked = true, requiredItemId = 123 }), reason = "invalid_config" },
				{ door = createDoor({ parent = Workspace, locked = true, requiredItemId = "" }), reason = "invalid_config" },
				{ door = createDoor({ parent = Workspace, locked = true, requiredItemId = "handgun" }), reason = "invalid_config" },
			}
			local itemService = newFakeItemService({ success = true })
			local service = DoorService.new(itemService :: any)
			table.insert(services, service)
			service:start()
			for _, case in cases do
				local result = invoke(service, createPlayer(Vector3.new(2, 4, 0)), case.door, "unlock")
				expect(result.reason).to.equal(case.reason)
			end
			expect(itemService.useCalls).to.equal(0)
		end)

		it("rejects a player beyond the server distance tolerance", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, createPlayer(Vector3.new(0, 4, 7)), door, "enter")
			expect(result.reason).to.equal("too_far")
		end)

		it("rejects a player on the Center plane as ambiguous", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, createPlayer(Vector3.new(0.0005, 4, 0)), door, "enter")
			expect(result.reason).to.equal("ambiguous_side")
		end)

		it("returns locked without moving a player when entering a locked door", function()
			local door = createDoor({ parent = Workspace, locked = true, requiredItemId = "iron_key" })
			local player = createPlayer(Vector3.new(2, 4, 0))
			local root = assert(player.Character.PrimaryPart, "player root")
			local before = root.Position
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, player, door, "enter")
			expect(result.reason).to.equal("locked")
			expect(root.Position).to.equal(before)
		end)

		it("rejects unlocking an open door", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local service = DoorService.new(newFakeItemService({ success = true }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, createPlayer(Vector3.new(2, 4, 0)), door, "unlock")
			expect(result.reason).to.equal("already_unlocked")
		end)

		it("unlocks with a compatible item without consuming it", function()
			local door = createDoor({ parent = Workspace, locked = true, requiredItemId = "iron_key" })
			local itemService, inventory, player = createRealItemService({ uid = "key", itemId = "iron_key" })
			local service = DoorService.new(itemService)
			table.insert(services, service)
			service:start()
			local result = invoke(service, player, door, "unlock")
			expect(result.success).to.equal(true)
			expect(result.action).to.equal("unlock")
			expect(door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)).to.equal(false)
			expect(inventory:find(player, "key")).to.be.ok()
		end)

		it("returns missing_item for absent or mismatched items", function()
			local door = createDoor({ parent = Workspace, locked = true, requiredItemId = "iron_key" })
			local itemService = newFakeItemService({ success = false, reason = "item_not_found" })
			local service = DoorService.new(itemService :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, createPlayer(Vector3.new(2, 4, 0)), door, "unlock")
			expect(result.reason).to.equal("missing_item")
			expect(door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)).to.equal(true)
		end)

		it("rejects a locked door with invalid required item configuration before item use", function()
			local door = createDoor({ parent = Workspace, locked = true, requiredItemId = "unknown" })
			local itemService = newFakeItemService({ success = true })
			local service = DoorService.new(itemService :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, createPlayer(Vector3.new(2, 4, 0)), door, "unlock")
			expect(result.reason).to.equal("invalid_config")
			expect(itemService.useCalls).to.equal(0)
		end)

		it("enters an open door on the opposite side with safe height and facing away", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local player = createPlayer(Vector3.new(2, 7, 0))
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			local result = invoke(service, player, door, "enter")
			local root = assert(player.Character.PrimaryPart, "player root")
			expect(result.success).to.equal(true)
			expect(root.Position.X).to.equal(-3.5)
			expect(root.Position.Y).to.equal(7)
			expect(root.CFrame.LookVector.X < 0).to.equal(true)
		end)

		it("produces opposite destinations for players on opposite sides", function()
			local door = createDoor({ parent = Workspace, locked = false, requiredItemId = "" })
			local positive = createPlayer(Vector3.new(2, 4, 0))
			local negative = createPlayer(Vector3.new(-2, 4, 0))
			local service = DoorService.new(newFakeItemService({ success = false, reason = "missing_item" }) :: any)
			table.insert(services, service)
			service:start()
			invoke(service, positive, door, "enter")
			invoke(service, negative, door, "enter")
			expect(assert(positive.Character.PrimaryPart, "positive root").Position.X).to.equal(-3.5)
			expect(assert(negative.Character.PrimaryPart, "negative root").Position.X).to.equal(3.5)
		end)

		it("returns busy for a concurrent action on the same door", function()
			local door = createDoor({ parent = Workspace, locked = true, requiredItemId = "iron_key" })
			local itemService = newFakeItemService({ success = true })
			local player = createPlayer(Vector3.new(2, 4, 0))
			local service = DoorService.new(itemService :: any)
			table.insert(services, service)
			service:start()
			local nested: any
			function itemService:use(_player: any, request: any): any
				self.useCalls += 1
				self.lastRequest = request
				nested = invoke(service, player, door, "unlock")
				return { success = true }
			end
			local result = invoke(service, player, door, "unlock")
			expect(result.success).to.equal(true)
			expect(nested.reason).to.equal("busy")
			expect(itemService.useCalls).to.equal(1)
		end)
	end)
end
