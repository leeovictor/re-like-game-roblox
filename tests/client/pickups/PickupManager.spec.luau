--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local PickupManager = require(client.pickups.PickupManager)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)

local fixtures: { Instance } = {}
local originalCharacter: Model? = nil

local function track<T>(instance: T & Instance): T & Instance
	 table.insert(fixtures, instance)
	 return instance
end

local function makePartPickup(itemId: any, quantity: any?): Part
	local part = track(Instance.new("Part")) :: Part
	part.Anchored = true
	part.Position = Vector3.zero
	part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
	part:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
	if quantity ~= nil then
		part:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
	end
	part.Parent = Workspace
	CollectionService:AddTag(part, interactionTypes.INTERACTABLE_TAG)
	return part
end

local function makeModelPickup(itemId: string, quantity: number?): Model
	local model = track(Instance.new("Model")) :: Model
	local part = Instance.new("Part")
	part.Anchored = true
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
	model:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, itemId)
	if quantity ~= nil then
		model:SetAttribute(interactionTypes.QUANTITY_ATTRIBUTE, quantity)
	end
	model.Parent = Workspace
	CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
	return model
end

local function makeCharacter(position: Vector3): Model
	local character = track(Instance.new("Model")) :: Model
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Position = position
	root.Parent = character
	character.Parent = Workspace
	Players.LocalPlayer.Character = character
	return character
end

local function newFactory(): any
	local nextUid = 0
	return ItemInstanceFactory.new(function(): string
		nextUid += 1
		return string.format("pickup-%02d", nextUid)
	end)
end

return function()
	describe("PickupManager", function()
		local manager: any
		local inventory: any

		beforeEach(function()
			originalCharacter = Players.LocalPlayer.Character
			inventory = { addCalls = 0, added = nil, fail = false, onAdd = nil }
			function inventory.addInstance(instance: any): boolean
				inventory.addCalls += 1
				inventory.added = instance
				if inventory.onAdd ~= nil then
					inventory.onAdd()
				end
				return not inventory.fail
			end
			manager = PickupManager.new({ inventory = inventory, factory = newFactory() })
		end)

		afterEach(function()
			manager:stop()
			Players.LocalPlayer.Character = originalCharacter
			for _, fixture in fixtures do
				if fixture.Parent ~= nil then
					fixture:Destroy()
				end
			end
			table.clear(fixtures)
		end)

		it("registers and collects an authored Part", function()
			local pickup = makePartPickup("access_card")
			manager:start()
			makeCharacter(pickup.Position)

			local result = manager:collect(pickup)
			expect(result.success).to.equal(true)
			expect(inventory.added.itemId).to.equal("access_card")
			expect(pickup.Parent).to.equal(nil)
		end)

		it("registers an authored Model and preserves quantity", function()
			local pickup = makeModelPickup("handgun_ammo", 3)
			manager:start()
			makeCharacter(pickup:GetPivot().Position)

			expect(manager:collect(pickup).success).to.equal(true)
			expect(inventory.added.itemId).to.equal("handgun_ammo")
			expect(inventory.added.quantity).to.equal(3)
		end)

		it("ignores invalid or unregistered roots", function()
			local pickup = makePartPickup("unknown-item")
			pickup:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
			manager:start()
			expect(manager:collect(pickup).reason).to.equal("not_registered")
			expect(inventory.addCalls).to.equal(0)
		end)

		it("rejects a pickup beyond the interaction distance", function()
			local pickup = makePartPickup("access_card")
			manager:start()
			makeCharacter(Vector3.new(7, 0, 0))

			expect(manager:collect(pickup).reason).to.equal("too_far")
			expect(inventory.addCalls).to.equal(0)
			expect(pickup.Parent).to.equal(Workspace)
		end)

		it("preserves the pickup when inventory insertion fails", function()
			local pickup = makePartPickup("access_card")
			inventory.fail = true
			manager:start()
			makeCharacter(pickup.Position)

			expect(manager:collect(pickup).reason).to.equal("inventory_failed")
			expect(pickup.Parent).to.equal(Workspace)
			expect(inventory.addCalls).to.equal(1)
		end)

	end)
end
