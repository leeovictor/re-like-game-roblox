--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local useDialogue = require(script.Parent.Parent.dialogue.useDialogue)
local CinematicController = require(script.Parent.Parent.cinematics.CinematicController)
local useInventory = require(script.Parent.Parent.inventory.useInventory)
local InventoryControllerModule = require(script.Parent.Parent.inventory.InventoryController)
local CombatConfig = require(script.Parent.Parent.combat.CombatConfig)
local CombatServiceModule = require(script.Parent.Parent.combat.CombatService)
local useObjectives = require(script.Parent.Parent.objectives.useObjectives)
local usePickupNotification = require(script.Parent.Parent.pickups.usePickupNotification)
local ObjectiveNotification = require(script.Parent.ObjectiveNotification)
local InventorySlot = require(script.Parent.InventorySlot)
local DropdownMenu = require(script.Parent.DropdownMenu)
local ConfirmationModal = require(script.Parent.ConfirmationModal)
local DialogueController = require(script.Parent.Parent.dialogue.DialogueController)
local TankController = require(script.Parent.Parent.player.TankController)
local CinematicLetterbox = require(script.Parent.CinematicLetterbox)

type Props = {
	cinematicController: CinematicController.Controller,
	dialogueController: DialogueController.DialogueController,
	inventoryController: InventoryControllerModule.InventoryController,
	movementController: TankController.MovementController,
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

local mockActionLabelsByItemId: { [string]: { string } } = {
	access_card = { "descartar" },
	bolt_cutter = { "descartar" },
	handgun = { "equipar" },
	handgun_ammo = { "descartar" },
	medkit = { "usar", "descartar" },
}

local function App(props: Props)
	local inventoryVisible, setInventoryVisible = React.useState(false)
	local selectedItemUid: string?, setSelectedItemUid: (string?) -> () = React.useState(nil :: string?)
	local confirmationItemUid: string?, setConfirmationItemUid: (string?) -> () = React.useState(nil :: string?)
	local cinematicPlaying, setCinematicPlaying = React.useState(props.cinematicController:isPlaying())
	local dungeonGuiHidden, setDungeonGuiHidden = React.useState(cinematicPlaying)
	local notificationItemId = usePickupNotification()
	local inventory: items.InventoryState? = useInventory(props.inventoryController)
	local objectives = useObjectives()
	local dialogue = useDialogue(props.dialogueController)
	local equippedWeapon: items.ItemInstance? = nil
	local weaponConfig: typeof(CombatConfig.handgun)? = nil
	local loadedAmmo: number? = nil
	local reserveAmmo = 0
	if inventory ~= nil then
		local equippedWeaponUid = inventory.equipped.weapon
		if equippedWeaponUid ~= nil then
			for _, instance in inventory.items do
				if instance.uid == equippedWeaponUid then
					equippedWeapon = instance
					break
				end
			end
		end
		if equippedWeapon ~= nil then
			weaponConfig = CombatConfig[equippedWeapon.itemId]
			if equippedWeapon.attributes ~= nil then
				local value = equippedWeapon.attributes.loadedAmmo
				if type(value) == "number" then
					loadedAmmo = value
				end
			end
			if loadedAmmo == nil and weaponConfig ~= nil
				and (equippedWeapon.attributes == nil or equippedWeapon.attributes.loadedAmmo == nil)
			then
				loadedAmmo = weaponConfig.magazineSize
			end
			if weaponConfig ~= nil then
				for _, instance in inventory.items do
					if instance.itemId == weaponConfig.ammoItemId and instance.quantity ~= nil then
						reserveAmmo += instance.quantity
					end
				end
			end
		end
	end
	local equippedWeaponDefinition = if equippedWeapon ~= nil then items[equippedWeapon.itemId] else nil
	local combatHudWeaponName = if equippedWeaponDefinition ~= nil then equippedWeaponDefinition.name else "SEM ARMA"
	local combatHudLoadedAmmo = if loadedAmmo ~= nil then tostring(loadedAmmo) else "--"
	local combatHudReserveAmmo = if weaponConfig ~= nil then tostring(reserveAmmo) else "--"

	local inventoryMovementEffectDependencies: { unknown } = {
		inventoryVisible,
		props.movementController,
		props.combatService,
	}
	React.useEffect(function()
		if not inventoryVisible then
			return
		end
		local releaseMovementLock = props.movementController:acquireMovementLock()
		local releaseCombatLock = props.combatService:acquireLock()
		return function()
			releaseCombatLock()
			releaseMovementLock()
		end
	end, inventoryMovementEffectDependencies)

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
	end, {})

	React.useEffect(function()
		if not inventoryVisible then
			setSelectedItemUid(nil)
		end
	end, { inventoryVisible })

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
	if inventory == nil then
		inventoryContent = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 28),
			Font = Enum.Font.Gotham,
			Text = "Carregando inventário...",
			TextColor3 = Color3.fromRGB(173, 179, 198),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		local function isItemEquipped(uid: string): boolean
			for _, equippedUid in inventory.equipped do
				if equippedUid == uid then
					return true
				end
			end
			return false
		end

		local function resolveDisplayItem(itemId: items.ItemId, quantity: number?)
			local item = items[itemId]
			return {
				name = if item ~= nil then item.name else itemId,
				quantity = quantity,
			}
		end

		local function getDisplayQuantity(instance: items.ItemInstance): number?
			if instance.quantity ~= nil then
				return instance.quantity
			end
			local definition = items[instance.itemId]
			if definition == nil or definition.category ~= "weapon" then
				return nil
			end
			local authoredLoadedAmmo = if instance.attributes ~= nil then instance.attributes.loadedAmmo else nil
			if authoredLoadedAmmo ~= nil then
				return if type(authoredLoadedAmmo) == "number" then authoredLoadedAmmo else nil
			end
			local config = CombatConfig[instance.itemId]
			return if config ~= nil then config.magazineSize else nil
		end

		local gridChildren = {}
		local overlayChildren = {}
		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = inventory.items[index]
			local quantity = if instance ~= nil then getDisplayQuantity(instance) else nil
			local displayItem = if instance ~= nil
				then resolveDisplayItem(
					instance.itemId,
					quantity
				)
				else nil
			local isEquipped = if instance ~= nil then isItemEquipped(instance.uid) else false
			local actionOptions: { { label: string, onActivated: () -> () } } = {}

			if instance ~= nil then
				local actionLabels = mockActionLabelsByItemId[instance.itemId]
				if actionLabels ~= nil then
					for _, label in actionLabels do
						table.insert(actionOptions, {
							label = label,
							onActivated = function()
								setSelectedItemUid(nil)
								if label == "equipar" then
									props.inventoryController:equip(instance.uid)
								elseif label == "descartar" then
									setConfirmationItemUid(instance.uid)
								end
							end,
						})
					end
				end
			end

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
			Position = UDim2.fromOffset(16, 44),
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

	local inventoryPanel = if inventoryVisible then React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(24, 154),
			Size = UDim2.new(0, 0, 0, 0),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(360, 244),
			}),
			Title = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.new(1, -32, 0, 24),
				Font = Enum.Font.GothamBold,
				Text = "INVENTÁRIO",
				TextColor3 = Color3.fromRGB(241, 237, 255),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
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
					then Color3.fromRGB(173, 196, 162)
					else Color3.fromRGB(225, 222, 239),
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
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
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
			TextColor3 = Color3.fromRGB(241, 237, 255),
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
				TextColor3 = Color3.fromRGB(191, 223, 161),
				TextSize = 20,
				TextStrokeColor3 = Color3.fromRGB(20, 22, 30),
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
				BackgroundColor3 = Color3.fromRGB(20, 22, 30),
				BackgroundTransparency = 0.08,
				Position = UDim2.new(0, 24, 1, -24),
				Size = UDim2.fromOffset(240, 42),
				Font = Enum.Font.GothamBold,
				Text = "Pegou " .. notificationName,
				TextColor3 = Color3.fromRGB(241, 237, 255),
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
				BackgroundColor3 = Color3.fromRGB(20, 22, 30),
				BackgroundTransparency = 0.08,
				Position = UDim2.new(1, -24, 1, -24),
				Size = UDim2.fromOffset(224, 76),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(107, 92, 168),
					Transparency = 0.25,
				}),
				Title = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 8),
					Size = UDim2.new(1, -28, 0, 16),
					Font = Enum.Font.Gotham,
					Text = "ARMA EQUIPADA",
					TextColor3 = Color3.fromRGB(173, 179, 198),
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Weapon = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 24),
					Size = UDim2.new(1, -28, 0, 22),
					Font = Enum.Font.GothamBold,
					Text = combatHudWeaponName,
					TextColor3 = Color3.fromRGB(241, 237, 255),
					TextSize = 14,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Ammo = React.createElement("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, 49),
					Size = UDim2.new(1, -28, 0, 18),
					Font = Enum.Font.GothamBold,
					Text = string.format("CARREGADA  %s    DISPONÍVEL  %s", combatHudLoadedAmmo, combatHudReserveAmmo),
					TextColor3 = Color3.fromRGB(191, 223, 161),
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
	})
end

return App
