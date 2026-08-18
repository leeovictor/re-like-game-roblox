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

local function press(actionName: string): ()
	local actions = ContextActionService:GetAllBoundActionInfo() :: any
	local actionInfo = actions[actionName]
	expect(actionInfo).to.be.ok()
	local callback = actionInfo["function"] :: any
	callback(actionName, Enum.UserInputState.Begin, nil)
end

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

		it("publishes a typing message and completes on the second confirm", function()
			local receivedValue: string? = "sentinel"
			local receivedReason: string? = nil
			local latestState: any = nil
			local connection = DialogueController.changed:Connect(function(state: any)
				latestState = state
			end) :: SignalConnection
			table.insert(signalConnections, connection)

			DialogueController.show("Porta trancada", function(value: nil, reason: string)
				receivedValue = value
				receivedReason = reason
			end)

			expect(latestState.kind).to.equal("message")
			expect(latestState.visibleText).to.equal("")
			expect(latestState.isTyping).to.equal(true)

			press(CONFIRM_ACTION)
			expect(latestState.visibleText).to.equal("Porta trancada")
			expect(latestState.isTyping).to.equal(false)

			press(CONFIRM_ACTION)
			expect(latestState).to.equal(nil)
			expect(receivedValue).to.equal(nil)
			expect(receivedReason).to.equal("completed")
		end)

		it("navigates and confirms question options", function()
			local selectedId: string? = nil
			local reason: string? = nil
			DialogueController.ask("Usar Spade Key?", {
				{ id = "yes", text = "Sim" },
				{ id = "no", text = "Nao" },
				{ id = "later", text = "Depois" },
			}, function(optionId: string?, callbackReason: string)
				selectedId = optionId
				reason = callbackReason
			end)

			press(CONFIRM_ACTION)
			press(NEXT_ACTION)
			press(NEXT_ACTION)
			press(NEXT_ACTION)

			local state = DialogueController.getState()
			expect(state).to.be.ok()
			expect(state.selectedIndex).to.equal(3)

			press(PREVIOUS_ACTION)
			expect(DialogueController.getState().selectedIndex).to.equal(2)
			press(CONFIRM_ACTION)

			expect(selectedId).to.equal("no")
			expect(reason).to.equal("completed")
			expect(DialogueController.getState()).to.equal(nil)
		end)

		it("cancels a question with Escape", function()
			local selectedId: string? = "sentinel"
			local reason: string? = nil
			DialogueController.ask("Cancelar?", {
				{ id = "yes", text = "Sim" },
			}, function(optionId: string?, callbackReason: string)
				selectedId = optionId
				reason = callbackReason
			end)

			press(CANCEL_ACTION)

			expect(selectedId).to.equal(nil)
			expect(reason).to.equal("cancelled")
			expect(DialogueController.getState()).to.equal(nil)
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
	end)
end
