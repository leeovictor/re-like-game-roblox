--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local React = require(ReplicatedStorage.Packages.React)
local theme = require(StarterPlayer.StarterPlayerScripts.Client.ui.theme)
local Locator = require(ReplicatedStorage.Shared.locator.locator)
local useDocuments = require(StarterPlayer.StarterPlayerScripts.Client.documents.useDocuments)
local DocumentsControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentsController)
local DocumentReaderControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentReaderController)
local documentsController: DocumentsControllerModule.DocumentsController = Locator.get("DocumentsController")
local documentReaderController: DocumentReaderControllerModule.DocumentReaderController = Locator.get("DocumentReaderController")

type Props = {
	onDocumentActivated: () -> (),
}

local function DocumentList(props: Props)
	local documents = useDocuments()
	local documentRows = {}
	local visibleDocumentCount = 0

	for index, documentId in documents.collectedIds do
		local document = documentsController.getDocument(documentId)
		if document ~= nil then
			visibleDocumentCount += 1
			documentRows[tostring(index)] = React.createElement("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = theme.surface,
				Font = Enum.Font.RobotoMono,
				LayoutOrder = index,
				Selectable = true,
				Size = UDim2.new(1, 0, 0, 36),
				Text = document.displayName,
				TextColor3 = theme.text,
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				[React.Event.Activated] = function()
					props.onDocumentActivated()
					documentReaderController.open(documentId)
				end,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 6),
				}),
			})
		end
	end

	if visibleDocumentCount == 0 then
		documentRows.Empty = React.createElement("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.RobotoMono,
			Size = UDim2.new(1, 0, 0, 36),
			Text = "Nenhum documento coletado.",
			TextColor3 = theme.textMuted,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	documentRows.Layout = React.createElement("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return React.createElement("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 0, 184),
	}, documentRows)
end

return DocumentList
