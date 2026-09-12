--!strict

local CameraSystemDialog = require(script.Parent.CameraSystemDialog)
local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotSelector = require(script.Parent.ShotSelector)
local TextInput = require(script.Parent.TextInput)

local CameraSystemWidget = {}
CameraSystemWidget.__index = CameraSystemWidget

type Callbacks = {
	onCreateShot: (string, number) -> (),
	onCreateZone: (string, string) -> (),
	onCaptureCamera: () -> (),
	onApplyCamera: () -> (),
	onSetDefault: () -> (),
	onAssignShot: () -> (),
	onMoveZone: (number) -> (),
	onFieldOfView: (number) -> (),
	onSelect: (Instance) -> (),
	classifySelection: (Instance) -> string?,
	getDefaultFieldOfView: () -> number,
}

export type Widget = typeof(setmetatable(
	{} :: {
		gui: DockWidgetPluginGui,
		callbacks: Callbacks,
		shotRows: { TextButton },
		zoneRows: { TextButton },
		rowInstances: { [TextButton]: BasePart },
		shotSelection: BasePart?,
		zoneSelection: BasePart?,
		shotIdInput: TextBox,
		fovInput: TextBox,
		status: TextLabel,
		actionButtons: { [string]: TextButton },
		shots: { BasePart },
		zones: { BasePart },
		defaultShotId: string?,
		dialog: CameraSystemDialog.Dialog?,
	},
	CameraSystemWidget
))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function trim(value: string): string
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function styleButton(button: TextButton)
	button.BackgroundColor3 = CameraSystemStyle.panel
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function makeButton(parent: Instance, text: string, callback: () -> ()): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	styleButton(button)
	button.Activated:Connect(callback)
	return button
end

local function makeSection(parent: Instance, title: string): (Frame, UIListLayout)
	local section = make("Frame", parent) :: Frame
	section.Name = title
	section.Size = UDim2.new(1, -12, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	local layout = make("UIListLayout", section) :: UIListLayout
	layout.Padding = UDim.new(0, 4)
	return section, layout
end

local function makeLabel(parent: Instance, text: string, order: number): TextLabel
	local label = make("TextLabel", parent) :: TextLabel
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = CameraSystemStyle.text
	label.TextSize = CameraSystemStyle.textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	return label
end

function CameraSystemWidget.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Widget
	gui.Title = "Camera System"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = make("ScrollingFrame", gui) :: ScrollingFrame
	root.Size = UDim2.fromScale(1, 1)
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 8
	root.BackgroundColor3 = CameraSystemStyle.background
	root.BorderSizePixel = 0
	local rootLayout = make("UIListLayout", root) :: UIListLayout
	rootLayout.Padding = UDim.new(0, 6)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)

	local widgetRef: Widget? = nil

	local actions = makeSection(root, "Actions")
	makeButton(actions, "New Shot", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewShotDialog()
		end
	end)
	local captureButton = makeButton(actions, "Capture Camera", callbacks.onCaptureCamera)
	local applyButton = makeButton(actions, "Apply To Camera", callbacks.onApplyCamera)
	local defaultButton = makeButton(actions, "Set Default", callbacks.onSetDefault)
	local newZoneButton = makeButton(actions, "New Zone", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewZoneDialog()
		end
	end)

	local shotsSection = makeSection(root, "Shots")
	local fovInput = TextInput.new(shotsSection, { placeholder = "Field of View (1-120)" })
	local fovButton = makeButton(shotsSection, "Set FOV", function()
		local value = tonumber(fovInput.Text)
		if value ~= nil then
			callbacks.onFieldOfView(value)
		end
	end)
	fovButton.Name = "SetFieldOfView"

	local zonesSection = makeSection(root, "Zones")
	local shotIdInput = TextInput.new(zonesSection, { placeholder = "ShotId" })
	local assignButton = makeButton(zonesSection, "Assign Shot", callbacks.onAssignShot)
	local moveUpButton = makeButton(zonesSection, "Move Up", function()
		callbacks.onMoveZone(-1)
	end)
	local moveDownButton = makeButton(zonesSection, "Move Down", function()
		callbacks.onMoveZone(1)
	end)

	local status = make("TextLabel", root) :: TextLabel
	status.Name = "Status"
	status.Size = UDim2.new(1, -12, 0, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = CameraSystemStyle.errorText
	status.BackgroundTransparency = 1
	status.TextSize = CameraSystemStyle.smallTextSize

	local widget = setmetatable({
		gui = gui,
		callbacks = callbacks,
		shotRows = {},
		zoneRows = {},
		rowInstances = {},
		shotSelection = nil,
		zoneSelection = nil,
		shotIdInput = shotIdInput,
		fovInput = fovInput,
		status = status,
		actionButtons = {
			capture = captureButton,
			apply = applyButton,
			default = defaultButton,
			assign = assignButton,
			moveUp = moveUpButton,
			moveDown = moveDownButton,
			fov = fovButton,
			newZone = newZoneButton,
		},
		shots = {},
		zones = {},
		defaultShotId = nil,
		dialog = nil,
	}, CameraSystemWidget) :: Widget

	widgetRef = widget
	return widget
end

function CameraSystemWidget.setSelection(self: Widget, instance: Instance?)
	local selectionKind = if instance == nil then nil else self.callbacks.classifySelection(instance)
	if selectionKind == "shot" and instance ~= nil and instance:IsA("BasePart") then
		self.shotSelection = instance
		self.fovInput.Text = tostring(instance:GetAttribute("FieldOfView") or "")
	elseif selectionKind == "zone" and instance ~= nil and instance:IsA("BasePart") then
		self.zoneSelection = instance
		self.shotIdInput.Text = tostring(instance:GetAttribute("ShotId") or "")
	elseif selectionKind == nil then
		self.shotSelection = nil
		self.zoneSelection = nil
	end
	self:updateSelectionVisuals()
end

function CameraSystemWidget.clearSelection(self: Widget)
	self.shotSelection = nil
	self.zoneSelection = nil
	self.fovInput.Text = ""
	self.shotIdInput.Text = ""
	self:updateSelectionVisuals()
end

function CameraSystemWidget.updateSelectionVisuals(self: Widget)
	for _, row in self.shotRows do
		row.BackgroundColor3 = if self.rowInstances[row] == self.shotSelection
			then CameraSystemStyle.accent
			else CameraSystemStyle.panel
	end
	for _, row in self.zoneRows do
		row.BackgroundColor3 = if self.rowInstances[row] == self.zoneSelection
			then CameraSystemStyle.accent
			else CameraSystemStyle.panel
	end
	local hasShot = self.shotSelection ~= nil
	local hasZone = self.zoneSelection ~= nil
	for name, button in self.actionButtons do
		local enabled = if name == "assign"
			then hasShot and hasZone
			elseif name == "moveUp" or name == "moveDown" then hasZone
			elseif name == "fov" or name == "capture" or name == "apply" or name == "default" then hasShot
			elseif name == "newZone" then #self.shots > 0
			else true
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.TextTransparency = if enabled then 0 else 0.5
	end
end

function CameraSystemWidget.refresh(
	self: Widget,
	shots: { BasePart },
	zones: { BasePart },
	defaultShotId: string?,
	errors: { string }
)
	self.shots = shots
	self.zones = zones
	self.defaultShotId = defaultShotId

	for _, row in self.shotRows do
		row:Destroy()
	end
	for _, row in self.zoneRows do
		row:Destroy()
	end
	table.clear(self.shotRows)
	table.clear(self.zoneRows)
	table.clear(self.rowInstances)

	for _, shot in shots do
		local row = make("TextButton", self.gui:FindFirstChild("ScrollingFrame") :: Instance) :: TextButton
		row.Name = "Shot_" .. shot.Name
		row.Text = string.format("Shot: %s%s", shot.Name, if shot.Name == defaultShotId then " (default)" else "")
		row.Size = UDim2.new(1, -12, 0, 24)
		styleButton(row)
		self.rowInstances[row] = shot
		row.Activated:Connect(function()
			self.shotSelection = shot
			self.callbacks.onSelect(shot)
		end)
		table.insert(self.shotRows, row)
	end

	for _, zone in zones do
		local row = make("TextButton", self.gui:FindFirstChild("ScrollingFrame") :: Instance) :: TextButton
		row.Name = "Zone_" .. zone.Name
		row.Text = string.format("Zone: %s -> %s", zone.Name, tostring(zone:GetAttribute("ShotId") or "<unassigned>"))
		row.Size = UDim2.new(1, -12, 0, 24)
		styleButton(row)
		self.rowInstances[row] = zone
		row.Activated:Connect(function()
			self.zoneSelection = zone
			self.callbacks.onSelect(zone)
		end)
		table.insert(self.zoneRows, row)
	end

	self.status.Text = if #errors == 0 then "Valid camera system" else table.concat(errors, "\n")
	self:updateSelectionVisuals()
end

function CameraSystemWidget.closeDialog(self: Widget)
	if self.dialog == nil then
		return
	end
	local dialog = self.dialog
	self.dialog = nil
	dialog:destroy()
end

function CameraSystemWidget.openNewShotDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local shotNameInput: TextBox? = nil
	local shotFovInput: TextBox? = nil

	local function nameAlreadyExists(name: string): boolean
		for _, shot in self.shots do
			if shot.Name == name then
				return true
			end
		end
		return false
	end

	local function evaluate()
		local currentDialog = dialog
		local currentInput = shotNameInput
		local currentFovInput = shotFovInput
		if currentDialog == nil or currentInput == nil or currentFovInput == nil then
			return
		end
		local name = trim(currentInput.Text)
		local duplicate = name ~= "" and nameAlreadyExists(name)
		local fieldOfView = tonumber(currentFovInput.Text)
		local validFieldOfView = fieldOfView ~= nil and fieldOfView >= 1 and fieldOfView <= 120
		if duplicate then
			currentDialog:setError(string.format('Shot "%s" already exists', name))
		elseif not validFieldOfView then
			currentDialog:setError("FieldOfView must be between 1 and 120")
		else
			currentDialog:setError(nil)
		end
		currentDialog:setConfirmEnabled(name ~= "" and not duplicate and validFieldOfView)
	end

	local created = CameraSystemDialog.new(self.gui, "Create Shot", {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = shotNameInput
			local currentFovInput = shotFovInput
			if currentInput == nil or currentFovInput == nil then
				return
			end
			local name = trim(currentInput.Text)
			local fieldOfView = tonumber(currentFovInput.Text)
			if name ~= "" and fieldOfView ~= nil then
				self.callbacks.onCreateShot(name, fieldOfView)
			end
		end,
	})
	dialog = created
	self.dialog = created

	local input = TextInput.new(created.content, {
		placeholder = "Shot name",
		label = "Enter the shot name",
		layoutOrder = 1,
	})
	shotNameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)
	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		if enterPressed and currentDialog ~= nil then
			currentDialog:tryConfirm()
		end
	end)

	local fovInput = TextInput.new(created.content, {
		placeholder = "Field of View (1-120)",
		label = "Field of View (1-120)",
		value = tostring(self.callbacks.getDefaultFieldOfView()),
		layoutOrder = 2,
	})
	shotFovInput = fovInput
	fovInput:GetPropertyChangedSignal("Text"):Connect(evaluate)
	fovInput.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		if enterPressed and currentDialog ~= nil then
			currentDialog:tryConfirm()
		end
	end)

	created:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.openNewZoneDialog(self: Widget)
	self:closeDialog()

	local dialog: CameraSystemDialog.Dialog? = nil
	local zoneNameInput: TextBox? = nil
	local selector: ShotSelector.Selector? = nil

	local function nameAlreadyExists(name: string): boolean
		for _, zone in self.zones do
			if zone.Name == name then
				return true
			end
		end
		return false
	end

	local function evaluate()
		local currentDialog = dialog
		local currentInput = zoneNameInput
		local currentSelector = selector
		if currentDialog == nil or currentInput == nil or currentSelector == nil then
			return
		end
		local name = trim(currentInput.Text)
		local duplicate = name ~= "" and nameAlreadyExists(name)
		if duplicate then
			currentDialog:setError(string.format('Zone "%s" already exists', name))
		else
			currentDialog:setError(nil)
		end
		currentDialog:setConfirmEnabled(name ~= "" and not duplicate and currentSelector:getSelected() ~= nil)
	end

	local names: { string } = {}
	for _, shot in self.shots do
		table.insert(names, shot.Name)
	end

	local created = CameraSystemDialog.new(self.gui, "Create Zone", {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			local currentInput = zoneNameInput
			local currentSelector = selector
			if currentInput == nil or currentSelector == nil then
				return
			end
			local name = trim(currentInput.Text)
			local shotName = currentSelector:getSelected()
			if name ~= "" and shotName ~= nil then
				self.callbacks.onCreateZone(name, shotName)
			end
		end,
		canCancel = function()
			local currentSelector = selector
			return currentSelector == nil or not currentSelector:isOpen()
		end,
	})
	dialog = created
	self.dialog = created

	local input = TextInput.new(created.content, {
		placeholder = "Zone name",
		label = "Enter the zone name",
		layoutOrder = 1,
	})
	zoneNameInput = input
	input:GetPropertyChangedSignal("Text"):Connect(evaluate)

	makeLabel(created.content, "Select a shot", 2)
	local shotSelector = ShotSelector.new(created.content, evaluate)
	shotSelector.root.LayoutOrder = 3
	selector = shotSelector
	shotSelector:setOptions(names, self.defaultShotId)

	input.FocusLost:Connect(function(enterPressed)
		local currentDialog = dialog
		local currentSelector = selector
		if enterPressed and currentDialog ~= nil and currentSelector ~= nil and not currentSelector:isOpen() then
			currentDialog:tryConfirm()
		end
	end)
	created:focusFirstInput()
	evaluate()
end

function CameraSystemWidget.destroy(self: Widget)
	self:closeDialog()
	self.gui:Destroy()
end

return CameraSystemWidget
