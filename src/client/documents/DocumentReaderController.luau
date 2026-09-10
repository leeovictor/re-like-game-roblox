--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Locator = require(ReplicatedStorage.Shared.locator.locator)
local DocumentsControllerModule = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentsController)
local InputManager = require(StarterPlayer.StarterPlayerScripts.Client.InputManager)
local Signal = require(ReplicatedStorage.Packages.Signal)
local DocumentData = require(StarterPlayer.StarterPlayerScripts.Client.documents.DocumentData)

export type DocumentReaderState = {
	document: DocumentData.Document,
	pageIndex: number,
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}
type ChangedSignal = {
	Fire: (self: ChangedSignal, state: DocumentReaderState?) -> (),
	Connect: (self: ChangedSignal, callback: (state: DocumentReaderState?) -> ()) -> SignalConnection,
}

export type DocumentReaderController = {
	changed: ChangedSignal,
	start: () -> (),
	stop: () -> (),
	getState: () -> DocumentReaderState?,
	open: (documentId: string) -> boolean,
	nextPage: () -> (),
	previousPage: () -> (),
	close: () -> (),
}

local DocumentReaderController = {} :: DocumentReaderController
local state: DocumentReaderState? = nil
local started = false
local inputConnections: { SignalConnection } = {}
local documentsController: DocumentsControllerModule.DocumentsController? = nil

DocumentReaderController.changed = (Signal.new() :: any) :: ChangedSignal

local function publish(nextState: DocumentReaderState?): ()
	state = nextState
	DocumentReaderController.changed:Fire(nextState)
end

local function handleClose(): ()
	DocumentReaderController.close()
end

local function bindActions(): ()
	local context = InputManager.Contexts.DocumentContext
	table.insert(inputConnections, context:BindActionStateChanged("PreviousPage", function(inputState: boolean)
		if inputState then
			DocumentReaderController.previousPage()
		end
	end))
	table.insert(inputConnections, context:BindActionStateChanged("NextPage", function(inputState: boolean)
		if inputState then
			DocumentReaderController.nextPage()
		end
	end))
	table.insert(inputConnections, context:BindActionStateChanged("Close", function(inputState: boolean)
		if inputState then
			handleClose()
		end
	end))
end

function DocumentReaderController.start(): ()
	if started then
		return
	end
	documentsController = Locator.get("DocumentsController")
	assert(documentsController ~= nil, "DocumentReaderController requires DocumentsController")
	started = true
	bindActions()
end

function DocumentReaderController.stop(): ()
	if not started and state == nil then
		return
	end

	started = false
	for _, connection in inputConnections do
		connection:Disconnect()
	end
	table.clear(inputConnections)
	if state ~= nil then
		publish(nil)
		InputManager.switchContext("PlayContext")
	end
end

function DocumentReaderController.getState(): DocumentReaderState?
	return state
end

function DocumentReaderController.open(documentId: string): boolean
	if not started or documentsController == nil then
		return false
	end

	local document = documentsController.getDocument(documentId)
	if document == nil then
		return false
	end

	publish({
		document = document,
		pageIndex = 1,
	})
	InputManager.switchContext("DocumentContext")
	return true
end

function DocumentReaderController.nextPage(): ()
	local current = state
	if current == nil then
		return
	end

	if current.pageIndex >= #current.document.pages then
		DocumentReaderController.close()
		return
	end

	publish({
		document = current.document,
		pageIndex = current.pageIndex + 1,
	})
end

function DocumentReaderController.previousPage(): ()
	local current = state
	if current == nil then
		return
	end

	publish({
		document = current.document,
		pageIndex = math.max(1, current.pageIndex - 1),
	})
end

function DocumentReaderController.close(): ()
	if state == nil then
		return
	end

	publish(nil)
	InputManager.switchContext("PlayContext")
end

return DocumentReaderController
