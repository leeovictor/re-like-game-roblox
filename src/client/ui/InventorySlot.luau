--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

type DisplayItem = {
	name: string,
	quantity: number?,
}

type ActionOption = {
	label: string,
	onActivated: () -> (),
}

type Props = {
	item: DisplayItem?,
	equipped: boolean,
	actions: { ActionOption },
	onActivated: (() -> ())?,
}

local SLOT_SIZE = UDim2.fromOffset(88, 88)

local function InventorySlot(props: Props)
	if props.item == nil then
		return React.createElement("Frame", {
			Active = false,
			BackgroundColor3 = Color3.fromRGB(31, 34, 45),
			BackgroundTransparency = 0.35,
			Size = SLOT_SIZE,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(78, 82, 105),
				Transparency = 0.35,
			}),
		})
	end

	local item = props.item
	local quantity = if item.quantity ~= nil then string.format(" x%d", item.quantity) else ""
	local itemText = item.name .. quantity
	local isInteractive = #props.actions > 0

	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(107, 92, 168),
			Transparency = if isInteractive then 0.1 else 0.35,
		}),
		Name = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 1, -14),
			Font = Enum.Font.GothamBold,
			Text = itemText,
			TextColor3 = Color3.fromRGB(241, 237, 255),
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 2,
		}),
	}

	if props.equipped then
		children.Equipped = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.fromRGB(107, 78, 168),
			Position = UDim2.new(1, -5, 0, 5),
			Size = UDim2.fromOffset(50, 18),
			Font = Enum.Font.GothamBold,
			Text = "equipado",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 9,
			ZIndex = 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	end

	return React.createElement("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(39, 42, 56),
		Size = SLOT_SIZE,
		Text = "",
		Activated = if isInteractive then props.onActivated else nil,
	}, children)
end

return InventorySlot
