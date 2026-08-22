--!strict

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local interactionTypes = require(ReplicatedStorage.Shared.interactions.interactionTypes)
local InteractionController = require(client.interactions.InteractionController)

local ACTION_NAME = "DungeonInteraction"
local probeConfig = { radius = 2, forwardOffset = 1 }
local currentController: any

type SignalConnection = RBXScriptConnection

local function pressF(): ()
	local actionInfo = (ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]
	expect(actionInfo).to.be.ok()
	currentController.interact(ACTION_NAME, Enum.UserInputState.Begin, nil)
end

local function makeCharacter(): Model
	local character = Instance.new("Model")
	character.Name = "InteractionSpecCharacter"
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

local function makePart(name: string, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Anchored = true
	part.Parent = workspace
	return part
end

local function makeInteractablePart(name: string, position: Vector3, interactionType: string?): Part
	local part = makePart(name, position)
	CollectionService:AddTag(part, interactionTypes.INTERACTABLE_TAG)
	if interactionType ~= nil then
		part:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionType)
	end
	return part
end

return function()
	describe("InteractionController", function()
		local character: Model
		local originalCharacter: Model?
		local originalCharacterParent: Instance?
		local fixtures: { Instance } = {}
		local controllers: { any } = {}
		local connections: { SignalConnection } = {}
		local warnings: { string } = {}
		local controller: any

		beforeEach(function()
			originalCharacter = Players.LocalPlayer.Character
			originalCharacterParent = if originalCharacter then originalCharacter.Parent else nil
			if originalCharacter ~= nil then
				originalCharacter.Parent = nil
			end
			character = makeCharacter()
			table.insert(fixtures, character)
			warnings = {}
			table.insert(connections, LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
				if messageType == Enum.MessageType.MessageWarning then
					table.insert(warnings, message)
				end
			end))
			controller = InteractionController.new(probeConfig)
			currentController = controller
			table.insert(controllers, controller)
		end)

		afterEach(function()
			for _, activeController in controllers do
				activeController.stop()
			end
			controllers = {}
			currentController = nil
			for _, connection in connections do
				connection:Disconnect()
			end
			connections = {}
			for _, fixture in fixtures do
				fixture:Destroy()
			end
			fixtures = {}
			Players.LocalPlayer.Character = nil
			if originalCharacter ~= nil then
				Players.LocalPlayer.Character = originalCharacter
				if originalCharacterParent ~= nil then
					originalCharacter.Parent = originalCharacterParent
				end
			end
			originalCharacter = nil
			originalCharacterParent = nil
		end)

		describe("probe", function()
			it("dispatches a pickup inside the sphere", function()
				local target = makeInteractablePart("Pickup", Vector3.new(0, 3, -1), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			local received: Instance? = nil
			controller.register(interactionTypes.PICKUP_TYPE, {
				interact = function(value: Instance)
					received = value
				end,
			})
			controller.start()
			pressF()
			expect(received).to.equal(target)
			expect(controller.getTarget()).to.equal(target)
			end)

			it("does not select a target outside the radius", function()
				local target = makeInteractablePart("Far", Vector3.new(0, 3, -4))
				table.insert(fixtures, target)
			controller.start()
			pressF()
			expect(controller.getTarget()).to.equal(nil)
			end)

			it("uses the root look direction and forward offset", function()
				local root = character:FindFirstChild("HumanoidRootPart") :: Part
				root.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(1, 3, 0))
				local target = makeInteractablePart("Right", Vector3.new(1, 3, 0), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			controller.start()
			pressF()
			expect(controller:getTarget()).to.equal(target)
			end)

			it("detects a target at the root height", function()
				local target = makeInteractablePart("Level", Vector3.new(0, 3, -1), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			controller:start()
			pressF()
			expect(controller:getTarget()).to.equal(target)
			end)

			it("excludes parts inside the character", function()
				local target = makeInteractablePart("CharacterPart", Vector3.new(0, 3, -1))
				target.Parent = character
				table.insert(fixtures, target)
			controller:start()
			pressF()
			expect(controller:getTarget()).to.equal(nil)
			end)

			it("resolves a tagged model from a descendant part", function()
				local model = Instance.new("Model")
				model.Name = "PickupModel"
				CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
				model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
				local target = makePart("Child", Vector3.new(0, 3, -1))
				target.Parent = model
				model.Parent = workspace
				table.insert(fixtures, model)
				controller:start()
				pressF()
				expect(controller:getTarget()).to.equal(model)
			end)

			it("selects one root when two parts belong to it", function()
				local model = Instance.new("Model")
				model.Name = "MultiPart"
				CollectionService:AddTag(model, interactionTypes.INTERACTABLE_TAG)
				model:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
				for index, position in { Vector3.new(0, 3, -1), Vector3.new(1, 3, -1) } do
					local part = makePart("Part" .. index, position)
					part.Parent = model
				end
				model.Parent = workspace
				table.insert(fixtures, model)
				controller:start()
				pressF()
				expect(controller:getTarget()).to.equal(model)
			end)

			it("selects the root nearest to the sphere center", function()
				local near = makeInteractablePart("Near", Vector3.new(0, 3, -1), interactionTypes.PICKUP_TYPE)
				local far = makeInteractablePart("Far", Vector3.new(0, 3, -2.5), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, near)
				table.insert(fixtures, far)
			controller:start()
			pressF()
			expect(controller:getTarget()).to.equal(near)
			end)

			it("clears the target when a later probe has no valid character or target", function()
				local target = makeInteractablePart("Pickup", Vector3.new(0, 3, -1))
				table.insert(fixtures, target)
			controller:start()
			pressF()
			Players.LocalPlayer.Character = nil
			pressF()
			expect(controller:getTarget()).to.equal(nil)
			end)

			it("does not poll for targets after start", function()
				controller:start()
			local target = makeInteractablePart("Late", Vector3.new(0, 3, -1))
				table.insert(fixtures, target)
			 task.wait()
				expect(controller:getTarget()).to.equal(nil)
			end)
		end)

		describe("contract and handlers", function()
			it("warns once for an invalid tagged root", function()
				local target = makeInteractablePart("Invalid", Vector3.new(0, 3, -1), "Other")
				table.insert(fixtures, target)
			controller:start()
			pressF()
			pressF()
			task.wait()
			expect(#warnings).to.equal(1)
				expect(string.find(warnings[1], target:GetFullName(), 1, true) ~= nil).to.equal(true)
			end)

			it("warns for metadata without the Interactable tag", function()
				local target = makePart("MetadataOnly", Vector3.new(0, 3, -1))
				target:SetAttribute(interactionTypes.INTERACTION_TYPE_ATTRIBUTE, interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			controller:start()
			pressF()
			task.wait()
				expect(string.find(warnings[1], target:GetFullName(), 1, true) ~= nil).to.equal(true)
			end)

			it("warns for ItemId without the Interactable tag", function()
				local target = makePart("ItemOnly", Vector3.new(0, 3, -1))
				target:SetAttribute(interactionTypes.ITEM_ID_ATTRIBUTE, "key")
				table.insert(fixtures, target)
			controller:start()
			pressF()
			task.wait()
				expect(string.find(warnings[1], target:GetFullName(), 1, true) ~= nil).to.equal(true)
			end)

			it("warns for the legacy Door tag but not plain geometry", function()
				local plainGeometry = makePart("PlainGeometry", Vector3.new(0, 3, -1))
				table.insert(fixtures, plainGeometry)
				controller:start()
				pressF()
				task.wait()
				expect(#warnings).to.equal(0)

				local target = makePart("LegacyDoor", Vector3.new(0, 3, -1))
				CollectionService:AddTag(target, "Door")
				table.insert(fixtures, target)
				pressF()
				task.wait()
				expect(#warnings).to.equal(1)
				expect(string.find(warnings[1], target:GetFullName(), 1, true) ~= nil).to.equal(true)
			end)

			it("keeps a valid target and warns when its handler is missing", function()
				local target = makeInteractablePart("Pickup", Vector3.new(0, 3, -1), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			controller:start()
			pressF()
			task.wait()
			expect(controller:getTarget()).to.equal(target)
				expect(string.find(warnings[1], interactionTypes.PICKUP_TYPE, 1, true) ~= nil).to.equal(true)
			end)

			it("dispatches the selected root to its registered handler", function()
				local target = makeInteractablePart("Pickup", Vector3.new(0, 3, -1), interactionTypes.PICKUP_TYPE)
				table.insert(fixtures, target)
			local received: Instance? = nil
			controller.register(interactionTypes.PICKUP_TYPE, {
				interact = function(value: Instance)
					received = value
				end,
			})
			controller:start()
			pressF()
			expect(received).to.equal(target)
			end)
		end)

		describe("lifecycle", function()
			it("starts enabled with one high-priority F binding", function()
			expect(controller.isEnabled()).to.equal(true)
			controller:start()
			local info = (ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]
			expect(info).to.be.ok()
			expect(info.priorityLevel).to.equal(Enum.ContextActionPriority.High.Value)
			expect(table.find(info.inputTypes, Enum.KeyCode.F)).to.be.ok()
			end)

			it("does not duplicate a repeated start", function()
				controller:start()
				controller:start()
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.be.ok()
			end)

			it("stops idempotently and clears the target", function()
				controller:start()
			controller.stop()
			controller.stop()
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.equal(nil)
				expect(controller:getTarget()).to.equal(nil)
			end)

			it("honors enabled state before and after start", function()
			controller.setEnabled(false)
				controller:start()
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.equal(nil)
			controller.setEnabled(true)
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.be.ok()
			controller.setEnabled(false)
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.equal(nil)
			controller.setEnabled(true)
				expect((ContextActionService:GetAllBoundActionInfo() :: any)[ACTION_NAME]).to.be.ok()
			end)

			it("allows the dialogue binding to remain above the generic binding", function()
				local dialogue = require(client.dialogue.DialogueController)
				dialogue.start()
				dialogue.show("Blocking")
				controller:start()
				local actions = ContextActionService:GetAllBoundActionInfo() :: any
				expect(actions.DungeonDialogueConfirm.priorityLevel).to.equal(Enum.ContextActionPriority.High.Value + 1)
				expect(actions[ACTION_NAME].priorityLevel).to.equal(Enum.ContextActionPriority.High.Value)
				dialogue.stop()
			end)
		end)
	end)
end
