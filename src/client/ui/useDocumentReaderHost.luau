--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local useDocumentReader = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocumentReader)
local DocumentReaderControllerModule =
	require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)

local controller: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

export type DocumentReaderHost = {
	active: boolean,
	presentation: DocumentReaderControllerModule.DocumentReaderState?,
	visible: boolean,
	nextPage: () -> (),
	previousPage: () -> (),
	onExitComplete: () -> (),
}

local function useDocumentReaderHost(): DocumentReaderHost
	local documentReader = useDocumentReader()
	local documentReaderActive = documentReader ~= nil
	local presentation, setPresentation = React.useState(documentReader)
	local visible, setVisible = React.useState(documentReader ~= nil)

	React.useEffect(function()
		if documentReader ~= nil then
			setPresentation(documentReader)
			setVisible(true)
		elseif presentation ~= nil then
			setVisible(false)
		end
	end, { documentReader })

	return {
		active = documentReaderActive or presentation ~= nil,
		presentation = presentation,
		visible = visible,
		nextPage = function()
			controller.nextPage()
		end,
		previousPage = function()
			controller.previousPage()
		end,
		onExitComplete = function()
			setPresentation(nil)
		end,
	}
end

return useDocumentReaderHost
