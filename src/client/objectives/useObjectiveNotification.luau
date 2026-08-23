--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.ObjectiveController)

type ObjectiveView = {
	id: string,
	text: string,
	completed: boolean,
}

local NOTIFICATION_DELAY = 5

local function useObjectiveNotification(): { ObjectiveView }?
	local initialState = controller.getState()
	local initialBatch = if initialState ~= nil then initialState.objectives else nil
	local batch, rawSetBatch = React.useState(initialBatch)
	local setBatch: ({ ObjectiveView }? | (({ ObjectiveView }?) -> { ObjectiveView }?)) -> () = rawSetBatch :: any

	React.useEffect(function()
		local active = true
		local notificationGeneration = 0
		if initialBatch ~= nil and #initialBatch > 0 then
			local currentGeneration = notificationGeneration
			task.delay(NOTIFICATION_DELAY, function()
				if active and currentGeneration == notificationGeneration then
					setBatch(nil)
				end
			end)
		end
		local connection = controller.activated:Connect(function(nextBatch: { ObjectiveView })
			notificationGeneration += 1
			local currentGeneration = notificationGeneration
			setBatch(nextBatch)
			task.delay(NOTIFICATION_DELAY, function()
				if active and currentGeneration == notificationGeneration then
					setBatch(nil)
				end
			end)
		end)

		return function()
			active = false
			notificationGeneration += 1
			connection:Disconnect()
		end
	end, {})

	return batch
end

return useObjectiveNotification
