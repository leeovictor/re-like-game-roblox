--!strict

local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local TextInput = require(script.Parent.TextInput)

local ShotEditPanel = {}
ShotEditPanel.__index = ShotEditPanel

export type Callbacks = {
	onApply: (BasePart) -> (),
	onCapture: (BasePart) -> (),
	onSetDefault: (BasePart) -> (),
	onDelete: (BasePart) -> (),
	onSave: (BasePart, string, number) -> (),
	onClose: () -> (),
}

export type Panel = typeof(setmetatable(
	{} :: {
		root: Frame,
		callbacks: Callbacks,
		nameInput: TextBox,
		fovInput: TextBox,
		errorLabel: TextLabel,
		saveButton: TextButton,
		closeButton: TextButton,
		deleteButton: TextButton,
		applyButton: TextButton,
		captureButton: TextButton,
		defaultButton: TextButton,
		editingPart: BasePart?,
		baseName: string,
		baseFov: string,
		syncing: boolean,
		destroyed: boolean,
	},
	ShotEditPanel
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

local function shotNameTaken(part: BasePart, name: string): boolean
	local parent = part.Parent
	if parent == nil then
		return false
	end
	for _, sibling in parent:GetChildren() do
		if sibling ~= part and sibling.Name == name then
			return true
		end
	end
	return false
end

local function isDirty(self: Panel): boolean
	return trim(self.nameInput.Text) ~= self.baseName or trim(self.fovInput.Text) ~= self.baseFov
end

local function evaluate(self: Panel, renderError: boolean)
	local part = self.editingPart
	if part == nil then
		return
	end
	local name = trim(self.nameInput.Text)
	local fovText = trim(self.fovInput.Text)
	local fov = tonumber(fovText)
	local error: string? = nil
	if name == "" then
		error = "Shot name is required"
	elseif shotNameTaken(part, name) then
		error = string.format('Shot "%s" already exists', name)
	elseif fov == nil or fov < 1 or fov > 120 then
		error = "Field of View must be between 1 and 120"
	end
	if renderError then
		self:setError(error)
	end
	setButtonEnabled(self.saveButton, error == nil and isDirty(self))
end

function ShotEditPanel.new(parent: Instance, callbacks: Callbacks): Panel
	local root = make("Frame", parent) :: Frame
	root.Name = "ShotEditPanel"
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
	actions.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight * 2 + 4)
	actions.BackgroundTransparency = 1
	actions.LayoutOrder = 1
	local actionsGrid = make("UIGridLayout", actions) :: UIGridLayout
	actionsGrid.CellSize = UDim2.new(0.5, -3, 0, CameraSystemStyle.buttonHeight)
	actionsGrid.CellPadding = UDim2.new(0, 6, 0, 4)
	actionsGrid.FillDirection = Enum.FillDirection.Horizontal
	actionsGrid.FillDirectionMaxCells = 2
	actionsGrid.SortOrder = Enum.SortOrder.LayoutOrder

	local applyButton = make("TextButton", actions) :: TextButton
	applyButton.Name = "Apply"
	applyButton.Text = "Apply To Camera"
	applyButton.LayoutOrder = 1
	styleButton(applyButton, CameraSystemStyle.input)

	local captureButton = make("TextButton", actions) :: TextButton
	captureButton.Name = "Capture"
	captureButton.Text = "Capture Camera"
	captureButton.LayoutOrder = 2
	styleButton(captureButton, CameraSystemStyle.input)

	local defaultButton = make("TextButton", actions) :: TextButton
	defaultButton.Name = "Default"
	defaultButton.Text = "Set Default"
	defaultButton.LayoutOrder = 3
	styleButton(defaultButton, CameraSystemStyle.input)

	local nameInput = TextInput.new(root, {
		placeholder = "Shot name",
		label = "Shot Name",
		layoutOrder = 2,
	})

	local fovInput = TextInput.new(root, {
		placeholder = "Field of View (1-120)",
		label = "Field of View",
		layoutOrder = 3,
	})

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
	errorLabel.LayoutOrder = 4

	local footer = make("Frame", root) :: Frame
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 5

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
		fovInput = fovInput,
		errorLabel = errorLabel,
		saveButton = saveButton,
		closeButton = closeButton,
		deleteButton = deleteButton,
		applyButton = applyButton,
		captureButton = captureButton,
		defaultButton = defaultButton,
		editingPart = nil,
		baseName = "",
		baseFov = "",
		syncing = false,
		destroyed = false,
	}, ShotEditPanel) :: Panel

	nameInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)
	fovInput:GetPropertyChangedSignal("Text"):Connect(function()
		if panel.syncing then
			return
		end
		evaluate(panel, true)
	end)

	applyButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onApply(part)
		end
	end)
	captureButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onCapture(part)
		end
	end)
	defaultButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onSetDefault(part)
		end
	end)
	deleteButton.Activated:Connect(function()
		local part = panel.editingPart
		if part ~= nil then
			callbacks.onDelete(part)
		end
	end)
	closeButton.Activated:Connect(function()
		callbacks.onClose()
	end)
	saveButton.Activated:Connect(function()
		local part = panel.editingPart
		if part == nil then
			return
		end
		local fov = tonumber(trim(panel.fovInput.Text))
		if fov == nil then
			return
		end
		callbacks.onSave(part, trim(panel.nameInput.Text), fov)
	end)

	return panel
end

function ShotEditPanel.show(self: Panel, shot: BasePart)
	self.editingPart = shot
	self.baseName = shot.Name
	self.baseFov = tostring(shot:GetAttribute("FieldOfView") or "")
	setFieldText(self, self.nameInput, self.baseName)
	setFieldText(self, self.fovInput, self.baseFov)
	evaluate(self, true)
	self.root.Visible = true
end

function ShotEditPanel.update(self: Panel, shot: BasePart)
	if self.editingPart ~= shot then
		return
	end
	local name = shot.Name
	local fovText = tostring(shot:GetAttribute("FieldOfView") or "")
	if trim(self.nameInput.Text) == self.baseName and self.baseName ~= name then
		setFieldText(self, self.nameInput, name)
		self.baseName = name
	end
	if trim(self.nameInput.Text) == name then
		self.baseName = name
	end
	if trim(self.fovInput.Text) == self.baseFov and self.baseFov ~= fovText then
		setFieldText(self, self.fovInput, fovText)
		self.baseFov = fovText
	end
	if trim(self.fovInput.Text) == fovText then
		self.baseFov = fovText
	end
	evaluate(self, false)
end

function ShotEditPanel.hide(self: Panel)
	self.editingPart = nil
	self.root.Visible = false
end

function ShotEditPanel.setError(self: Panel, message: string?)
	if message == nil then
		self.errorLabel.Text = ""
		self.errorLabel.Visible = false
	else
		self.errorLabel.Text = message
		self.errorLabel.Visible = true
	end
end

function ShotEditPanel.getEditingPart(self: Panel): BasePart?
	return self.editingPart
end

function ShotEditPanel.destroy(self: Panel)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.editingPart = nil
	self.root:Destroy()
end

return ShotEditPanel
