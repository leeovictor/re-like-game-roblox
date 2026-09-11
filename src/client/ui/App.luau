--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local items = require(ReplicatedStorage.Shared.inventory.items)
local StarterPlayer = game:GetService("StarterPlayer")

local useDialogue = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.useDialogue)
local CinematicController = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.CinematicController)
local useInventory = require(StarterPlayer.StarterPlayerScripts.Client.inventory.useInventory)
local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local CombatServiceModule = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatService)
local useObjectives = require(StarterPlayer.StarterPlayerScripts.Client.objectives.useObjectives)
local usePickupNotification = require(StarterPlayer.StarterPlayerScripts.Client.pickups.usePickupNotification)
local ObjectiveNotification = require(StarterPlayer.StarterPlayerScripts.Client.ui.ObjectiveNotification)
local InventoryPanel = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryPanel)
local ConfirmationModal = require(StarterPlayer.StarterPlayerScripts.Client.ui.ConfirmationModal)
local combatHudState = require(StarterPlayer.StarterPlayerScripts.Client.ui.combatHudState)
local CombatStatus = require(StarterPlayer.StarterPlayerScripts.Client.ui.CombatStatus)
local PickupToast = require(StarterPlayer.StarterPlayerScripts.Client.ui.PickupToast)
local DialogueOverlay = require(StarterPlayer.StarterPlayerScripts.Client.ui.DialogueOverlay)
local ObjectivesPanel = require(StarterPlayer.StarterPlayerScripts.Client.ui.ObjectivesPanel)
local DialogueController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)
local CinematicLetterbox = require(StarterPlayer.StarterPlayerScripts.Client.ui.CinematicLetterbox)
local DocumentReaderOverlayComponent = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentReaderOverlay)
local useDocumentReader = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocumentReader)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local documentReaderController: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

type Props = {
	cinematicController: CinematicController.Controller,
	dialogueController: DialogueController.DialogueController,
	inventoryController: InventoryControllerModule.InventoryController,
	combatService: CombatServiceModule.CombatService,
}

local INVENTORY_TOGGLE_ACTION = "DungeonInventoryToggle"
local INVENTORY_TOGGLE_PRIORITY = Enum.ContextActionPriority.High.Value + 3

local function App(props: Props)
	local inventoryVisible, setInventoryVisible = React.useState(false)
	local confirmationItemUid: string?, setConfirmationItemUid: (string?) -> () = React.useState(nil :: string?)
	local cinematicPlaying, setCinematicPlaying = React.useState(props.cinematicController:isPlaying())
	local dungeonGuiHidden, setDungeonGuiHidden = React.useState(cinematicPlaying)
	local notificationItemId = usePickupNotification()
	local inventory: items.InventoryState? = useInventory(props.inventoryController)
	local documentReader = useDocumentReader()
	local documentReaderActive = documentReader ~= nil
	local documentReaderPresentation, setDocumentReaderPresentation = React.useState(documentReader)
	local documentReaderVisible, setDocumentReaderVisible = React.useState(documentReader ~= nil)
	local documentReaderMounted = documentReaderPresentation ~= nil
	local objectives = useObjectives()
	local dialogue = useDialogue(props.dialogueController)
	local combatHud = combatHudState.getEquippedWeaponStats(inventory)

	React.useEffect(function()
		local connection = props.cinematicController.playingChanged:Connect(function(playing: boolean)
			setCinematicPlaying(playing)
			if playing then
				setDungeonGuiHidden(true)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, { props.cinematicController })

	React.useEffect(function()
		local playerListWasEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		ContextActionService:BindActionAtPriority(
			INVENTORY_TOGGLE_ACTION,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Sink
				end
				if documentReaderActive or documentReaderMounted then
					return Enum.ContextActionResult.Sink
				end
				setInventoryVisible(function(previousVisible: boolean): boolean
					return not previousVisible
				end)
				return Enum.ContextActionResult.Sink
			end,
			false,
			INVENTORY_TOGGLE_PRIORITY,
			Enum.KeyCode.Tab
		)

		return function()
			ContextActionService:UnbindAction(INVENTORY_TOGGLE_ACTION)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, playerListWasEnabled)
		end
	end, { documentReaderActive, documentReaderMounted })

	React.useEffect(function()
		if documentReader ~= nil then
			setDocumentReaderPresentation(documentReader)
			setDocumentReaderVisible(true)
		elseif documentReaderPresentation ~= nil then
			setDocumentReaderVisible(false)
		end
	end, { documentReader })

	React.useEffect(function()
		if documentReaderActive or documentReaderMounted then
			setInventoryVisible(false)
		end
	end, { documentReaderActive, documentReaderMounted })

	React.useEffect(function()
		if not documentReaderMounted then
			return
		end

		local blur = Instance.new("BlurEffect")
		blur.Name = "DocumentReaderBlur"
		blur.Size = 18
		blur.Parent = Lighting

		return function()
			blur:Destroy()
		end
	end, { documentReaderMounted })

	local documentReaderOverlay = if documentReaderPresentation ~= nil
		then React.createElement(DocumentReaderOverlayComponent, {
			enabled = not dungeonGuiHidden,
			onNextPage = function()
				documentReaderController.nextPage()
			end,
			onExitComplete = function()
				setDocumentReaderPresentation(nil)
			end,
			onPreviousPage = function()
				documentReaderController.previousPage()
			end,
			state = documentReaderPresentation,
			visible = documentReaderVisible,
		})
		else nil

	return React.createElement(React.Fragment, nil, {
		DungeonGui = React.createElement("ScreenGui", {
			Enabled = not dungeonGuiHidden,
			Name = "DungeonGui",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			ObjectiveStack = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -24, 0, 24),
			Size = UDim2.new(1, -48, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			ListLayout = React.createElement("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(340, 1000),
			}),
			Notice = React.createElement(ObjectiveNotification),
			Panel = React.createElement(ObjectivesPanel, {
				visible = inventoryVisible,
				objectives = objectives,
			}),
			}),
			InventoryPanel = React.createElement(InventoryPanel, {
				visible = inventoryVisible and not documentReaderActive and not documentReaderMounted,
				inventory = inventory,
				inventoryController = props.inventoryController,
				onDocumentActivated = function()
					setInventoryVisible(false)
				end,
				onRequestDiscard = function(uid: string)
					setConfirmationItemUid(uid)
				end,
			}),
			ConfirmationModal = React.createElement(ConfirmationModal, {
			visible = confirmationItemUid ~= nil,
			message = "Deseja descartar o item?",
			cancelLabel = "não",
			confirmLabel = "sim",
			onCancel = function()
				setConfirmationItemUid(nil)
			end,
			onConfirm = function()
				setConfirmationItemUid(nil)
			end,
			}),
			Dialogue = React.createElement(DialogueOverlay, {
				dialogue = dialogue,
			}),
			PickupNotification = React.createElement(PickupToast, {
				itemId = notificationItemId,
			}),
			CombatStatus = React.createElement(CombatStatus, {
				weaponName = combatHud.weaponName,
				loadedAmmo = combatHud.loadedAmmo,
				reserveAmmo = combatHud.reserveAmmo,
			}),
		}),
		CinematicLetterbox = React.createElement(CinematicLetterbox, {
			playing = cinematicPlaying,
			onExitComplete = function()
				setDungeonGuiHidden(false)
			end,
		}),
		DocumentReader = documentReaderOverlay,
	})
end

return App
