--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local StarterPlayer = game:GetService("StarterPlayer")

local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)

local function useDocumentReader(controller: DocumentReaderControllerModule.DocumentReaderController)
	local reader, setReader = React.useState(controller:getState())

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
