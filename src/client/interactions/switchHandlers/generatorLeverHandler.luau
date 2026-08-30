local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")

local CinematicController = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.CinematicController)
local Locator = require(ReplicatedStorage.Shared.locator.locator)

local TIMELINE_GENERATOR_POWER_ON: CinematicController.Timeline = {
	id = "generator-power-on",
	steps = {
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
                    attributes = { soundId = 'rbxassetid://9078877103' },
                },
                {
                    name = "set-model-profile",
                    attributes = { model = "Machine", profile = "fixed" },
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
                        profile = "locked",
                    },
                },
                {
                    name = "set-seal-door",
                    attributes = {
                        door = "FacilityEntrance.DoorTest",
                        value = false
                    }
                },
                {
                    name = "set-attribute",
                    attributes = {
                        instance = 'Machine.LeverInteraction',
                        name = 'enabled',
                        value = false
                    }
                },
                {
                    name = "set-model-profile",
                    attributes = {
                        model = "SimpleLamp_1",
                        profile = "enabled"
                    }
                },
		    },
	    },
    },
}

return function (optionId, reason)
    local cinematicController: CinematicController.Controller = Locator.get('CinematicController')
    
    if optionId == 'yes' then
        local sound = Instance.new('Sound')
        sound.SoundId = 'rbxassetid://91232411976994'
        SoundService:PlayLocalSound(sound)

        local res = cinematicController:play(TIMELINE_GENERATOR_POWER_ON) 
        if not res then
            warn('error while playing cinematic generator power on')
        end
    end
end
