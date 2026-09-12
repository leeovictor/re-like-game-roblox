--!strict

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)

local TextInput = {}

export type Options = {
	placeholder: string,
	label: string?,
	value: string?,
	layoutOrder: number?,
}

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

function TextInput.new(parent: Instance, options: Options): TextBox
	local root = make("Frame", parent) :: Frame
	root.Name = "TextInput"
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.LayoutOrder = options.layoutOrder or 0
	local layout = make("UIListLayout", root) :: UIListLayout
	layout.Padding = UDim.new(0, CameraSystemStyle.labelSpacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	if options.label ~= nil then
		local label = make("TextLabel", root) :: TextLabel
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.BackgroundTransparency = 1
		label.TextColor3 = CameraSystemStyle.text
		label.TextSize = CameraSystemStyle.textSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = options.label
		label.LayoutOrder = 1
	end

	local input = make("TextBox", root) :: TextBox
	input.Name = "Field"
	input.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	input.PlaceholderText = options.placeholder
	input.Text = options.value or ""
	input.ClearTextOnFocus = false
	input.TextColor3 = CameraSystemStyle.text
	input.PlaceholderColor3 = CameraSystemStyle.mutedText
	input.BackgroundColor3 = CameraSystemStyle.input
	input.BorderSizePixel = 0
	input.TextSize = CameraSystemStyle.textSize
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.LayoutOrder = 2
	local corner = make("UICorner", input) :: UICorner
	corner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local stroke = make("UIStroke", input) :: UIStroke
	stroke.Color = CameraSystemStyle.outline
	stroke.Thickness = 1
	stroke.Transparency = CameraSystemStyle.outlineTransparency
	local padding = make("UIPadding", input) :: UIPadding
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	return input
end

return TextInput
