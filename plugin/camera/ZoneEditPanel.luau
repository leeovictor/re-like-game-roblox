--!strict

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotSelector = require(script.Parent.ShotSelector)
local TextInput = require(script.Parent.TextInput)

local ZoneEditPanel = {}
ZoneEditPanel.__index = ZoneEditPanel

export type Callbacks = {
	onMoveUp: (BasePart) -> (),
	onMoveDown: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, string) -> (),
	onClose: () -> (),
}

export type Panel = typeof(setmetatable(
	{} :: {
		root: Frame,
		callbacks: Callbacks,
		nameInput: TextBox,
		selector: ShotSelector.Selector,
		errorLabel: TextLabel,
		saveButton: TextButton,
		closeButton: TextButton,
		deleteButton: TextButton,
		moveUpButton: TextButton,
		moveDownButton: TextButton,
		editingPart: BasePart?,
		baseName: string,
		baseShotId: string?,
		syncing: boolean,
		destroyed: boolean,
	},
	ZoneEditPanel
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function styleButton(button: TextButton, background: Color3)
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function addHorizontalPadding(button: TextButton, padding: number)
	local buttonPadding = make("UIPadding", button) :: UIPadding
	buttonPadding.PaddingLeft = UDim.new(0, padding)
	buttonPadding.PaddingRight = UDim.new(0, padding)
end

local function setFieldText(self: Panel, field: TextBox, text: string)
	self.syncing = true
	field.Text = text
	self.syncing = false
end

local function zoneNameTaken(zone: BasePart, name: string): boolean
	local parent = zone.Parent
	if parent == nil then
		return false
	end
	for _, sibling in parent:GetChildren() do
		if sibling ~= zone and sibling.Name == name then
			return true
		end
	end
	return false
end

local function isDirty(self: Panel): boolean
	local selected = self.selector:getSelected()
	return trim(self.nameInput.Text) ~= self.baseName or (selected or "") ~= (self.baseShotId or "")
end

local function evaluate(self: Panel, renderError: boolean)
	local zone = self.editingPart
	if zone == nil then
		return
	end
	local name = trim(self.nameInput.Text)
	local selected = self.selector:getSelected()
	local error: string? = nil
	if name == "" then
		error = "Zone name is required"
	elseif zoneNameTaken(zone, name) then
		error = string.format('Zone "%s" already exists', name)
	elseif selected == nil then
		error = "Select a shot"
	end
	if renderError then
		self:setError(error)
	end
	setButtonEnabled(self.saveButton, error == nil and isDirty(self))
end

local function currentShotId(zone: BasePart): string?
	local value = zone:GetAttribute("ShotId")
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function ZoneEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
	local root = make("Frame", parent) :: Frame
	root.Name = "ZoneEditPanel"
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = CameraSystemStyle.panel
	root.BorderSizePixel = 0
	root.Visible = false
	local corner = make("UICorner", root) :: UICorner
	corner.CornerRadius = UDim.new(0, CameraSystemStyle.cornerRadius)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	local layout = make("UIListLayout", root) :: UIListLayout
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local actions = make("Frame", root) :: Frame
	actions.Name = "Actions"
	actions.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	actions.BackgroundTransparency = 1
	actions.LayoutOrder = 1
	local actionsLayout = make("UIListLayout", actions) :: UIListLayout
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.Padding = UDim.new(0, 6)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local moveUpButton = make("TextButton", actions) :: TextButton
	moveUpButton.Name = "MoveUp"
	moveUpButton.Text = "Move Up"
	moveUpButton.Size = UDim2.new(0.5, -3, 1, 0)
	moveUpButton.LayoutOrder = 1
	styleButton(moveUpButton, CameraSystemStyle.input)

	local moveDownButton = make("TextButton", actions) :: TextButton
	moveDownButton.Name = "MoveDown"
	moveDownButton.Text = "Move Down"
	moveDownButton.Size = UDim2.new(0.5, -3, 1, 0)
	moveDownButton.LayoutOrder = 2
	styleButton(moveDownButton, CameraSystemStyle.input)

	local nameInput = TextInput.new(root, {
		placeholder = "Zone name",
		label = "Zone Name",
		layoutOrder = 2,
	})

	local shotLabel = make("TextLabel", root) :: TextLabel
	shotLabel.Name = "ShotLabel"
	shotLabel.Size = UDim2.new(1, 0, 0, 0)
	shotLabel.AutomaticSize = Enum.AutomaticSize.Y
	shotLabel.BackgroundTransparency = 1
	shotLabel.TextColor3 = CameraSystemStyle.text
	shotLabel.TextSize = CameraSystemStyle.textSize
	shotLabel.TextXAlignment = Enum.TextXAlignment.Left
	shotLabel.Text = "Shot"
	shotLabel.LayoutOrder = 3

	local selector = ShotSelector.new(root, nil, { openUpward = true })
	selector.root.LayoutOrder = 4

	local errorLabel = make("TextLabel", root) :: TextLabel
	errorLabel.Name = "Error"
	errorLabel.Size = UDim2.new(1, 0, 0, 0)
	errorLabel.AutomaticSize = Enum.AutomaticSize.Y
	errorLabel.TextWrapped = true
	errorLabel.TextXAlignment = Enum.TextXAlignment.Left
	errorLabel.TextColor3 = CameraSystemStyle.errorText
	errorLabel.BackgroundTransparency = 1
	errorLabel.TextSize = CameraSystemStyle.smallTextSize
	errorLabel.Text = ""
	errorLabel.Visible = false
	errorLabel.LayoutOrder = 5

	local footer = make("Frame", root) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 6

	local deleteButton = make("TextButton", footer) :: TextButton
	deleteButton.Name = "Delete"
	deleteButton.Text = "Delete"
	deleteButton.Position = UDim2.new(0, 0, 0, 0)
	deleteButton.Size = UDim2.new(0, 0, 1, 0)
	deleteButton.AutomaticSize = Enum.AutomaticSize.X
	styleButton(deleteButton, CameraSystemStyle.input)
	deleteButton.TextColor3 = CameraSystemStyle.errorText
	addHorizontalPadding(deleteButton, 10)

	local rightActions = make("Frame", footer) :: Frame
	rightActions.Name = "RightActions"
	rightActions.AnchorPoint = Vector2.new(1, 0)
	rightActions.Position = UDim2.new(1, 0, 0, 0)
	rightActions.Size = UDim2.new(0, 0, 1, 0)
	rightActions.AutomaticSize = Enum.AutomaticSize.X
	rightActions.BackgroundTransparency = 1
	local rightLayout = make("UIListLayout", rightActions) :: UIListLayout
	rightLayout.FillDirection = Enum.FillDirection.Horizontal
	rightLayout.Padding = UDim.new(0, 6)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local closeButton = make("TextButton", rightActions) :: TextButton
	closeButton.Name = "Close"
	closeButton.Text = "Close"
	closeButton.Size = UDim2.new(0, 0, 1, 0)
	closeButton.AutomaticSize = Enum.AutomaticSize.X
	closeButton.LayoutOrder = 1
	styleButton(closeButton, CameraSystemStyle.input)
	addHorizontalPadding(closeButton, 10)

	local saveButton = make("TextButton", rightActions) :: TextButton
	saveButton.Name = "Save"
	saveButton.Text = "Save Changes"
	saveButton.Size = UDim2.new(0, 0, 1, 0)
	saveButton.AutomaticSize = Enum.AutomaticSize.X
	saveButton.LayoutOrder = 2
	styleButton(saveButton, CameraSystemStyle.accent)
	addHorizontalPadding(saveButton, 10)

	local panel = setmetatable({
		root = root,
		callbacks = callbacks,
		nameInput = nameInput,
		selector = selector,
		errorLabel = errorLabel,
		saveButton = saveButton,
		closeButton = closeButton,
		deleteButton = deleteButton,
		moveUpButton = moveUpButton,
		moveDownButton = moveDownButton,
		editingPart = nil,
		baseName = "",
		baseShotId = nil,
		syncing = false,
		destroyed = false,
	}, ZoneEditPanel) :: Panel

	selector.onChanged = function()
		evaluate(panel, true)
	end

	nameInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)

	moveUpButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onMoveUp(zone)
		end
	end)
	moveDownButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onMoveDown(zone)
		end
	end)
	deleteButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone ~= nil then
			callbacks.onDelete(zone)
		end
	end)
	closeButton.Activated:Connect(function()
		callbacks.onClose()
	end)
	saveButton.Activated:Connect(function()
		local zone = panel.editingPart
		if zone == nil then
			return
		end
		local shotName = panel.selector:getSelected()
		if shotName == nil then
			return
		end
		callbacks.onSave(zone, trim(panel.nameInput.Text), shotName)
	end)

	return panel
end

function ZoneEditPanel.show(self: Panel, zone: BasePart, shotNames: { string }, defaultShotId: string?)
	self.editingPart = zone
	self.baseName = zone.Name
	setFieldText(self, self.nameInput, self.baseName)
	local shotName = currentShotId(zone)
	self.selector:setOptions(shotNames, shotName, defaultShotId)
	self.baseShotId = shotName
	evaluate(self, true)
	self.root.Visible = true
end

function ZoneEditPanel.update(
	self: Panel,
	zone: BasePart,
	shotNames: { string },
	defaultShotId: string?,
	canMoveUp: boolean,
	canMoveDown: boolean
)
	if self.editingPart ~= zone then
		return
	end
	local name = zone.Name
	if trim(self.nameInput.Text) == self.baseName and self.baseName ~= name then
		setFieldText(self, self.nameInput, name)
		self.baseName = name
	end
	if trim(self.nameInput.Text) == name then
		self.baseName = name
	end

	local shotId = currentShotId(zone)
	local selected = self.selector:getSelected()
	if selected == self.baseShotId and self.baseShotId ~= shotId then
		self.selector:setOptions(shotNames, shotId, defaultShotId)
		self.baseShotId = shotId
	else
		self.selector:syncOptions(shotNames, defaultShotId)
		if self.selector:getSelected() == shotId then
			self.baseShotId = shotId
		end
	end

	setButtonEnabled(self.moveUpButton, canMoveUp)
	setButtonEnabled(self.moveDownButton, canMoveDown)
	evaluate(self, false)
end

function ZoneEditPanel.hide(self: Panel)
	self.selector:close()
	self.editingPart = nil
	self.root.Visible = false
end

function ZoneEditPanel.setError(self: Panel, message: string?)
	if message == nil then
		self.errorLabel.Text = ""
		self.errorLabel.Visible = false
	else
		self.errorLabel.Text = message
		self.errorLabel.Visible = true
	end
end

function ZoneEditPanel.getEditingPart(self: Panel): BasePart?
	return self.editingPart
end

function ZoneEditPanel.destroy(self: Panel)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.editingPart = nil
	self.root:Destroy()
end

return ZoneEditPanel
