--!strict

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local StarterPlayer = game:GetService("StarterPlayer")

local DoorSoundConfig = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorSoundConfig)

export type StopPlayback = () -> ()
export type SoundName = "locked" | "unlocked" | "transitionOpen" | "transitionClose"
export type DoorSoundPlayer = {
	playOneShot: (self: DoorSoundPlayer, name: SoundName) -> (),
	start: (self: DoorSoundPlayer, name: SoundName) -> StopPlayback,
	getDuration: (self: DoorSoundPlayer, name: SoundName) -> number,
	startAtEnd: (self: DoorSoundPlayer, name: SoundName, duration: number) -> StopPlayback,
}

type SoundSet = { [SoundName]: Sound }

local function createSound(soundId: string, volume: number): Sound
	if soundId == "" then
		error("Door sound ID cannot be empty")
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService
	pcall(function()
		ContentProvider:PreloadAsync({ sound })
	end)
	return sound
end

local function play(sound: Sound): ()
	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local function createSounds(): SoundSet
	return {
		locked = createSound(DoorSoundConfig.locked, DoorSoundConfig.lockedVolume),
		unlocked = createSound(DoorSoundConfig.unlocked, DoorSoundConfig.unlockedVolume),
		transitionOpen = createSound(DoorSoundConfig.transitionOpen, DoorSoundConfig.transitionOpenVolume),
		transitionClose = createSound(DoorSoundConfig.transitionClose, DoorSoundConfig.transitionCloseVolume),
	}
end

local function createPlayer(): DoorSoundPlayer
	local sounds = createSounds()
	local player = {} :: DoorSoundPlayer

	function player:playOneShot(name: SoundName): ()
		play(sounds[name])
	end

	function player:start(name: SoundName): StopPlayback
		local sound = sounds[name]
		play(sound)
		local stopped = false
		return function()
			if stopped then
				return
			end
			stopped = true
			sound:Stop()
		end
	end

	function player:getDuration(name: SoundName): number
		return math.max(0, sounds[name].TimeLength)
	end

	function player:startAtEnd(name: SoundName, duration: number): StopPlayback
		local sound = sounds[name]
		local stopped = false
		local scheduledPlayback: thread? = nil
		local scheduledStop: thread? = nil

		local function stop(): ()
			if stopped then
				return
			end
			stopped = true
			if scheduledPlayback ~= nil then
				task.cancel(scheduledPlayback)
				scheduledPlayback = nil
			end
			if scheduledStop ~= nil then
				task.cancel(scheduledStop)
				scheduledStop = nil
			end
			sound:Stop()
		end

		local soundDuration = sound.TimeLength
		local playbackDelay = if soundDuration > 0 then math.max(0, duration - soundDuration) else 0
		if playbackDelay == 0 then
			play(sound)
		else
			scheduledPlayback = task.delay(playbackDelay, function()
				scheduledPlayback = nil
				if not stopped then
					play(sound)
				end
			end)
		end
		scheduledStop = task.delay(math.max(0, duration), function()
			scheduledStop = nil
			stop()
		end)

		return stop
	end

	return player
end

return {
	new = createPlayer,
}
