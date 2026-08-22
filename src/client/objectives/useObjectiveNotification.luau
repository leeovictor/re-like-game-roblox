--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.ObjectiveController)

local function useObjectiveNotification()
	local batch, rawSetBatch = React.useState(nil :: { any }?)
	local setBatch: ({ any }? | (({ any }?) -> { any }?)) -> () = rawSetBatch :: any

	React.useEffect(function()
		local active = true
		local notificationGeneration = 0
		local connection = controller.activated:Connect(function(nextBatch: { any })
			notificationGeneration += 1
			local currentGeneration = notificationGeneration
			setBatch(nextBatch)
			task.delay(3, function()
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
