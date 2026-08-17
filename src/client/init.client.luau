--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.camera.CameraConfig)
local CameraController = require(script.camera.CameraController)
local CameraDebugger = require(script.camera.CameraDebugger)
local InventoryController = require(script.inventory.InventoryController)
local PickupNotificationController = require(script.pickups.PickupNotificationController)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local Players = game:GetService("Players")
local App = require(script.ui.App)

local controller = CameraController.new(CameraConfig)
controller:start()

local debugger = CameraDebugger.new(CameraConfig)
debugger:start()

PickupNotificationController.start()
InventoryController.start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App))
