--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ObjectiveController = require(script.Parent.Parent.objectives.ObjectiveController)
local useObjectiveNotification = require(script.Parent.Parent.objectives.useObjectiveNotification)
local timing = require(script.Parent.Parent.objectives.ObjectiveNotificationTiming)

local function ObjectiveNotification()
	local objectiveNotification = useObjectiveNotification()
	local objectiveNotificationRef = React.useRef(nil :: Frame?)
	local titleRef = React.useRef(nil :: TextLabel?)
	local descriptionRef = React.useRef(nil :: TextLabel?)

	React.useEffect(function()
		local notification = objectiveNotificationRef.current
		local title = titleRef.current
		local description = descriptionRef.current
		if objectiveNotification == nil or notification == nil or title == nil or description == nil then
			return
		end

		local active = true
		ObjectiveController.playSound()
		local strokeInstance = notification:FindFirstChild("Stroke")
		local stroke = if strokeInstance ~= nil and strokeInstance:IsA("UIStroke") then strokeInstance else nil
		local fadeOut: Tween? = nil
		local textFadeOut: Tween? = nil
		local descriptionFadeOut: Tween? = nil
		local strokeFadeOut: Tween? = nil

		local fadeIn = TweenService:Create(notification, TweenInfo.new(timing.fadeInDuration), {
			BackgroundTransparency = 0.08,
		})
		local textFadeIn = TweenService:Create(title, TweenInfo.new(timing.fadeInDuration), {
			TextTransparency = 0,
		})
		local descriptionFadeIn = TweenService:Create(description, TweenInfo.new(timing.fadeInDuration), {
			TextTransparency = 0,
		})
		local strokeFadeIn = if stroke ~= nil
			then TweenService:Create(stroke, TweenInfo.new(timing.fadeInDuration), { Transparency = 0.25 })
			else nil

		fadeIn:Play()
		textFadeIn:Play()
		descriptionFadeIn:Play()
		if strokeFadeIn ~= nil then
			strokeFadeIn:Play()
		end

		task.delay(timing.fadeInDuration + timing.visibleDuration, function()
			if not active then
				return
			end
			local nextFadeOut = TweenService:Create(notification, TweenInfo.new(timing.fadeOutDuration), {
				BackgroundTransparency = 1,
			})
			local nextTextFadeOut = TweenService:Create(title, TweenInfo.new(timing.fadeOutDuration), {
				TextTransparency = 1,
			})
			local nextDescriptionFadeOut = TweenService:Create(description, TweenInfo.new(timing.fadeOutDuration), {
				TextTransparency = 1,
			})
			fadeOut = nextFadeOut
			textFadeOut = nextTextFadeOut
			descriptionFadeOut = nextDescriptionFadeOut
			strokeFadeOut = if stroke ~= nil
				then TweenService:Create(stroke, TweenInfo.new(timing.fadeOutDuration), { Transparency = 1 })
				else nil
			nextFadeOut:Play()
			nextTextFadeOut:Play()
			nextDescriptionFadeOut:Play()
			if strokeFadeOut ~= nil then
				strokeFadeOut:Play()
			end
		end)

		return function()
			active = false
			fadeIn:Cancel()
			textFadeIn:Cancel()
			descriptionFadeIn:Cancel()
			if strokeFadeIn ~= nil then
				strokeFadeIn:Cancel()
			end
			if fadeOut ~= nil then
				fadeOut:Cancel()
			end
			if textFadeOut ~= nil then
				textFadeOut:Cancel()
			end
			if descriptionFadeOut ~= nil then
				descriptionFadeOut:Cancel()
			end
			if strokeFadeOut ~= nil then
				strokeFadeOut:Cancel()
			end
		end
	end, { objectiveNotification })

	if objectiveNotification == nil then
		return nil
	end

	local objectiveText = table.concat((function()
		local texts = {}
		for _, objective in objectiveNotification do
			table.insert(texts, objective.text)
		end
		return texts
	end)(), "\n")

	return React.createElement("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ref = objectiveNotificationRef,
	}, {
		Padding = React.createElement("UIPadding", {
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
		}),
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			LayoutOrder = 1,
			ref = titleRef,
			Size = UDim2.new(1, 0, 0, 18),
			Text = if #objectiveNotification == 1 then "OBJETIVO ATUALIZADO" else "OBJETIVOS ATUALIZADOS",
			TextColor3 = Color3.fromRGB(173, 179, 198),
			TextSize = 12,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Description = React.createElement("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			LayoutOrder = 2,
			ref = descriptionRef,
			Size = UDim2.new(1, 0, 0, 0),
			Text = objectiveText,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 16,
			TextTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		})
	})
end

return ObjectiveNotification
