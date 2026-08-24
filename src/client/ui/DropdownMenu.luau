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

local function DropdownOption(props: { option: Option, layoutOrder: number })
	local highlighted, setHighlighted = React.useState(false)

	return React.createElement("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = if highlighted
			then Color3.fromRGB(78, 65, 111)
			else Color3.fromRGB(52, 55, 70),
		Font = Enum.Font.GothamBold,
		LayoutOrder = props.layoutOrder,
		Selectable = true,
		Size = UDim2.new(1, 0, 0, 30),
		Text = props.option.label,
		TextColor3 = Color3.fromRGB(241, 237, 255),
		TextSize = 13,
		[React.Event.Activated] = props.option.onActivated,
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
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 5),
		}),
	})
end

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
		optionChildren[tostring(index)] = React.createElement(DropdownOption, {
			layoutOrder = index,
			option = option,
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
