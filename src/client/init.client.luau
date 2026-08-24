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
local DoorManager = require(script.doors.DoorManager)
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
local cameraController = CameraController.new({
	cameraMapReader = CameraMapReader,
})
CameraVisibility.hide(cameraSystem)
cameraController:start()
local tankController = TankController.new()
tankController:start()

local cinematicSoundPlayer = CinematicSoundPlayer.new()

local dialogueController = DialogueController.new({
	movement = tankController,
})
dialogueController:start()

local cinematicController = CinematicController.new({
	camera = cameraController,
	movement = tankController,
	sound = cinematicSoundPlayer,
})

local function showDialogue(text: string, callback: ((nil, string) -> ())?): ()
	dialogueController:show(text, callback)
end

local dialogueInteractionController = DialogueInteractionController.new({
	show = showDialogue,
})
local interactionController = InteractionController.new(nil, nil)

FootstepController.start()

PickupNotificationController.start()
InventoryController.start()
TransitionController.start()
local doorManager = DoorManager.new({
	inventory = InventoryController,
})
local doorController = DoorController.new({
	manager = doorManager,
	dialogue = dialogueController,
	transition = TransitionController,
})
ObjectiveController.start()
PickupEventBridge.start()

interactionController:register("Door", doorController)
interactionController:register("Pickup", PickupController)
interactionController:register("Dialogue", dialogueInteractionController)
interactionController:start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App, {
	dialogueController = dialogueController,
}))

local manualCinematic = {
	{
		frame = 1,
		duration = 2,
		effects = {
			{ name = "play-sound", attributes = { soundId = "rbxassetid://131940090612749" } },
			{ name = "set-camera-shot", attributes = { shot = "Final_G" } },
		} :: { any },
	},
	{
		frame = 2,
		duration = 2,
		effects = {
			{ name = "set-camera-shot", attributes = { shot = "MachineRoom_MachineCloseUp" } },
		} :: { any },
	},
	{
		frame = 3,
		duration = 2,
		effects = {
			{ name = "play-sound", attributes = { soundId = "rbxassetid://131940090612749" } },
			{ name = "set-camera-shot", attributes = { shot = "Start_Enter_Cave_C" } },
		} :: { any },
	},
};

task.delay(5, function()
	local result = cinematicController:play(manualCinematic)
	print('cinematic result', result)
end)
