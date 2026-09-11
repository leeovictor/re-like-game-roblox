--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local inventoryPresentation = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryPresentation)
local inventoryActions = require(StarterPlayer.StarterPlayerScripts.Client.inventory.inventoryActions)
local InventorySlot = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventorySlot)
local DropdownMenu = require(StarterPlayer.StarterPlayerScripts.Client.ui.DropdownMenu)

type Props = {
	inventory: items.InventoryState,
	selectedItemUid: string?,
	onSelectItem: (uid: string?) -> (),
	onEquip: (uid: string) -> (),
	onRequestDiscard: (uid: string) -> (),
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

local function InventoryGrid(props: Props)
	local selectionEffectDependencies: { unknown } = { props.inventory, props.selectedItemUid }
	React.useEffect(function()
		if props.selectedItemUid == nil then
			return
		end

		for index = 1, INVENTORY_SLOT_COUNT do
			local instance = props.inventory.items[index]
			if instance ~= nil and instance.uid == props.selectedItemUid then
				return
			end
		end

		props.onSelectItem(nil)
	end, selectionEffectDependencies)

	local gridChildren = {}
	local overlayChildren = {}
	for index = 1, INVENTORY_SLOT_COUNT do
		local instance = props.inventory.items[index]
		local quantity = if instance ~= nil then inventoryPresentation.getDisplayQuantity(instance) else nil
		local displayItem = if instance ~= nil
			then inventoryPresentation.resolveDisplayItem(instance.itemId, quantity)
			else nil
		local isEquipped = if instance ~= nil
			then inventoryPresentation.isItemEquipped(props.inventory.equipped, instance.uid)
			else false
		local actionOptions: { inventoryActions.ActionOption } = if instance ~= nil
			then inventoryActions.buildActionOptions(instance.uid, instance.itemId, {
				dismiss = function()
					props.onSelectItem(nil)
				end,
				equip = function(uid: string)
					props.onEquip(uid)
				end,
				requestDiscard = function(uid: string)
					props.onRequestDiscard(uid)
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
						props.onSelectItem(instance.uid)
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
			Menu = if instance ~= nil and props.selectedItemUid == instance.uid
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
	overlayChildren.Layout = React.createElement("UIGridLayout", {
		CellPadding = UDim2.fromOffset(INVENTORY_GAP, INVENTORY_GAP),
		CellSize = INVENTORY_CELL_SIZE,
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = INVENTORY_GRID_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
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

return InventoryGrid
