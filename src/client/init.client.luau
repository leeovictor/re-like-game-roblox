--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local CameraController = require(script.camera.CameraController)
local CameraDebugger = require(script.camera.CameraDebugger)
local CameraVisibility = require(script.camera.CameraVisibility)
local InventoryController = require(script.inventory.InventoryController)
local PickupNotificationController = require(script.pickups.PickupNotificationController)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local Players = game:GetService("Players")
local App = require(script.ui.App)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local cameraSystem = workspace:WaitForChild("CameraSystem")
local shotsFolder = cameraSystem:WaitForChild("Shots")
cameraSystem:WaitForChild("Zones")
local defaultShotId = cameraSystem:GetAttribute("DefaultShotId")
if type(defaultShotId) == "string" and defaultShotId ~= "" then
	shotsFolder:WaitForChild(defaultShotId)
end
local cameraConfig = CameraMapReader.read(cameraSystem)
CameraVisibility.hide(cameraSystem)
local controller = CameraController.new(cameraConfig)
controller:start()

local debugger = CameraDebugger.new(cameraConfig)
debugger:start()

PickupNotificationController.start()
InventoryController.start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App))
