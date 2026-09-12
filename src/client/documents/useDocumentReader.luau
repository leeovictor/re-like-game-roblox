--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local StarterPlayer = game:GetService("StarterPlayer")

local DocumentReaderControllerModule =
	require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local controller: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

local function useDocumentReader()
	local reader, setReader = React.useState(controller.getState())

	React.useEffect(function()
		local connection = controller.changed:Connect(function(nextState)
			setReader(nextState)
		end)

		return function()
			connection:Disconnect()
		end
	end, { controller })

	return reader
end

return useDocumentReader
