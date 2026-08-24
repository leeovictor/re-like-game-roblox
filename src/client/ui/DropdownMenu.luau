--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

type Option = {
	label: string,
	onActivated: () -> (),
}

type Props = {
	visible: boolean,
	options: { Option },
	position: UDim2,
}

local function DropdownMenu(props: Props)
	if not props.visible or #props.options == 0 then
		return nil
	end

	local optionChildren = {
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, option in props.options do
		optionChildren[tostring(index)] = React.createElement("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(52, 55, 70),
			Font = Enum.Font.GothamBold,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 30),
			Text = option.label,
			TextColor3 = Color3.fromRGB(241, 237, 255),
			TextSize = 13,
			[React.Event.Activated] = option.onActivated,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
		})
	end

	return React.createElement("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
		BackgroundTransparency = 0.04,
		ClipsDescendants = false,
		Position = props.position,
		Size = UDim2.fromOffset(144, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 7),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(132, 104, 205),
			Transparency = 0.1,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingBottom = UDim.new(0, 7),
			PaddingLeft = UDim.new(0, 7),
			PaddingRight = UDim.new(0, 7),
			PaddingTop = UDim.new(0, 7),
		}),
		Options = React.createElement("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, optionChildren),
	})
end

return DropdownMenu
