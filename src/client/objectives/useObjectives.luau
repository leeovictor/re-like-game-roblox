--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local controller = require(script.Parent.ObjectiveController)

local function useObjectives()
	local objectives, setObjectives = React.useState(controller.getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(nextState)
			setObjectives(nextState)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	return objectives
end

return useObjectives
