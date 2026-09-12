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
local editorActive = false
local deactivating = false

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

local function ensureModel()
	if model == nil then
		model = CameraSystemModel.new(Workspace, Selection, ChangeHistoryService)
	end
	return model
end

local function persistParts(): boolean
	if model == nil then
		return false
	end
	local currentModel = model
	local success, failure = pcall(function()
		local config = currentModel:captureConfig()
		currentModel:writeData(config)
	end)
	if not success then
		warn(string.format("Camera System: persist parts failed: %s", tostring(failure)))
		return false
	end
	return true
end

local function removeParts(): boolean
	if model == nil then
		return false
	end
	local currentModel = model
	local success, failure = pcall(function()
		currentModel:destroyParts()
	end)
	if not success then
		warn(string.format("Camera System: remove parts failed: %s", tostring(failure)))
		return false
	end
	return true
end

local function normalizeInactiveState()
	local existing = Workspace:FindFirstChild("CameraSystem")
	if existing == nil or not existing:IsA("Folder") then
		return
	end
	local currentModel = ensureModel()
	currentModel:ensureHierarchy()
	if currentModel:hasParts() then
		if persistParts() then
			removeParts()
		end
	end
end

local function deactivateEditor()
	if deactivating or not editorActive then
		return
	end
	deactivating = true
	disconnectAll()
	if preview ~= nil then
		preview:clear()
	end
	if persistParts() then
		removeParts()
	end
	if widget ~= nil then
		widget:clearSelection()
	end
	if widget ~= nil then
		widget:closeDialog()
	end
	if widget ~= nil and widget.gui.Enabled then
		widget.gui.Enabled = false
	end
	editorActive = false
	deactivating = false
end

local function destroyEditor()
	deactivateEditor()
	if widget ~= nil then
		widget:destroy()
	end
	widget = nil
	preview = nil
	model = nil
end

local function activateEditor()
	if editorActive then
		return
	end

	ensureModel()

	if widget == nil then
		preview = CameraSystemPreview.new(Workspace)

		local callbacks = {
			getDefaultFieldOfView = function(): number
				return Workspace.CurrentCamera.FieldOfView
			end,
			onCreateShot = function(name: string, fieldOfView: number)
				run("New Shot", function()
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createShot(name, camera, fieldOfView)
				end)
			end,
			onCreateZone = function(name: string, shotName: string)
				run("New Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local shot = hierarchy.shots:FindFirstChild(shotName)
					assert(shot ~= nil and shot:IsA("BasePart"), string.format('Shot "%s" not found', shotName))
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:createZone(
						name,
						CFrame.new(camera.Focus.Position),
						Vector3.new(10, 10, 10),
						shot :: BasePart
					)
				end)
			end,
			onCaptureCamera = function(shot: BasePart)
				run("Capture Camera", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:captureCamera(ownedPart, camera)
				end)
			end,
			onApplyCamera = function(shot: BasePart)
				run("Apply To Camera", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local camera = Workspace.CurrentCamera
					local currentModel = model :: any
					currentModel:applyShot(ownedPart, camera)
				end)
			end,
			onSetDefault = function(shot: BasePart)
				run("Set Default", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local currentModel = model :: any
					currentModel:setDefaultShot(owned :: BasePart)
				end)
			end,
			onSaveShot = function(shot: BasePart, name: string, fieldOfView: number)
				run("Save Shot", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local ownedPart = owned :: BasePart
					local currentModel = model :: any
					if ownedPart.Name ~= name then
						currentModel:renameShot(ownedPart, name)
					end
					if ownedPart:GetAttribute("FieldOfView") ~= fieldOfView then
						currentModel:setFieldOfView(ownedPart, fieldOfView)
					end
				end)
			end,
			onSaveZone = function(zone: BasePart, name: string, shotName: string)
				run("Save Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local ownedPart = owned :: BasePart
					local shot = hierarchy.shots:FindFirstChild(shotName)
					assert(shot ~= nil and shot:IsA("BasePart"), string.format('Shot "%s" not found', shotName))
					local currentModel = model :: any
					if ownedPart.Name ~= name then
						currentModel:renameZone(ownedPart, name)
					end
					if ownedPart:GetAttribute("ShotId") ~= shotName then
						currentModel:assignShot(ownedPart, shot :: BasePart)
					end
				end)
			end,
			onMoveZone = function(zone: BasePart, delta: number)
				run("Move Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local currentModel = model :: any
					currentModel:reorderZone(owned :: BasePart, delta)
				end)
			end,
			onDeleteShot = function(shot: BasePart)
				run("Delete Shot", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.shots, shot)
					assert(owned ~= nil, "Select a shot first")
					local currentModel = model :: any
					currentModel:deleteShot(owned :: BasePart)
				end)
			end,
			onDeleteZone = function(zone: BasePart)
				run("Delete Zone", function()
					local hierarchy = (model :: any):ensureHierarchy()
					local owned = selectedPart(hierarchy.zones, zone)
					assert(owned ~= nil, "Select a zone first")
					local currentModel = model :: any
					currentModel:deleteZone(owned :: BasePart)
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
		widget.gui:BindToClose(function()
			deactivateEditor()
		end)
	end

	editorActive = true
	local currentModel = model :: any
	currentModel:ensureHierarchy()
	if not currentModel:hasParts() then
		local config = currentModel:readData()
		if config ~= nil then
			currentModel:materialize(config)
		end
	end
	currentModel:showParts()
	table.insert(
		connections,
		Selection.SelectionChanged:Connect(function()
			local instances = (Selection :: any):Get()
			local instance = instances[1]
			if widget ~= nil then
				widget:setSelection(instance)
			end
			refresh()
		end)
	)
	local hierarchy = model:ensureHierarchy()
	for _, signal in
		{ hierarchy.root.DescendantAdded, hierarchy.root.DescendantRemoving, hierarchy.root.AttributeChanged }
	do
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
	table.insert(
		connections,
		hierarchy.root.DescendantAdded:Connect(function(instance)
			watchPart(instance)
			refresh()
		end)
	)
	refresh()
	local currentWidget = widget :: any
	currentWidget.gui.Enabled = true
end

toolbarButton.Click:Connect(function()
	if widget == nil or not editorActive then
		activateEditor()
	else
		deactivateEditor()
	end
end)

pluginApi.Unloading:Connect(destroyEditor)
normalizeInactiveState()
