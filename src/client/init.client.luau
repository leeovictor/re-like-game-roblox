--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
InputManager.init()

local CameraMapReader = require(ReplicatedStorage.Shared.camera.CameraMapReader)
local AudioService = require(ReplicatedStorage.Shared.audio.AudioService)
local CameraController = require(StarterPlayer.StarterPlayerScripts.Client.camera.CameraController)
local CameraVisibility = require(StarterPlayer.StarterPlayerScripts.Client.camera.CameraVisibility)
local CinematicController = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.CinematicController)
local MachineRoomCinematicController = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.MachineRoomCinematicController)
local CinematicSoundPlayer = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.CinematicSoundPlayer)
local DialogueController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueController)
local DialogueInteractionController = require(StarterPlayer.StarterPlayerScripts.Client.dialogue.DialogueInteractionController)
local DoorController = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorController)
local DoorManager = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorManager)
local TransitionController = require(StarterPlayer.StarterPlayerScripts.Client.doors.TransitionController)
local EnemyController = require(StarterPlayer.StarterPlayerScripts.Client.enemies.EnemyController)
local InventoryController = require(StarterPlayer.StarterPlayerScripts.Client.inventory.InventoryController)
local CombatService = require(StarterPlayer.StarterPlayerScripts.Client.combat.CombatService)
local PlayerController = require(StarterPlayer.StarterPlayerScripts.Client.player.PlayerController)
local PlayerAttackController = require(StarterPlayer.StarterPlayerScripts.Client.player.PlayerAttackController)
local InteractionController = require(StarterPlayer.StarterPlayerScripts.Client.interactions.InteractionController)
local ObjectiveController = require(StarterPlayer.StarterPlayerScripts.Client.objectives.ObjectiveController)
local PickupInteraction = require(StarterPlayer.StarterPlayerScripts.Client.pickups.PickupInteraction)
local PickupManager = require(StarterPlayer.StarterPlayerScripts.Client.pickups.PickupManager)
local PickupNotificationController = require(StarterPlayer.StarterPlayerScripts.Client.pickups.PickupNotificationController)
local ItemInstanceFactory = require(ReplicatedStorage.Shared.inventory.ItemInstanceFactory)
local FootstepController = require(StarterPlayer.StarterPlayerScripts.Client.player.FootstepController)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local createSwitchInteraction = require(StarterPlayer.StarterPlayerScripts.Client.interactions.SwitchInteraction)
local Locator = require(ReplicatedStorage.Shared.locator.locator)

local Players = game:GetService("Players")

local App = require(StarterPlayer.StarterPlayerScripts.Client.ui.App)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
AudioService.preload()

local cameraSystem = workspace:WaitForChild("CameraSystem")
local cameraController = CameraController.new({
	cameraMapReader = CameraMapReader,
})
CameraVisibility.hide(cameraSystem)
cameraController:start()

local cinematicSoundPlayer = CinematicSoundPlayer.new()

local dialogueController = DialogueController.new()
dialogueController:start()

local function showDialogue(text: string, callback: ((nil, string) -> ())?): ()
	dialogueController:show(text, callback)
end

local dialogueInteractionController = DialogueInteractionController.new({
	show = showDialogue,
})
local interactionController = InteractionController.new(nil, nil)

FootstepController.start()

local inventoryController = InventoryController.new()
inventoryController:start()
local enemyController = EnemyController.new()
local combatService = CombatService.new({
	inventory = inventoryController,
	enemies = enemyController,
})
local playerController = PlayerController.new({
	combat = combatService,
})
local playerAttackController = PlayerAttackController.new({
	player = playerController,
	attackStarted = enemyController.playerAttackStarted,
	attackEnded = enemyController.playerAttackEnded,
})
playerAttackController:start()
playerController:start()
enemyController:start()
local factory = ItemInstanceFactory.new()
local pickupManager = PickupManager.new({
	inventory = inventoryController,
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
	inventory = inventoryController,
})
local doorController = DoorController.new({
	manager = doorManager,
	dialogue = dialogueController,
	movement = playerController,
	transition = TransitionController,
})
ObjectiveController.start()

local cinematicController = CinematicController.new({
	camera = cameraController,
	sound = cinematicSoundPlayer,
	doorManager = doorManager
})

local machineRoomCinematicController = MachineRoomCinematicController.new({
	cinematic = cinematicController,
	inventory = inventoryController,
})
machineRoomCinematicController:start()

interactionController:register("Door", doorController)
interactionController:register("Pickup", pickupInteraction)
interactionController:register("Dialogue", dialogueInteractionController)
interactionController:register("Switch", createSwitchInteraction({ dialogueController = dialogueController }))
interactionController:start()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = ReactRoblox.createRoot(playerGui)
root:render(React.createElement(App, {
		dialogueController = dialogueController,
		cinematicController = cinematicController,
		inventoryController = inventoryController,
		combatService = combatService,
	}))

Locator.register('CinematicController', cinematicController)
