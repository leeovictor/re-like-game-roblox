--!strict

local CameraSystemDialog = require(script.Parent.CameraSystemDialog)
local CameraSystemStyle = require(script.Parent.CameraSystemStyle)
local ShotEditPanel = require(script.Parent.ShotEditPanel)
local ShotSelector = require(script.Parent.ShotSelector)
local TextInput = require(script.Parent.TextInput)
local ZoneEditPanel = require(script.Parent.ZoneEditPanel)

local CameraSystemWidget = {}
CameraSystemWidget.__index = CameraSystemWidget

export type TabName = "shots" | "zones"

type Callbacks = {
	onCreateShot: (string, number) -> (),
	onCreateZone: (string, string) -> (),
	onCaptureCamera: (BasePart) -> (),
	onApplyCamera: (BasePart) -> (),
	onSetDefault: (BasePart) -> (),
	onMoveZone: (BasePart, number) -> (),
	onSaveShot: (BasePart, string, number) -> (),
	onSaveZone: (BasePart, string, string) -> (),
	onDeleteShot: (BasePart) -> (),
	onDeleteZone: (BasePart) -> (),
	onSelect: (Instance) -> (),
	classifySelection: (Instance) -> string?,
	getDefaultFieldOfView: () -> number,
}

export type Widget = typeof(setmetatable(
	{} :: {
		gui: DockWidgetPluginGui,
		callbacks: Callbacks,
		activeTab: TabName,
		shotsContent: ScrollingFrame,
		zonesContent: ScrollingFrame,
		shotsTab: TextButton,
		zonesTab: TextButton,
		shotsEmpty: TextLabel,
		zonesEmpty: TextLabel,
		newZoneButton: TextButton,
		status: TextLabel,
		shotPanel: ShotEditPanel.Panel,
		zonePanel: ZoneEditPanel.Panel,
		shotRows: { TextButton },
		zoneRows: { TextButton },
		rowInstances: { [TextButton]: BasePart },
		shotSelection: BasePart?,
		zoneSelection: BasePart?,
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

local function makeButton(parent: Instance, text: string, callback: () -> ()): TextButton
	local button = make("TextButton", parent) :: TextButton
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	styleButton(button, CameraSystemStyle.panel)
	button.Activated:Connect(callback)
	return button
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

local function makeEmptyLabel(parent: Instance, text: string): TextLabel
	local label = make("TextLabel", parent) :: TextLabel
	label.Name = "Empty"
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = CameraSystemStyle.mutedText
	label.TextSize = CameraSystemStyle.smallTextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = 2
	return label
end

local function makeList(parent: Instance, name: string): ScrollingFrame
	local list = make("ScrollingFrame", parent) :: ScrollingFrame
	list.Name = name
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	local layout = make("UIListLayout", list) :: UIListLayout
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local padding = make("UIPadding", list) :: UIPadding
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	return list
end

local function styleTab(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then CameraSystemStyle.accent else CameraSystemStyle.panel
	button.BorderSizePixel = 0
	button.TextColor3 = CameraSystemStyle.text
	button.TextSize = CameraSystemStyle.textSize
	button.AutoButtonColor = true
end

local function formatNameList(names: { string }): string
	local quoted: { string } = {}
	for _, name in names do
		table.insert(quoted, string.format('"%s"', name))
	end
	return table.concat(quoted, ", ")
end

function CameraSystemWidget.new(gui: DockWidgetPluginGui, callbacks: Callbacks): Widget
	gui.Title = "Camera System"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = make("Frame", gui) :: Frame
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = CameraSystemStyle.background
	root.BorderSizePixel = 0
	local rootLayout = make("UIListLayout", root) :: UIListLayout
	rootLayout.Padding = UDim.new(0, 6)
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local rootPadding = make("UIPadding", root) :: UIPadding
	rootPadding.PaddingTop = UDim.new(0, 6)
	rootPadding.PaddingBottom = UDim.new(0, 6)
	rootPadding.PaddingLeft = UDim.new(0, 6)
	rootPadding.PaddingRight = UDim.new(0, 6)

	local widgetRef: Widget? = nil

	local tabBar = make("Frame", root) :: Frame
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, CameraSystemStyle.buttonHeight)
	tabBar.BackgroundTransparency = 1
	tabBar.LayoutOrder = 1
	local tabLayout = make("UIListLayout", tabBar) :: UIListLayout
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local shotsTab = make("TextButton", tabBar) :: TextButton
	shotsTab.Name = "ShotsTab"
	shotsTab.Text = "Shots"
	shotsTab.Size = UDim2.new(0.5, -3, 1, 0)
	shotsTab.LayoutOrder = 1
	styleTab(shotsTab, true)

	local zonesTab = make("TextButton", tabBar) :: TextButton
	zonesTab.Name = "ZonesTab"
	zonesTab.Text = "Zones"
	zonesTab.Size = UDim2.new(0.5, -3, 1, 0)
	zonesTab.LayoutOrder = 2
	styleTab(zonesTab, false)

	local contentArea = make("Frame", root) :: Frame
	contentArea.Name = "ContentArea"
	contentArea.Size = UDim2.new(1, 0, 0, 0)
	contentArea.BackgroundTransparency = 1
	contentArea.LayoutOrder = 2
	local flex = make("UIFlexItem", contentArea) :: UIFlexItem
	flex.FlexMode = Enum.UIFlexMode.Fill

	local shotsContent = makeList(contentArea, "ShotsContent")
	local newShotButton = makeButton(shotsContent, "New Shot", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewShotDialog()
		end
	end)
	newShotButton.LayoutOrder = 1
	local shotsEmpty = makeEmptyLabel(shotsContent, "No shots yet")

	local zonesContent = makeList(contentArea, "ZonesContent")
	zonesContent.Visible = false
	local newZoneButton = makeButton(zonesContent, "New Zone", function()
		local current = widgetRef
		if current ~= nil then
			current:openNewZoneDialog()
		end
	end)
	newZoneButton.LayoutOrder = 1
	local zonesEmpty = makeEmptyLabel(zonesContent, "No zones yet")

	local status = make("TextLabel", root) :: TextLabel
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = CameraSystemStyle.errorText
	status.BackgroundTransparency = 1
	status.TextSize = CameraSystemStyle.smallTextSize
	status.LayoutOrder = 3

	local shotPanel = ShotEditPanel.new(root, {
		onApply = function(shot: BasePart)
			callbacks.onApplyCamera(shot)
		end,
		onCapture = function(shot: BasePart)
			callbacks.onCaptureCamera(shot)
		end,
		onSetDefault = function(shot: BasePart)
			callbacks.onSetDefault(shot)
		end,
		onDelete = function(shot: BasePart)
			local current = widgetRef
			if current ~= nil then
				current:requestDeleteShot(shot)
			end
		end,
		onSave = function(shot: BasePart, name: string, fieldOfView: number)
			callbacks.onSaveShot(shot, name, fieldOfView)
		end,
		onClose = function()
			local current = widgetRef
			if current ~= nil then
				current:closeShotPanel()
			end
		end,
	})
	shotPanel.root.LayoutOrder = 4

	local zonePanel = ZoneEditPanel.new(root, {
		onMoveUp = function(zone: BasePart)
			callbacks.onMoveZone(zone, -1)
		end,
		onMoveDown = function(zone: BasePart)
			callbacks.onMoveZone(zone, 1)
		end,
		onDelete = function(zone: BasePart)
			local current = widgetRef
			if current ~= nil then
				current:requestDeleteZone(zone)
			end
		end,
		onSave = function(zone: BasePart, name: string, shotName: string)
			callbacks.onSaveZone(zone, name, shotName)
		end,
		onClose = function()
			local current = widgetRef
			if current ~= nil then
				current:closeZonePanel()
			end
		end,
	})
	zonePanel.root.LayoutOrder = 5

	local widget = setmetatable({
		gui = gui,
		callbacks = callbacks,
		activeTab = "shots" :: TabName,
		shotsContent = shotsContent,
		zonesContent = zonesContent,
		shotsTab = shotsTab,
		zonesTab = zonesTab,
		shotsEmpty = shotsEmpty,
		zonesEmpty = zonesEmpty,
		newZoneButton = newZoneButton,
		status = status,
		shotPanel = shotPanel,
		zonePanel = zonePanel,
		shotRows = {},
		zoneRows = {},
		rowInstances = {},
		shotSelection = nil,
		zoneSelection = nil,
		shots = {},
		zones = {},
		defaultShotId = nil,
		dialog = nil,
	}, CameraSystemWidget) :: Widget

	widgetRef = widget

	shotsTab.Activated:Connect(function()
		local current = widgetRef
		if current ~= nil then
			current:setActiveTab("shots")
		end
	end)
	zonesTab.Activated:Connect(function()
		local current = widgetRef
		if current ~= nil then
			current:setActiveTab("zones")
		end
	end)

	return widget
end

function CameraSystemWidget.setActiveTab(self: Widget, tab: TabName)
	self.activeTab = tab
	local shotsActive = tab == "shots"
	self.shotsContent.Visible = shotsActive
	self.zonesContent.Visible = not shotsActive
	styleTab(self.shotsTab, shotsActive)
	styleTab(self.zonesTab, not shotsActive)
	self:updatePanels()
end

function CameraSystemWidget.updateRows(self: Widget)
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
end

function CameraSystemWidget.updatePanels(self: Widget)
	local shot = self.shotSelection
	if self.activeTab == "shots" and shot ~= nil then
		if self.shotPanel:getEditingPart() ~= shot then
			self.shotPanel:show(shot)
		else
			self.shotPanel:update(shot)
		end
	elseif self.shotPanel.root.Visible then
		self.shotPanel:hide()
	end

	local zone = self.zoneSelection
	if self.activeTab == "zones" and zone ~= nil then
		local names: { string } = {}
		for _, item in self.shots do
			table.insert(names, item.Name)
		end
		local index = table.find(self.zones, zone)
		local canMoveUp = index ~= nil and index > 1
		local canMoveDown = index ~= nil and index < #self.zones
		if self.zonePanel:getEditingPart() ~= zone then
			self.zonePanel:show(zone, names, self.defaultShotId)
		end
		self.zonePanel:update(zone, names, self.defaultShotId, canMoveUp, canMoveDown)
	elseif self.zonePanel.root.Visible then
		self.zonePanel:hide()
	end
end

function CameraSystemWidget.setSelection(self: Widget, instance: Instance?)
	local selectionKind = if instance == nil then nil else self.callbacks.classifySelection(instance)
	if selectionKind == "shot" and instance ~= nil and instance:IsA("BasePart") then
		self.shotSelection = instance
		self:setActiveTab("shots")
	elseif selectionKind == "zone" and instance ~= nil and instance:IsA("BasePart") then
		self.zoneSelection = instance
		self:setActiveTab("zones")
	elseif selectionKind == nil then
		self:clearSelection()
	end
	self:updateRows()
end

function CameraSystemWidget.clearSelection(self: Widget)
	self.shotSelection = nil
	self.zoneSelection = nil
	self.shotPanel:hide()
	self.zonePanel:hide()
	self:updateRows()
end

function CameraSystemWidget.closeShotPanel(self: Widget)
	self.shotSelection = nil
	self.shotPanel:hide()
	self:updateRows()
end

function CameraSystemWidget.closeZonePanel(self: Widget)
	self.zoneSelection = nil
	self.zonePanel:hide()
	self:updateRows()
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

	for index, shot in shots do
		local row = make("TextButton", self.shotsContent) :: TextButton
		row.Name = "Shot_" .. shot.Name
		row.Text = string.format("Shot: %s%s", shot.Name, if shot.Name == defaultShotId then " (default)" else "")
		row.Size = UDim2.new(1, -12, 0, 24)
		row.LayoutOrder = index + 2
		styleButton(row, CameraSystemStyle.panel)
		self.rowInstances[row] = shot
		row.Activated:Connect(function()
			self.shotSelection = shot
			self:setActiveTab("shots")
			self:updateRows()
			self.callbacks.onSelect(shot)
		end)
		table.insert(self.shotRows, row)
	end

	for index, zone in zones do
		local row = make("TextButton", self.zonesContent) :: TextButton
		row.Name = "Zone_" .. zone.Name
		row.Text = string.format("Zone: %s -> %s", zone.Name, tostring(zone:GetAttribute("ShotId") or "<unassigned>"))
		row.Size = UDim2.new(1, -12, 0, 24)
		row.LayoutOrder = index + 2
		styleButton(row, CameraSystemStyle.panel)
		self.rowInstances[row] = zone
		row.Activated:Connect(function()
			self.zoneSelection = zone
			self:setActiveTab("zones")
			self:updateRows()
			self.callbacks.onSelect(zone)
		end)
		table.insert(self.zoneRows, row)
	end

	self.shotsEmpty.Visible = #shots == 0
	self.zonesEmpty.Visible = #zones == 0
	setButtonEnabled(self.newZoneButton, #shots > 0)
	self.status.Text = if #errors == 0 then "Valid camera system" else table.concat(errors, "\n")

	if self.shotSelection ~= nil and table.find(shots, self.shotSelection) == nil then
		self.shotSelection = nil
		self.shotPanel:hide()
	end
	if self.zoneSelection ~= nil and table.find(zones, self.zoneSelection) == nil then
		self.zoneSelection = nil
		self.zonePanel:hide()
	end

	self:updateRows()
	self:updatePanels()
end

function CameraSystemWidget.closeDialog(self: Widget)
	if self.dialog == nil then
		return
	end
	local dialog = self.dialog
	self.dialog = nil
	dialog:destroy()
end

function CameraSystemWidget.openConfirmDialog(self: Widget, title: string, message: string, onConfirm: () -> ())
	self:closeDialog()
	local created = CameraSystemDialog.new(self.gui, title, {
		onCancel = function()
			self.dialog = nil
		end,
		onConfirm = function()
			self.dialog = nil
			onConfirm()
		end,
	}, { confirmText = "Delete", cancelText = "Cancel" })
	self.dialog = created
	makeLabel(created.content, message, 1)
end

function CameraSystemWidget.requestDeleteShot(self: Widget, shot: BasePart)
	local referencing: { string } = {}
	for _, zone in self.zones do
		if zone:GetAttribute("ShotId") == shot.Name then
			table.insert(referencing, zone.Name)
		end
	end
	if #referencing > 0 then
		self.shotPanel:setError(string.format("Cannot delete: referenced by zones %s", formatNameList(referencing)))
		return
	end
	self:openConfirmDialog("Delete Shot", string.format('Delete shot "%s"?', shot.Name), function()
		self.callbacks.onDeleteShot(shot)
	end)
end

function CameraSystemWidget.requestDeleteZone(self: Widget, zone: BasePart)
	self:openConfirmDialog("Delete Zone", string.format('Delete zone "%s"?', zone.Name), function()
		self.callbacks.onDeleteZone(zone)
	end)
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
	shotSelector:setOptions(names, self.defaultShotId, self.defaultShotId)

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
