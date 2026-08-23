--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local useObjectiveNotification = require(script.Parent.Parent.objectives.useObjectiveNotification)
local timing = require(script.Parent.Parent.objectives.ObjectiveNotificationTiming)

local function ObjectiveNotification()
	local objectiveNotification = useObjectiveNotification()
	local objectiveNotificationRef = React.useRef(nil :: TextLabel?)

	React.useEffect(function()
		local notification = objectiveNotificationRef.current
		if objectiveNotification == nil or notification == nil then
			return
		end

		local active = true
		local strokeInstance = notification:FindFirstChild("Stroke")
		local stroke = if strokeInstance ~= nil and strokeInstance:IsA("UIStroke") then strokeInstance else nil
		local fadeOut: Tween? = nil
		local strokeFadeOut: Tween? = nil

		local fadeIn = TweenService:Create(notification, TweenInfo.new(timing.fadeInDuration), {
			TextTransparency = 0,
			BackgroundTransparency = 0.08,
		})
		local strokeFadeIn = if stroke ~= nil
			then TweenService:Create(stroke, TweenInfo.new(timing.fadeInDuration), { Transparency = 0.25 })
			else nil

		fadeIn:Play()
		if strokeFadeIn ~= nil then
			strokeFadeIn:Play()
		end

		task.delay(timing.fadeInDuration + timing.visibleDuration, function()
			if not active then
				return
			end
			local nextFadeOut = TweenService:Create(notification, TweenInfo.new(timing.fadeOutDuration), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			fadeOut = nextFadeOut
			strokeFadeOut = if stroke ~= nil
				then TweenService:Create(stroke, TweenInfo.new(timing.fadeOutDuration), { Transparency = 1 })
				else nil
			nextFadeOut:Play()
			if strokeFadeOut ~= nil then
				strokeFadeOut:Play()
			end
		end)

		return function()
			active = false
			fadeIn:Cancel()
			if strokeFadeIn ~= nil then
				strokeFadeIn:Cancel()
			end
			if fadeOut ~= nil then
				fadeOut:Cancel()
			end
			if strokeFadeOut ~= nil then
				strokeFadeOut:Cancel()
			end
		end
	end, { objectiveNotification })

	if objectiveNotification == nil then
		return nil
	end

	return React.createElement("TextLabel", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.GothamBold,
		ref = objectiveNotificationRef,
		Text = (if #objectiveNotification == 1 then "NOVO OBJETIVO" else "NOVOS OBJETIVOS")
			.. "\n"
			.. table.concat((function()
				local texts = {}
				for _, objective in objectiveNotification do
					table.insert(texts, objective.text)
				end
				return texts
			end)(), "\n"),
		TextColor3 = Color3.fromRGB(241, 237, 255),
		TextSize = 14,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(107, 92, 168),
			Transparency = 1,
		}),
	})
end

return ObjectiveNotification
