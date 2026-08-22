--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorController = require(client.doors.DoorController)
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)

local function makeDoor(
	name: string,
	locked: boolean,
	requiredItem: string,
	doorKey: string?
): Model
	local door = Instance.new("Model")
	door.Name = name
	door:SetAttribute(doorTypes.LOCKED_ATTRIBUTE, locked)
	door:SetAttribute(doorTypes.REQUIRED_ITEM_ID_ATTRIBUTE, requiredItem)
	if doorKey ~= nil then
		door:SetAttribute(doorTypes.DOOR_KEY_ATTRIBUTE, doorKey)
	end
	door:SetAttribute("InteractionType", "Door")
	door.Parent = workspace
	return door
end

return function()
	describe("DoorController", function()
		local instances: { Instance } = {}
		local shown: { string } = {}
		local dialogueCallbacks: { any } = {}
		local requests: { any } = {}
		local transitionRequests: { any } = {}
		local transitionCallbacks: { any } = {}
		local inventoryItems: { any } = {}
		local events: { any } = {}
		local invokeResult: any
		local transitionCalls: number
		local controller: any

		local function addInstance<T>(instance: T): T
			table.insert(instances, instance :: any)
			return instance
		end

		local function completeDialogue(index: number, reason: string): ()
			local callback = dialogueCallbacks[index]
			if callback ~= nil then
				callback(nil, reason)
			end
		end

		beforeEach(function()
			instances = {}
			shown = {}
			dialogueCallbacks = {}
			requests = {}
			transitionRequests = {}
			transitionCallbacks = {}
			inventoryItems = {}
			events = {}
			invokeResult = { success = true, action = "unlock" }
			transitionCalls = 0
			controller = DoorController.new({
				getInventory = function()
					return { version = 1, items = inventoryItems, equipped = {} }
				end,
				invokeDoor = function(request: any)
					table.insert(requests, request)
					return invokeResult
				end,
				emit = function(event: any)
					table.insert(events, event)
				end,
				dialogue = {
					show = function(text: string, callback: any)
						table.insert(shown, text)
						if callback ~= nil then
							table.insert(dialogueCallbacks, callback)
						end
					end,
				},
				transition = {
					run = function(request: any, callback: any)
						transitionCalls += 1
						table.insert(transitionRequests, request)
						table.insert(transitionCallbacks, callback)
						return true
					end,
				},
			})
		end)

		afterEach(function()
			for _, instance in instances do
				instance:Destroy()
			end
		end)

		it("rejects a target that is not a Model", function()
			local part = addInstance(Instance.new("Part"))

			controller.interact(part)

			expect(#requests).to.equal(0)
			expect(transitionCalls).to.equal(0)
			expect(#shown).to.equal(0)
		end)

		it("sends only an unlock request when the required item is present", function()
			local door = addInstance(makeDoor("Locked", true, "iron_key"))
			table.insert(inventoryItems, { uid = "key-1", itemId = "iron_key" })

			controller.interact(door)

			expect(#requests).to.equal(1)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("unlock")
			expect(transitionCalls).to.equal(0)
			expect(door:GetAttribute("Locked")).to.equal(true)
			expect(door:GetAttribute("RequiredItemId")).to.equal("iron_key")
			expect(door:GetAttribute("InteractionType")).to.equal("Door")
		end)

		it("shows the unlock success message without entering on the same interaction", function()
			local door = addInstance(makeDoor("Locked", true, "iron_key"))
			table.insert(inventoryItems, { uid = "key-1", itemId = "iron_key" })
			invokeResult = { success = true, action = "unlock" }

			controller.interact(door)

			expect(shown[1]).to.equal("Porta destrancada.")
			expect(#requests).to.equal(1)
			expect(transitionCalls).to.equal(0)
		end)

		it("shows ordered locked messages only after completed callbacks", function()
			local door = addInstance(makeDoor("Locked", true, "iron_key"))
			local folder = Instance.new("Folder")
			folder.Name = "LockedDialogue"
			folder.Parent = door
			local second = Instance.new("StringValue")
			second.Name = "02_Second"
			second.Value = "second"
			second.Parent = folder
			local first = Instance.new("StringValue")
			first.Name = "01_First"
			first.Value = "first"
			first.Parent = folder
			local ignored = Instance.new("Folder")
			ignored.Name = "00_IgnoredNested"
			ignored.Parent = folder
			local nested = Instance.new("StringValue")
			nested.Value = "nested"
			nested.Parent = ignored

			controller.interact(door)
			expect(shown[1]).to.equal("first")
			expect(#requests).to.equal(0)

			completeDialogue(1, "completed")
			expect(shown[2]).to.equal("second")
			completeDialogue(2, "completed")
			expect(#shown).to.equal(2)
			expect(#requests).to.equal(0)
		end)

		it("uses the fallback for absent, empty, and unusable locked dialogue folders", function()
			local cases = { "absent", "empty", "empty-values" }
			for _, caseName in cases do
				local door = addInstance(makeDoor(caseName, true, "iron_key"))
				if caseName ~= "absent" then
					local folder = Instance.new("Folder")
					folder.Name = "LockedDialogue"
					folder.Parent = door
					if caseName == "empty-values" then
						local message = Instance.new("StringValue")
						message.Name = "01_Empty"
						message.Parent = folder
					end
				end

				controller.interact(door)
				expect(shown[#shown]).to.equal("Porta trancada.")
				expect(#requests).to.equal(0)
			end
		end)

		it("does not show the next locked message after cancellation", function()
			local door = addInstance(makeDoor("Locked", true, "iron_key"))
			local folder = Instance.new("Folder")
			folder.Name = "LockedDialogue"
			folder.Parent = door
			for index, text in { "first", "second" } do
				local message = Instance.new("StringValue")
				message.Name = string.format("%02d", index)
				message.Value = text
				message.Parent = folder
			end

			controller.interact(door)
			completeDialogue(1, "cancelled")

			expect(#shown).to.equal(1)
			expect(shown[1]).to.equal("first")
		end)

		it("sends only enter through the transition for an open door", function()
			local door = addInstance(makeDoor("Open", false, ""))
			invokeResult = { success = true, action = "enter" }

			controller.interact(door)

			expect(transitionCalls).to.equal(1)
			expect(#requests).to.equal(0)
			local result = transitionRequests[1]()
			transitionCallbacks[1](result)
			expect(#requests).to.equal(1)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("enter")
		end)

		it("shows the locked dialogue when enter returns missing_item", function()
			local door = addInstance(makeDoor("Open", false, ""))
			invokeResult = { success = false, reason = "missing_item" }

			controller.interact(door)
			expect(transitionCalls).to.equal(1)
			expect(#requests).to.equal(0)

			local result = transitionRequests[1]()
			transitionCallbacks[1](result)

			expect(#requests).to.equal(1)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("enter")
			expect(shown[1]).to.equal("Porta trancada.")
			expect(#requests).to.equal(1)
			expect(transitionCalls).to.equal(1)
		end)

		it("does not create follow-up actions for stale or server-side failures", function()
			local door = addInstance(makeDoor("Locked", true, "iron_key"))
			table.insert(inventoryItems, { uid = "key-1", itemId = "iron_key" })
			local results: { any } = {
				{ success = true, action = "enter" },
				{ success = false, reason = "locked" },
				{ success = false, reason = "already_unlocked" },
				{ success = false, reason = "busy" },
				{ success = false, reason = "invalid_config" },
			}
			for _, result in results do
				invokeResult = result
				local requestCount = #requests
				local shownCount = #shown

				controller.interact(door)

				expect(#requests).to.equal(requestCount + 1)
				expect(#shown).to.equal(shownCount)
				expect(transitionCalls).to.equal(0)
			end

			invokeResult = { success = false, reason = "missing_item" }
			controller.interact(door)
			expect(#requests).to.equal(#results + 1)
			expect(shown[#shown]).to.equal("Porta trancada.")

			local openDoor = addInstance(makeDoor("Open", false, ""))
			invokeResult = { success = false, reason = "locked" }
			controller.interact(openDoor)
			local enterRequest = transitionRequests[#transitionRequests]
			local enterCallback = transitionCallbacks[#transitionCallbacks]
			enterCallback(enterRequest())
			expect(requests[#requests].door).to.equal(openDoor)
			expect(requests[#requests].action).to.equal("enter")
			expect(shown[#shown]).to.equal("Porta trancada.")
		end)

		it("publishes door_blocked when a locked door has no compatible item", function()
			local door = addInstance(makeDoor("VisualExit", true, "iron_key", "cave_exit"))

			controller.interact(door)

			expect(events[1].name).to.equal("door_blocked")
			expect(events[1].doorKey).to.equal("cave_exit")
		end)

		it("publishes door_unlocked only after a successful unlock", function()
			local door = addInstance(makeDoor("VisualExit", true, "iron_key", "logical_exit"))
			table.insert(inventoryItems, { uid = "key-1", itemId = "iron_key" })
			invokeResult = { success = true, action = "unlock" }

			controller.interact(door)

			expect(events[1].name).to.equal("door_unlocked")
			expect(events[1].doorKey).to.equal("logical_exit")
		end)

		it("publishes door_entered only after the transition request succeeds", function()
			local door = addInstance(makeDoor("DoorVisual", false, "", "facility_entrance"))
			invokeResult = { success = true, action = "enter" }

			controller.interact(door)
			transitionCallbacks[1]({ success = true, action = "enter" })

			expect(events[1].name).to.equal("door_entered")
			expect(events[1].doorKey).to.equal("facility_entrance")
		end)

		it("does not publish a progress event for a door without DoorKey", function()
			local door = addInstance(makeDoor("NoLogicalKey", true, "iron_key", nil))

			controller.interact(door)

			expect(#events).to.equal(0)
		end)
	end)
end
