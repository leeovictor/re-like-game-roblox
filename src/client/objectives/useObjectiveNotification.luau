--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local StarterPlayer = game:GetService("StarterPlayer")

local controller = require(StarterPlayer.StarterPlayerScripts.Client.objectives.ObjectiveController)
local timing = require(StarterPlayer.StarterPlayerScripts.Client.objectives.ObjectiveNotificationTiming)

type ObjectiveView = {
	id: string,
	text: string,
	completed: boolean,
}

local function useObjectiveNotification(): { ObjectiveView }?
	local initialState = controller.getState()
	local initialBatch = if initialState ~= nil then initialState.objectives else nil
	local batch, rawSetBatch = React.useState(nil :: { ObjectiveView }?)
	local setBatch: ({ ObjectiveView }? | (({ ObjectiveView }?) -> { ObjectiveView }?)) -> () = rawSetBatch :: any

	React.useEffect(function()
		local active = true
		local notificationGeneration = 0

		local function scheduleNotification(nextBatch: { ObjectiveView }, generation: number): ()
			task.delay(timing.entryDelay, function()
				if not active or generation ~= notificationGeneration then
					return
				end
				setBatch(nextBatch)
				task.delay(
					timing.fadeInDuration + timing.visibleDuration + timing.fadeOutDuration,
					function()
						if active and generation == notificationGeneration then
							setBatch(nil)
						end
					end
				)
			end)
		end

		local connection = controller.activated:Connect(function(nextBatch: { ObjectiveView })
			notificationGeneration += 1
			setBatch(nil)
			scheduleNotification(nextBatch, notificationGeneration)
		end)

		if initialBatch ~= nil and #initialBatch > 0 then
			notificationGeneration += 1
			scheduleNotification(initialBatch, notificationGeneration)
		end

		return function()
			active = false
			notificationGeneration += 1
			connection:Disconnect()
		end
	end, {})

	return batch
end

return useObjectiveNotification
