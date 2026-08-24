--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorController = require(client.doors.DoorController)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local GameplayEvents = require(client.events.GameplayEvents)

local function makeDoor(locked: boolean, key: string?): Model
	local door = Instance.new("Model")
	door.Name = "ControllerDoor"
	door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, locked)
	door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, if locked then "access_card" else "")
	door:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.DOOR_TYPE)
	if key ~= nil then
		door:SetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE, key)
	end
	CollectionService:AddTag(door, interactionTypes.INTERACTABLE_TAG)
	local doorway = Instance.new("Part")
	doorway.Name = doorTypes.DOORWAY_NAME
	doorway.Parent = door
	local center = Instance.new("Attachment")
	center.Name = doorTypes.CENTER_NAME
	center.Parent = doorway
	door.Parent = workspace
	return door
end

return function()
	describe("DoorController", function()
		local instances: { Instance } = {}
		local shown: { string } = {}
		local callbacks: { any } = {}
		local events: { any } = {}
		local managerLocked = true
		local unlockResult: any = { success = false, reason = "missing_item" }
		local enterResult: any = { success = true, action = "enter" }
		local calls = { isLocked = 0, unlock = 0, enter = 0, transition = 0 }
		local eventConnection: any
		local controller: any

		beforeEach(function()
			instances, shown, callbacks, events = {}, {}, {}, {}
			managerLocked = true
			unlockResult = { success = false, reason = "missing_item" }
			enterResult = { success = true, action = "enter" }
			calls = { isLocked = 0, unlock = 0, enter = 0, transition = 0 }
			local manager = {
				isLocked = function(_self: any, _door: Model)
					calls.isLocked += 1
					return managerLocked, nil
				end,
				unlock = function(_self: any, _door: Model)
					calls.unlock += 1
					return unlockResult
				end,
				enter = function(_self: any, _door: Model)
					calls.enter += 1
					return enterResult
				end,
			}
			eventConnection = GameplayEvents.subscribe(function(event: any)
				table.insert(events, event)
			end)
			controller = DoorController.new({
				manager = manager,
				dialogue = { show = function(_self: any, text: string, callback: any)
					table.insert(shown, text)
					if callback ~= nil then
						table.insert(callbacks, callback)
					end
				end },
				transition = { run = function(request: any, callback: any)
					calls.transition += 1
					task.spawn(function()
						callback(request())
					end)
					return true
				end },
			})
		end)

		afterEach(function()
			if eventConnection ~= nil then
				eventConnection:Disconnect()
			end
			for _, instance in instances do
				instance:Destroy()
			end
			for _, door in workspace:GetChildren() do
				if door.Name == "ControllerDoor" then
					door:Destroy()
				end
			end
		end)

		it("ignores non-model targets", function()
			local part = Instance.new("Part")
		table.insert(instances, part)
			controller.interact(part)
			expect(calls.isLocked).to.equal(0)
		end)

		it("unlocks a closed door without entering", function()
			local door = makeDoor(true, "unlock-key")
			table.insert(instances, door)
			managerLocked = true
			unlockResult = { success = true, action = "unlock" }
			controller.interact(door)
			expect(calls.unlock).to.equal(1)
			expect(calls.enter).to.equal(0)
			expect(shown[1]).to.equal("Porta destrancada.")
			callbacks[1](nil, "completed")
			expect(events[1].name).to.equal("door_unlocked")
		end)

		it("shows ordered locked dialogue and publishes blocked after completion", function()
			local door = makeDoor(true, "blocked-key")
			table.insert(instances, door)
			local folder = Instance.new("Folder")
			folder.Name = doorTypes.LOCKED_DIALOGUE_NAME
			folder.Parent = door
			for index, text in { "second", "first" } do
				local value = Instance.new("StringValue")
				value.Name = string.format("%02d", 3 - index)
				value.Value = text
				value.Parent = folder
			end
			controller.interact(door)
			expect(shown[1]).to.equal("first")
			callbacks[1](nil, "completed")
			expect(shown[2]).to.equal("second")
			callbacks[2](nil, "completed")
			expect(events[1].name).to.equal("door_blocked")
		end)

		it("runs enter only through the transition and publishes after success", function()
			local door = makeDoor(false, "entry-key")
			table.insert(instances, door)
			managerLocked = false
			controller.interact(door)
			expect(calls.transition).to.equal(1)
			expect(calls.enter).to.equal(1)
			expect(events[1].name).to.equal("door_entered")
		end)

		it("does not publish progress for a door without a key", function()
			local door = makeDoor(true, nil)
			table.insert(instances, door)
			controller.interact(door)
			expect(#events).to.equal(0)
		end)
	end)
end
