--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local DialogueController = require(script.Parent.DialogueController)

local function useDialogue(controller: DialogueController.DialogueController)
	local dialogue, setDialogue = React.useState(controller:getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(nextDialogue)
			setDialogue(nextDialogue)
		end)

		return function()
			connection:Disconnect()
		end
	end, { controller })

	return dialogue
end

return useDialogue
