--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local CameraController = require(script.camera.CameraController)
local CameraVisibility = require(script.camera.CameraVisibility)
local CinematicController = require(script.cinematics.CinematicController)
local CinematicSoundPlayer = require(script.cinematics.CinematicSoundPlayer)
local DialogueController = require(script.dialogue.DialogueController)
local DialogueInteractionController = require(script.dialogue.DialogueInteractionController)
local DoorController = require(script.doors.DoorController)
local TransitionController = require(script.doors.TransitionController)
local PickupEventBridge = require(script.events.PickupEventBridge)
local InventoryController = require(script.inventory.InventoryController)
local InteractionController = require(script.interactions.InteractionController)
local ObjectiveController = require(script.objectives.ObjectiveController)
local PickupController = require(script.pickups.PickupController)
local PickupNotificationController = require(script.pickups.PickupNotificationController)
local FootstepController = require(script.player.FootstepController)
local TankController = require(script.player.TankController)
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
local cameraController = CameraController.new(cameraConfig)
cameraController:start()
TankController.start()

local cinematicSoundPlayer = CinematicSoundPlayer.new()

local cinematicController = CinematicController.new({
	camera = cameraController,
	movement = TankController,
	sound = cinematicSoundPlayer,
})

FootstepController.start()

PickupNotificationController.start()
InventoryController.start()
DialogueController.start()
TransitionController.start()
ObjectiveController.start()
PickupEventBridge.start()
InteractionController.register("Door", DoorController)
InteractionController.register("Pickup", PickupController)
InteractionController.register("Dialogue", DialogueInteractionController)
InteractionController.start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App))

local manualCinematic = {
	{
		frame = 1,
		duration = 10,
		effects = {
			{ name = "play-sound", attributes = { soundId = "rbxassetid://131940090612749" } },
			{ name = "set-camera-shot", attributes = { shot = "Final_G" } },
		},
	},
	{
		frame = 2,
		duration = 2,
		effects = {
			{ name = "set-camera-shot", attributes = { shot = "Start_Enter_Cave_B" } },
		},
	},
	{
		frame = 3,
		duration = 2,
		effects = {
			{ name = "play-sound", attributes = { soundId = "rbxassetid://131940090612749" } },
			{ name = "set-camera-shot", attributes = { shot = "Start_Enter_Cave_C" } },
		},
	},
}

task.delay(5, function()
	print('testes')
	local result = cinematicController:play(manualCinematic)
	print(result)
end)
