--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DoorController = require(client.doors.DoorController)

local function pressF(controller: any): ()
	controller.interact("DungeonDoorInteract", Enum.UserInputState.Begin, nil)
end

local function makeCharacter(): Model
	local character = Instance.new("Model")
	character.Name = "DoorSpecCharacter"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	Players.LocalPlayer.Character = character
	return character
end

local function makeDoor(name: string, position: Vector3, locked: boolean, requiredItem: string): Model
	local door = Instance.new("Model")
	door.Name = name
	door:SetAttribute("Locked", locked)
	door:SetAttribute("RequiredItemId", requiredItem)
	local part = Instance.new("Part")
	part.Name = "Doorway"
	part.Size = Vector3.new(1, 8, 6)
	part.Position = position
	part.Anchored = true
	part.Parent = door
	CollectionService:AddTag(door, "Door")
	door.Parent = workspace
	return door
end

return function()
	describe("DoorController", function()
		local character: Model
		local doors: { Model } = {}
		local shown: { string } = {}
		local requests: { any } = {}
		local dialogState: any = nil
		local controller: any

		beforeEach(function()
			character = makeCharacter()
			shown = {}
			requests = {}
			dialogState = nil
			controller = DoorController.new({
				getInventory = function() return { version = 1, items = {}, equipped = {} } end,
				invokeDoor = function(request: any)
					table.insert(requests, request)
					return { success = true, action = request.action }
				end,
				dialogue = {
					getState = function() return dialogState end,
					show = function(text: string, callback: any)
						table.insert(shown, text)
						if callback ~= nil then
							callback(nil, "completed")
						end
					end,
				},
				transition = {
					run = function(request: any, callback: any)
						callback(request())
						return true
					end,
				},
			})
			controller.start()
		end)

		afterEach(function()
			controller.stop()
			for _, door in doors do
				door:Destroy()
			end
			doors = {}
			character:Destroy()
			Players.LocalPlayer.Character = nil
		end)

		it("detects the closest door in the forward spherecast and publishes it", function()
			doors = { makeDoor("Far", Vector3.new(0, 3, -5), false, ""), makeDoor("Near", Vector3.new(0, 3, -3), false, "") }
			task.wait()
			expect(controller.getTarget()).to.equal(nil)
			pressF(controller)
			expect(controller.getTarget()).to.equal(doors[2])
		end)

		it("does not detect a door behind or outside the probe", function()
			doors = { makeDoor("Behind", Vector3.new(0, 3, 4), false, ""), makeDoor("Far", Vector3.new(0, 3, -10), false, "") }
			pressF(controller)
			expect(controller.getTarget()).to.equal(nil)
		end)

		it("shows ordered locked dialogue without invoking the server", function()
			local door = makeDoor("Locked", Vector3.new(0, 3, -3), true, "iron_key")
			doors = { door }
			local folder = Instance.new("Folder")
			folder.Name = "LockedDialogue"
			local dialogue: { [string]: string } = { Z = "second", A = "first" }
			for name, value in dialogue do
				local message = Instance.new("StringValue")
				message.Name = name
				message.Value = value
				message.Parent = folder
			end
			folder.Parent = door
			task.wait()
			pressF(controller)
			expect(shown[1]).to.equal("first")
			expect(shown[2]).to.equal("second")
			expect(#requests).to.equal(0)
		end)

		it("refreshes the target when F is pressed", function()
			local door = makeDoor("Open", Vector3.new(0, 3, -3), false, "")
			doors = { door }
			pressF(controller)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("enter")
		end)

		it("unlocks with the required item but does not enter on the same input", function()
			local door = makeDoor("Locked", Vector3.new(0, 3, -3), true, "iron_key")
			doors = { door }
			controller.stop()
			controller = DoorController.new({
				getInventory = function() return { version = 1, items = {{ uid = "1", itemId = "iron_key" }}, equipped = {} } end,
				invokeDoor = function(request: any)
					table.insert(requests, request)
					return { success = true, action = "unlock" }
				end,
				dialogue = {
					getState = function() return nil end,
					show = function(text: string)
						table.insert(shown, text)
					end,
				},
				transition = { run = function() error("must not enter") end },
			})
			controller.start()
			task.wait()
			pressF(controller)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("unlock")
			expect(shown[1]).to.equal("Porta destrancada")
		end)

		it("does not act while dialogue is active", function()
			doors = { makeDoor("Open", Vector3.new(0, 3, -3), false, "") }
			dialogState = { kind = "message" }
			task.wait()
			pressF(controller)
			expect(#requests).to.equal(0)
		end)

		it("uses the fallback message when locked dialogue has no usable values", function()
			local door = makeDoor("Locked", Vector3.new(0, 3, -3), true, "iron_key")
			doors = { door }
			task.wait()
			pressF(controller)
			expect(shown[1]).to.equal("Porta trancada.")
			expect(#requests).to.equal(0)
		end)

		it("sends enter through the transition and handles a stale locked result", function()
			local door = makeDoor("Open", Vector3.new(0, 3, -3), false, "")
			doors = { door }
			local transitionCalls = 0
			controller.stop()
			controller = DoorController.new({
				getInventory = function() return { version = 1, items = {}, equipped = {} } end,
				invokeDoor = function(request: any)
					table.insert(requests, request)
					return { success = false, reason = "locked" }
				end,
				dialogue = {
					getState = function() return nil end,
					show = function(text: string) table.insert(shown, text) end,
				},
				transition = {
					run = function(request: any, callback: any)
						transitionCalls += 1
						callback(request())
						return true
					end,
				},
			})
			controller.start()
			task.wait()
			pressF(controller)
			expect(transitionCalls).to.equal(1)
			expect(requests[1].door).to.equal(door)
			expect(requests[1].action).to.equal("enter")
			expect(#shown).to.equal(0)
		end)
	end)
end
