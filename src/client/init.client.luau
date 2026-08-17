--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local CameraController = require(script.camera.CameraController)
local CameraDebugger = require(script.camera.CameraDebugger)
local InventoryController = require(script.inventory.InventoryController)
local PickupNotificationController = require(script.pickups.PickupNotificationController)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local Players = game:GetService("Players")
local App = require(script.ui.App)

local cameraSystem = workspace:FindFirstChild("CameraSystem")
local cameraConfig = CameraMapReader.read(cameraSystem)
local controller = CameraController.new(cameraConfig)
controller:start()

local debugger = CameraDebugger.new(cameraConfig)
debugger:start()

PickupNotificationController.start()
InventoryController.start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App))
