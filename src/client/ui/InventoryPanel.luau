--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local InventoryControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local DocumentList = require(StarterPlayer.StarterPlayerScripts.Client.ui.DocumentList)
local InventoryTabs = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryTabs)
local InventoryGrid = require(StarterPlayer.StarterPlayerScripts.Client.ui.InventoryGrid)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

type Props = {
	visible: boolean,
	inventory: items.InventoryState?,
	inventoryController: InventoryControllerModule.InventoryController,
	onDocumentActivated: () -> (),
	onRequestDiscard: (uid: string) -> (),
}

local function InventoryPanel(props: Props)
	local inventoryTab, setInventoryTab = React.useState("items")
	local selectedItemUid: string?, setSelectedItemUid: (string?) -> () = React.useState(nil :: string?)

	React.useEffect(function()
		if not props.visible then
			setSelectedItemUid(nil)
		end
	end, { props.visible })

	if not props.visible then
		return nil
	end

	local inventory = props.inventory
	local content
	if inventoryTab == "documents" then
		content = React.createElement(DocumentList, {
			onDocumentActivated = props.onDocumentActivated,
		})
	elseif inventory == nil then
		content = React.createElement("TextLabel", {
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
		content = React.createElement(InventoryGrid, {
			inventory = inventory,
			selectedItemUid = selectedItemUid,
			onSelectItem = function(uid: string?)
				setSelectedItemUid(uid)
			end,
			onEquip = function(uid: string)
				props.inventoryController:equip(uid)
			end,
			onRequestDiscard = props.onRequestDiscard,
		})
	end

	return React.createElement("Frame", {
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
		Tabs = React.createElement(InventoryTabs, {
			activeTab = inventoryTab,
			onTabChanged = function(nextTab: string)
				setInventoryTab(nextTab)
			end,
		}),
		Content = content,
	})
end

return InventoryPanel
