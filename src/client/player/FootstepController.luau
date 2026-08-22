--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.FootstepConfig)

local player = Players.LocalPlayer
local started = false
local characterConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local humanoidRunningConnection: RBXScriptConnection? = nil
local defaultRunningConnection: RBXScriptConnection? = nil
local setupGeneration = 0
local activeHumanoid: Humanoid? = nil
local activeSounds: { Sound } = {}
local lastSound: Sound? = nil
local currentSpeed = 0
local timeSinceLastStep = 0

local function randomBetween(range: Config.Range): number
	return range.min + (range.max - range.min) * math.random()
end

local function disconnectHumanoidRunning(): ()
	if humanoidRunningConnection ~= nil then
		humanoidRunningConnection:Disconnect()
		humanoidRunningConnection = nil
	end
end

local function disconnectDefaultRunningWatcher(): ()
	if defaultRunningConnection ~= nil then
		defaultRunningConnection:Disconnect()
		defaultRunningConnection = nil
	end
end

local function clearCharacter(): ()
	disconnectHumanoidRunning()
	disconnectDefaultRunningWatcher()

	for _, sound in activeSounds do
		sound:Stop()
		sound:Destroy()
	end

	table.clear(activeSounds)
	activeHumanoid = nil
	lastSound = nil
	currentSpeed = 0
	timeSinceLastStep = 0
end

local function destroyDefaultRunning(rootPart: BasePart): ()
	local running = rootPart:FindFirstChild("Running")
	if running ~= nil then
		running:Destroy()
	end
end

local function createFootstepSounds(rootPart: BasePart): { Sound }
	local sounds = {}
	for index, soundId in Config.soundIds do
		local sound = Instance.new("Sound")
		sound.Name = `Footstep_{index}`
		sound.SoundId = soundId
		sound.Looped = false
		sound.PlaybackSpeed = Config.playbackSpeed.min
		sound.Volume = Config.volume.min
		sound.RollOffMode = Config.rollOffMode
		sound.RollOffMinDistance = Config.rollOffMinDistance
		sound.RollOffMaxDistance = Config.rollOffMaxDistance
		sound.Parent = rootPart
		table.insert(sounds, sound)
	end
	return sounds
end

local function chooseSound(): Sound?
	local soundCount = #activeSounds
	if soundCount == 0 then
		return nil
	end

	if soundCount == 1 or lastSound == nil then
		return activeSounds[math.random(1, soundCount)]
	end

	local candidates = {}
	for _, sound in activeSounds do
		if sound ~= lastSound then
			table.insert(candidates, sound)
		end
	end
	return candidates[math.random(1, #candidates)]
end

local function playFootstep(): ()
	local sound = chooseSound()
	if sound == nil then
		return
	end

	lastSound = sound
	sound.PlaybackSpeed = randomBetween(Config.playbackSpeed)
	sound.Volume = randomBetween(Config.volume)
	sound:Play()
end

local function intervalForSpeed(speed: number): number
	local interval = Config.referenceStepInterval * Config.referenceSpeed / speed
	return math.clamp(interval, Config.minInterval, Config.maxInterval)
end

local function update(deltaTime: number): ()
	if not started or activeHumanoid == nil or #activeSounds == 0 then
		return
	end

	if currentSpeed <= Config.movementThreshold or activeHumanoid.FloorMaterial == Enum.Material.Air then
		timeSinceLastStep = 0
		return
	end

	timeSinceLastStep += deltaTime
	if timeSinceLastStep < intervalForSpeed(currentSpeed) then
		return
	end

	timeSinceLastStep = 0
	playFootstep()
end

local function configureCharacter(character: Model): ()
	setupGeneration += 1
	local generation = setupGeneration
	clearCharacter()

	local rootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	if not started or generation ~= setupGeneration or player.Character ~= character then
		return
	end
	if not rootPart:IsA("BasePart") or not humanoid:IsA("Humanoid") then
		return
	end

	defaultRunningConnection = rootPart.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Running" then
			child:Destroy()
		end
	end)
	destroyDefaultRunning(rootPart)
	activeHumanoid = humanoid
	activeSounds = createFootstepSounds(rootPart)
	humanoidRunningConnection = humanoid.Running:Connect(function(speed: number)
		if activeHumanoid ~= humanoid then
			return
		end
		currentSpeed = speed
		if speed <= Config.movementThreshold then
			timeSinceLastStep = 0
		end
	end)
end

local controller = {}

function controller.start(): ()
	if started then
		return
	end

	started = true
	characterConnection = player.CharacterAdded:Connect(configureCharacter)
	local character = player.Character
	if character ~= nil then
		configureCharacter(character)
	end
	renderConnection = RunService.PreRender:Connect(update)
end

function controller.stop(): ()
	if not started then
		return
	end

	started = false
	setupGeneration += 1
	if characterConnection ~= nil then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	if renderConnection ~= nil then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	clearCharacter()
end

return controller
