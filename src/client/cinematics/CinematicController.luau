--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local CameraController = require(StarterPlayer.StarterPlayerScripts.Client.camera.CameraController)
local CinematicSoundPlayer = require(StarterPlayer.StarterPlayerScripts.Client.cinematics.CinematicSoundPlayer)
local DoorManager = require(StarterPlayer.StarterPlayerScripts.Client.doors.DoorManager)
local GameplayEvents = require(StarterPlayer.StarterPlayerScripts.Client.events.GameplayEvents)

local ModelProfiles = require(ReplicatedStorage.Shared.modelProfiles)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type SetCameraShotEffect = {
	name: "set-camera-shot",
	attributes: {
		shot: string,
	},
}

export type PlaySoundEffect = {
	name: "play-sound",
	attributes: {
		soundId: string,
	},
}

export type SetModelProfileEffect = {
	name: "set-model-profile",
	attributes: {
		model: string,
		profile: string,
	},
}

export type SetSealDoorEffect = {
	name: "set-seal-door",
	attributes: {
		door: string,
		value: boolean
	},
}

export type SetAttribute = {
	name: "set-attribute",
	attributes: {
		instance: string,
		name: string,
		value: any
	}	
}

export type Effect = SetCameraShotEffect | PlaySoundEffect | SetModelProfileEffect | SetSealDoorEffect | SetAttribute

export type TimelineStep = {
	frame: number,
	duration: number,
	effects: { Effect },
}

export type Timeline = {
	id: string,
	steps: { TimelineStep },
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

export type PlayingChangedSignal = {
	Fire: (self: PlayingChangedSignal, playing: boolean) -> (),
	Connect: (
		self: PlayingChangedSignal,
		callback: (playing: boolean) -> ()
	) -> SignalConnection,
}

export type Dependencies = {
	camera: CameraController.CameraController,
	sound: CinematicSoundPlayer.CinematicSoundPlayer,
	doorManager: DoorManager.DoorManager,
}

type State = "idle" | "preloading" | "playing"

export type Controller = {
	dependencies: Dependencies,
	playingChanged: PlayingChangedSignal,
	state: State,
	generation: number,
	nextExecutionId: number,
	currentExecutionId: number?,
	currentTimelineId: string?,
	preload: (self: Controller, timeline: any) -> boolean,
	play: (self: Controller, timeline: any) -> boolean,
	stop: (self: Controller) -> (),
	isPlaying: (self: Controller) -> boolean,
}

local CinematicController = {}
CinematicController.__index = CinematicController

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function unknownField(value: any, allowed: { [string]: boolean }): string?
	for key in value do
		if type(key) ~= "string" or allowed[key] ~= true then
			return tostring(key)
		end
	end
	return nil
end

local function resolveWorkspaceInstance(path: string): Instance?
	if string.match(path, "^%.") ~= nil
		or string.match(path, "%.$") ~= nil
		or string.match(path, "%.%.") ~= nil
	then
		return nil
	end

	local current: Instance = workspace
	for segment in string.gmatch(path, "[^%.]+") do
		local child = current:FindFirstChild(segment)
		if child == nil then
			return nil
		end
		current = child
	end
	
	return current
end

local function resolveWorkspaceModel(path: string): Model?
	local instance = resolveWorkspaceInstance(path)
	return if instance ~= nil and instance:IsA("Model") then instance else nil
end

local function contiguousLength(value: any): (number?, string?)
	if type(value) ~= "table" then
		return nil, "must be a table"
	end

	local maximum = 0
	for key in value do
		if type(key) ~= "number" or not isFinite(key) or key < 1 or key ~= math.floor(key) then
			return nil, "must contain contiguous numeric indexes"
		end
		if key > maximum then
			maximum = key
		end
	end

	for index = 1, maximum do
		if value[index] == nil then
			return nil, "must contain contiguous numeric indexes"
		end
	end
	return maximum, nil
end

local function validateEffect(
	value: any,
	index: number,
	camera: CameraController.CameraController
): (Effect?, string?)
	if type(value) ~= "table" then
		return nil, string.format("effects[%d] must be a table", index)
	end

	local field = unknownField(value, { name = true, attributes = true })
	if field ~= nil then
		return nil, string.format("effects[%d] has unknown field %s", index, field)
	end

	if type(value.name) ~= "string" then
		return nil, string.format("effects[%d].name must be a string", index)
	end
	if type(value.attributes) ~= "table" then
		return nil, string.format("effects[%d].attributes must be a table", index)
	end

	if value.name == "set-camera-shot" then
		field = unknownField(value.attributes, { shot = true })
		if field ~= nil then
			return nil, string.format("effects[%d].attributes has unknown field %s", index, field)
		end
		if type(value.attributes.shot) ~= "string" then
			return nil, string.format("effects[%d].attributes.shot must be a string", index)
		end

		local hasShotOk, hasShot = pcall(function()
			return camera:hasShot(value.attributes.shot)
		end)
		if not hasShotOk or not hasShot then
			return nil, string.format("effects[%d] references an unknown shot", index)
		end

		return {
			name = "set-camera-shot",
			attributes = { shot = value.attributes.shot },
		}, nil
	elseif value.name == "play-sound" then
		field = unknownField(value.attributes, { soundId = true })
		if field ~= nil then
			return nil, string.format("effects[%d].attributes has unknown field %s", index, field)
		end
		if type(value.attributes.soundId) ~= "string"
			or string.match(value.attributes.soundId, "^rbxassetid://%d+$") == nil
		then
			return nil, string.format("effects[%d].attributes.soundId is invalid", index)
		end

		return {
			name = "play-sound",
			attributes = { soundId = value.attributes.soundId },
		}, nil
	elseif value.name == "set-model-profile" then
		field = unknownField(value.attributes, { model = true, profile = true })
		if field ~= nil then
			return nil, string.format("effects[%d].attributes has unknown field %s", index, field)
		end
		if type(value.attributes.model) ~= "string" or value.attributes.model == "" then
			return nil, string.format("effects[%d].attributes.model must be a non-empty string", index)
		end
		if type(value.attributes.profile) ~= "string" or value.attributes.profile == "" then
			return nil, string.format("effects[%d].attributes.profile must be a non-empty string", index)
		end

		return {
			name = "set-model-profile",
			attributes = {
				model = value.attributes.model,
				profile = value.attributes.profile,
			},
		}, nil
	elseif value.name == "set-seal-door" then
		field = unknownField(value.attributes, { door = true, value = true })
		if field ~= nil then
			return nil, string.format("effects[%d].attributes has unknown field %s", index, field)
		end
		
		return {
			name = "set-seal-door",
			attributes = {
				door = value.attributes.door,
				value = value.attributes.value,
			},
		}, nil
	elseif value.name == "set-attribute" then
		field = unknownField(value.attributes, { instance = true, name = true, value = true })
		if field ~= nil then
			return nil, string.format("effects[%d].attributes has unknown field %s", index, field)
		end
		
		return {
			name = "set-attribute",
			attributes = {
				instance = value.attributes.instance,
				name = value.attributes.name,
				value = value.attributes.value,
			},
		}, nil
	end

	return nil, string.format("effects[%d] has an unknown name", index)
end

local function validateTimeline(
	value: any,
	camera: CameraController.CameraController
): (Timeline?, { string }?, string?)
	if type(value) ~= "table" then
		return nil, nil, "timeline must be a table"
	end
	local rootField = unknownField(value, { id = true, steps = true })
	if rootField ~= nil then
		return nil, nil, "timeline has unknown field " .. rootField
	end
	if type(value.id) ~= "string" or value.id == "" then
		return nil, nil, "timeline.id must be a non-empty string"
	end
	local timelineLength, timelineError = contiguousLength(value.steps)
	if timelineLength == nil then
		return nil, nil, "timeline " .. (timelineError :: string)
	end
	if timelineLength == 0 then
		return nil, nil, "timeline.steps must not be empty"
	end

	local timeline: Timeline = { id = value.id, steps = {} }
	local soundIds: { string } = {}
	local seenSoundIds: { [string]: boolean } = {}

	for index = 1, timelineLength do
		local step = value.steps[index]
		if type(step) ~= "table" then
			return nil, nil, string.format("timeline.steps[%d] must be a table", index)
		end

		local field = unknownField(step, { frame = true, duration = true, effects = true })
		if field ~= nil then
			return nil, nil, string.format("timeline.steps[%d] has unknown field %s", index, field)
		end

		local frame = step.frame
		if type(frame) ~= "number" or not isFinite(frame) or frame ~= math.floor(frame) then
			return nil, nil, string.format("timeline.steps[%d].frame must be a finite integer", index)
		end
		if frame ~= index then
			return nil, nil, string.format("timeline.steps[%d].frame must equal its sequential index", index)
		end

		local duration = step.duration
		if type(duration) ~= "number" or not isFinite(duration) then
			return nil, nil, string.format("timeline.steps[%d].duration must be finite", index)
		end
		if duration < 0 then
			return nil, nil, string.format("timeline.steps[%d].duration must not be negative", index)
		end

		local effectsLength, effectsError = contiguousLength(step.effects)
		if effectsLength == nil then
			return nil, nil, string.format("timeline.steps[%d].effects %s", index, effectsError :: string)
		end

		local effects: { Effect } = {}
		for effectIndex = 1, effectsLength do
			local validatedEffect, effectError = validateEffect(step.effects[effectIndex], effectIndex, camera)
			if validatedEffect == nil then
				return nil, nil, string.format("timeline.steps[%d] %s", index, effectError :: string)
			end
			table.insert(effects, validatedEffect)

			if validatedEffect.name == "play-sound" then
				local soundId = validatedEffect.attributes.soundId
				if not seenSoundIds[soundId] then
					seenSoundIds[soundId] = true
					table.insert(soundIds, soundId)
				end
			end
		end

		table.insert(timeline.steps, {
			frame = frame,
			duration = duration,
			effects = effects,
		})
	end

	return timeline, soundIds, nil
end

local function warnInvalidTimeline(message: string): ()
	warn("CinematicController invalid timeline: " .. message)
end

local function ensureCurrentGeneration(self: Controller, executionId: number, generation: number): boolean
	return self.generation == generation
		and self.currentExecutionId == executionId
		and self.state ~= "idle"
end

local function clearCamera(self: Controller): ()
	local ok = pcall(function()
		self.dependencies.camera:clearCinematicShot()
	end)
	if not ok then
		warn("CinematicController camera cleanup failed")
	end
end

local function stopSound(self: Controller, executionId: number): ()
	local ok = pcall(function()
		self.dependencies.sound:stop(executionId)
	end)
	if not ok then
		warn("CinematicController sound cleanup failed")
	end
end

local function firePlayingChanged(self: Controller, playing: boolean): ()
	local ok, errorMessage = pcall(function()
		self.playingChanged:Fire(playing)
	end)
	if not ok then
		warn("CinematicController playingChanged failed: " .. tostring(errorMessage))
	end
end

local function emitCinematicEvent(event: GameplayEvents.GameplayEvent): ()
	local ok, errorMessage = pcall(function()
		GameplayEvents.emit(event)
	end)
	if not ok then
		warn("CinematicController gameplay event failed: " .. tostring(errorMessage))
	end
end

local function finishNormally(self: Controller, executionId: number): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	local wasPlaying = self.state == "playing"
	local timelineId = self.currentTimelineId
	self.state = "idle"
	self.currentExecutionId = nil
	self.currentTimelineId = nil
	if wasPlaying then
		firePlayingChanged(self, false)
	end
	clearCamera(self)
	if wasPlaying and timelineId ~= nil then
		emitCinematicEvent({ name = "cinematic_play_ended", timelineId = timelineId })
	end
end

local function finishInterrupted(self: Controller, executionId: number): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	local wasPlaying = self.state == "playing"
	local timelineId = self.currentTimelineId
	self.state = "idle"
	self.currentExecutionId = nil
	self.currentTimelineId = nil
	if wasPlaying then
		firePlayingChanged(self, false)
	end
	stopSound(self, executionId)
	clearCamera(self)
	if wasPlaying and timelineId ~= nil then
		emitCinematicEvent({ name = "cinematic_play_ended", timelineId = timelineId })
	end
end

local function finishWithoutEffects(self: Controller, executionId: number): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	local wasPlaying = self.state == "playing"
	self.state = "idle"
	self.currentExecutionId = nil
	self.currentTimelineId = nil
	if wasPlaying then
		firePlayingChanged(self, false)
	end
	stopSound(self, executionId)
	clearCamera(self)
end

local function handleSetCameraShot(self: Controller, effect: Effect, _executionId: number): boolean
	if effect.name ~= "set-camera-shot" then
		return false
	end
	return self.dependencies.camera:setCinematicShot(effect.attributes.shot)
end

local function handlePlaySound(self: Controller, effect: Effect, executionId: number): boolean
	if effect.name ~= "play-sound" then
		return false
	end
	self.dependencies.sound:play(effect.attributes.soundId, executionId)
	return true
end

local function handleSetModelProfile(_self: Controller, effect: Effect, _executionId: number): boolean
	if effect.name ~= "set-model-profile" then
		return false
	end

	local model = resolveWorkspaceModel(effect.attributes.model)
	if model == nil then
		warn("CinematicController model path did not resolve to a Model: " .. effect.attributes.model)
		return false
	end

	local result = ModelProfiles.setProfile(model, effect.attributes.profile)
	if not result.success then
		local firstError = result.errors[1]
		warn("CinematicController model profile failed: " .. (if firstError ~= nil then firstError.message else "unknown error"))
		return false
	end
	return true
end

local function handleSetSealDoor(self: Controller, effect: Effect, _executionId: number): boolean
	if effect.name ~= "set-seal-door" then
		return false
	end

	local model = resolveWorkspaceModel(effect.attributes.door)
	if model == nil then
		warn("CinematicController model path did not resolve to a Model: " .. effect.attributes.door)
		return false
	end

	local result, reason = self.dependencies.doorManager:setSealed(model, effect.attributes.value)
	if not result and reason then
		warn('CinematicController error at set seal door effect beacause ' .. reason)
		return false
	end
	return true
end

local function handleSetAttribute(_self: Controller, effect: Effect, _executionId: number): boolean
	if effect.name ~= "set-attribute" then
		return false
	end

	local instance = resolveWorkspaceInstance(effect.attributes.instance)
	if instance == nil then
		warn("CinematicController model path did not resolve to a Model: " .. effect.attributes.instance)
		return false
	end

	instance:SetAttribute(effect.attributes.name, effect.attributes.value)
	return true
end

local effectHandlers: { [string]: (self: Controller, effect: Effect, executionId: number) -> boolean } = {
	["set-camera-shot"] = handleSetCameraShot,
	["play-sound"] = handlePlaySound,
	["set-model-profile"] = handleSetModelProfile,
	["set-seal-door"] = handleSetSealDoor,
	["set-attribute"] = handleSetAttribute,
}

local function executeEffect(self: Controller, effect: Effect, executionId: number): boolean
	local handler = effectHandlers[effect.name]
	if handler == nil then
		return false
	end

	local ok, result = pcall(function()
		return handler(self, effect, executionId)
	end)
	if not ok then
		warn("CinematicController effect failed: " .. tostring(result))
		return false
	end
	if result ~= true then
		warn("CinematicController effect was rejected: " .. effect.name)
		return false
	end
	return true
end

local function runExecution(
	self: Controller,
	timeline: Timeline,
	soundIds: { string },
	executionId: number,
	generation: number
): ()
	if not ensureCurrentGeneration(self, executionId, generation) then
		return
	end

	local preloaded, preloadResult = pcall(function()
		return self.dependencies.sound:preload(soundIds)
	end)
	if not preloaded or preloadResult ~= true then
		if ensureCurrentGeneration(self, executionId, generation) then
			finishWithoutEffects(self, executionId)
		end
		return
	end

	if not ensureCurrentGeneration(self, executionId, generation) then
		return
	end

	self.state = "playing"
	firePlayingChanged(self, true)
	emitCinematicEvent({ name = "cinematic_started", timelineId = timeline.id })

	for _, step in timeline.steps do
		if not ensureCurrentGeneration(self, executionId, generation) then
			return
		end

		for _, effect in step.effects do
			if not ensureCurrentGeneration(self, executionId, generation) then
				return
			end
			if not executeEffect(self, effect, executionId) then
				if ensureCurrentGeneration(self, executionId, generation) then
					finishInterrupted(self, executionId)
				end
				return
			end
		end

		if not ensureCurrentGeneration(self, executionId, generation) then
			return
		end
		local waited, waitError = pcall(function()
			task.wait(step.duration)
		end)
		if not waited then
			warn("CinematicController wait failed: " .. tostring(waitError))
			if ensureCurrentGeneration(self, executionId, generation) then
				finishInterrupted(self, executionId)
			end
			return
		end
	end

	if ensureCurrentGeneration(self, executionId, generation) then
		finishNormally(self, executionId)
	end
end

function CinematicController.preload(self: Controller, timeline: any): boolean
	if self.state ~= "idle" then
		return false
	end

	local validatedTimeline, soundIds, validationError = validateTimeline(timeline, self.dependencies.camera)
	if validatedTimeline == nil then
		warnInvalidTimeline(validationError :: string)
		return false
	end

	self.generation += 1
	local generation = self.generation
	self.state = "preloading"
	local ok, result = pcall(function()
		return self.dependencies.sound:preload(soundIds :: { string })
	end)
	if self.generation ~= generation then
		return false
	end
	self.state = "idle"
	if not ok then
		warn("CinematicController preload failed: " .. tostring(result))
		return false
	end
	return result == true
end

function CinematicController.play(self: Controller, timeline: any): boolean
	if self.state ~= "idle" then
		return false
	end

	local validatedTimeline, soundIds, validationError = validateTimeline(timeline, self.dependencies.camera)
	if validatedTimeline == nil then
		warnInvalidTimeline(validationError :: string)
		return false
	end

	self.nextExecutionId += 1
	local executionId = self.nextExecutionId
	self.generation += 1
	local generation = self.generation
	self.currentExecutionId = executionId
	self.currentTimelineId = validatedTimeline.id
	self.state = "preloading"
	task.spawn(function()
		runExecution(self, validatedTimeline, soundIds :: { string }, executionId, generation)
	end)
	return true
end

function CinematicController.stop(self: Controller): ()
	self.generation += 1
	local wasPlaying = self.state == "playing"
	local executionId = self.currentExecutionId
	local timelineId = self.currentTimelineId
	self.state = "idle"
	self.currentExecutionId = nil
	self.currentTimelineId = nil

	if executionId ~= nil then
		stopSound(self, executionId)
	end
	if wasPlaying then
		firePlayingChanged(self, false)
	end
	clearCamera(self)
	if wasPlaying and timelineId ~= nil then
		emitCinematicEvent({ name = "cinematic_play_ended", timelineId = timelineId })
	end
end

function CinematicController.isPlaying(self: Controller): boolean
	return self.state == "playing"
end

function CinematicController.new(dependencies: Dependencies): Controller
	local self = setmetatable({
		dependencies = dependencies,
		playingChanged = (Signal.new() :: any) :: PlayingChangedSignal,
		state = "idle",
		generation = 0,
		nextExecutionId = 0,
		currentExecutionId = nil,
		currentTimelineId = nil,
	}, CinematicController)
	return (self :: any) :: Controller
end

return CinematicController
