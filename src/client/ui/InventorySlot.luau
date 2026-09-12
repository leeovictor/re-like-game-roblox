--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)

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

local SLOT_SIZE = UDim2.fromScale(1, 1)

local function createOccupiedChildren(itemText: string, equipped: boolean, quantity: number?, strokeColor: Color3)
	local children = {
		AspectRatio = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = 1,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = strokeColor,
			Transparency = 0.1,
		}),
		Name = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -14, 1, -14),
			Font = Enum.Font.GothamBold,
			Text = itemText,
			TextColor3 = theme.text,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 2,
		}),
	}

	if equipped then
		children.Equipped = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = theme.equipped,
			Position = UDim2.new(1, -5, 0, 5),
			Size = UDim2.fromOffset(50, 18),
			Font = Enum.Font.GothamBold,
			Text = "equipado",
			TextColor3 = theme.white,
			TextSize = 9,
			ZIndex = 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	end

	if quantity ~= nil then
		children.Quantity = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = theme.slotHighlight,
			Position = UDim2.new(1, -5, 1, -5),
			Size = UDim2.fromOffset(24, 18),
			Font = Enum.Font.GothamBold,
			Text = tostring(quantity),
			TextColor3 = theme.white,
			TextSize = 10,
			ZIndex = 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	end
	return children
end

local function InteractiveSlot(props: {
	itemText: string,
	equipped: boolean,
	quantity: number?,
	onActivated: (() -> ())?,
})
	local highlighted, setHighlighted = React.useState(false)
	local buttonProps = {
		AutoButtonColor = false,
		BackgroundColor3 = if highlighted then theme.slotHighlight else theme.surface,
		Selectable = true,
		Size = SLOT_SIZE,
		Text = "",
		[React.Event.MouseEnter] = function()
			setHighlighted(true)
		end,
		[React.Event.MouseLeave] = function()
			setHighlighted(false)
		end,
		[React.Event.SelectionGained] = function()
			setHighlighted(true)
		end,
		[React.Event.SelectionLost] = function()
			setHighlighted(false)
		end,
	}
	if props.onActivated ~= nil then
		buttonProps[React.Event.Activated] = props.onActivated
	end

	return React.createElement(
		"TextButton",
		buttonProps,
		createOccupiedChildren(
			props.itemText,
			props.equipped,
			props.quantity,
			if highlighted then theme.accentBright else theme.accent
		)
	)
end

local function InventorySlot(props: Props)
	if props.item == nil then
		return React.createElement("Frame", {
			Active = false,
			BackgroundColor3 = theme.slotEmpty,
			BackgroundTransparency = 0.35,
			Size = SLOT_SIZE,
		}, {
			AspectRatio = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = 1,
			}),
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = React.createElement("UIStroke", {
				Color = theme.stroke,
				Transparency = 0.35,
			}),
		})
	end

	local item = props.item
	local itemText = item.name
	local isInteractive = #props.actions > 0

	if not isInteractive then
		return React.createElement("Frame", {
			Active = false,
			BackgroundColor3 = theme.slotEmpty,
			BackgroundTransparency = 0.18,
			Size = SLOT_SIZE,
		}, createOccupiedChildren(itemText, props.equipped, item.quantity, theme.stroke))
	end

	return React.createElement(InteractiveSlot, {
		itemText = itemText,
		equipped = props.equipped,
		quantity = item.quantity,
		onActivated = props.onActivated,
	})
end

return InventorySlot
