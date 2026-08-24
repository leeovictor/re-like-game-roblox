--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorManager = require(client.doors.DoorManager)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)

local function makeDoor(locked: any, requiredItemId: any, options: any?): Model
	options = options or {}
	local door = Instance.new("Model")
	door.Name = options.name or "Door"
	if options.tag ~= false then
		CollectionService:AddTag(door, interactionTypes.INTERACTABLE_TAG)
	end
	if options.interactionType ~= false then
		door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, options.interactionType or interactionTypes.DOOR_TYPE)
	end
	if options.locked ~= false then
		door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, locked)
	end
	if options.requiredItemId ~= false then
		door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, requiredItemId)
	end
	if options.doorway ~= false then
		local doorway = Instance.new(options.doorwayClass or "Part")
		doorway.Name = doorTypes.DOORWAY_NAME
		if doorway:IsA("BasePart") then
			doorway.Anchored = true
		end
		(doorway :: BasePart).Size = Vector3.new(4, 8, 1)
		doorway.Parent = door
		if options.center ~= false then
			local center = Instance.new(options.centerClass or "Attachment")
			center.Name = doorTypes.CENTER_NAME
			center.Parent = doorway
		end
	end
	door.Parent = options.parent or Workspace
	return door
end

local function makeCharacter(position: Vector3): (Model, BasePart)
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Position = position
	root.Parent = character
	character.Parent = Workspace
	Players.LocalPlayer.Character = character
	return character, root
end

return function()
	describe("DoorManager", function()
		local originalCharacter: Model?
		local instances: { Instance } = {}
		local inventory: any
		local manager: any

		beforeEach(function()
			originalCharacter = Players.LocalPlayer.Character
			instances = {}
			inventory = { state = { version = 1, items = {}, equipped = {} }, used = false }
			function inventory.getState()
				return inventory.state
			end
			function inventory.use()
				inventory.used = true
				error("DoorManager must not consume unlock items")
			end
			manager = DoorManager.new({ inventory = inventory })
		end)

		afterEach(function()
			Players.LocalPlayer.Character = originalCharacter
			for _, instance in instances do
				instance:Destroy()
			end
			for _, door in Workspace:GetChildren() do
				if door.Name == "Door" or door.Name == "SecondDoor" then
					door:Destroy()
				end
			end
		end)

		local function add<T>(instance: T): T
			table.insert(instances, instance :: any)
			return instance
		end

		it("accepts the named inventory dependency", function()
			expect(manager).to.be.ok()
		end)

		it("reports valid locked and open doors", function()
			local locked = add(makeDoor(true, "access_card"))
			local open = add(makeDoor(false, ""))
			expect(manager:isLocked(locked)).to.equal(true)
			expect(manager:isLocked(open)).to.equal(false)
		end)

		it("rejects invalid door structure and configuration", function()
			local cases: { { any } } = {
				{ Instance.new("Part"), "invalid_door" },
				{ makeDoor(true, "access_card", { tag = false }), "invalid_door" },
				{ makeDoor(true, "access_card", { interactionType = "Pickup" }), "invalid_door" },
				{ makeDoor(true, "access_card", { doorway = false }), "invalid_door" },
				{ makeDoor(true, "access_card", { center = false }), "invalid_door" },
				{ makeDoor("yes", "access_card"), "invalid_config" },
				{ makeDoor(true, 12), "invalid_config" },
				{ makeDoor(true, "unknown"), "invalid_config" },
				{ makeDoor(true, "handgun"), "invalid_config" },
			}
			for _, case in cases do
				local door = add(case[1] :: any)
				local locked, reason = manager:isLocked(door)
				expect(locked).to.equal(nil)
				expect(reason).to.equal(case[2])
			end
		end)

		it("does not require an item for a valid open door with an empty requirement", function()
			local door = add(makeDoor(false, ""))
			expect(manager:isLocked(door)).to.equal(false)
		end)

		it("rejects unlock when distant or exactly on the center plane", function()
			local door = add(makeDoor(true, "access_card"))
			local _, root = makeCharacter(Vector3.new(100, 0, 0))
			expect(manager:unlock(door).reason).to.equal("too_far")
			expect(door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)).to.equal(true)
			root.Position = Vector3.zero
			local doorway = door:FindFirstChild(doorTypes.DOORWAY_NAME)
			assert(doorway ~= nil, "test door must have a doorway")
			local center = doorway:FindFirstChild(doorTypes.CENTER_NAME) :: Attachment
			center.WorldPosition = root.Position
			expect(manager:unlock(door).reason).to.equal("ambiguous_side")
		end)

		it("returns already_unlocked and missing_item without consuming inventory", function()
			local open = add(makeDoor(false, ""))
			makeCharacter(Vector3.new(2, 0, 0))
			expect(manager:unlock(open).reason).to.equal("already_unlocked")
			local locked = add(makeDoor(true, "access_card"))
			expect(manager:unlock(locked).reason).to.equal("missing_item")
			expect(inventory.used).to.equal(false)
		end)

		it("unlocks with a compatible item and preserves that item", function()
			local door = add(makeDoor(true, "access_card"))
			makeCharacter(Vector3.new(2, 0, 0))
			inventory.state.items = { { uid = "card", itemId = "access_card" } }
			expect(manager:unlock(door).success).to.equal(true)
			expect(door:GetAttribute(doorTypes.LOCKED_ATTRIBUTE)).to.equal(false)
			expect(inventory.state.items[1].itemId).to.equal("access_card")
			expect(inventory.used).to.equal(false)
		end)

		it("enters an open door on the opposite side while preserving height", function()
			local door = add(makeDoor(false, ""))
			local _, root = makeCharacter(Vector3.new(2, 2, 0))
			local doorway = door:FindFirstChild(doorTypes.DOORWAY_NAME) :: BasePart
			local center = doorway:FindFirstChild(doorTypes.CENTER_NAME) :: Attachment
			local sourceSide = (root.Position - center.WorldPosition):Dot(center.WorldCFrame.XVector)
			expect(manager:enter(door).success).to.equal(true)
			local destinationSide = (root.Position - center.WorldPosition):Dot(center.WorldCFrame.XVector)
			expect(destinationSide * sourceSide < 0).to.equal(true)
			expect(math.abs(destinationSide) > doorway.Size.X / 2).to.equal(true)
			expect(root.Position.Y).to.equal(2)
		end)

		it("allows repeated synchronous requests without a busy lock", function()
			local first = add(makeDoor(true, "access_card"))
			first.Name = "Door"
			local second = add(makeDoor(true, "access_card", { name = "SecondDoor" }))
			makeCharacter(Vector3.new(2, 0, 0))
			local result = manager:unlock(first)
			expect(result.reason).to.equal("missing_item")
			expect(manager:unlock(second).reason).to.equal("missing_item")
			expect(DoorManager.new({ inventory = inventory }):unlock(first).reason).to.equal("missing_item")
		end)
	end)
end
