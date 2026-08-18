--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client") :: any
local require = require :: (ModuleScript) -> any
local DialogueController = require(client.dialogue.DialogueController)

local CONFIRM_ACTION = "DungeonDialogueConfirm"
local CANCEL_ACTION = "DungeonDialogueCancel"
local PREVIOUS_ACTION = "DungeonDialoguePrevious"
local NEXT_ACTION = "DungeonDialogueNext"

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

return function()
	describe("DialogueController", function()
		local signalConnections: { SignalConnection } = {}

		beforeEach(function()
			signalConnections = {}
			DialogueController.start()
		end)

		afterEach(function()
			DialogueController.stop()
			for _, connection in signalConnections do
				connection:Disconnect()
			end
			signalConnections = {}
		end)

		it("replaces the active dialog and notifies the old callback", function()
			local oldReason: string? = nil
			DialogueController.show("Mensagem antiga", function(_: nil, reason: string)
				oldReason = reason
			end)

			DialogueController.show("Mensagem nova")

			expect(oldReason).to.equal("replaced")
			expect(DialogueController.getState().text).to.equal("Mensagem nova")
		end)

		it("keeps the active dialog when a new input is invalid", function()
			DialogueController.show("Mensagem valida")

			local ok = pcall(function()
				DialogueController.ask("Pergunta invalida", {
					{ id = "same", text = "Uma" },
					{ id = "same", text = "Duas" },
				}, function() end)
			end)

			expect(ok).to.equal(false)
			expect(DialogueController.getState().text).to.equal("Mensagem valida")
		end)

		it("binds input above the tank priority and unbinds on stop", function()
			DialogueController.show("Bloquear movimento")
			DialogueController.start()

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			local expectedActions = {
				[CONFIRM_ACTION] = Enum.KeyCode.F,
				[CANCEL_ACTION] = Enum.KeyCode.Escape,
				[PREVIOUS_ACTION] = Enum.KeyCode.Up,
				[NEXT_ACTION] = Enum.KeyCode.Down,
			}

			for actionName, keyCode in expectedActions do
				local actionInfo = actions[actionName]
				expect(actionInfo).to.be.ok()
				expect(actionInfo.priorityLevel).to.equal(Enum.ContextActionPriority.High.Value + 1)
				expect(table.find(actionInfo.inputTypes, keyCode)).to.be.ok()
			end

			DialogueController.stop()
			actions = ContextActionService:GetAllBoundActionInfo() :: any
			expect(actions[CONFIRM_ACTION]).to.equal(nil)
			expect(actions[CANCEL_ACTION]).to.equal(nil)
			expect(actions[PREVIOUS_ACTION]).to.equal(nil)
			expect(actions[NEXT_ACTION]).to.equal(nil)
		end)

		it("preserves a dialog started by a stop callback", function()
			DialogueController.show("Dialogo inicial", function()
				DialogueController.start()
				DialogueController.show("Proximo dialogo")
			end)

			DialogueController.stop()

			local state = DialogueController.getState()
			expect(state).to.be.ok()
			expect(state.text).to.equal("Proximo dialogo")

			local actions = ContextActionService:GetAllBoundActionInfo() :: any
			expect(actions[CONFIRM_ACTION]).to.be.ok()
			expect(actions[CANCEL_ACTION]).to.be.ok()
		end)

		it("does not show a dialog after stop until restarted", function()
			DialogueController.stop()
			DialogueController.show("Nao deve aparecer")

			expect(DialogueController.getState()).to.equal(nil)

			DialogueController.start()
			DialogueController.show("Pode aparecer")
			expect(DialogueController.getState().text).to.equal("Pode aparecer")
		end)
	end)
end
