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
local inventoryPresentation = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryPresentation)
local inventoryActions = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryActions)
local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local CombatServiceModule = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatService)
local useObjectives = require(StarterPlayer.StarterPlayerScripts.Client.objectives.useObjectives)
local usePickupNotification = require(StarterPlayer.StarterPlayerScripts.Client.pickups.usePickupNotification)
local ObjectiveNotification = require(StarterPlayer.StarterPlayerScripts.Client.ui.ObjectiveNotification)
local InventorySlot = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventorySlot)
local DocumentList = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentList)
local DropdownMenu = require(StarterPlayer.StarterPlayerScripts.Client.ui.DropdownMenu)
local ConfirmationModal = require(StarterPlayer.StarterPlayerScripts.Client.ui.ConfirmationModal)
local combatHudState = require(StarterPlayer.StarterPlayerScripts.Client.ui.combatHudState)
local DialogueController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)
local CinematicLetterbox = require(StarterPlayer.StarterPlayerScripts.Client.ui.CinematicLetterbox)
local DocumentReaderOverlayComponent = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentReaderOverlay)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local useDocumentReader = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocumentReader)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local documentReaderController: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

type Props = {
	cinematicController: CinematicController.Controller,
	dialogueController: DialogueController.DialogueController,
	inventoryController: InventoryControllerModule.InventoryController,
	combatService: CombatServiceModule.CombatService,
}

local INVENTORY_SLOT_COUNT = 6
local INVENTORY_GRID_COLUMNS = 3
local INVENTORY_GAP = 8
local INVENTORY_CELL_SIZE = UDim2.new(
	1 / INVENTORY_GRID_COLUMNS,
	-6,
	0.5,
	-(INVENTORY_GAP / 2)
)
local INVENTORY_CONTENT_ASPECT_RATIO = 280 / 184
local DROPDOWN_WIDTH = 144
local INVENTORY_TOGGLE_ACTION = "DungeonInventoryToggle"
local INVENTORY_TOGGLE_PRIORITY = Enum.ContextActionPriority.High.Value + 3

local function App(props: Props)
	local inventoryVisible, setInventoryVisible = React.useState(false)
	local inventoryTab, setInventoryTab = React.useState("items")
	local selectedItemUid: string?, setSelectedItemUid: (string?) -> () = React.useState(nil :: string?)
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

	local selectionEffectDependencies: { unknown } = { inventory, selectedItemUid }
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
		if not inventoryVisible then
			setSelectedItemUid(nil)
		end
	end, { inventoryVisible })

	React.useEffect(function()
		if documentReaderActive or documentReaderMounted then
			setInventoryVisible(false)
		end
	end, { documentReaderActive, documentReaderMounted })

	React.useEffect(function()
		if inventory == nil or selectedItemUid == nil then
			return
		end

		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = inventory.items[index]
			if instance ~= nil and instance.uid == selectedItemUid then
				return
			end
		end

		setSelectedItemUid(nil)
	end, selectionEffectDependencies)

	local inventoryContent
	if inventoryTab == "documents" then
		inventoryContent = React.createElement(DocumentList, {
			onDocumentActivated = function()
				setInventoryVisible(false)
			end,
		})
	elseif inventory == nil then
		inventoryContent = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.new(1, -32, 0, 28),
			Font = Enum.Font.Gotham,
			Text = "Carregando inventário...",
			TextColor3 = theme.textMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		local gridChildren = {}
		local overlayChildren = {}
		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = inventory.items[index]
			local quantity = if instance ~= nil then inventoryPresentation.getDisplayQuantity(instance) else nil
			local displayItem = if instance ~= nil
				then inventoryPresentation.resolveDisplayItem(
					instance.itemId,
					quantity
				)
				else nil
			local isEquipped = if instance ~= nil then inventoryPresentation.isItemEquipped(inventory.equipped, instance.uid) else false
			local actionOptions: { inventoryActions.ActionOption } = if instance ~= nil
				then inventoryActions.buildActionOptions(instance.uid, instance.itemId, {
					dismiss = function()
						setSelectedItemUid(nil)
					end,
					equip = function(uid: string)
						props.inventoryController:equip(uid)
					end,
					requestDiscard = function(uid: string)
						setConfirmationItemUid(uid)
					end,
				})
				else {}

			gridChildren[tostring(index)] = React.createElement("Frame", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 1),
			}, {
				Slot = React.createElement(InventorySlot, {
					item = displayItem,
					equipped = isEquipped,
					actions = actionOptions,
					onActivated = if instance ~= nil
						then function()
							setSelectedItemUid(instance.uid)
						end
						else nil,
				}),
			})

			local column = ((index - 1) % INVENTORY_GRID_COLUMNS) + 1
			local dropdownPosition = if column < INVENTORY_GRID_COLUMNS
				then UDim2.new(1, INVENTORY_GAP, 0, 0)
				else UDim2.new(0, -DROPDOWN_WIDTH - INVENTORY_GAP, 0, 0)
			overlayChildren[tostring(index)] = React.createElement("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = false,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 10,
			}, {
				Menu = if instance ~= nil and selectedItemUid == instance.uid
					then React.createElement(DropdownMenu, {
						visible = true,
						options = actionOptions,
						position = dropdownPosition,
					})
					else nil,
			})
		end

		gridChildren.Layout = React.createElement("UIGridLayout", {
			CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
			CellSize = INVENTORY_CELL_SIZE,
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local overlayLayout = React.createElement("UIGridLayout", {
			CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
			CellSize = INVENTORY_CELL_SIZE,
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		overlayChildren.Layout = overlayLayout
		inventoryContent = React.createElement("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.new(1, -32, 0, 184),
		}, {
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(280, 184),
			}),
			AspectRatio = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = INVENTORY_CONTENT_ASPECT_RATIO,
				DominantAxis = Enum.DominantAxis.Width,
			}),
			Grid = React.createElement("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
			}, gridChildren),
			Overlay = React.createElement("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 10,
			}, overlayChildren),
		})
	end

	local inventoryPanel = if inventoryVisible and not documentReaderActive and not documentReaderMounted then React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = theme.panel,
			BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(24, 154),
			Size = UDim2.new(0, 0, 0, 0),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(360, 300),
			}),
			Title = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.new(1, -32, 0, 24),
				Font = Enum.Font.GothamBold,
				Text = "INVENTÁRIO",
				TextColor3 = theme.text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Tabs = React.createElement("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 40),
				Size = UDim2.new(1, -32, 0, 28),
			}, {
				Items = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = if inventoryTab == "items"
						then theme.surfaceActive
						else theme.surface,
					Font = Enum.Font.GothamBold,
					Size = UDim2.new(0.48, -3, 1, 0),
					Text = "ITENS",
					TextColor3 = theme.text,
					TextSize = 11,
					[React.Event.Activated] = function()
						setInventoryTab("items")
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),
				Documents = React.createElement("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = if inventoryTab == "documents"
						then theme.surfaceActive
						else theme.surface,
					Font = Enum.Font.GothamBold,
					Position = UDim2.new(0.52, 3, 0, 0),
					Size = UDim2.new(0.48, -3, 1, 0),
					Text = "DOCUMENTOS",
					TextColor3 = theme.text,
					TextSize = 11,
					[React.Event.Activated] = function()
						setInventoryTab("documents")
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 5),
					}),
				}),
			}),
			Content = inventoryContent,
		})
		else nil

	local objectiveRows = {}
	if objectives ~= nil then
		for index, objective in objectives.objectives do
			local marker = if objective.completed then "[x] " else "* "
			objectiveRows[objective.id] = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.new(1, -24, 0, 28),
				AutomaticSize = Enum.AutomaticSize.Y,
				Font = Enum.Font.Gotham,
				Text = marker .. objective.text,
				TextColor3 = if objective.completed
					then theme.successMuted
					else theme.objectiveText,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
			})
		end
	end
	objectiveRows.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local objectivePanel = if inventoryVisible and objectives ~= nil then React.createElement("Frame", {
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		SizeConstraint = React.createElement("UISizeConstraint", {
			MaxSize = Vector2.new(340, 1000),
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 24),
			Font = Enum.Font.GothamBold,
			Text = "OBJETIVOS",
			TextColor3 = theme.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		List = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, objectiveRows),
	}) else nil

	local notificationItem = if notificationItemId ~= nil then items[notificationItemId] else nil
	local notificationName = if notificationItem ~= nil then notificationItem.name else notificationItemId
	local dialogueText: string? = nil

	if dialogue ~= nil then
		dialogueText = dialogue.visibleText
		if dialogue.kind == "question" and not dialogue.isTyping then
			local renderedOptions = {}
			for index, option in dialogue.options do
				local marker = if index == dialogue.selectedIndex then "> " else "  "
				table.insert(renderedOptions, marker .. option.text)
			end
			local visibleText: string = dialogue.visibleText or ""
			dialogueText = visibleText .. "\n" .. table.concat(renderedOptions, "    ")
		end
	end

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
			Panel = objectivePanel,
			}),
			InventoryPanel = inventoryPanel,
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
			Dialogue = if dialogueText ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.8, 0),
				Size = UDim2.new(0.6, 0, 0, 0),
				Font = Enum.Font.RobotoMono,
				RichText = true,
				Text = '<b>' .. dialogueText .. "</b>",
				TextColor3 = theme.success,
				TextSize = 20,
				TextStrokeColor3 = theme.panel,
				TextStrokeTransparency = 0.05,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 20,
			})
				else nil,
			PickupNotification = if notificationName ~= nil
			then React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = theme.panel,
				BackgroundTransparency = 0.08,
				Position = UDim2.new(0, 24, 1, -24),
				Size = UDim2.fromOffset(240, 42),
				Font = Enum.Font.GothamBold,
				Text = "Pegou " .. notificationName,
				TextColor3 = theme.text,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 14),
					PaddingRight = UDim.new(0, 14),
				}),
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			})
				else nil,
			CombatStatus = React.createElement("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = theme.panel,
				BackgroundTransparency = 0.08,
				Position = UDim2.new(1, -24, 1, -24),
				Size = UDim2.fromOffset(224, 76),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = React.createElement("UIStroke", {
					Color = theme.accent,
					Transparency = 0.25,
				}),
				Title = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 8),
					Size = UDim2.new(1, -28, 0, 16),
					Font = Enum.Font.Gotham,
					Text = "ARMA EQUIPADA",
					TextColor3 = theme.textMuted,
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Weapon = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 24),
					Size = UDim2.new(1, -28, 0, 22),
					Font = Enum.Font.GothamBold,
					Text = combatHud.weaponName,
					TextColor3 = theme.text,
					TextSize = 14,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Ammo = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 49),
					Size = UDim2.new(1, -28, 0, 18),
					Font = Enum.Font.GothamBold,
					Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", combatHud.loadedAmmo, combatHud.reserveAmmo),
					TextColor3 = theme.success,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
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
