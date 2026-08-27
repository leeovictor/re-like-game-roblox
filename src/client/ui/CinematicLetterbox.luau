--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

type Props = {
	playing: boolean,
	onExitComplete: () -> (),
}

local CINEMATIC_ASPECT_RATIO = 2.39
local MAX_BAR_SCALE = 0.45
local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getBarScale(): number
	local camera: Camera? = Workspace.CurrentCamera
	if camera == nil or camera.ViewportSize.Y <= 0 then
		return (1 - (16 / 9) / CINEMATIC_ASPECT_RATIO) / 2
	end

	local viewportSize = camera.ViewportSize
	local viewportAspect = viewportSize.X / viewportSize.Y
	local visibleHeightScale = math.min(1, viewportAspect / CINEMATIC_ASPECT_RATIO)
	return math.clamp((1 - visibleHeightScale) / 2, 0, MAX_BAR_SCALE)
end

local function CinematicLetterbox(props: Props)
	local topBarRef = React.useRef(nil :: Frame?)
	local bottomBarRef = React.useRef(nil :: Frame?)
	local transitionIdRef = React.useRef(0)
	local onExitCompleteRef = React.useRef(props.onExitComplete)
	onExitCompleteRef.current = props.onExitComplete

	React.useEffect(function()
		transitionIdRef.current += 1
		local transitionId = transitionIdRef.current
		local topBar = topBarRef.current
		local bottomBar = bottomBarRef.current
		if topBar == nil or bottomBar == nil then
			return
		end

		local topTween: Tween? = nil
		local bottomTween: Tween? = nil
		local completionConnection: RBXScriptConnection? = nil

		local function tweenBars(barScale: number, onCompleted: (() -> ())?): ()
			if topTween ~= nil then
				topTween:Cancel()
			end
			if bottomTween ~= nil then
				bottomTween:Cancel()
			end

			local goal = { Size = UDim2.fromScale(1, barScale) }
			local nextTopTween = TweenService:Create(topBar, TWEEN_INFO, goal)
			local nextBottomTween = TweenService:Create(bottomBar, TWEEN_INFO, goal)
			topTween = nextTopTween
			bottomTween = nextBottomTween
			if onCompleted ~= nil and bottomTween ~= nil then
				completionConnection = bottomTween.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or transitionIdRef.current ~= transitionId then
						return
					end
					onCompleted()
				end)
			end
			nextTopTween:Play()
			nextBottomTween:Play()
		end

		tweenBars(
			if props.playing then getBarScale() else 0,
			if props.playing then nil else function()
				onExitCompleteRef.current()
			end
		)

		local viewportConnection: RBXScriptConnection? = nil
		local function watchCurrentCamera(): ()
			if viewportConnection ~= nil then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			local camera: Camera? = Workspace.CurrentCamera
			if props.playing and camera ~= nil then
				viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					tweenBars(getBarScale())
				end)
			end
		end

		local cameraConnection: RBXScriptConnection? = nil
		if props.playing then
			watchCurrentCamera()
			cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCurrentCamera)
		end

		return function()
			if completionConnection ~= nil then
				completionConnection:Disconnect()
			end
			if cameraConnection ~= nil then
				cameraConnection:Disconnect()
			end
			if viewportConnection ~= nil then
				viewportConnection:Disconnect()
			end
			if topTween ~= nil then
				topTween:Cancel()
			end
			if bottomTween ~= nil then
				bottomTween:Cancel()
			end
		end
	end, { props.playing })

	return React.createElement("ScreenGui", {
		Name = "CinematicLetterboxGui",
		DisplayOrder = 1000,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		TopBar = React.createElement("Frame", {
			AnchorPoint = Vector2.zero,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			ref = topBarRef,
			Size = UDim2.fromScale(1, 0),
		}),
		BottomBar = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 1),
			ref = bottomBarRef,
			Size = UDim2.fromScale(1, 0),
		}),
	})
end

return CinematicLetterbox
