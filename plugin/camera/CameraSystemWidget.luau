--!strict

local CameraSystemWidget = {}
CameraSystemWidget.__index = CameraSystemWidget

type Callbacks = {
	onNewShot: () -> (),
	onCaptureCamera: () -> (),
	onApplyCamera: () -> (),
	onSetDefault: () -> (),
	onNewZone: () -> (),
	onAssignShot: () -> (),
	onMoveZone: (number) -> (),
	onFieldOfView: (number) -> (),
	onSelect: (Instance) -> (),
}

export type Widget = typeof(setmetatable({} :: {
	gui: DockWidgetPluginGui,
	callbacks: Callbacks,
	shotRows: { TextButton },
	zoneRows: { TextButton },
	shotSelection: BasePart?,
	zoneSelection: BasePart?,
	nameInput: TextBox,
	shotIdInput: TextBox,
	fovInput: TextBox,
	status: TextLabel,
	actionButtons: { [string]: TextButton },
	}, CameraSystemWidget))

local function make(className: string, parent: Instance): Instance
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local function styleButton(button: TextButton)
	button.BackgroundColor3 = Color3.fromRGB(45, 48, 55)
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.TextSize = 13
	button.AutoButtonColor = true
end

local function makeButton(parent: Instance, text: string, callback: () -> ()): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, 26)
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

local function makeInput(parent: Instance, placeholder: string): TextBox
	local input = make("TextBox", parent) :: TextBox
	input.Size = UDim2.new(1, 0, 0, 26)
	input.PlaceholderText = placeholder
	input.Text = ""
	input.ClearTextOnFocus = false
	input.TextColor3 = Color3.fromRGB(235, 235, 235)
	input.BackgroundColor3 = Color3.fromRGB(32, 34, 39)
	input.BorderSizePixel = 0
	return input
end

function CameraSystemWidget.new(widgetInfo: DockWidgetPluginGuiInfo, callbacks: Callbacks): Widget
	local gui = (plugin :: any):CreateDockWidgetPluginGui("CameraSystem", widgetInfo) :: DockWidgetPluginGui
	gui.Title = "Camera System"

	local root = make("ScrollingFrame", gui) :: ScrollingFrame
	root.Size = UDim2.fromScale(1, 1)
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 8
	root.BackgroundColor3 = Color3.fromRGB(24, 25, 29)
	root.BorderSizePixel = 0
	local rootLayout = make("UIListLayout", root) :: UIListLayout
	rootLayout.Padding = UDim.new(0, 6)
	local padding = make("UIPadding", root) :: UIPadding
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)

	local actions = makeSection(root, "Actions")
	local nameInput = makeInput(actions, "Name for new shot or zone")
	makeButton(actions, "New Shot", callbacks.onNewShot)
	local captureButton = makeButton(actions, "Capture Camera", callbacks.onCaptureCamera)
	local applyButton = makeButton(actions, "Apply To Camera", callbacks.onApplyCamera)
	local defaultButton = makeButton(actions, "Set Default", callbacks.onSetDefault)
	makeButton(actions, "New Zone", callbacks.onNewZone)

	local shotsSection = makeSection(root, "Shots")
	local fovInput = makeInput(shotsSection, "Field of View (1-120)")
	local fovButton = makeButton(shotsSection, "Set FOV", function()
		local value = tonumber(fovInput.Text)
		if value ~= nil then
			callbacks.onFieldOfView(value)
		end
	end)
	fovButton.Name = "SetFieldOfView"

	local zonesSection = makeSection(root, "Zones")
	local shotIdInput = makeInput(zonesSection, "ShotId")
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
	status.TextColor3 = Color3.fromRGB(255, 170, 120)
	status.BackgroundTransparency = 1
	status.TextSize = 12

	return setmetatable({
		gui = gui,
		callbacks = callbacks,
		shotRows = {},
		zoneRows = {},
		shotSelection = nil,
		zoneSelection = nil,
		nameInput = nameInput,
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
		},
	}, CameraSystemWidget) :: Widget
end

function CameraSystemWidget.setSelection(self: Widget, instance: Instance?)
	self.shotSelection = nil
	self.zoneSelection = nil
	if instance ~= nil and instance:IsA("BasePart") then
		if instance.Parent ~= nil and instance.Parent.Name == "Shots" then
			self.shotSelection = instance
			self.fovInput.Text = tostring(instance:GetAttribute("FieldOfView") or "")
		elseif instance.Parent ~= nil and instance.Parent.Name == "Zones" then
			self.zoneSelection = instance
			self.shotIdInput.Text = tostring(instance:GetAttribute("ShotId") or "")
		end
	end
	for _, row in self.shotRows do
		row.BackgroundColor3 = if row:GetAttribute("InstanceName") == if self.shotSelection then self.shotSelection.Name else "" then Color3.fromRGB(70, 90, 125) else Color3.fromRGB(45, 48, 55)
	end
	for _, row in self.zoneRows do
		row.BackgroundColor3 = if row:GetAttribute("InstanceName") == if self.zoneSelection then self.zoneSelection.Name else "" then Color3.fromRGB(70, 90, 125) else Color3.fromRGB(45, 48, 55)
	end
	local hasShot = self.shotSelection ~= nil
	local hasZone = self.zoneSelection ~= nil
	for name, button in self.actionButtons do
		local enabled = if name == "assign" then hasShot and hasZone elseif name == "moveUp" or name == "moveDown" then hasZone elseif name == "fov" or name == "capture" or name == "apply" or name == "default" then hasShot else true
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.TextTransparency = if enabled then 0 else 0.5
	end
end

function CameraSystemWidget.refresh(self: Widget, shots: { BasePart }, zones: { BasePart }, defaultShotId: string?, errors: { string })
	for _, row in self.shotRows do
		row:Destroy()
	end
	for _, row in self.zoneRows do
		row:Destroy()
	end
	table.clear(self.shotRows)
	table.clear(self.zoneRows)

	for _, shot in shots do
		local row = make("TextButton", self.gui:FindFirstChild("ScrollingFrame") :: Instance) :: TextButton
		row.Name = "Shot_" .. shot.Name
		row.Text = string.format("Shot: %s%s", shot.Name, if shot.Name == defaultShotId then " (default)" else "")
		row.Size = UDim2.new(1, -12, 0, 24)
		row:SetAttribute("InstanceName", shot.Name)
		styleButton(row)
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
		row:SetAttribute("InstanceName", zone.Name)
		styleButton(row)
		row.Activated:Connect(function()
			self.zoneSelection = zone
			self.callbacks.onSelect(zone)
		end)
		table.insert(self.zoneRows, row)
	end

	self.status.Text = if #errors == 0 then "Valid camera system" else table.concat(errors, "\n")
	self:setSelection(if self.shotSelection then self.shotSelection else self.zoneSelection)
end

function CameraSystemWidget.destroy(self: Widget)
	self.gui:Destroy()
end

return CameraSystemWidget
