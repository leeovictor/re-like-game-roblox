--!strict

local CinematicController = {}
local CameraController = require(script.Parent.Parent.camera.CameraController)
local CinematicSoundPlayer = require(script.Parent.CinematicSoundPlayer)
local TankController = require(script.Parent.Parent.player.TankController)

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

export type Effect = SetCameraShotEffect | PlaySoundEffect

export type TimelineStep = {
	frame: number,
	duration: number,
	effects: { Effect },
}

export type Timeline = { TimelineStep }

export type Dependencies = {
	camera: CameraController.CameraController,
	movement: TankController.TankController,
	sound: CinematicSoundPlayer.CinematicSoundPlayer,
}

type State = "idle" | "preloading" | "playing"

type Controller = {
	dependencies: Dependencies,
	state: State,
	generation: number,
	nextExecutionId: number,
	currentExecutionId: number?,
	movementRelease: (() -> ())?,
	preload: (self: Controller, timeline: any) -> boolean,
	play: (self: Controller, timeline: any) -> boolean,
	stop: (self: Controller) -> (),
	isPlaying: (self: Controller) -> boolean,
}

local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

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
	end

	return nil, string.format("effects[%d] has an unknown name", index)
end

local function validateTimeline(
	value: any,
	camera: CameraController.CameraController
): (Timeline?, { string }?, string?)
	local timelineLength, timelineError = contiguousLength(value)
	if timelineLength == nil then
		return nil, nil, "timeline " .. (timelineError :: string)
	end
	if timelineLength == 0 then
		return nil, nil, "timeline must not be empty"
	end

	local timeline: Timeline = {}
	local soundIds: { string } = {}
	local seenSoundIds: { [string]: boolean } = {}

	for index = 1, timelineLength do
		local step = value[index]
		if type(step) ~= "table" then
			return nil, nil, string.format("timeline[%d] must be a table", index)
		end

		local field = unknownField(step, { frame = true, duration = true, effects = true })
		if field ~= nil then
			return nil, nil, string.format("timeline[%d] has unknown field %s", index, field)
		end

		local frame = step.frame
		if type(frame) ~= "number" or not isFinite(frame) or frame ~= math.floor(frame) then
			return nil, nil, string.format("timeline[%d].frame must be a finite integer", index)
		end
		if frame ~= index then
			return nil, nil, string.format("timeline[%d].frame must equal its sequential index", index)
		end

		local duration = step.duration
		if type(duration) ~= "number" or not isFinite(duration) then
			return nil, nil, string.format("timeline[%d].duration must be finite", index)
		end
		if duration < 0 then
			return nil, nil, string.format("timeline[%d].duration must not be negative", index)
		end

		local effectsLength, effectsError = contiguousLength(step.effects)
		if effectsLength == nil then
			return nil, nil, string.format("timeline[%d].effects %s", index, effectsError :: string)
		end

		local effects: { Effect } = {}
		for effectIndex = 1, effectsLength do
			local validatedEffect, effectError = validateEffect(step.effects[effectIndex], effectIndex, camera)
			if validatedEffect == nil then
				return nil, nil, string.format("timeline[%d] %s", index, effectError :: string)
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

		table.insert(timeline, {
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

local function releaseMovement(self: Controller, release: (() -> ())?): ()
	if release == nil or self.movementRelease ~= release then
		return
	end
	self.movementRelease = nil
	local ok = pcall(release)
	if not ok then
		warn("CinematicController movement release failed")
	end
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

local function finishNormally(self: Controller, executionId: number, release: (() -> ())): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	self.state = "idle"
	self.currentExecutionId = nil
	clearCamera(self)
	releaseMovement(self, release)
end

local function finishInterrupted(self: Controller, executionId: number, release: (() -> ())?): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	self.state = "idle"
	self.currentExecutionId = nil
	stopSound(self, executionId)
	clearCamera(self)
	releaseMovement(self, release)
end

local function finishWithoutEffects(self: Controller, executionId: number): ()
	if self.currentExecutionId ~= executionId then
		return
	end
	self.state = "idle"
	self.currentExecutionId = nil
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

local effectHandlers: { [string]: (self: Controller, effect: Effect, executionId: number) -> boolean } = {
	["set-camera-shot"] = handleSetCameraShot,
	["play-sound"] = handlePlaySound,
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

	local acquired, release = pcall(function(): () -> ()
		return self.dependencies.movement.acquireMovementLock()
	end)
	if not acquired then
		warn("CinematicController movement lock failed: " .. tostring(release))
		if ensureCurrentGeneration(self, executionId, generation) then
			finishWithoutEffects(self, executionId)
		end
		return
	end

	self.movementRelease = release
	self.state = "playing"

	for _, step in timeline do
		if not ensureCurrentGeneration(self, executionId, generation) then
			return
		end

		for _, effect in step.effects do
			if not ensureCurrentGeneration(self, executionId, generation) then
				return
			end
			if not executeEffect(self, effect, executionId) then
				if ensureCurrentGeneration(self, executionId, generation) then
					finishInterrupted(self, executionId, release)
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
				finishInterrupted(self, executionId, release)
			end
			return
		end
	end

	if ensureCurrentGeneration(self, executionId, generation) then
		finishNormally(self, executionId, release)
	end
end

local function createController(dependencies: Dependencies): Controller
	local self = setmetatable({
		dependencies = dependencies,
		state = "idle",
		generation = 0,
		nextExecutionId = 0,
		currentExecutionId = nil,
		movementRelease = nil,
	}, ControllerMethods)
	return (self :: any) :: Controller
end

function ControllerMethods.preload(self: Controller, timeline: any): boolean
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

function ControllerMethods.play(self: Controller, timeline: any): boolean
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
	self.state = "preloading"
	task.spawn(function()
		runExecution(self, validatedTimeline, soundIds :: { string }, executionId, generation)
	end)
	return true
end

function ControllerMethods.stop(self: Controller): ()
	self.generation += 1
	local executionId = self.currentExecutionId
	local release = self.movementRelease
	self.movementRelease = nil
	self.state = "idle"
	self.currentExecutionId = nil

	if executionId ~= nil then
		stopSound(self, executionId)
	end
	clearCamera(self)
	if release ~= nil then
		local ok = pcall(release)
		if not ok then
			warn("CinematicController movement release failed")
		end
	end
end

function ControllerMethods.isPlaying(self: Controller): boolean
	return self.state == "playing"
end

function CinematicController.new(dependencies: Dependencies): Controller
	return createController(dependencies)
end

return CinematicController
