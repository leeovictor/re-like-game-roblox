--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local items = require(ReplicatedStorage.Shared.inventory.items)
local useInventory = require(script.Parent.Parent.inventory.useInventory)

local function App()
	local inventory = useInventory()
	local inventoryRows = {}

	if inventory ~= nil then
		for index, itemId in inventory.items do
			local item = items[itemId]
			local itemName = if item ~= nil then item.name else itemId

			inventoryRows[tostring(index) .. ":" .. itemId] = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Size = UDim2.new(1, -24, 0, 28),
				Font = Enum.Font.Gotham,
				Text = itemName,
				TextColor3 = Color3.fromRGB(225, 222, 239),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	local listChildren = inventoryRows
	listChildren.ListLayout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	if inventory == nil then
		listChildren = {
			Loading = React.createElement("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 28),
				Font = Enum.Font.Gotham,
				Text = "Carregando inventário...",
				TextColor3 = Color3.fromRGB(173, 179, 198),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ListLayout = listChildren.ListLayout,
		}
	end

	return React.createElement("ScreenGui", {
		Name = "DungeonGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		InventoryPanel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(24, 154),
			Size = UDim2.new(1, -48, 0, 220),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(107, 92, 168),
				Transparency = 0.25,
			}),
			SizeConstraint = React.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(360, 220),
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
			List = React.createElement("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 1, -56),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				ScrollBarImageColor3 = Color3.fromRGB(107, 92, 168),
				ScrollBarThickness = 4,
			}, listChildren),
		})
	})
end

return App
