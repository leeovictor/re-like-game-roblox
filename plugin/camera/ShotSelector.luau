--!strict

local UserInputService = game:GetService("UserInputService")

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local TextInput = require(script.Parent.TextInput)

local ShotSelector = {}
ShotSelector.__index = ShotSelector

export type Options = {
	openUpward: boolean?,
}

export type Selector = typeof(setmetatable(
	{} :: {
		root: Frame,
		fieldLabel: TextLabel,
		fieldStroke: UIStroke,
		popup: Frame,
		search: TextBox,
		list: ScrollingFrame,
		options: { string },
		selected: string?,
		defaultName: string?,
		openUpward: boolean,
		onChanged: (() -> ())?,
		inputConnection: RBXScriptConnection?,
		destroyed: boolean,
	},
	ShotSelector
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function isPointInside(frame: GuiObject, position: Vector2): boolean
	local topLeft = frame.AbsolutePosition
	local bottomRight = topLeft + frame.AbsoluteSize
	return position.X >= topLeft.X
		and position.X <= bottomRight.X
		and position.Y >= topLeft.Y
		and position.Y <= bottomRight.Y
end

function ShotSelector.new(parent: Instance, onChanged: (() -> ())?, options: Options?): Selector
	local root = make("Frame", parent) :: Frame
	root.Name = "ShotSelector"
	root.Size = UDim2.new(1, 0, 0, CameraSystemStyle.inputHeight)
	root.BackgroundTransparency = 1

	local field = make("TextButton", root) :: TextButton
	field.Name = "Field"
	field.Size = UDim2.fromScale(1, 1)
	field.BackgroundColor3 = CameraSystemStyle.input
	field.BorderSizePixel = 0
	field.Text = ""
	field.AutoButtonColor = true
	local fieldCorner = make("UICorner", field) :: UICorner
	fieldCorner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local fieldStroke = make("UIStroke", field) :: UIStroke
	fieldStroke.Color = CameraSystemStyle.outline
	fieldStroke.Thickness = 1
	fieldStroke.Transparency = CameraSystemStyle.outlineTransparency

	local fieldLabel = make("TextLabel", field) :: TextLabel
	fieldLabel.Name = "Value"
	fieldLabel.Position = UDim2.new(0, 6, 0, 0)
	fieldLabel.Size = UDim2.new(1, -26, 1, 0)
	fieldLabel.BackgroundTransparency = 1
	fieldLabel.TextColor3 = CameraSystemStyle.mutedText
	fieldLabel.TextSize = CameraSystemStyle.textSize
	fieldLabel.TextXAlignment = Enum.TextXAlignment.Left
	fieldLabel.TextTruncate = Enum.TextTruncate.AtEnd
	fieldLabel.Text = "Select a shot"

	local chevron = make("TextLabel", field) :: TextLabel
	chevron.Name = "Chevron"
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.fromScale(1, 0.5)
	chevron.Size = UDim2.new(0, 20, 1, 0)
	chevron.BackgroundTransparency = 1
	chevron.TextColor3 = CameraSystemStyle.mutedText
	chevron.TextSize = CameraSystemStyle.smallTextSize
	chevron.Text = "v"

	local popup = make("Frame", root) :: Frame
	popup.Name = "Popup"
	popup.Size = UDim2.new(1, 0, 0, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.BackgroundColor3 = CameraSystemStyle.popup
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 50
	local popupCorner = make("UICorner", popup) :: UICorner
	popupCorner.CornerRadius = UDim.new(0, 6)
	local popupStroke = make("UIStroke", popup) :: UIStroke
	popupStroke.Color = CameraSystemStyle.outline
	popupStroke.Thickness = 1
	popupStroke.Transparency = CameraSystemStyle.outlineTransparency
	local popupPadding = make("UIPadding", popup) :: UIPadding
	popupPadding.PaddingTop = UDim.new(0, 4)
	popupPadding.PaddingBottom = UDim.new(0, 4)
	popupPadding.PaddingLeft = UDim.new(0, 4)
	popupPadding.PaddingRight = UDim.new(0, 4)
	local popupLayout = make("UIListLayout", popup) :: UIListLayout
	popupLayout.Padding = UDim.new(0, 4)
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local search = TextInput.new(popup, { placeholder = "Search shots", layoutOrder = 1 })
	search.Name = "Search"

	local list = make("ScrollingFrame", popup) :: ScrollingFrame
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.CanvasSize = UDim2.new()
	list.ScrollingEnabled = true
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.ScrollBarThickness = 6
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.LayoutOrder = 2
	local listLayout = make("UIListLayout", list) :: UIListLayout
	listLayout.Padding = UDim.new(0, 2)

	local openUpward = options ~= nil and options.openUpward == true
	if openUpward then
		popup.AnchorPoint = Vector2.new(0, 1)
		popup.Position = UDim2.new(0, 0, 0, -4)
	else
		popup.Position = UDim2.new(0, 0, 1, 4)
	end

	local selector = setmetatable({
		root = root,
		fieldLabel = fieldLabel,
		fieldStroke = fieldStroke,
		popup = popup,
		search = search,
		list = list,
		options = {},
		selected = nil,
		defaultName = nil,
		openUpward = openUpward,
		onChanged = onChanged,
		inputConnection = nil,
		destroyed = false,
	}, ShotSelector) :: Selector

	field.Activated:Connect(function()
		if selector.popup.Visible then
			selector:close()
		else
			selector:open()
		end
	end)

	search:GetPropertyChangedSignal("Text"):Connect(function()
		selector:renderOptions(search.Text)
	end)

	root.Destroying:Connect(function()
		selector:close()
	end)

	return selector
end

function ShotSelector.updateFieldLabel(self: Selector)
	if self.selected == nil then
		self.fieldLabel.Text = "Select a shot"
		self.fieldLabel.TextColor3 = CameraSystemStyle.mutedText
	else
		self.fieldLabel.Text = self.selected
		self.fieldLabel.TextColor3 = CameraSystemStyle.text
	end
end

function ShotSelector.renderOptions(self: Selector, filter: string)
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local normalized = string.lower(filter)
	local matches = 0
	for index, name in self.options do
		if normalized == "" or string.find(string.lower(name), normalized, 1, true) ~= nil then
			matches += 1
			local button = make("TextButton", self.list) :: TextButton
			button.Name = "Option_" .. name
			button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
			button.Text = if name == self.defaultName then name .. "  (default)" else name
			button.BackgroundColor3 = if name == self.selected then CameraSystemStyle.accent else CameraSystemStyle.item
			button.BorderSizePixel = 0
			button.TextColor3 = CameraSystemStyle.text
			button.TextSize = CameraSystemStyle.textSize
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.AutoButtonColor = true
			button.LayoutOrder = index
			local buttonCorner = make("UICorner", button) :: UICorner
			buttonCorner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
			local buttonStroke = make("UIStroke", button) :: UIStroke
			buttonStroke.Color = CameraSystemStyle.outline
			buttonStroke.Thickness = 1
			buttonStroke.Transparency = CameraSystemStyle.outlineTransparency
			local buttonPadding = make("UIPadding", button) :: UIPadding
			buttonPadding.PaddingLeft = UDim.new(0, 8)
			buttonPadding.PaddingRight = UDim.new(0, 8)
			button.Activated:Connect(function()
				self.selected = name
				self:updateFieldLabel()
				self:close()
				if self.onChanged ~= nil then
					self.onChanged()
				end
			end)
		end
	end

	if matches == 0 then
		local empty = make("TextLabel", self.list) :: TextLabel
		empty.Name = "Empty"
		empty.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = CameraSystemStyle.mutedText
		empty.TextSize = CameraSystemStyle.smallTextSize
		empty.Text = "No shots found"
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.LayoutOrder = 1
		local emptyPadding = make("UIPadding", empty) :: UIPadding
		emptyPadding.PaddingLeft = UDim.new(0, 8)
	end

	local itemCount = if matches == 0 then 1 else matches
	local contentHeight = itemCount * CameraSystemStyle.buttonHeight + (itemCount - 1) * 2
	self.list.CanvasSize = UDim2.fromOffset(0, contentHeight)
	self.list.Size = UDim2.new(1, 0, 0, math.min(contentHeight, CameraSystemStyle.listMaxHeight))
end

function ShotSelector.setOptions(self: Selector, names: { string }, selectedName: string?, defaultName: string?)
	local options: { string } = {}
	for _, name in names do
		table.insert(options, name)
	end
	self.options = options
	self.defaultName = defaultName
	self.selected = nil
	if selectedName ~= nil then
		for _, name in self.options do
			if name == selectedName then
				self.selected = selectedName
				break
			end
		end
	end
	self:updateFieldLabel()
	if self.popup.Visible then
		self:renderOptions(self.search.Text)
	end
end

function ShotSelector.syncOptions(self: Selector, names: { string }, defaultName: string?)
	local options: { string } = {}
	for _, name in names do
		table.insert(options, name)
	end
	self.options = options
	self.defaultName = defaultName
	if self.selected ~= nil and table.find(options, self.selected) == nil then
		self.selected = nil
	end
	self:updateFieldLabel()
	if self.popup.Visible then
		self:renderOptions(self.search.Text)
	end
end

function ShotSelector.getSelected(self: Selector): string?
	return self.selected
end

function ShotSelector.isOpen(self: Selector): boolean
	return self.popup.Visible
end

function ShotSelector.open(self: Selector)
	if self.destroyed or self.popup.Visible then
		return
	end
	self.search.Text = ""
	self:renderOptions("")
	self.popup.Visible = true
	self.fieldStroke.Color = CameraSystemStyle.accent
	self.search:CaptureFocus()
	self.inputConnection = UserInputService.InputBegan:Connect(function(input)
		if self.destroyed or not self.popup.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:close()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local insideField = isPointInside(self.root, position)
		local insidePopup = isPointInside(self.popup, position)
		if not insideField and not insidePopup then
			self:close()
		end
	end)
end

function ShotSelector.close(self: Selector)
	if not self.popup.Visible then
		return
	end
	self.popup.Visible = false
	self.fieldStroke.Color = CameraSystemStyle.outline
	if self.inputConnection ~= nil then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
end

function ShotSelector.destroy(self: Selector)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:close()
	self.root:Destroy()
end

return ShotSelector
