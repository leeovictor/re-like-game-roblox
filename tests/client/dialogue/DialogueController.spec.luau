--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local ActionPriorities = require(ReplicatedStorage.Shared.input.ActionPriorities)
local DialogueController = require(client.dialogue.DialogueController)
local TankController = require(client.player.TankController)

local CONFIRM_ACTION = "DungeonDialogueConfirm"
local CANCEL_ACTION = "DungeonDialogueCancel"
local PREVIOUS_ACTION = "DungeonDialoguePrevious"
local NEXT_ACTION = "DungeonDialogueNext"

local function invokeBoundAction(controller, actionName: string, inputState: Enum.UserInputState)
	local callback = (controller :: any):_testGetBoundActionCallback(actionName)
	expect(callback).to.be.ok()
	return (callback :: any)(actionName, inputState)
end

local function invokeForward(controller, inputState: Enum.UserInputState)
	return invokeBoundAction(controller, "DungeonTankForward", inputState)
end

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

return function()
	describe("DialogueController", function()
		local signalConnections: { SignalConnection } = {}
		local tankController
		local dialogueController

		beforeEach(function()
			signalConnections = {}
			tankController = TankController.new()
			dialogueController = DialogueController.new({
				movement = tankController,
			})
			tankController:start()
			dialogueController:start()
		end)

		afterEach(function()
			dialogueController:stop()
			tankController:stop()
			for _, connection in signalConnections do
				connection:Disconnect()
			end
			signalConnections = {}
		end)

		it("replaces the active dialog and notifies the old callback", function()
			local oldReason: string? = nil
			dialogueController:show("Mensagem antiga", function(_: nil, reason: string)
				oldReason = reason
			end)

			dialogueController:show("Mensagem nova")

			expect(oldReason).to.equal("replaced")
			expect(dialogueController:getState().text).to.equal("Mensagem nova")
		end)

		it("keeps the active dialog when a new input is invalid", function()
			dialogueController:show("Mensagem valida")

			local ok = pcall(function()
				dialogueController:ask("Pergunta invalida", {
					{ id = "same", text = "Uma" },
					{ id = "same", text = "Duas" },
				}, function() end)
			end)

			expect(ok).to.equal(false)
			expect(dialogueController:getState().text).to.equal("Mensagem valida")
		end)

		it("binds input above the tank priority and unbinds on stop", function()
			dialogueController:show("Bloquear movimento")
			dialogueController:start()

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			local expectedActions = {
				[CONFIRM_ACTION] = Enum.KeyCode.F,
				[CANCEL_ACTION] = Enum.KeyCode.Escape,
				[PREVIOUS_ACTION] = Enum.KeyCode.A,
				[NEXT_ACTION] = Enum.KeyCode.D,
			}

			for actionName, keyCode in expectedActions do
				local actionInfo = actions[actionName]
				expect(actionInfo).to.be.ok()
				expect(actionInfo.priorityLevel).to.equal(ActionPriorities.DIALOGUE)
				expect(table.find(actionInfo.inputTypes, keyCode)).to.be.ok()
			end

			dialogueController:stop()
			actions = ContextActionService:GetAllBoundActionInfo() :: any
			expect(actions[CONFIRM_ACTION]).to.equal(nil)
			expect(actions[CANCEL_ACTION]).to.equal(nil)
			expect(actions[PREVIOUS_ACTION]).to.equal(nil)
			expect(actions[NEXT_ACTION]).to.equal(nil)
		end)

		it("preserves a dialog started by a stop callback", function()
			dialogueController:show("Dialogo inicial", function()
				dialogueController:start()
				dialogueController:show("Proximo dialogo")
			end)

			dialogueController:stop()

			local state = dialogueController:getState()
			expect(state).to.be.ok()
			expect(state.text).to.equal("Proximo dialogo")

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			expect(actions[CONFIRM_ACTION]).to.be.ok()
			expect(actions[CANCEL_ACTION]).to.be.ok()
		end)

		it("does not show a dialog after stop until restarted", function()
			dialogueController:stop()
			dialogueController:show("Nao deve aparecer")

			expect(dialogueController:getState()).to.equal(nil)

			dialogueController:start()
			dialogueController:show("Pode aparecer")
			expect(dialogueController:getState().text).to.equal("Pode aparecer")
		end)

		it("preserva o lock de movimento de outro dono ao fechar o dialogo", function()
			local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid

			local otherRelease = tankController:acquireMovementLock()
			dialogueController:show("Dialogo bloqueado")

			dialogueController:stop()
			invokeForward(tankController, Enum.UserInputState.Begin)
			RunService.PreRender:Wait()
			expect(humanoid.MoveDirection).to.equal(Vector3.zero)

			otherRelease()
		end)

		it("isola estado e signal entre instancias", function()
			local first = DialogueController.new({ movement = tankController })
			local second = DialogueController.new({ movement = tankController })
			local observed = false

			first:start()
			second:start()
			table.insert(signalConnections, second.changed:Connect(function()
				observed = true
			end))
			first:show("Somente o primeiro")

			expect(first:getState().text).to.equal("Somente o primeiro")
			expect(second:getState()).to.equal(nil)
			expect(observed).to.equal(false)
			first:stop()
			second:stop()
		end)
	end)
end
