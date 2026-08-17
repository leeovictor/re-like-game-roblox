--!strict

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Workspace = game:GetService("Workspace")

local CameraSystemModel: any = require(script.camera.CameraSystemModel)
local CameraSystemPreview: any = require(script.camera.CameraSystemPreview)
local CameraSystemWidget: any = require(script.camera.CameraSystemWidget)
local pluginApi = plugin :: any

local toolbar = pluginApi:CreateToolbar("Camera System")
local toolbarButton = toolbar:CreateButton("Edit Camera System", "Edit persisted camera shots and zones", "")
toolbarButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, false, true, 320, 520, 280, 360)
local widget: any = nil
local preview: any = nil
local model: any = nil
local connections: { RBXScriptConnection } = {}

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function selectedPart(folder: Folder, instance: Instance?): BasePart?
	if instance ~= nil and instance:IsA("BasePart") and instance.Parent == folder then
		return instance
	end
	return nil
end

local function refresh()
	if widget == nil or preview == nil or model == nil then
		return
	end
	local hierarchy = model:ensureHierarchy()
	local shots = model:listShots()
	local zones = model:listZones()
	local defaultShotId = hierarchy.root:GetAttribute("DefaultShotId")
	local defaultId = if type(defaultShotId) == "string" then defaultShotId else nil
	widget:refresh(shots, zones, defaultId, model:validate())
	preview:refresh(shots, zones)
end

local function run(label: string, operation: () -> ())
	local success, failure = pcall(function()
		operation()
	end)
	if not success then
		warn(string.format("Camera System: %s failed: %s", label, tostring(failure)))
	end
	refresh()
end

local function closeWidget()
	disconnectAll()
	if preview ~= nil then
		preview:clear()
	end
	if widget ~= nil then
		widget:destroy()
	end
	widget = nil
	preview = nil
	model = nil
end

local function openWidget()
	if widget ~= nil then
		return
	end

	model = CameraSystemModel.new(Workspace, Selection, ChangeHistoryService)
	model:ensureHierarchy()
	preview = CameraSystemPreview.new(Workspace)

	local callbacks = {
		onNewShot = function()
			local name = widget :: any
			run("New Shot", function()
				local camera = Workspace.CurrentCamera
				local shotName = name.nameInput.Text
				assert(shotName ~= "", "Enter a name first")
				local currentModel = model :: any
				currentModel:createShot(shotName, camera)
			end)
		end,
		onCaptureCamera = function()
			run("Capture Camera", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local shot = selectedPart(hierarchy.shots, (widget :: any).shotSelection)
				local camera = Workspace.CurrentCamera
				assert(shot ~= nil, "Select a shot first")
				local currentModel = model :: any
				currentModel:captureCamera(shot :: BasePart, camera)
			end)
		end,
		onApplyCamera = function()
			run("Apply To Camera", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local shot = selectedPart(hierarchy.shots, (widget :: any).shotSelection)
				local camera = Workspace.CurrentCamera
				assert(shot ~= nil, "Select a shot first")
				local currentModel = model :: any
				currentModel:applyShot(shot :: BasePart, camera)
			end)
		end,
		onSetDefault = function()
			run("Set Default", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local shot = selectedPart(hierarchy.shots, (widget :: any).shotSelection)
				assert(shot ~= nil, "Select a shot first")
				local currentModel = model :: any
				currentModel:setDefaultShot(shot :: BasePart)
			end)
		end,
		onNewZone = function()
			local currentWidget = widget :: any
			run("New Zone", function()
				local camera = Workspace.CurrentCamera
				local zoneName = currentWidget.nameInput.Text
				assert(zoneName ~= "", "Enter a name first")
				local currentModel = model :: any
				currentModel:createZone(zoneName, CFrame.new(camera.Focus.Position), Vector3.new(10, 10, 10))
			end)
		end,
		onAssignShot = function()
			run("Assign Shot", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local currentWidget = widget :: any
				local zone = selectedPart(hierarchy.zones, currentWidget.zoneSelection)
				local shot = selectedPart(hierarchy.shots, currentWidget.shotSelection)
				assert(zone ~= nil and shot ~= nil, "Select a zone and a shot first")
				local currentModel = model :: any
				currentModel:assignShot(zone :: BasePart, shot :: BasePart)
			end)
		end,
		onMoveZone = function(delta: number)
			run("Move Zone", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local zone = selectedPart(hierarchy.zones, (widget :: any).zoneSelection)
				assert(zone ~= nil, "Select a zone first")
				local currentModel = model :: any
				currentModel:reorderZone(zone :: BasePart, delta)
			end)
		end,
		onFieldOfView = function(value: number)
			run("Set FieldOfView", function()
				local hierarchy = (model :: any):ensureHierarchy()
				local shot = selectedPart(hierarchy.shots, (widget :: any).shotSelection)
				assert(shot ~= nil, "Select a shot first")
				local currentModel = model :: any
				currentModel:setFieldOfView(shot :: BasePart, value)
			end)
		end,
		onSelect = function(instance: Instance)
			(Selection :: any):Set({ instance })
			if widget ~= nil then
				widget:setSelection(instance)
			end
		end,
		classifySelection = function(instance: Instance): string?
			local hierarchy = (model :: any):ensureHierarchy()
			if instance:IsA("BasePart") and instance.Parent == hierarchy.shots then
				return "shot"
			elseif instance:IsA("BasePart") and instance.Parent == hierarchy.zones then
				return "zone"
			end
			return nil
		end,
	}

	local gui = pluginApi:CreateDockWidgetPluginGui("CameraSystem", widgetInfo) :: DockWidgetPluginGui
	widget = CameraSystemWidget.new(gui, callbacks)
	widget.gui.BindToClose(function()
		closeWidget()
	end)
	table.insert(connections, Selection.SelectionChanged:Connect(function()
		local instances = (Selection :: any):Get()
		local instance = instances[1]
		if widget ~= nil then
			widget:setSelection(instance)
		end
		refresh()
	end))
	local hierarchy = model:ensureHierarchy()
	for _, signal in { hierarchy.root.DescendantAdded, hierarchy.root.DescendantRemoving, hierarchy.root.AttributeChanged } do
		table.insert(connections, signal:Connect(refresh))
	end
	local function watchPart(instance: Instance)
		if instance:IsA("BasePart") then
			table.insert(connections, instance:GetPropertyChangedSignal("CFrame"):Connect(refresh))
			table.insert(connections, instance:GetPropertyChangedSignal("Size"):Connect(refresh))
			table.insert(connections, instance.AttributeChanged:Connect(refresh))
		end
	end
	for _, instance in hierarchy.root:GetDescendants() do
		watchPart(instance)
	end
	table.insert(connections, hierarchy.root.DescendantAdded:Connect(function(instance)
		watchPart(instance)
		refresh()
	end))
	refresh()
	widget.gui.Enabled = true
end

toolbarButton.Click:Connect(function()
	if widget == nil then
		openWidget()
	else
		(widget :: any).gui.Enabled = not (widget :: any).gui.Enabled
		if not (widget :: any).gui.Enabled then
			closeWidget()
		end
	end
end)
