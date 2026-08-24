--!strict

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local CinematicSoundPlayer = {}
CinematicSoundPlayer.__index = CinematicSoundPlayer

export type Dependencies = {
	parent: Instance?,
	preloadAsync: ((sounds: { Sound }) -> ())?,
	isLoaded: ((sound: Sound) -> boolean)?,
}

type Playback = {
	sound: Sound,
	endedConnection: RBXScriptConnection?,
}

export type CinematicSoundPlayer = {
	parent: Instance,
	templateFolder: Folder,
	playbackFolder: Folder,
	templates: { [string]: Sound? },
	prepared: { [string]: boolean },
	active: { [number]: { Playback } },
	nextTemplateId: number,
	preloadAsync: (sounds: { Sound }) -> (),
	isLoaded: (sound: Sound) -> boolean,
	preload: (self: CinematicSoundPlayer, soundIds: { string }) -> boolean,
	play: (self: CinematicSoundPlayer, soundId: string, executionId: number) -> (),
	stop: (self: CinematicSoundPlayer, executionId: number) -> (),
	getActiveCount: (self: CinematicSoundPlayer, executionId: number) -> number,
}

local function defaultPreloadAsync(sounds: { Sound }): ()
	ContentProvider:PreloadAsync(sounds)
end

local function defaultIsLoaded(sound: Sound): boolean
	return sound.IsLoaded
end

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function CinematicSoundPlayer.new(dependencies: Dependencies?): CinematicSoundPlayer
	local parent = if dependencies ~= nil and dependencies.parent ~= nil then dependencies.parent else SoundService
	local preloadAsync = if dependencies ~= nil and dependencies.preloadAsync ~= nil
		then dependencies.preloadAsync
		else defaultPreloadAsync
	local isLoaded = if dependencies ~= nil and dependencies.isLoaded ~= nil then dependencies.isLoaded else defaultIsLoaded

	local self = setmetatable({
		parent = parent,
		templateFolder = newFolder(parent, "CinematicSoundTemplates"),
		playbackFolder = newFolder(parent, "CinematicSoundPlayback"),
		templates = {},
		prepared = {},
		active = {},
		nextTemplateId = 0,
		preloadAsync = preloadAsync,
		isLoaded = isLoaded,
	}, CinematicSoundPlayer)
	return (self :: any) :: CinematicSoundPlayer
end

local function createTemplate(self: CinematicSoundPlayer, soundId: string): Sound
	local existingTemplate = self.templates[soundId]
	if existingTemplate ~= nil then
		return existingTemplate
	end

	self.nextTemplateId += 1
	local template = Instance.new("Sound")
	template.Name = "CinematicSoundTemplate" .. tostring(self.nextTemplateId)
	template.SoundId = soundId
	template.Looped = false
	template.Parent = self.templateFolder
	self.templates[soundId] = template
	self.prepared[soundId] = false
	return template
end

function CinematicSoundPlayer.preload(self: CinematicSoundPlayer, soundIds: { string }): boolean
	local soundsToPreload: { Sound } = {}
	local idsToPrepare: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, soundId in soundIds do
		if not seen[soundId] then
			seen[soundId] = true
			local template = createTemplate(self, soundId)
			if not self.prepared[soundId] then
				table.insert(soundsToPreload, template)
				table.insert(idsToPrepare, soundId)
			end
		end
	end

	if #soundsToPreload == 0 then
		return true
	end

	local ok, errorMessage = pcall(function()
		self.preloadAsync(soundsToPreload)
	end)
	if not ok then
		warn(string.format("CinematicSoundPlayer preload failed: %s", tostring(errorMessage)))
		return false
	end

	for _, soundId in idsToPrepare do
		local template = self.templates[soundId]
		if template == nil then
			warn("CinematicSoundPlayer template disappeared during preload")
			return false
		end

		local loaded, isLoaded = pcall(function()
			return self.isLoaded(template)
		end)
		if not loaded or not isLoaded then
			warn(string.format("CinematicSoundPlayer sound was not loaded: %s", soundId))
			return false
		end
	end

	for _, soundId in idsToPrepare do
		self.prepared[soundId] = true
	end
	return true
end

local function removePlayback(
	self: CinematicSoundPlayer,
	executionId: number,
	playback: Playback
): ()
	local active = self.active[executionId]
	if active == nil then
		return
	end

	local index = table.find(active, playback)
	if index == nil then
		return
	end

	table.remove(active, index)
	if #active == 0 then
		self.active[executionId] = nil
	end

	local connection = playback.endedConnection
	if connection ~= nil then
		connection:Disconnect()
		playback.endedConnection = nil
	end
	playback.sound:Destroy()
end

function CinematicSoundPlayer.play(self: CinematicSoundPlayer, soundId: string, executionId: number): ()
	local template = self.templates[soundId]
	if template == nil or not self.prepared[soundId] then
		warn(string.format("CinematicSoundPlayer sound was not preloaded: %s", soundId))
		return
	end

	local sound = template:Clone()
	sound.Looped = false
	sound.Parent = self.playbackFolder

	local active = self.active[executionId]
	if active == nil then
		active = {}
		self.active[executionId] = active
	end

	local playback: Playback = {
		sound = sound,
		endedConnection = nil,
	}
	table.insert(active, playback)
	playback.endedConnection = sound.Ended:Connect(function()
		removePlayback(self, executionId, playback)
	end)
	sound:Play()
end

function CinematicSoundPlayer.stop(self: CinematicSoundPlayer, executionId: number): ()
	local active = self.active[executionId]
	if active == nil then
		return
	end
	self.active[executionId] = nil

	for _, playback in active do
		local connection = playback.endedConnection
		if connection ~= nil then
			connection:Disconnect()
			playback.endedConnection = nil
		end
		playback.sound:Stop()
		playback.sound:Destroy()
	end
end

function CinematicSoundPlayer.getActiveCount(self: CinematicSoundPlayer, executionId: number): number
	local active = self.active[executionId]
	return if active == nil then 0 else #active
end

return CinematicSoundPlayer
