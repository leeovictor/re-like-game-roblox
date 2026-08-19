--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local doorTypes = require(ReplicatedStorage.Shared.doors.doorTypes)

local FADE_IN_DURATION = 0.2
local FADE_OUT_DURATION = 0.2
local TRANSITION_SOUND_ID = ""

export type TransitionRequest = () -> doorTypes.DoorActionResult
export type TransitionCallback = (result: doorTypes.DoorActionResult) -> ()
export type TransitionController = {
	start: () -> (),
	stop: () -> (),
	run: (request: TransitionRequest, callback: TransitionCallback) -> boolean,
}

type ControllerState = {
	screen: ScreenGui?,
	fade: Frame?,
	started: boolean,
	busy: boolean,
	generation: number,
	tween: Tween?,
}

local function createController(playerGui: PlayerGui): TransitionController
	local state: ControllerState = {
		screen = nil,
		fade = nil,
		started = false,
		busy = false,
		generation = 0,
		tween = nil,
	}

	local function ensureGui(): Frame
		local screenInstance = playerGui:FindFirstChild("DoorTransitionGui")
		if screenInstance == nil then
			local newScreen = Instance.new("ScreenGui")
			newScreen.Name = "DoorTransitionGui"
			newScreen.ResetOnSpawn = false
			newScreen.IgnoreGuiInset = true
			newScreen.DisplayOrder = 100
			newScreen.Parent = playerGui
			screenInstance = newScreen
		end
		if screenInstance == nil or not screenInstance:IsA("ScreenGui") then
			if screenInstance ~= nil then
				screenInstance:Destroy()
			end
			return ensureGui()
		end
		local screen = screenInstance :: ScreenGui

		local fadeInstance = screen:FindFirstChild("Fade")
		if fadeInstance == nil then
			local newFade = Instance.new("Frame")
			newFade.Name = "Fade"
			newFade.BackgroundColor3 = Color3.new(0, 0, 0)
			newFade.BorderSizePixel = 0
			newFade.Size = UDim2.fromScale(1, 1)
			newFade.BackgroundTransparency = 1
			newFade.ZIndex = 100
			newFade.Parent = screen
			fadeInstance = newFade
		end
		if fadeInstance == nil or not fadeInstance:IsA("Frame") then
			if fadeInstance ~= nil then
				fadeInstance:Destroy()
			end
			return ensureGui()
		end
		local fade = fadeInstance :: Frame

		state.screen = screen
		state.fade = fade
		return fade
	end

	local function animate(transparency: number, duration: number, generation: number): boolean
		local fade = state.fade
		if fade == nil or state.generation ~= generation then
			return false
		end
		if state.tween ~= nil then
			state.tween:Cancel()
		end
		local tween = TweenService:Create(fade, TweenInfo.new(duration), { BackgroundTransparency = transparency })
		state.tween = tween
		tween:Play()
		tween.Completed:Wait()
		if state.tween == tween then
			state.tween = nil
		end
		return state.generation == generation
	end

	local controller = {} :: TransitionController

	function controller.start(): ()
		if state.started then
			return
		end
		state.started = true
		local fade = ensureGui()
		fade.BackgroundTransparency = 1
	end

	function controller.stop(): ()
		state.started = false
		state.generation += 1
		state.busy = false
		if state.tween ~= nil then
			state.tween:Cancel()
			state.tween = nil
		end
		if state.fade ~= nil then
			state.fade.BackgroundTransparency = 1
		end
	end

	function controller.run(request: TransitionRequest, callback: TransitionCallback): boolean
		if not state.started or state.busy then
			return false
		end
		local fade = ensureGui()
		state.busy = true
		state.generation += 1
		local generation = state.generation
		task.spawn(function()
			local result: doorTypes.DoorActionResult = { success = false }
			if animate(0, FADE_IN_DURATION, generation) then
				local ok, value = pcall(request)
				if ok and type(value) == "table" then
					result = value :: doorTypes.DoorActionResult
				end
				if state.generation == generation then
					if result.success and result.action == "enter" and TRANSITION_SOUND_ID ~= "" then
						local sound = Instance.new("Sound")
						sound.SoundId = TRANSITION_SOUND_ID
						sound.Parent = fade
						sound:Play()
					end
					animate(1, FADE_OUT_DURATION, generation)
				end
			end
			if state.generation == generation then
				state.busy = false
				fade.BackgroundTransparency = 1
				pcall(callback, result)
			end
		end)
		return true
	end

	return controller
end

local defaultController = createController(Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui)
local module = {
	new = createController,
	start = defaultController.start,
	stop = defaultController.stop,
	run = defaultController.run,
}

return module
