--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local StarterPlayer = game:GetService("StarterPlayer")
local DocumentsControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentsController)
local controller: DocumentsControllerModule.DocumentsController = Locator.get("DocumentsController")

local function useDocuments()
	local documents, setDocuments = React.useState(controller.getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(nextState)
			setDocuments(nextState)
		end)

		return function()
			connection:Disconnect()
		end
	end, { controller })

	return documents
end

return useDocuments
