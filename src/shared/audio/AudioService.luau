--!strict

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local SoundEnum = require(script.Parent.SoundEnum)

type SoundName = SoundEnum.Sound

local audioAssetIds: { [SoundName]: string } = {
	[SoundEnum.HandgunShot] = "rbxassetid://115357684629977",
	[SoundEnum.HandgunReload] = "rbxassetid://125937654152770",
}

local audioInstances: { [string]: Sound } = {}
local preloaded = false

local AudioService = {}

function AudioService.preload(): ()
	if preloaded then
		return
	end

	if next(audioInstances) == nil then
		for soundName, assetId in audioAssetIds do
			local sound = Instance.new("Sound")
			sound.Name = soundName
			sound.SoundId = assetId
			sound.Parent = SoundService
			audioInstances[soundName] = sound
		end
	end

	local soundsToPreload: { Instance } = {}
	for _, sound in audioInstances do
		table.insert(soundsToPreload, sound)
	end
	ContentProvider:PreloadAsync(soundsToPreload)
	preloaded = true
end

function AudioService.getSound(soundName: SoundName): Sound
	if not preloaded then
		error("AudioService.preload() must be called before getting an audio asset")
	end
	return audioInstances[soundName]
end

function AudioService.play(soundName: SoundName, volume: number?): ()
	local sound = AudioService.getSound(soundName)
	if volume ~= nil then
		sound.Volume = volume
	end
	sound:Play()
end

return AudioService
