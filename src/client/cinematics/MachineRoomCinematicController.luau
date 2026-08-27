--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CinematicController = require(script.Parent.CinematicController)
local CharacterRoot = require(script.Parent.Parent.player.CharacterRoot)
local InventoryControllerModule = require(script.Parent.Parent.inventory.InventoryController)

type InventoryController = InventoryControllerModule.InventoryController

export type Dependencies = {
	cinematic: CinematicController.Controller,
	inventory: InventoryController,
}

export type Controller = {
	dependencies: Dependencies,
	started: boolean,
	triggered: boolean,
	trigger: BasePart?,
	touchedConnection: RBXScriptConnection?,
	start: (self: Controller) -> (),
	stop: (self: Controller) -> (),
}

local TRIGGER_NAME = "MachineRoomCinematicTrigger"
local ACCESS_CARD_ID = "access_card"

local TIMELINE: CinematicController.Timeline = {
	{
		frame = 1,
		duration = 1.5,
		effects = {},
	},
	{
		frame = 2,
		duration = 1,
		effects = {
			{
				name = "set-camera-shot",
				attributes = { shot = "MachineRoom_MachineCloseUp" },
			},
		},
	},
	{
		frame = 3,
		duration = 1.4,
		effects = {
			{
				name = "play-sound",
				attributes = { soundId = 'rbxassetid://91232411976994' },
			},
			{
				name = "set-model-profile",
				attributes = { model = "Machine", profile = "disabled" },
			},
		},
	},
	{
		frame = 4,
		duration = 1,
		effects = {
			{
				name = "set-camera-shot",
				attributes = { shot = "Final_G" },
			},
		},
	},
	{
		frame = 5,
		duration = 1.8,
		effects = {
			{
				name = "play-sound",
				attributes = { soundId = 'rbxassetid://125440417623813' },
			},
			{
				name = "set-model-profile",
				attributes = {
					model = "FacilityEntrance.DoorTest",
					profile = "power_off",
				},
			},
		},
	},
}

local function hasAccessCard(inventory: InventoryController): boolean
	local state = inventory.getState()
	if state == nil then
		return false
	end

	for _, item in state.items do
		if item.itemId == ACCESS_CARD_ID then
			return true
		end
	end
	return false
end

local MachineRoomCinematicController = {}
MachineRoomCinematicController.__index = MachineRoomCinematicController

function MachineRoomCinematicController.new(dependencies: Dependencies): Controller
	assert(type(dependencies) == "table", "MachineRoomCinematicController dependencies are required")
	assert(type(dependencies.cinematic.play) == "function", "MachineRoomCinematicController cinematic.play is required")
	assert(type(dependencies.inventory.getState) == "function", "MachineRoomCinematicController inventory.getState is required")

	local controller = setmetatable({
		dependencies = dependencies,
		started = false,
		triggered = false,
		trigger = nil,
		touchedConnection = nil,
	}, MachineRoomCinematicController)

	local function tryPlay(otherPart: BasePart): ()
		if not controller.started or controller.triggered then
			return
		end

		local character = Players.LocalPlayer.Character
		if character == nil or not otherPart:IsDescendantOf(character) then
			return
		end
		if CharacterRoot.get() == nil or not hasAccessCard(dependencies.inventory) then
			return
		end

		if dependencies.cinematic:play(TIMELINE) then
			controller.triggered = true
		end
	end

	function controller.start(self: Controller): ()
		if self.started then
			return
		end

		local trigger = Workspace:FindFirstChild(TRIGGER_NAME)
		if trigger == nil or not trigger:IsA("BasePart") then
			warn(string.format("MachineRoomCinematicController could not find Workspace.%s BasePart", TRIGGER_NAME))
			return
		end

		self.started = true
		self.trigger = trigger
		self.touchedConnection = trigger.Touched:Connect(tryPlay)
	end

	function controller.stop(self: Controller): ()
		if not self.started then
			return
		end

		self.started = false
		if self.touchedConnection ~= nil then
			self.touchedConnection:Disconnect()
			self.touchedConnection = nil
		end
		self.trigger = nil
		self.dependencies.cinematic:stop()
	end

	return (controller :: any) :: Controller
end

return MachineRoomCinematicController
