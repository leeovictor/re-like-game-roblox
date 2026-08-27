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
local EnemyController = require(script.enemies.EnemyController)
local InventoryController = require(script.inventory.InventoryController)
local InteractionController = require(script.interactions.InteractionController)
local ObjectiveController = require(script.objectives.ObjectiveController)
local PickupInteraction = require(script.pickups.PickupInteraction)
local PickupManager = require(script.pickups.PickupManager)
local PickupNotificationController = require(script.pickups.PickupNotificationController)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
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
local enemyController = EnemyController.new({
	movement = tankController,
})
enemyController:start()

local cinematicSoundPlayer = CinematicSoundPlayer.new()

local dialogueController = DialogueController.new({
	movement = tankController,
})
dialogueController:start()

local _cinematicController = CinematicController.new({
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

InventoryController.start()
local factory = ItemInstanceFactory.new()
local pickupManager = PickupManager.new({
	inventory = InventoryController,
	factory = factory,
})
pickupManager:start()
local pickupInteraction = PickupInteraction.new({
	manager = pickupManager,
})
PickupNotificationController.start({
	source = pickupManager.collected,
})
TransitionController.start()
local doorManager = DoorManager.new({
	inventory = InventoryController,
})
local doorController = DoorController.new({
	manager = doorManager,
	dialogue = dialogueController,
	movement = tankController,
	transition = TransitionController,
})
ObjectiveController.start()

interactionController:register("Door", doorController)
interactionController:register("Pickup", pickupInteraction)
interactionController:register("Dialogue", dialogueInteractionController)
interactionController:start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App, {
	dialogueController = dialogueController,
}))
