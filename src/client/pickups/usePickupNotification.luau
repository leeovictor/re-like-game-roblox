--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local StarterPlayer = game:GetService("StarterPlayer")

local controller = require(StarterPlayer.StarterPlayerScripts.Client.pickups.PickupNotificationController)

local function usePickupNotification(): string?
	local itemId, rawSetItemId = React.useState(nil :: string?)
	local setItemId: (string? | ((string?) -> string?)) -> () = rawSetItemId :: any

	React.useEffect(function()
		local active = true
		local notificationGeneration = 0
		local connection = controller.changed:Connect(function(nextItemId: string)
			notificationGeneration += 1
			local currentGeneration = notificationGeneration
			setItemId(nextItemId)

			task.delay(2, function()
				if active and currentGeneration == notificationGeneration then
					setItemId(function(_: string?): string?
						return nil
					end)
				end
			end)
		end)

		return function()
			active = false
			notificationGeneration += 1
			connection:Disconnect()
		end
	end, {})

	return itemId
end

return usePickupNotification
